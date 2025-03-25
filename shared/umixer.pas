{unit to handle sound mixing}
unit uMixer;

{$MODE delphi}

interface

uses
  uTest,
  uDebug,
  uUtils,
  uA96,
  go32,
  uSound,
  uTimer,
  uInfo;

CONST
  NUM_CHANNELS = 8;

type

  {measured in samples (usually from start of program)}
  tTimeCode = int64;
  {measure in samples * 256, usually an offset}
  {limited to 190 seconds (~3 minutes)}
  tTimeTick = int32;

  tSoundChannelSelection = (
    SCS_SELFOVERWRITE,    // overwrite is sound is already playing,
                          // otherwise next free
    SCS_NEXTFREE,         // find the next free channel
    SCS_OLDEST,           // find the next free channel, or overwrite if needed
    SCS_FIXED1,           // use a fixed channel
    SCS_FIXED2,
    SCS_FIXED3,
    SCS_FIXED4
  );

  tSoundChannel = class
    id: word;
    sfx: tSound;   {the currently playing sound effect}
    lastUpdateVolume, lastUpdatePitch: single;
    volume: single;
    pitch: single;
    delay: tTimeCode;                     {ticks until sound starts playing}
    sampleTick: tTimeTick;                {current sample position (in ticks)}
    looping: boolean;
    constructor create(id: word);
    procedure reset();
    function  inUse(): boolean;
  end;

  tSoundMixer = class
    {handles mixing of channels}
    channels: array[1..NUM_CHANNELS] of tSoundChannel;
    noiseBuffer: array[0..64*1024] of int32; {+1 so that we can read 64bytes at a time}

    mute: boolean;
    noise: boolean;

    constructor create();
    destructor destroy(); override;
    function getFreeChannel(sfx: tSound; strategy: tSoundChannelSelection): tSoundChannel;
    function playRepeat(sfx: tSound; channelSelection: tSoundChannelSelection; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0): tSoundChannel;
    function play(sfx: tSound; volume: single=1.0; channelSelection: tSoundChannelSelection = SCS_OLDEST; pitch: single=1.0;timeOffset: single=0.0): tSoundChannel; overload;
  end;

type
  tMusicStats = record
    bufferFramesMax: integer;
    bufferFramesFilled: integer;
    bufferFramesFree: integer;
    cpuUsage: single; // as a fraction
  end;

var
  {our global mixer}
  mixer: tSoundMixer;

const
  {This is 1M of memory, or ~6 seconds}
  {todo: make this something we can configure}
  MB_LOG2SAMPLES = 18;
  MB_SAMPLES = 1 shl MB_LOG2SAMPLES;
  MB_MASK: dword = MB_SAMPLES-1;

function  mixDown(startTC: tTimeCode;bufBytes:dword): pointer;
procedure musicPlay(filename: string); overload;
procedure musicPlay(reader: tLA96Reader); overload;
procedure musicSet(reader: tLA96Reader);
procedure musicRestoreDefaultReader();
procedure musicStop();
function  musicBufferReadPos(): dword;
function  musicBufferWritePos(): dword;
function  getMusicStats(): tMusicStats;
procedure musicUpdate(maxNewFrames: integer=-1);

function  mixClickDetection(): dword;

function scratchBufferPtr: pAudioSample16S;

implementation

uses
  uKeyboard, {stub}
  crt, {also stub}
  uSBDriver;

const
  MAX_MIXER_SAMPLES = 8*1024;

var
  {global buffers and stuff}
  scratchBuffer: array[0..MAX_MIXER_SAMPLES-1] of tAudioSample16S;
  scratchBufferF32: array[0..MAX_MIXER_SAMPLES-1] of tAudioSampleF32;
  scratchBufferI32: array[0..MAX_MIXER_SAMPLES-1] of tAudioSampleI32; {$align 8}
  noiseCounter: dword;

  {todo: maybe put this in mixer? or just keep them global... yeah global is the way}
  {also, this need not be a sound effect, just a buffer as above?}
  musicBuffer: tSound;
  mbReadPos, mbWritePos: dword;
  {handles reading music.}
  musicReader: tLA96Reader; {the current one}
  masterMusicReader: tLA96Reader; {another reference to musicReader (which might get modified)}
  musicTimer: tTimer;

  // debug registers, used to indicate errors during interrupt.
  MIX_COUNTER: dword;
  MIX_ERRORS: dword;
  MIX_ERROR_STR: shortstring;
  MIX_WARNINGS: dword;
  MIX_WARNING_STR: shortstring;
  MIX_NOTES: dword;
  MIX_NOTE_STR: shortstring;
  DR1: int64 = 0;
  DR2: int64 = 0;
  DR3: int64 = 0;
  DR4: int64 = 0;
  MIX_CLICK_DETECTION: dword;

{Mixer is called during interrupt, so stack might be invalid,
 also, make sure to not throw any errors. These will get turned
 back on below}
{$S-,R-,Q-}

{$i mix_ref.inc}
{$i mix_asm.inc}
{$i mix_mmx.inc}

{-----------------------------------------------------}

function fake8Bit(value: int32): int32;
begin
  exit(value div 65536 * 65536);
end;

function fakeULAW(value: int32): int32;
var
  sign: int32;
  x,y: single;
const
  MU = 256-1;
  INV_LOG1P_MU = 0.18021017998;
begin
  if value < 0 then sign := -1 else sign := 1;
  x := value / (256*32*1024);             // normalize to -1 to 1
  y := sign * ln(1+MU*abs(x)) / ln(1+MU); // encode (output is also -1 to 1)}
  y := trunc(y*128) / 128;                // encode as 8bit, including sign
  x := sign * (power(1 + MU, abs(y)) - 1) / MU;  // decode
  result := round(x*256*32*1024);          // we're mixing in 24.8
end;

procedure mixError(msg: shortstring); inline;
begin
  inc(MIX_ERRORS);
  MIX_ERROR_STR := msg;
end;

procedure mixWarn(msg: shortstring); inline;
begin
  inc(MIX_WARNINGS);
  MIX_WARNING_STR := msg;
end;

procedure mixNote(msg: shortstring); inline;
begin
  inc(MIX_NOTES);
  MIX_NOTE_STR := msg;
end;

function mixAssertLess(value, limit: int64; msg: shortstring): boolean;
begin
  if not (value < limit) then begin
    mixError(msg);
    DR3 := value;
    DR4 := limit;
    exit(false)
  end;
  exit(true);
end;

function mixAssertGreaterOrEqual(value, limit: int64; msg: shortstring): boolean;
begin
  if not (value >= limit) then begin
    mixError(msg);
    DR3 := value;
    DR4 := limit;
    exit(false)
  end;
  exit(true);
end;

{-----------------------------------------------------}

{our big mixdown function}
{note: this can not be mixer.mixdown, as calls to
 class methods can cause crashes apparently (due to RTL being invalid)
}
function mixDown(startTC: tTimeCode;bufBytes:dword): pointer;
var
  sfx: tSound;
  i,j: int32;
  noise: int32;
  sample, finalSample: pointer;
  bufPos, bufSamples: int32;
  sampleTick, ticksPerSample: int32;
  remainingBufferSamples, chunkBufferSamples: int32;
  chunkSourceTicks, sampleTicksRemaining: int32;
  volumeChunkStart, volumeChunkEnd: single;
  channel: tSoundChannel;
  prevSample: tAudioSample16S;
  clickStrength: int32;
  sfxTicks: int64;

  processAudio: tProcessAudioProc;

  DEBUG_CHUNK_COUNTER: int32;

begin

  result := nil;

  {The budget here is about 10ms (for 8ksamples).
    Even 20MS is sort of ok, as we'd just reduce halve the block size
    and 10% CPU to audio is probably ok on a P166}

  bufSamples := bufBytes div 4;
  if bufSamples > (MAX_MIXER_SAMPLES) then exit;
  if bufSamples <= 0 then exit;
  if (mixer = nil) then exit;

  inc(MIX_COUNTER);

  {note: I'm in two minds about this,
   maybe we just always use the music buffer, and 'no music'
   just means zero it out}

  {intialize buffer with currently playing music (if any)}
  if musicReader.isLoaded then begin
    initializeBuffer_ASM(musicBuffer.data+(mbReadPos and MB_MASK)*4, bufSamples);
    {advance our position within music buffer. Since music buffer length
     is a multiple of the SB buffer, we will never up straddling the
     start/end of the buffer}
    mbReadPos += bufSamples;
  end else begin
    {this was the old method of just clearing the buffer, could do this
    if no music is playing I guess..?}
    filldword(scratchBufferI32, bufSamples * 2, 0);
  end;

  {process each active channel}
  for j := 1 to NUM_CHANNELS do begin

    if mixer.mute or mixer.noise then continue;
    channel := mixer.channels[j];

    if channel.inUse then begin

      bufPos := 0;
      remainingBufferSamples := bufSamples; // why is this needed?
      sfx := channel.sfx;
      ticksPerSample := trunc(channel.pitch*256);
      sampleTick := channel.sampleTick;
      sfxTicks := int64(sfx.length)*256;

      if sfx.length = 0 then continue; // should not happen
      if channel.volume = 0 then continue;

      // handle delay
      if channel.delay >= bufSamples then begin
        channel.delay -= bufSamples;
        continue;
      end;

      if channel.delay > 0 then begin
        {we need only delay for a portion of the buffer}
        bufPos := channel.delay;
        remainingBufferSamples -= channel.delay;
        channel.sampleTick := 256 * channel.delay;
        channel.delay := 0;
      end;

      // should not be needed, but just in case.
      if sampleTick >= sfxTicks then begin
        mixWarn('Sample tick was out of bounds ');
        if channel.looping then
          sampleTick := sampleTick mod sfxTicks
        else begin
          channel.reset();
          continue;
        end;
      end;

      if remainingBufferSamples <= 0 then continue;

      processAudio := processAudio_ASM;

      // break audio into chunks so that process need not handle looping
      DEBUG_CHUNK_COUNTER := 0;
      while remainingBufferSamples > 0 do begin

        inc(DEBUG_CHUNK_COUNTER);

        if DEBUG_CHUNK_COUNTER > 16 then begin
          // this can happen if we, for some reason, start splitting
          // audio into very small (e.g. 1 sample) chunks.
          // but it also happens if audio is very short.
          mixWarn('Too many chunks, short audio?');
          break;
        end;

        chunkBufferSamples := remainingBufferSamples;
        chunkSourceTicks := remainingBufferSamples * ticksPerSample;

        if (sampleTick + chunkSourceTicks) >= sfxTicks then begin
          // this means audio ends early within the buffer
          // so make sure this chunk ends at the boundary,
          // then we handle loop or stop later on.
          sampleTicksRemaining := sfxTicks - sampleTick;
          // round up
          chunkBufferSamples := (sampleTicksRemaining+(ticksPerSample-1)) div ticksPerSample;
        end;

        // this should never happen!
        if chunkBufferSamples <= 0 then begin
          mixWarn('chunkBufferSamples was <= 0');
          channel.sampleTick := sampleTick;
          DR3 := remainingBufferSamples;
          DR4 := chunkBufferSamples;
          break;
        end;

        DR1 := chunkBufferSamples;
        DR2 := sampleTick;

        volumeChunkStart := channel.lastUpdateVolume + (bufPos / bufSamples) * (channel.volume - channel.lastUpdateVolume);
        volumeChunkEnd := channel.lastUpdateVolume + ((bufPos + chunkBufferSamples) / bufSamples) * (channel.volume - channel.lastUpdateVolume);

        processAudio(
          sfx.format,
          sampleTick, sfx.data, sfx.length,
          bufPos, chunkBufferSamples,
          trunc(volumeChunkStart*65536), trunc(volumeChunkEnd*65536),
          ticksPerSample
        );
        sampleTick += (chunkBufferSamples * ticksPerSample);

        // handle looping
        if sampleTick >= sfxTicks then begin
          if channel.looping then begin
            sampleTick := sampleTick mod sfxTicks;
          end else begin
            // reset channel
            channel.sfx := nil;
            channel.delay := 0;
            channel.sampleTick := 0;
            break;
          end;
        end;

        bufPos += chunkBufferSamples;
        remainingBufferSamples -= chunkBufferSamples;
        channel.sampleTick := sampleTick;
      end;
    end;
  end;

  // update each channel
  for j := 1 to NUM_CHANNELS do
    with mixer.channels[j] do begin
      if volume < (1/256) then volume := 0;
      lastUpdateVolume := volume;
      lastUpdatePitch := pitch;
    end;

  {mix down}
  if mixer.mute then begin
    filldword(scratchBuffer, bufSamples, 0);
  end else if mixer.noise then begin
    for i := 0 to bufSamples-1 do begin
      noise := ((rnd + rnd) div 2) - 128;
      scratchBuffer[i].left := noise*128;
      scratchBuffer[i].right := noise*128;
    end;
  end else begin
    if cpuInfo.hasMMX then
      clipAndConvert_MMX(bufSamples)
    else
      clipAndConvert_ASM(bufSamples);
  end;

  {$ifdef DEBUG}
  {might be buggy? (202 error)}
  {
  clickStrength := clickDetection_ASM(prevSample, @scratchBuffer[0], bufSamples);
  if clickStrength > MIX_CLICK_DETECTION then
    MIX_CLICK_DETECTION := clickStrength
  else
    MIX_CLICK_DETECTION := (MIX_CLICK_DETECTION * 255) div 256;
  }
  {$endif}

  result := @scratchBuffer[0];
end;

{$S+,R+,Q+}

{-----------------------------------------------------}

function mixClickDetection(): dword;
begin
  result := MIX_CLICK_DETECTION;
end;

{converts from seconds since app launch, to timestamp code}
function secToTC(s: double): tTimeCode;
begin
  {note, we do not allow fractional samples when converting}
  result := round(s * 44100);
end;

{-----------------------------------------------------}

constructor tSoundChannel.create(id: word);
begin
  inherited create();
  self.id := id;
  reset();
end;

procedure tSoundChannel.reset();
begin
  sfx := nil;
  lastUpdateVolume := 0;
  lastUpdatePitch := 1.0;
  volume := 1.0;
  pitch := 1.0;
  delay := 0;
  sampleTick := 0;
  looping := false;
end;

function tSoundChannel.inUse(): boolean;
begin
  result := assigned(sfx);
end;

{-----------------------------------------------------}
{ Music stuff }
{-----------------------------------------------------}

{ maybe move this into mixer? }

procedure processNextMusicFrame();
begin
  if mbReadPos > mbWritePos then
    warning(format('Buffer underflow read:%d write:%d', [mbReadPos div 1024, mbWritePos div 1024]));
  assert(mbWritePos mod 1024 = 0, 'WritePos must be a multiple of frameSize');
  if not musicReader.isLoaded then exit;
  musicReader.readNextFrame(musicBuffer.data + (mbWritePos and MB_MASK) * 4);
  mbWritePos += musicReader.frameSize;
  //note(format('Processing r:%d w:%d', [mbReadPos div 1024, mbWritePos div 1024]));
end;

procedure musicUpdate(maxNewFrames: integer=-1);
var
  framesProcessed: integer;
  timer: tTimer;
  framesFilled: integer;
begin

  if not musicReader.isLoaded then begin
    //decay timer to zero
    musicTimer.avElapsed *= 0.90;
    exit;
  end;

  framesFilled := getMusicStats().bufferFramesFilled;

  if maxNewFrames < 0 then begin
    {work out how many frames to process}
    if framesFilled < 44 then
      maxNewFrames := 16
    else if framesFilled < 44*2 then
      maxNewFrames := 8
    else if framesFilled < 44*4 then
      maxNewFrames := 4
    else
      maxNewFrames := 2;
  end;

  framesProcessed := 0;
  musicTimer.start();
  while (framesProcessed < maxNewFrames) and (getMusicStats().bufferFramesFree > 0) do begin
    processNextMusicFrame();
    inc(framesProcessed);
  end;
  musicTimer.stop(musicReader.frameSize * framesProcessed);
end;

{returns pointer to scratch buffer. Use with caution}
function scratchBufferPtr: pAudioSample16S;
begin
  result := @scratchBuffer[0];
end;

function getMusicStats: tMusicStats;
var
  sbSamples: int32;
  frameSize: int32;
begin
  sbSamples := uSBDriver.HALF_BUFFER_SIZE div 4;
  frameSize := 1024; // hard code this for the moment.
  result.bufferFramesMax := (MB_SAMPLES - sbSamples) div frameSize;
  result.bufferFramesFilled := (int64(mbWritePos) - mbReadPos) div frameSize;
  result.bufferFramesFree := result.bufferFramesMax - result.bufferFramesFilled;
  result.cpuUsage := musicTimer.avElapsed / (1 / 44100);
end;

{plays background music. Music must be a compressed A96 file stored on disk.
 this involves reading the entire (compressed) file into memory and then
 decompressing the first part.}
procedure musicPlay(filename: string); overload;
begin
  info('Music play called on '+filename);
  if musicReader.isLoaded() then musicReader.close();
  mbReadPos := 0;
  mbWritePos := 0;
  musicReader.open(filename);
  {since we read the whole thing off disk, we may as well load a fair bit}
  {this should be ~10 seconds}
  musicUpdate(256);
end;

{plays background music. Music must be a compressed A96 file stored on disk.
 this involves reading the entire (compressed) file into memory and then
 decompressing the first part.}
procedure musicPlay(reader: tLA96Reader); overload;
var
  currentFrame: dword;
  i: integer;
  factor: single;
  baseOffset: dword;
  samplePtr: pAudioSample16S;
  mixerID: dword;
const
  FADE_FRAMES = 4;
  WAIT_FRAMES = 12;

  function enoughHeadroomForFade(): boolean;
  begin
    if not musicReader.isLoaded then exit(false);
    result := ((currentFrame+WAIT_FRAMES+FADE_FRAMES)*1024) <= mbWritePos;
  end;

begin
  {allow the current frame to keep, player,
   use the next frame as a fade down,
   and the one after we will start writing into}
  assert(reader.frameSize = 1024, 'Only framesize=1024 supported now');

  mixerID := MIX_COUNTER;
  currentFrame := mbReadPos div 1024;

  {if we have something already playing, it would be nice to fade it out
   this means we need to get a little bit ahead...}
  if musicReader.isLoaded and not enoughHeadroomForFade() then
    musicUpdate(FADE_FRAMES+WAIT_FRAMES);

  {apply fadeout if we can}
  if musicReader.isLoaded and enoughHeadroomForFade then begin
    note(format('Applying fade-out at frame %d (writePos=%d)', [currentFrame+WAIT_FRAMES, mbWritePos div 1024]));
    baseOffset := (currentFrame+WAIT_FRAMES)*1024;
    for i := 0 to (FADE_FRAMES*1024)-1 do begin
      factor := 1-(i/(FADE_FRAMES*1024));
      samplePtr := musicBuffer.data + ((baseOffset+i) and MB_MASK) * 4;
      samplePtr^.left := round(samplePtr^.left * factor);
      samplePtr^.right := round(samplePtr^.right * factor);
      inc(samplePtr);
    end;
    mbWritePos := (currentFrame+WAIT_FRAMES+FADE_FRAMES) * 1024;
    note(format('Setting writePos to frame %d', [mbWritePos div 1024]));
  end else begin
    if musicReader.isLoaded then
      warning(format('Not enough buffer for fade out (read: %d write %d), performing hard cut', [currentFrame, mbWritePos div 1024]))
    else
      note('performing hard cut as there was no previous track');
    mbWritePos := (currentFrame + 1) * 1024;
  end;

  musicReader := reader;
  {quickly get a sample (incase interrupt fires on next line}
  note(format('about to generate samples %d %d/%d', [mbWritePos div 1024, getMusicStats().bufferFramesFilled, getMusicStats().bufferFramesFree]));
  musicUpdate(4);
  note(format('done generating samples %d %d/%d', [mbWritePos div 1024, getMusicStats().bufferFramesFilled, getMusicStats().bufferFramesFree]));

  {fade up... so silly, does music have a click or something?}
  if true then begin
    note(format('Applying fade-in at frame %d (writePos=%d)', [currentFrame+WAIT_FRAMES+FADE_FRAMES, mbWritePos div 1024]));
    baseOffset := (currentFrame+WAIT_FRAMES+FADE_FRAMES)*1024;
    for i := 0 to (1*1024)-1 do begin
      factor := i/(1*1024);
      samplePtr := musicBuffer.data + ((baseOffset+i) and MB_MASK) * 4;
      samplePtr^.left := round(samplePtr^.left * factor);
      samplePtr^.right := round(samplePtr^.right * factor);
      inc(samplePtr);
    end;
  end;

  if MIX_COUNTER <> mixerID then warning(format('Warning, looks like IRQ was fired during this update, %d <> %d', [mixerID, MIX_COUNTER]));

  {then get a few to keep us going}
  musicUpdate(40);

  //musicBuffer.saveToWave('temp.wav');

end;

{This is a bit dodgy, but set the music reader directly.
 This can be used to quickly switch between different compressed
 sources (e.g. for AB testing)
 Call musicRestoreDefaultReader() to restore the default one.
 Note: this keeps all readers in sync, so good for switching between
 sources to check audio differences
 }
procedure musicSet(reader: tLA96Reader);
begin
  mbWritePos := mbReadPos + 1024;
  musicReader := reader;
  reader.seek(mbWritePos div reader.frameSize);
  {just need a few frames to keep us going}
  musicUpdate(4);
end;

function musicBufferReadPos(): dword;
begin
  result := mbReadPos and MB_MASK;
end;

function musicBufferWritePos(): dword;
begin
  result := mbWritePos and MB_MASK;
end;

procedure musicRestoreDefaultReader();
begin
  musicSet(masterMusicReader);
end;

procedure musicStop();
begin
  info('Music stop called.');
  mbReadPos := 0;
  mbWritePos := 0;
  musicReader.close();
  {todo: either fade out the buffer, or just cut it?}
  fillchar(musicBuffer.data^, musicBuffer.length*4, 0);
end;
{-----------------------------------------------------}

constructor tSoundMixer.create();
var
  i: integer;
begin
  mute := false;
  noise := false;
  for i := 1 to NUM_CHANNELS do
    channels[i] := tSoundChannel.create(i);
  for i := 0 to length(noiseBuffer)-1 do begin
    noiseBuffer[i] := ((random(256) + random(256)) div 2) - 128;
  end;
end;

destructor tSoundMixer.destroy();
var
  i: integer;
begin
  for i := 1 to NUM_CHANNELS do
    channels[i].free;
  inherited destroy();
end;

{returns a channel to use for given sound}
function tSoundMixer.getFreeChannel(sfx: tSound; strategy: tSoundChannelSelection): tSoundChannel;
var
  i: integer;
  bestIndex: integer;
  bestScore: int64;
  score: int64;

begin

  case strategy of
    SCS_SELFOVERWRITE: begin
      for i := 1 to NUM_CHANNELS do
        if channels[i].sfx = sfx then
          exit(channels[i]);
      exit(getFreeChannel(sfx, SCS_OLDEST));
    end;
    SCS_NEXTFREE: begin
      for i := 1 to NUM_CHANNELS do
        if not channels[i].inUse then
          exit(channels[i]);
      exit(nil);
    end;
    SCS_OLDEST: begin
      {look for free channel, if none found use the one that's been
       playing the longest}
      bestIndex :=  -1;
      bestScore := -1;
      for i := 1 to NUM_CHANNELS do begin
        if not channels[i].inUse then
          exit(channels[i])
        else
          score := channels[i].sampleTick;
        if score > bestScore then begin
          bestScore := score;
          bestIndex := i;
        end;
      end;
      exit(channels[bestIndex]);
    end;
    SCS_FIXED1: exit(channels[1]);
    SCS_FIXED2: exit(channels[2]);
    SCS_FIXED3: exit(channels[3]);
    SCS_FIXED4: exit(channels[4]);
    else fatal('Invalid sound channel selection strategoy');
  end;
end;

function tSoundMixer.playRepeat(sfx: tSound; channelSelection: tSoundChannelSelection; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0): tSoundChannel;
var
  channel: tSoundChannel;
begin
  channel := play(sfx, volume, channelSelection, pitch, timeOffset);
  if assigned(channel) then
    channel.looping := true;
  result := channel;
end;

function tSoundMixer.play(sfx: tSound; volume: single=1.0; channelSelection: tSoundChannelSelection = SCS_OLDEST; pitch: single=1.0;timeOffset: single=0.0): tSoundChannel;
var
  ticksOffset: int32;
  offsetString: string;
begin

  {for the moment lock onto the first channel}
  if not assigned(sfx) then
    fatal('Tried to play invalid sound file');

  {find a slot to use}
  result := getFreeChannel(sfx, channelSelection);
  if not assigned(result) then begin
    //note(format('playing %s but no free channels', [sfx.toString] ));
    exit;
  end;

  if timeOffset <> 0 then
    offsetString := format(' (%.2fs)', [timeOffset])
  else
    offsetString := '';
  //note(format('playing %s channel %d%s', [sfx.toString, result.id, offsetString]));

  ticksOffset := round(timeOffset*44100);

  // we don't want channel to be in an invalid state when interrupt occurs.
  asm
    cli
  end;

  result.sfx := sfx;
  result.volume := volume;
  result.pitch := pitch;
  result.delay := ticksOffset;
  result.sampleTick := 0;
  result.looping := false;

  asm
    sti
  end;

end;

procedure initMixer();
begin
  note('[init] Mixer');
  if not lock_data(scratchBuffer, sizeof(scratchBuffer)) then
    warning('Could not lock mixer buffer. Audio might stutter.' );
  if not lock_data(scratchBufferF32, sizeof(scratchBufferF32)) then
    warning('Could not lock mixer buffer. Audio might stutter.' );
  if not lock_data(scratchBufferI32, sizeof(scratchBufferI32)) then
    warning('Could not lock mixer buffer. Audio might stutter.' );
end;

procedure closeMixer();
begin
  note('[close] Mixer');
  if MIX_WARNINGS > 0 then
    warning(format(' - %d warnings occured, the last of which was: %s', [MIX_WARNINGS, MIX_WARNING_STR]));
  if MIX_ERRORS > 0 then
    warning(format(' - %d errors occured, the last of which was: %s', [MIX_ERRORS, MIX_ERROR_STR]));
  if MIX_NOTE_STR <> '' then
    note(' - last note:' + MIX_NOTE_STR);
  note(' - DR1:' + intToStr(DR1));
  note(' - DR2:' + intToStr(DR2));
  note(' - DR3:' + intToStr(DR3));
  note(' - DR4:' + intToStr(DR4));
  unlock_data(scratchBuffer, sizeof(scratchBuffer));
  unlock_data(scratchBufferF32, sizeof(scratchBufferF32));
  unlock_data(scratchBufferI32, sizeof(scratchBufferI32));
end;

initialization

  musicTimer := tTimer.create('music');

  mbReadPos := 0;
  mbWritePos := 0;

  MIX_CLICK_DETECTION := 0;
  MIX_COUNTER := 0;

  {music buffer must no smaller than SB buffer, and if larger, be a multiple}
  assert((MB_SAMPLES mod (BUFFER_SIZE div 4)) = 0);
  assert(MB_SAMPLES >= (BUFFER_SIZE div 4));

  mixer := tSoundMixer.create();
  musicBuffer := tSound.create(AF_16_STEREO, MB_SAMPLES);
  masterMusicReader := tLA96Reader.create();
  masterMusicReader.looping := true;
  musicReader := masterMusicReader;

  initMixer();

finalization

  {wait for music to close...}
  closeMixer();
  delay(500);

  musicTimer.free;
  musicBuffer.free;
  musicReader.free;
  mixer.free;
  { we might not own the musicReader, so don't free it... }
  //if assigned(masterMusicReader) then masterMusicReader.free;

end.
