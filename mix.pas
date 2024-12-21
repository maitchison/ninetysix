{unit to handle sound mixing}
unit mix;

{$MODE delphi}

interface

uses
  test,
  debug,
  utils,
  sound,
  go32;

CONST
  NUM_CHANNELS = 4;

type

  tSoundChannelSelection = (
    SCS_SELFOVERWRITE,    // overwrite is sound is already playing,
                          // otherwise next free
    SCS_NEXTFREE,         // find the next free channel
    SCS_FIXED1,           // use a fixed channel
    SCS_FIXED2,
    SCS_FIXED3,
    SCS_FIXED4
  );

  tSoundChannel = class
    id: word;
    sfx: tSoundEffect;   {the currently playing sound effect}
    lastUpdateVolume, lastUpdatePitch: single;
    volume: single;
    pitch: single;
    startTC: tTimeCode;       {when the sound starts playing}
    looping: boolean;
    constructor create(id: word);
    procedure reset();
    function  endTC(): tTimeCode;         {when the sound stops playing (if no looping)}
    function  inUse(): boolean;
    procedure update(currentTC: tTimeCode);
    procedure play(sfx: tSoundEffect; volume:single; pitch: single;startTime:tTimeCode);
  end;

  tSoundMixer = class
    {handles mixing of channels}
    channels: array[1..NUM_CHANNELS] of tSoundChannel;
    noiseBuffer: array[0..64*1024] of int32; {+1 so that we can read 64bytes at a time}

    mute: boolean;
    noise: boolean;

    constructor create();
    function getFreeChannel(sfx: tSoundEffect; strategy: tSoundChannelSelection): tSoundChannel;
    function playRepeat(sfx: tSoundEffect; channelSelection: tSoundChannelSelection; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0): tSoundChannel;
    function play(sfx: tSoundEffect; channelSelection: tSoundChannelSelection = SCS_NEXTFREE; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0): tSoundChannel;
  end;

var
  {our global mixer}
  mixer: tSoundMixer = nil;

function mixDown(startTC: tTimeCode;bufBytes:dword): pointer;

implementation

uses
  keyboard, {stub}
  sbdriver;

var
  scratchBuffer: array[0..8*1024-1] of tAudioSample;
  scratchBufferF32: array[0..8*1024-1] of tAudioSampleF32;
  scratchBufferI32: array[0..8*1024-1] of tAudioSampleI32; {$align 8}
  noiseCounter: dword;

{Mixer is called during interupt, so stack might be invalid,
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

{-----------------------------------------------------}

{our big mixdown function}
{note: this can not be mixer.mixdown, as calls to
 class methods can cause crashes apparently (due to RTL being invalid)
}
function mixDown(startTC: tTimeCode;bufBytes:dword): pointer;
var
  sfx: tSoundEffect;
  i,j: int32;
  noise: int32;
  sample, finalSample: pointer;
  bufPos, bufSamples: int32;
  samplePos, remainingBufferSamples, chunkBufferSamples: int32;
  bufferSamplesRequiredToCatchUp,chunkSourceSamples: int32;
  channel: tSoundChannel;

  pitchVel: int32; // (sfx samples per buffer sample) * 256

  processAudio: tProcessAudioProc;

begin

  result := nil;

  {The budget here is about 10ms (for 8ksamples).
    Even 20MS is sort of ok, as we'd just reduce halve the block size
    and 10% CPU to audio is probably ok on a P166}

  bufSamples := bufBytes div 4;
  if bufSamples > (8*1024) then exit;
  if bufSamples <= 0 then exit;
  if (mixer = nil) then exit;

  filldword(scratchBufferI32, bufSamples * 2, 0);

  {process each active channel}
  for j := 1 to NUM_CHANNELS do begin

    if mixer.mute or mixer.noise then continue;

    channel := mixer.channels[j];

    if channel.inUse then begin

      sfx := channel.sfx;
      if sfx.length = 0 then continue; // should not happen
      if channel.volume = 0 then continue;

      pitchVel := trunc(256*channel.pitch);

      {todo: have sub sample precision for samplePos
       - this means all process functions bellow must support it}
      samplePos := (startTC - channel.startTC) * pitchVel div 256;
      if samplePos > 0 then samplePos := samplePos mod sfx.length;
      remainingBufferSamples := bufSamples;

      bufPos := 0;

      if samplePos < 0 then begin
        // this means sample starts partway in this buffer.
        bufferSamplesRequiredToCatchUp := -samplePos * 256 div pitchVel;
        bufPos := bufferSamplesRequiredToCatchUp;
        samplePos := 0;
        remainingBufferSamples -= bufferSamplesRequiredToCatchUp;
      end;

      if remainingBufferSamples <= 0 then continue;

      if samplePos >= sfx.length then begin
        if channel.looping then
          samplePos := samplePos mod sfx.length
        else
          continue;
      end;

      case sfx.format of
        // stub: support asm again
        AF_16_STEREO: processAudio:= process16S_ASM;
        AF_16_MONO: processAudio:= process16M_REF;
        // stub: support 8bit again
        //AF_8_STEREO: process8S_REF(sample, sfx.data, finalSample, bufSamples);
        else continue; // ignore error as we're in an interupt.
      end;

      // break audio into chunks such that...
      // - process need not handle looping
      // - volume is linear within chunk

      while remainingBufferSamples > 0 do begin
        chunkBufferSamples := remainingBufferSamples;
        if (samplePos + chunkBufferSamples) >= sfx.length then
          // this means audio ends early within the buffer
          chunkBufferSamples := sfx.length - samplePos;
        processAudio(
          samplePos, sfx.data, sfx.length,
          bufPos, chunkBufferSamples,
          trunc(channel.lastUpdateVolume*65536), trunc(channel.volume*65536),
          trunc(channel.pitch*256)
        );
        chunkSourceSamples := chunkBufferSamples * 256 div pitchVel;
        samplePos := (samplePos + chunkSourceSamples) mod sfx.length;
        bufPos += chunkBufferSamples;
        remainingBufferSamples -= chunkBufferSamples;
      end;
    end;
  end;

  for j := 1 to NUM_CHANNELS do
    mixer.channels[j].update(startTC);

  {stub: simulate 8 bit}
  if keyDownNoCheck(key_8) then
    for i := 0 to bufSamples-1 do begin
      scratchBufferI32[i].left := fake8Bit(scratchBufferI32[i].left);
      scratchBufferI32[i].right := fake8Bit(scratchBufferI32[i].right);
    end;
  {stub: simulate u-law}
  if keyDownNoCheck(key_u) then
    for i := 0 to bufSamples-1 do begin
      scratchBufferI32[i].left := fakeULAW(scratchBufferI32[i].left);
      scratchBufferI32[i].right := fakeULAW(scratchBufferI32[i].right);
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

  result := @scratchBuffer[0];
end;

{$S+,R+,Q+}


{-----------------------------------------------------}

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
  startTC := 0;
  looping := false;
end;

procedure tSoundChannel.update(currentTC: tTimeCode);
begin
  // we can't really process a volume this quite, so just mute.
  if volume < (1/256) then volume := 0;
  lastUpdateVolume := volume;
  lastUpdatePitch := pitch;
  if inUse and (not looping) then begin
    if currentTC >= endTC then
      reset();
  end;
end;

function tSoundChannel.endTC(): tTimeCode;         {when the sound stops playing (if no looping)}
begin
  if inUse then
    result := startTC + sfx.length
  else
    result := startTC;
end;

function tSoundChannel.inUse(): boolean;
begin
  result := assigned(sfx);
end;

procedure tSoundChannel.play(sfx: tSoundEffect; volume:single; pitch: single;startTime:tTimeCode);
begin
  self.sfx := sfx;
  self.volume := volume;
  self.pitch := pitch;
  self.startTC := startTime;
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

{returns a channel to use for given sound}
function tSoundMixer.getFreeChannel(sfx: tSoundEffect; strategy: tSoundChannelSelection): tSoundChannel;
var
  i: integer;
begin
  case strategy of
    SCS_SELFOVERWRITE:
      //NIY
      exit(nil);
    SCS_NEXTFREE: begin
      for i := 1 to NUM_CHANNELS do
        if not channels[i].inUse then
          exit(channels[i]);
      exit(nil);
      end;
    SCS_FIXED1: exit(channels[1]);
    SCS_FIXED2: exit(channels[2]);
    SCS_FIXED3: exit(channels[3]);
    SCS_FIXED4: exit(channels[4]);
    else error('Invalid sound channel selection strategoy');
  end;
end;

function tSoundMixer.playRepeat(sfx: tSoundEffect; channelSelection: tSoundChannelSelection; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0): tSoundChannel;
var
  channel: tSoundChannel;
begin
  channel := play(sfx, channelSelection, volume, pitch, timeOffset);
  if assigned(channel) then
    channel.looping := true;
  result := channel;
end;

function tSoundMixer.play(sfx: tSoundEffect; channelSelection: tSoundChannelSelection = SCS_NEXTFREE; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0): tSoundChannel;
var
  ticksOffset: int32;
  offsetString: string;
begin

  {for the moment lock onto the first channel}
  if not assigned(sfx) then
    error('Tried to play invalid sound file');

  {find a slot to use}
  result := getFreeChannel(sfx, channelSelection);
  if not assigned(result) then begin
    note(format('playing %s but no free channels', [sfx.toString] ));
    exit;
  end;

  if timeOffset <> 0 then
    offsetString := format(' (%.2fs)', [timeOffset])
  else
    offsetString := '';
  note(format('playing %s channel %d%s', [sfx.toString, result.id, offsetString]));

  ticksOffset := round(timeOffset*44100);
  result.play(sfx, volume, pitch, sbDriver.currentTC+ticksOffset);
  result.looping := false;
end;

procedure initMixer();
begin
  note('[init] Mixer');
  if not lock_data(scratchBuffer, sizeof(scratchBuffer)) then
    warn('Could not lock mixer buffer. Audio might stutter.' );
  if not lock_data(scratchBufferF32, sizeof(scratchBufferF32)) then
    warn('Could not lock mixer buffer. Audio might stutter.' );
  if not lock_data(scratchBufferI32, sizeof(scratchBufferI32)) then
    warn('Could not lock mixer buffer. Audio might stutter.' );
end;

procedure closeMixer();
begin
  note('[close] Mixer');
  unlock_data(scratchBuffer, sizeof(scratchBuffer));
  unlock_data(scratchBufferF32, sizeof(scratchBufferF32));
  unlock_data(scratchBufferI32, sizeof(scratchBufferI32));
end;

begin
  mixer := tSoundMixer.create();
  initMixer();
  addExitProc(closeMixer);
end.
