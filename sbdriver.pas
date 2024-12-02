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

var
	didWeGo: int32 = 0;

implementation


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

function DSPStop(): boolean;
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
 begin

  inc(didWeGo);

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
  	{stop the audio}
    DSPStop();
    {not sure if we should ack or not}
  end;

  // end of interupt
  // apparently I need to send EOI to slave and master PIC when I'm on IRQ 10
  port[$A0] := $20;
  port[$20] := $20;
end;
{$F-,S+,R+,Q+}

var
	oldIntVec: tSegInfo;
  newIntVec: tSegInfo;


{$F+}
procedure int10h_handler; assembler;
asm
    push eax

    mov eax, [didWeGo]
    inc eax
    mov [didWeGo], eax

    pop eax
    iret
end;
{$F-}

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

  {why do we do this?}
  writeln(port[$A1]);
  writeln('then');
  port[$A1] := port[$A1] and IRQStartMask;
  writeln(port[$A1]);

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
	addr := (dosSegment shl 3);

	port[$D4] := $04+channel_number;	// mask DMA channel
  port[$D8] := $00;									// any value
  port[$D6] := $48+channel_number;	// mode (was $48, but now $59 as channel_number=1

  port[$8B] := byte(addr shr 16);	// page address, high bits of address, probably 0

  port[$C4] := lo(word(addr));	
  port[$C4] := hi(word(addr));

  port[$C6] := lo(word(length-1));	// length is words -1
  port[$C6] := hi(word(length-1));

  port[$D4] := $01;		// unmask DMA channel 5}
  	
end;

{----------------------------------------------------------}

var userproc: pointer;

(*
{kind of dodgy real-mode DMA}
procedure installRMProc(userproc : pointer; userproclen : longint);
var r : trealregs;
begin
  get_rm_callback(@callback_handler, mouse_regs, mouse_seginfo);
  { install callback }
  r.eax := $0c; r.ecx := $7f;
  r.edx := longint(mouse_seginfo.offset);
  r.es := mouse_seginfo.segment;
  realintr(mouseint, r);
  { show mouse cursor }
  r.eax := $01;
  realintr(mouseint, r);
end;*)


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
	addr := (dosSegment shl 3);
	port[$D4] := $05;	// mask DMA channel
  port[$D8] := $01;	// any value
  port[$D6] := $59; // single mode, auto-initialize, write
  port[$8B] := byte(addr shr 16);	// page address, high bits of address, probably 0
  port[$C4] := lo(word(addr));	
  port[$C4] := hi(word(addr));
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


  (*
  writeln('dma');

  programDMA(bytes shr 1);

  writeln('start');
  startAutoPlayback(bytes shr 1);

  writeln('done');*)


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
	  info(format('Detected SoundBlaster compatible soundcard at %hh (V%d.0)', [SB_BASE, DSPVersion]))
  else
  	warn('No SoundBlaster detected');


  writeln('Writeln DSP version ',DSPVersion);


	res := Global_Dos_Alloc(BUFFER_SIZE);
  dosSelector := word(res);
  dosSegment := word(res shr 16);
  if dossegment = 0 then
  	Error('Failed to allocate dos memory');
  note('Sucessfully allocated dos memory for DMA');

  install_ISR();

end;

procedure closeSound();
begin
	note('[done] sound');
  uninstall_ISR();
end;

{----------------------------------------------------------}

begin

	runTests();
  initSound;

  addExitProc(closeSound);

end.
