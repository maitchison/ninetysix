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
  	function getSample(tc: tTimeCode): tAudioSample;
  end;


  tSoundMixer = class
    {handles mixing of channels}
    channel: array[1..NUM_CHANNELS] of tSoundChannel;

    constructor create();
    procedure play(soundEffect: tSoundEffect; volume: single=1.0; pitch: single=1.0;timeOffset: single=0.0);

  end;


var
	{our global mixer}
	mixer: tSoundMixer = nil;

function mixDown(startTC: tTimeCode;bufBytes:dword): pointer;

implementation

uses
	sbdriver;

var
  scratchBuffer: array[0..8*1024-1] of tAudioSample;
  scratchBufferF32: array[0..8*1024-1] of tAudioSampleF32;
  scratchBufferI32: array[0..8*1024-1] of tAudioSampleI32;

	BAD_ES_COUNTER: dword = 0;

{-----------------------------------------------------}
{our big mixdown function}
{note: this can not be mixer.mixdown, as calls to
 class methods can cause crashes apparently (due to RTL being invalid)
}

{$S-,R-,Q-}
function mixDown(startTC: tTimeCode;bufBytes:dword): pointer;
var
	numSamples: int32;
  sfx: tSoundEffect;
  i,j: int32;
	currentDS, currentES: word;
  volume: single = 0.49;
  noise: int32;
  pos,len: int32;
begin

	result := nil;

	{The budget here is about 10ms (for 8ksamples).
  	Even 20MS is sort of ok, as we'd just reduce halve the block size
    and 10% CPU to audio is probably ok on a P166}

  asm
    mov [currentES], es
    mov [currentDS], ds
  end;

  {pascal expects es and ds to be set to to start of linear space,
   if they do not match, then someone has modified them when the
   interupt was fired. In this case some functions (e.g. fillchar)
   will not work, so just exit.}
  if (currentES <> currentDS) then begin
  	inc(BAD_ES_COUNTER);
  	exit;
  end;

  numSamples := bufBytes div 4;
  if numSamples > (8*1024) then exit;
  if (mixer = nil) then exit;

  fillchar(scratchBufferI32, sizeof(scratchBufferI32), 0);

  {process each active channel}
  for j := 1 to NUM_CHANNELS do begin
	  if (mixer.channel[j].soundEffect <> nil) then begin
			sfx := mixer.channel[j].soundEffect;
      len := length(sfx.sample);
      pos := startTC mod len;
	  	for i := 0 to numSamples-1 do begin
        scratchBufferI32[i].left += int32(sfx.sample[pos].left)*256;
    	  scratchBufferI32[i].right += int32(sfx.sample[pos].right)*256;
        inc(pos);
        if pos > len then pos := 0; {looping}
	    end;
	  end;
  end;

  {mix down}
  for i := 0 to numSamples-1 do begin
  	{adding triangle noise to reduce quantization distortion}
    {costs 2ms, for 8ks samples, but I think it's worth it}
    noise := ((rnd + rnd) div 2) - 128;
		scratchBuffer[i].left := (scratchBufferI32[i].left + noise) div 256;
		scratchBuffer[i].right := (scratchBufferI32[i].right + noise) div 256;    	
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

function tSoundChannel.getSample(tc: tTimeCode): tAudioSample;
begin
	{todo: remove this and have the channel handle it (faster}
	result.value := 0;
	if tc < 0 then exit;
  if tc >= length(soundEffect.sample) then exit;
	result := soundEffect.sample[tc];
end;


{-----------------------------------------------------}

constructor tSoundMixer.create();
var
	i: integer;
begin
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

(*
procedure tSoundEffect.play();
begin
  if not assigned(mix.mixer) then
  	error('Mixer has not yet been created.');
  note('playing sound!  <<---------');
 	mixer.channel[1].soundEffect := self;	
end;
*)


(*
{generate mix for given time}
{$S-,R-,Q-}
procedure tSoundMixer.mixDown(startTC: tTimeCode;var buf: array of tAudioSample);
var
	leftF32, rightF32: single;
  left16, right16: word;
  i,j: int32;
  numSamples: int32;
  sample: tAudioSample;
begin

	numSamples := length(buf);

  for i := 0 to numSamples-1 do begin

  	leftF32 := 0; rightF32 := 0;

		for j := 1 to NUM_CHANNELS do begin
  		if not assigned(channel[j].soundEffect) then continue;
      {sample := channel[j].getSample(channel[j].startTime-startTC+i);}
      sample.left := rnd*64;
      sample.right := rnd*64;
      leftF32 += sample.left;
      rightF32 += sample.right;
	  end;

    sample.left := clamp(round(leftF32), -32768, 32767);
    sample.right := clamp(round(rightF32), -32768, 32767);
    buf[i] := sample;
  end;
end;
{$S+,R+,Q+}
*)

procedure closeMixer();
begin
	note('[close] Mixer');
  if BAD_ES_COUNTER > 0 then begin
  	warn(format(' - BAD_ES_COUNTER non-zero %d',[BAD_ES_COUNTER]));
  	sbdriver.directNoise(0.5);
  end;
end;

begin
  mixer := tSoundMixer.create();
  addExitProc(closeMixer);
end.
