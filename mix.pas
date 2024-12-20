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

  tSoundChannel = class
    soundEffect: tSoundEffect;   {the currently playing sound effect}
    volume: single;
    pitch: single;
    startTC: tTimeCode;       {when the sound starts playing}
    looping: boolean;
    constructor create();
    procedure reset();
    function  endTC(): tTimeCode;         {when the sound stops playing (if no looping)}
    function  inUse(): boolean;
    procedure update(currentTC: tTimeCode);
    procedure play(soundEffect: tSoundEffect; volume:single; pitch: single;startTime:tTimeCode; loop: boolean=false);
  end;

  tSoundMixer = class
    {handles mixing of channels}
    channel: array[1..NUM_CHANNELS] of tSoundChannel;
    noiseBuffer: array[0..64*1024] of int32; {+1 so that we can read 64bytes at a time}

    mute: boolean;
    noise: boolean;

    constructor create();
    procedure play(soundEffect: tSoundEffect; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0);
  end;

var
  {our global mixer}
  mixer: tSoundMixer = nil;

  inIRQ: boolean = false;

  noiseCounter: dword;

function mixDown(startTC: tTimeCode;bufBytes:dword): pointer;

implementation

uses
  keyboard, {stub}
  sbdriver;

var
  scratchBuffer: array[0..8*1024-1] of tAudioSample;
  scratchBufferF32: array[0..8*1024-1] of tAudioSampleF32;
  scratchBufferI32: array[0..8*1024-1] of tAudioSampleI32; {$align 8}

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
  bufSamples: int32;
  pos: int32;

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

    if mixer.channel[j].inUse then begin
      sfx := mixer.channel[j].soundEffect;
      if sfx.length = 0 then exit;
      pos := (startTC - mixer.channel[j].startTC) mod sfx.length;
      case sfx.format of
        // stub: support asm again
        AF_16_STEREO: process16S_REF(
          pos, sfx.data, sfx.length, bufSamples,
          mixer.channel[j].looping
        );
        // stub: support 8bit again
        //AF_8_STEREO: process8S_REF(sample, sfx.data, finalSample, bufSamples);
        else ; // ignore error as we're in an interupt.
      end;
    end;

    mixer.channel[j].update(startTC);

  end;

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

constructor tSoundChannel.create();
begin
  inherited create;
  reset();
end;

procedure tSoundChannel.reset();
begin
  soundEffect := nil;
  volume := 1.0;
  pitch := 1.0;
  startTC := 0;
  looping := false;
end;

procedure tSoundChannel.update(currentTC: tTimeCode);
begin
  if inUse and (not looping) then begin
    if currentTC >= endTC then
      reset();
  end;
end;

function tSoundChannel.endTC(): tTimeCode;         {when the sound stops playing (if no looping)}
begin
  if inUse then
    result := startTC + soundEffect.length
  else
    result := startTC;
end;

function tSoundChannel.inUse(): boolean;
begin
  result := assigned(soundEffect);
end;

procedure tSoundChannel.play(soundEffect: tSoundEffect; volume:single; pitch: single;startTime:tTimeCode; loop: boolean=false);
begin
  self.soundEffect := soundEffect;
  self.volume := volume;
  self.pitch := pitch;
  self.startTC := startTime;
  self.looping := loop;
end;

{-----------------------------------------------------}

constructor tSoundMixer.create();
var
  i: integer;
begin
  mute := false;
  noise := false;
  for i := 1 to NUM_CHANNELS do
    channel[i] := tSoundChannel.create();
  for i := 0 to length(noiseBuffer)-1 do begin
    noiseBuffer[i] := ((random(256) + random(256)) div 2) - 128;
  end;
end;

procedure tSoundMixer.play(soundEffect: tSoundEffect; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0);
var
  channelNum: integer;
  ticksOffset: int32;
  i: integer;
begin
  {for the moment lock onto the first channel}
  if not assigned(soundEffect) then
    error('Tried to play invalid sound file');

  {find a slot to use}
  channelNum := -1;
  for i := 1 to NUM_CHANNELS do begin
    if not channel[i].inUse then begin
      channelNum := i;
      break;
    end;
  end;

  // no free channels
  if channelNum < 0 then exit;

  ticksOffset := round(timeOffset*44100);
  channel[channelNum].play(soundEffect, volume, pitch, sbDriver.currentTC+ticksOffset);
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
