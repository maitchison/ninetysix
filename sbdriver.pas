{Basic sound blaster driver}
unit sbDriver;

{$MODE delphi}

interface

uses
	dos,
  test,
  debug,
  utils,
  go32;

type
	tWords = array of word;

procedure directNoise(s: double);
procedure directPCMData(buffer: tWords);
procedure playPCMData(buffer: tWords);
procedure backgroundPCMData(buffer: tWords);

procedure DSPWrite(command: byte);

VAR
  INTERRUPT_COUNTER: int32 = 0;
  LOOP_MUSIC: boolean = True;

var
	{number of seconds it took to process the last audio chunk}
	lastChunkTime: double;

implementation

CONST
  NUM_CHANNELS = 8;

type

	{time, where unit is 1/256 of a sample.}
  tTimeCode = int64;

  tAudioSample = packed record
  {16 bit stereo sample}
  case byte of
		0: (left,right: int16);
  	1: (value: dword);
  end;

  tAudioSampleHD = packed record
  {32 bit stereo sample, used for mixing}
		left,right: single;
  end;

	tSoundEffect = class
  	sample: array of tAudioSample;
    function getSample(tc: tTimeCode;looped: boolean=false): tAudioSample;
    constructor FromFile(filename: string);
  end;

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

    constructor create();
    procedure play(soundEffect: tSoundEffect; volume: single; pitch: single;timeOffset: single=0);
		procedure mixDown(startTC: tTimeCode;buf: pointer; bufBytes: int32);

  end;


{-----------------------------------------------------}

{converts from seconds since app launch, to timestamp code}
function secToTC(s: double): tTimeCode;
begin
	{note, we do not allow fractional samples when converting}
	result := round(s * 44100) * 256;
end;


{-----------------------------------------------------}

{returns sample at given time code (where 0 is the first sample of the file}
function tSoundEffect.getSample(tc: tTimeCode;looped:boolean=false): tAudioSample;
begin
	result.value := 0;
  tc := tc div 256;
	if tc < 0 then exit;
  if looped then
  	{todo: this is too expensive}
  	tc := tc mod length(sample)
  else
  	if tc >= length(sample) then exit;
	result := sample[tc];
end;

constructor tSoundEffect.FromFile(filename: string);
begin
	{todo: load}
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

procedure tSoundMixer.play(soundEffect: tSoundEffect; volume:single; pitch: single;timeOffset:single=0);
var
	channelNum: integer;
begin
	{for the moment lock onto the first channel}
  channelNum := 1;
	channel[channelNum].play(soundEffect, volume, pitch, secToTC(getSec+timeOffset));
end;

{generate mix for given time}
procedure tSoundMixer.mixDown(startTC: tTimeCode;buf: pointer; bufBytes: int32);
var
	value: single;
  value16: word;
  i,j: int32;
  numSamples: int32;
begin
	numSamples := bufBytes div 4; {16-bit stereo}

  for i := 0 to numSamples-1 do begin
  	value := 0;
		for j := 1 to 8 do begin
  		if not assigned(channel[j].soundEffect) then continue;
    	value += channel[j].soundEffect.getSample(channel[j].startTime-startTC+i).left;
	  end;
    value16 := clamp(trunc(value), 0, 65535);
    {mono -> stereo for the moment}
    pWord(buf+i*2)^ := value16;
    pWord(buf+i*2+1)^ := value16;
  end;		
end;


{-----------------------------------------------------}

const
{72?}
	SB_IRQ = $72; {INT10 in protected mode is $70+IRQ-8}

var
	sbGood: boolean = false;
  DSPVersion: byte = 0;
  dosSegment: word;
  dosSelector: word;

  backgroundBuffer: tWords;
  audioDataPosition: dword;
  currentBuffer: boolean;			// True = BufferA, False = BufferB

const
	SB_BASE = $220;
  DSP_RESET = SB_BASE + $6;
  DSP_READ_DATA = SB_BASE + $A;
  DSP_WRITE_DATA = SB_BASE + $C;
  DSP_WRITE_STATUS = SB_BASE + $C;
  DSP_DATA_AVAIL = SB_BASE + $E;

  //half buffer size in bytes
  BUFFER_SIZE = 64*1024;
  HALF_BUFFER_SIZE = BUFFER_SIZE div 2;

{----------------------------------------------------------}
{ DSP stuff}
{----------------------------------------------------------}

function DSPReadyToWrite(): boolean;
begin
	result := (port[DSP_WRITE_STATUS] and $80) = 0;
end;

function DSPDataAvailable(): boolean;
begin
	result := (port[DSP_DATA_AVAIL] and $80) <> 0;
end;

procedure DSPStop();
begin	
	DSPWrite($D9);
end;

procedure DSPWaitForWrite(timeout: double=1);
var	
	timeLimit: double;
begin
	timeLimit := getSec+timeout;
	while not DSPReadyToWrite do
  	if (getSec > timeLimit) then Error('Timeout waiting for DSPWrite');
end;

procedure DSPWrite(command: byte);
var	
	timeout: double;
begin
	DSPWaitForWrite();
  port[DSP_WRITE_DATA] := command;
end;

function DSPRead(): byte;
var	
	timeout: double;
begin
	timeout := getSec+1;
  while not DSPDataAvailable do
  	if (getSec > timeout) then Error('Timeout waiting for DSPRead');
  result := port[DSP_READ_DATA];
end;

{Reset DSP, return if successful}
function DSPReset(): boolean;
begin
	port[DSP_RESET] := $1;
  sleep(1);
  port[DSP_RESET] := $0;
  sleep(1);

  {DSP should respond with $AA}
  result := DSPRead = $AA;

  {get version as well}
  DSPWrite($E1);
  dspVersion := DSPRead()
end;


function DSPIrq(): integer;
var
	value: byte;
begin
	asm
  	mov dx, SB_BASE
    add dx, 4
    mov al, $80
    out dx, al
    inc dx

    in  al, dx
    mov [value], al
  end;

  case value of
  	1: exit(2);
    2: exit(5);
    4: exit(7);
    8: exit(10);
    else exit(-1);
  end;
end;

{----------------------------------------------------------}
{ DMA Stuff }
{----------------------------------------------------------}

CONST
	{for channel 5}
  {words}
	ISA_StartAddress = $C4;
	ISA_CountRegister = $C6;
  {bytes}
	ISA_STATUS = $D0;
	ISA_COMMAND = $D0;
	ISA_MODE = $D6;
	ISA_FLIP_FLOP = $D8;
	ISA_SINGLE_CHANNEL_MASK = $D4;
	ISA_CH5_PAGE = $8B;

const
	SB_OUTPUT = $41;
	SB_INPUT 	= $42;

	SB_OUTPUT_8BIT = $C0;
	SB_OUTPUT_16BIT = $B0;

  SB_MONO_16BIT_SIGNED_PCM = $10;
  SB_STEREO_16BIT_SIGNED_PCM = $30;

{length is samples? or words?}
procedure startPlayback(length: word);
begin
	DSPWrite(SB_OUTPUT);
  DSPWrite($AC);              // 44.1 HZ (according to manual)
  DSPWrite($44);
  DSPWrite(SB_OUTPUT_16BIT); 	
  DSPWrite(SB_STEREO_16BIT_SIGNED_PCM);
  DSPWrite(lo(word(length-1)));
  DSPWrite(hi(word(length-1)));	
end;

{$F+,S-,R-,Q-}
{note: this could all be in asm if we wanted}
{also... should set up a read from file}
procedure soundBlaster_ISR; interrupt;
var
	bytesToCopy: int32;
  readAck: byte;
  bufOfs: word;
  bytesRemaining: dword;
  startTime: double;
 begin

 	startTime := getSec;
  inc(INTERRUPT_COUNTER);
  currentBuffer := not currentBuffer;

  // refill the buffer
  bytesRemaining := (length(backgroundBuffer) - audioDataPosition)*2;
  bytesToCopy := min(bytesRemaining, HALF_BUFFER_SIZE);
  if bytesToCopy > 1 then begin
  	if currentBuffer then
    	bufOfs := HALF_BUFFER_SIZE
    else
    	bufOfs := 0;
    	
    // update the non-active buffer
	  dosMemPut(dosSegment, bufOfs, backgroundBuffer[audioDataPosition], bytesToCopy);

    audioDataPosition += (bytesToCopy shr 1);
    // acknowledge the DSP interupt.
	  // $F for 16bit, $E for 8bit
		readAck := port[SB_BASE + $F];
  end else begin
  	if LOOP_MUSIC then begin
    	audioDataPosition := 0;
      readAck := port[SB_BASE + $F];
    end else
	  	{stop the audio}
      {note: I intentially do not ack here, not sure if that's right or not}
  	  DSPStop();
  end;

  lastChunkTime := getSec-startTime;

  // end of interupt
  // apparently I need to send EOI to slave and master PIC when I'm on IRQ 10
  port[$A0] := $20;
  port[$20] := $20;
end;
{$F-,S+,R+,Q+}

var
	oldIntVec: tSegInfo;
  newIntVec: tSegInfo;

var
	irqStartMask,
  irqStopMask: byte;

var
	hasInstalledInt: boolean=False;

procedure install_ISR();
begin
	note('Installing music interupt');	
	newIntVec.offset := @soundBlaster_ISR;
  newIntVec.segment := get_cs;

  irqStopMask := 1 shl (10 mod 8);
  irqStartMask := not IRQStopMask;

	get_pm_interrupt(SB_IRQ, oldIntVec);
  set_pm_interrupt(SB_IRQ, newIntVec);

  port[$A1] := port[$A1] and IRQStartMask;

  hasInstalledInt := true;


end;

procedure uninstall_ISR;
begin
	if not hasInstalledInt then exit;
	note('Removing music interupt');
  port[$A1] := port[$A1] or IRQStopMask;
	set_pm_interrupt(SB_IRQ, oldIntVec);
  hasInstalledInt := false;
end;


procedure startAutoPlayback(length: word);
begin
	DSPWrite(SB_OUTPUT);
  DSPWrite($AC);              // 44.1 HZ (according to manual)
  DSPWrite($44);
  DSPWrite(SB_OUTPUT_16BIT); 	
  DSPWrite(SB_STEREO_16BIT_SIGNED_PCM);
  DSPWrite(lo(word(length-1)));
  DSPWrite(hi(word(length-1)));
end;

{program DMA channel 5 for 16-bit DMA
	length: Number of words to transfer}
procedure programDMA(length:dword);
var
  len: word;
  addr: dword;
const
  channel_number = 1; // DMA 5 is 16bit version of channel 1.
begin
	
  {note: 16bit transfers have address div 2, i.e. * 16 / 2}
	addr := (dosSegment shl 4);

	port[$D4] := $04+channel_number;	// mask DMA channel
  port[$D8] := $00;									// any value
  port[$D6] := $48+channel_number;	// mode (was $48, but now $59 as channel_number=1

  port[$8B] := byte(addr shr 16);		// page address, high bits of address, probably 0

  port[$C4] := lo(word(addr shr 1));	
  port[$C4] := hi(word(addr shr 1));

  port[$C6] := lo(word(length-1));	// length is words -1
  port[$C6] := hi(word(length-1));

  port[$D4] := $01;		// unmask DMA channel 5}
  	
end;

{----------------------------------------------------------}

{play noise directly (blocking) for s seconds.}
procedure directNoise(s: double);
var
	timeLimit: double;
  x: word;
begin
	timeLimit := getSec + s;
  DSPWrite($D1); // turn on speaker
  while getSec < timeLimit do begin
	  DSPWrite($10); // direct 8bit mino 'pc speaker'
	  DSPWrite(rnd);
  end;
  DSPWrite($D3); // end playback
end;

{play PCM audio using direct writes.
Input should be mono, 16-bit, and 44.1khz, however when played
will be converted to 8bit.
This will sound quite bad, a bit like 'pc speaker'.
}
procedure directPCMData(buffer: tWords);
var
  i: int32;
  j: int32;
  startTime: double;
	{used for 16-8bit dithering}
  sample: int32;
  hiSample,loSample: int32;

begin
  startTime := getSec;
  for i := 0 to length(buffer)-1 do begin
  	DSPWrite($10); // direct 8bit mono 'pc speaker'}
    sample := int16(buffer[i]);
    //write(sample, ' ');
    sample := sample + (32*1024);
    hiSample := sample shr 8;
    loSample := sample and $ff;

    if loSample > rnd then inc(hiSample);

    if hiSample > 255 then hiSample := 255;
    if hiSample < 0 then hiSample := 0;

    DSPWrite(hiSample);

    while getSec < startTime + (i / 44100) do;
  end;
end;

{play PCM audio using DMA.
Input should be stero 16-bit, and 44.1kh.}
procedure playPCMData(buffer: tWords);
var
	bytes: dword;
  samples: dword;
begin
	bytes := length(buffer)*2;
  samples := bytes div 4; {16-bit stereo}
	if bytes > 65536 then
  	Error('Buffer too long');
  if length(buffer) = 0 then
  	Error('Buffer is empty');

	{copy to dos memory}
  dosMemPut(dosSegment, 0, buffer[0], bytes);

  programDMA(bytes shr 1);
  startPlayback(bytes shr 1);

  delay(samples*1000/44100);
end;

{Play audio in background using IRQ.
Input should be stero 16-bit, and 44.1kh.}
procedure backgroundPCMData(buffer: tWords);
var
	bytestoCopy: dword;
  samples: dword;
  len: word;
  addr: dword;
  words: word;
  halfWords: word;
  blockSize: word;

  tmp: byte;

begin

	backgroundBuffer := buffer;
  audioDataPosition := 0;

  note(format('Playing new audio, with %d bytes', [length(buffer)*2]));
  note('Setting up initial transfer.');

  DSPReset();

  {first transfer}
  {note: full buffer transfer}
  bytesToCopy := min(BUFFER_SIZE, length(buffer)*2);
  dosMemPut(dosSegment, 0, backgroundBuffer[0], bytesToCopy);
  audioDataPosition += (bytesToCopy shr 1);

  currentBuffer := True;

  {this took a long time to get right...

  DMA should the setup to transfer the entire buffer.
  SB should be told to use half the buffer as the blocksize, this way
  we get an interupt halfway through the block}

  words := BUFFER_SIZE div 2; 					// number of words in buffer.
  halfWords := HALF_BUFFER_SIZE div 2;	// number of words in halfbuffer.

  {ok.. now the steps}

  {1. reset}
	DSPReset;
  {2. load sound}
  {aleady done}
  {3. master}
  {skip}
  {4. speaker on}
  {skip}
  {5. program ISA DMA}
	addr := (dosSegment shl 4);
	port[$D4] := $05;	// mask DMA channel
  port[$D8] := $01;	// any value
  port[$D6] := $59; // single mode, auto-initialize, write
  port[$8B] := byte(addr shr 16);	// page address, high bits of address, probably 0
  port[$C4] := lo(word(addr shr 1));	
  port[$C4] := hi(word(addr shr 1));
  port[$C6] := lo(word(words-1));	// length is words -1
  port[$C6] := hi(word(words-1));
  port[$D4] := $01;		// unmask DMA channel 5}
  {6. time constant}
  DSPWrite($41); 		
  DSPWrite(hi(44100));              // 44.1 HZ (according to manual)
  DSPWrite(lo(44100));

  DSPWrite($B6);	// 16-bit output mode.
  DSPWrite($30);	// 16-bit stereo signed PCM input.

  // according to manual, this must be half the DMA size.
  // since we using 16-bit audio, these are words

  DSPWrite(lo(word(halfWords-1)));
  DSPWrite(hi(word(halfWords-1)));

  {we should now expect an interupt}

  	
end;

{----------------------------------------------------------}

procedure runTests();
begin
end;

procedure initSound();
var
	res: dword;
begin
	note('[init] Sound');
  sbGood := DSPReset;

  if sbGood then
	  info(format('Detected SoundBlaster compatible soundcard at %hh (V%d.0) IRQ:%d', [SB_BASE, DSPVersion, DSPIrq]))
  else
  	warn('No SoundBlaster detected');


	res := Global_Dos_Alloc(BUFFER_SIZE);
  dosSelector := word(res);
  dosSegment := word(res shr 16);
  if dossegment = 0 then
  	Error('Failed to allocate dos memory');
  note(format('Sucessfully allocated dos memory for DMA (%d|%d)', [dosSelector, dosSegment]));

  install_ISR();

end;

procedure closeSound();
begin
	note('[done] sound');
  note(' -IRQ was triggered '+intToStr(INTERRUPT_COUNTER)+' times.');
  uninstall_ISR();
  DSPStop();
end;

{----------------------------------------------------------}

begin

	runTests();
  initSound;

  addExitProc(closeSound);

end.
