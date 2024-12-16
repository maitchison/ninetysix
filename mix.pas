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
    offset: tTimeCode;       {when the sound should start playing}
    loop: boolean;
    constructor create();
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
  scratchBufferI32: array[0..8*1024-1] of tAudioSampleI32; {$ALIGN 8}

{-----------------------------------------------------}
{our big mixdown function}
{note: this can not be mixer.mixdown, as calls to
 class methods can cause crashes apparently (due to RTL being invalid)
}

{$S-,R-,Q-}

procedure clipAndConvert_MMX(bufSamples:int32);
var
  srcPtr, dstPtr, noisePtr: pointer;
  FPUState: array[0..108-1] of byte; {$ALIGN 16}
begin

  srcPtr := @scratchBufferI32[0];
  dstPtr := @scratchBuffer[0];
  noisePtr := @mixer.noiseBuffer[0];

  asm

    add noiseCounter, 1997

    pushad

    lea eax, FPUState
    fsave [eax]

    mov ecx, bufSamples
    mov esi, srcPtr
    mov edi, dstPtr

  @LOOP:

    {noise}
    mov ebx, noiseCounter
    and ebx, $FFFF
    shl ebx, 2
    add ebx, noisePtr
    movq mm1, qword ptr [ebx]

    add noiseCounter, 97

    {convert and clip}
    movq   mm0, [esi]            // mm0 = LEFT|RIGHT
    paddd mm0, mm1              // mm0 = LEFT+noise|RIGHT+noise}
    psrad  mm0, 8                // mm0 = (LEFT+noise)/256|(RIGHT+noise)/256
    packssdw mm0, mm0            // mm0 = left|right|left|right (16bit)

    movd [edi], mm0

    add esi, 8
    add edi, 4
    dec ecx
    jnz @LOOP

    lea eax, FPUState
    frstor [eax]

    popad

  end;

end;

procedure clipAndConvert_REF(bufSamples:int32);
var
  i: int32;
  left,right: int32;
  noise: int32;
begin
   for i := 0 to bufSamples-1 do begin
     {adding triangle noise to reduce quantization distortion}
     {costs 2ms, for 8ks samples, but I think it's worth it}
     noise := ((rnd + rnd) div 2) - 128;
    left := (scratchBufferI32[i].left + noise) div 256;
    right := (scratchBufferI32[i].right + noise) div 256;
    if left > 32767 then left := 32767 else if left < -32768 then left := -32768;
    if right > 32767 then right := 32767 else if right < -32768 then right := -32768;
    scratchBuffer[i].left := left;
    scratchBuffer[i].right := right;
   end;
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

function fake8Bit(value: int32): int32;
begin
  exit(value div 65536 * 65536);
end;

function mixDown(startTC: tTimeCode;bufBytes:dword): pointer;
var
  sfx: tSoundEffect;
  i,j: int32;
  noise: int32;
  pos,len: int32;
  sample,lastSample: pAudioSample;
  bufSamples: int32;

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
    if assigned(mixer.channel[j].soundEffect) then begin
      sfx := mixer.channel[j].soundEffect;
      len := sfx.length;
      if len <= 0 then continue;

      {todo: support this case, this just means audio plays later, perhaps
       even within this chunk}
      if (startTC - mixer.channel[j].offset < 0) then continue;

      pos := (startTC - mixer.channel[j].offset) mod len;
      sample := pointer(sfx.sample) + (pos * 4);
      lastSample := pointer(sfx.sample) + (len * 4);
      for i := 0 to bufSamples-1 do begin
        scratchBufferI32[i].left += sample^.left*256;
        scratchBufferI32[i].right += sample^.right*256;
        inc(sample);
        if sample >= lastSample then
          sample := pointer(sfx.sample)
      end;
    end;
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
    clipAndConvert_MMX(bufSamples);
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
  soundEffect := nil;
  volume := 1.0;
  pitch := 1.0;
  offset := 0;
  loop := false;
end;

procedure tSoundChannel.play(soundEffect: tSoundEffect; volume:single; pitch: single;startTime:tTimeCode; loop: boolean=false);
begin
  self.soundEffect := soundEffect;
  self.volume := volume;
  self.pitch := pitch;
  self.offset := startTime;
  self.loop := loop;
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
begin
  {for the moment lock onto the first channel}
  if not assigned(soundEffect) then
    error('Tried to play invalid sound file');
  note('playing sound!  <<--------- self='+hexStr(@self));
  channelNum := 1;
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
