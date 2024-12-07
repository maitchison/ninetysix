{Basic sound blaster driver}
unit sbDriver;

{$MODE delphi}

{todo: remove references to mixer, and just have a procedure call}

interface

uses
	dos,
  test,
  debug,
  utils,
  go32;

type
	tWords = array of word;

{todo: remove these, and handle through mixer
 (except the direct ones)}
procedure directNoise(s: double);
procedure directPCMData(buffer: tWords);
procedure playPCMData(buffer: tWords);

{-----------------------------------------------------}

var
  INTERRUPT_COUNTER: int32 = 0;
  LOOP_MUSIC: boolean = True;

	{number of seconds it took to process the last audio chunk}
	lastChunkTime: double = -1;
  currentTC: uint64;

  backgroundMusicBuffer: pointer = nil;
  backgroundMusicPosition: int32 = 0;
  backgroundMusicLength: int32 = 0;

var
	bufferDirty: boolean = false;  	

implementation

uses
	mix,
	sound;

{-----------------------------------------------------}

var
	{during IRQ our segements will sometime be wrong, so we need to
   reference a copy of it}
	backupDS: word = 0;

const
{72?}
	SB_IRQ = $72; {INT10 in protected mode is $70+IRQ-8}

var
	sbGood: boolean = false;
  IS_DMA_ACTIVE: boolean = false;
  DSPVersion: byte = 0;
  dosSegment: word = 0;
  dosSelector: word = 0;

  currentBuffer: boolean;			// True = BufferA, False = BufferB

const
	SB_BASE = $220;
  DSP_RESET = SB_BASE + $6;
  DSP_READ_DATA = SB_BASE + $A;
  DSP_WRITE_DATA = SB_BASE + $C;
  DSP_WRITE_STATUS = SB_BASE + $C;
  DSP_DATA_AVAIL = SB_BASE + $E;

  {
  Timings for 16bit stereo

  64k = ~200-400 ms 		This is way too much latency
  32k = ~100-200 ms			Perhaps a safe trade-off
  16k = ~50-100 ms			Might be ideal.
  8k  = ~25-50 ms			
  }

  //buffer size in bytes
  BUFFER_SIZE = 8*1024;
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

procedure DSPStop();
begin	
	DSPWrite($D9);
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
procedure soundBlaster_ISR; interrupt;
var
  readAck: byte;
  bufOfs: word;
  startTime: double;
  musicBuffer: pointer;	
  newSamples: int32;

begin

	{todo: do everything in asm, and without any calls}
	asm
    push es
    push ds
    push fs
    push gs
  	pushad

    mov ax, cs:[backupDS]
    mov ds, ax
    mov es, ax
  	end;

  // acknowledge the DSP
	// $F for 16bit, $E for 8bit
	readAck := port[SB_BASE + $F];

 	startTime := getSec;
  inc(INTERRUPT_COUNTER);
  currentBuffer := not currentBuffer;

	if currentBuffer then
  	bufOfs := HALF_BUFFER_SIZE
  else
  	bufOfs := 0;

  {Initialize the buffer with the music stream.}

  if (dosSegment <> 0) then begin

	  if backgroundMusicBuffer <> nil then begin
  		{todo: hande end case better}		
	  	newSamples := HALF_BUFFER_SIZE div 4;
  	  if (backgroundMusicPosition + newSamples) >= backgroundMusicLength then
    	  backgroundMusicPosition := 0;
  	  dosMemPut(dosSegment, bufOfs, (backgroundMusicBuffer + (backgroundMusicPosition * 4))^, HALF_BUFFER_SIZE);
	    backgroundMusicPosition += newSamples;
	  end else begin
	  	dosMemFillWord(dosSegment, bufOfs, HALF_BUFFER_SIZE div 2, 0);
	  end;
	  bufferDirty := true;
  end;

  lastChunkTime := getSec-startTime;

  // end of interupt
  // apparently I need to send EOI to slave and master PIC when I'm on IRQ 10
  port[$A0] := $20;
  port[$20] := $20;

  asm
  	
  	popad
    pop gs
    pop fs
    pop ds
    pop es
  end;

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

{Start IRQ and DMA to handle audio in background.}
procedure initiateDMAPlayback();
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

	if IS_DMA_ACTIVE then
  	error('DMA transfer is already active');

  note('Setting up DMA transfer.');
  if not assigned(mixer) then
  	error('A mixer has not yet been assigned.');

  DSPReset();

  {start with an empty buffer}
  dosMemFillWord(dosSegment, 0, BUFFER_SIZE div 2, 0);

  currentBuffer := True;

  {this took a long time to get right...

  DMA should the setup to transfer the entire buffer.
  SB should be told to use half the buffer as the blocksize, this way
  we get an interupt halfway through the block}

  words := BUFFER_SIZE div 2; 					// number of words in buffer.
  halfWords := HALF_BUFFER_SIZE div 2;	// number of words in halfbuffer.
	addr := (dosSegment shl 4);

  {check address does not span 64K}
  if (addr shr 16) <> ((addr + words*2) shr 16) then
  	error('DMA destination buffer spans 64k boundary');

  {1. reset}
	DSPReset();
  port[$D4] := $05; // mask DMA channel
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

  IS_DMA_ACTIVE := true;
  	
end;

procedure stopDMAPlayback();
begin
	{does this actually stop playback?}
	DSPStop();
  IS_DMA_ACTIVE := false;
end;

{----------------------------------------------------------}

procedure initSound();
var
	res: longint;
begin
	note('[init] Sound');
  sbGood := DSPReset();

  if sbGood then
	  info(format('Detected SoundBlaster compatible soundcard at %hh (V%d.0) IRQ:%d', [SB_BASE, DSPVersion, DSPIrq]))
  else
  	warn('No SoundBlaster detected');

	res := Global_Dos_Alloc(BUFFER_SIZE);
  dosSelector := word(res);
  dosSegment := word(res shr 16);
  if dossegment = 0 then
  	error('Failed to allocate dos memory');
  note(format('Sucessfully allocated dos memory for DMA (%d|%d)', [dosSelector, dosSegment]));

  install_ISR();
  initiateDMAPlayback();

end;

procedure freeBuffer();
begin
  global_dos_free(dosSelector);
  dosSegment := 0;
  dosSelector := 0;
end;

procedure closeSound();
begin
	note('[done] sound');
  note(' -IRQ was triggered '+intToStr(INTERRUPT_COUNTER)+' times.');
  uninstall_ISR();
  stopDMAPlayback();
  delay(10); {make sure SB has stoped reading}
  freeBuffer();
end;

{----------------------------------------------------------}

procedure runTests();
begin
end;

{----------------------------------------------------------}

begin

	backupDS := get_ds();

	runTests();

  initSound();

  addExitProc(closeSound);

end.
