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
  scratchBufferI32: array[0..8*1024-1] of tAudioSampleI32;

{-----------------------------------------------------}
{our big mixdown function}
{note: this can not be mixer.mixdown, as calls to
 class methods can cause crashes apparently (due to RTL being invalid)
}

{$S-,R-,Q-}
function mixDown(startTC: tTimeCode;bufBytes:dword): pointer;
var
  sfx: tSoundEffect;
  i,j: int32;
  volume: single = 0.49;
  noise: int32;
  pos,len: int32;
  sample: pAudioSample;
	bufSamples: int32;

begin

	result := nil;

	{The budget here is about 10ms (for 8ksamples).
  	Even 20MS is sort of ok, as we'd just reduce halve the block size
    and 10% CPU to audio is probably ok on a P166}

  bufSamples := bufBytes div 4;
  if bufSamples > (8*1024) then exit;
  if (mixer = nil) then exit;

  (*
	for i := 0 to numSamples-1 do begin
  	scratchBufferI32[i].left := 0;
  	scratchBufferI32[i].right := 0;
  end;*)

  	{fillchar does not work?}
  filldword(scratchBufferI32, bufSamples * 2, 0);

  {process each active channel}
  for j := 1 to NUM_CHANNELS do begin
	  if assigned(mixer.channel[j].soundEffect) then begin
			sfx := mixer.channel[j].soundEffect;
      len := sfx.length;
      if len <= 0 then continue;
      pos := startTC mod len;
	  	for i := 0 to bufSamples-1 do begin
      	sample := pointer(sfx.sample) + (pos * 4);
        scratchBufferI32[i].left += sample^.left*256;
    	  scratchBufferI32[i].right += sample^.right*256;
        inc(pos);
        if pos >= len then pos := 0;
	    end;
	  end;
  end;


  {mix down}
  for i := 0 to bufSamples-1 do begin
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
end;

begin
  mixer := tSoundMixer.create();
  addExitProc(closeMixer);
end.
