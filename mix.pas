{unit to handle sound mixing}
unit mix;

{$MODE delphi}

interface

uses
	test,
  debug,
  utils,
	sound;

CONST
  NUM_CHANNELS = 4;

type

	tSoundChannel = class
		soundEffect: tSoundEffect; 	{the currently playing sound effect}
    volume: single;
    pitch: single;
    startTime: tTimeCode;      {when the sound should start playing}
    loop: boolean;
    constructor create();
		procedure play(soundEffect: tSoundEffect; volume:single; pitch: single;startTime:tTimeCode; loop: boolean=false);
  end;


  tSoundMixer = class
    {handles mixing of channels}
    channel: array[1..NUM_CHANNELS] of tSoundChannel;

    mute: boolean;
    noise: boolean;

    constructor create();
    procedure play(soundEffect: tSoundEffect; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0);

  end;


var
	{our global mixer}
	mixer: tSoundMixer = nil;

  inIRQ: boolean = false;

function mixDown(startTC: tTimeCode;bufBytes:dword): pointer;

implementation

uses
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
	srcPtr, dstPtr: pointer;
  FPUState: array[0..108-1] of byte; {$ALIGN 16}
begin

	srcPtr := @scratchBufferI32[0];
	dstPtr := @scratchBuffer[0];

	asm
  	pushad


    lea eax, FPUState
    fsave [eax]

  	mov ecx, bufSamples
    mov esi, srcPtr
    mov edi, dstPtr

  @LOOP:

  	{noise}
  	xor ebx, ebx
  	call rnd
    shr al, 1
    add bl, al
    call rnd
    shr al, 1
    add bl, al
    sub ebx, 128								// ebx = noise
    movd mm1, ebx
    punpckldq mm1, mm1					// mm1 = noise|noise

    {convert and clip}
    movq 	mm0, [esi]						// mm0 = LEFT|RIGHT
    paddd mm0, mm1							// mm0 = LEFT+noise|RIGHT+noise}
    psrad	mm0, 8								// mm0 = (LEFT+noise)/256|(RIGHT+noise)/256
    packssdw mm0, mm0						// mm0 = left|right|left|right (16bit)

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
      pos := startTC mod len;
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
  startTime := 0;
  loop := false;		
end;

procedure tSoundChannel.play(soundEffect: tSoundEffect; volume:single; pitch: single;startTime:tTimeCode; loop: boolean=false);
begin
	self.soundEffect := soundEffect;
  self.volume := volume;
  self.pitch := pitch;
	self.startTime := startTime;
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
end;

procedure tSoundMixer.play(soundEffect: tSoundEffect; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0);
var
	channelNum: integer;
begin
	{for the moment lock onto the first channel}
  if not assigned(soundEffect) then
  	error('Tried to play invalid sound file');
  note('playing sound!  <<--------- self='+hexStr(@self));
  channelNum := 1;
	channel[channelNum].play(soundEffect, volume, pitch, secToTC(getSec+timeOffset));
end;

procedure closeMixer();
begin
	note('[close] Mixer');
end;

begin
  mixer := tSoundMixer.create();
  addExitProc(closeMixer);
end.
