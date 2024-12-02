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

procedure directPCMData(buffer: array of word);
procedure playPCMData(buffer: array of word);

implementation

var
	sbGood: boolean = false;
  DSPVersion: byte = 0;
  dosSegment: word;
  dosSelector: word;

const
	SB_BASE = $220;
  DSP_RESET = SB_BASE + $6;
  DSP_READ_DATA = SB_BASE + $A;
  DSP_WRITE_DATA = SB_BASE + $C;
  DSP_WRITE_STATUS = SB_BASE + $C;
  DSP_DATA_AVAIL = SB_BASE + $E;

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

procedure setSampleRate(sampleRate: word);
begin
	DSPWrite($40); {time constant}
  {44.1hz}
  DSPWrite($AC);
  DSPWRITE($44);
end;

{play noise directly (blocking) for s seconds.}
procedure directNoise(s: double);
var
	timeLimit: double;
  counter: int32;
  x: word;
begin
	timeLimit := getSec + s;
  DSPWrite($D1); // turn on speaker
  setSampleRate(8000);
  counter := 0;
  while getSec < timeLimit do begin
	  DSPWrite($10); // direct 8bit mino 'pc speaker'
	  DSPWrite(rnd);
  end;
  DSPWrite($D3); // end playback
end;


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

{program DMA channel 5 for 16-bit DMA
	length: Number of words to transfer}
procedure programDMA(length:word);
var
  len: word;
  addr: dword;
const
  channel_number = 1; // DMA 5 is 16bit version of channel 1.
begin
	
  {note: 16bit transfers have address div 2, i.e. * 16 / 2}
	addr := (dosSegment shl 3);

	port[$D4] := $04+channel_number;	// mask DMA channel
  port[$D8] := $01;									// any value
  port[$D6] := $58+channel_number;	// mode (was $48, but now $59 as channel_number=1

  port[$8B] := byte(addr shr 16);	// page address, high bits of address, probably 0

  port[$C4] := lo(word(addr));	
  port[$C4] := hi(word(addr));

  port[$C6] := lo(length);
  port[$C6] := hi(length);

  port[$D4] := $01;		// unmask DMA channel 5}
  	
end;

const
	SB_OUTPUT = $41;
	SB_INPUT 	= $42;

	SB_OUTPUT_8BIT = $C0;
	SB_OUTPUT_16BIT = $B0;

  SB_MONO_16BIT_SIGNED_PCM = $10;
  SB_STEREO_16BIT_SIGNED_PCM = $30;

{length is samples?}
procedure startPlayback(length: word);
begin
	DSPWrite(SB_OUTPUT);
{  DSPWrite(lo(44100));
  DSPWrite(hi(44100));}
  DSPWrite($AC);
  DSPWrite($44);	{for 44.1hz}

  DSPWrite(SB_OUTPUT_16BIT); 	// Command: 16-bit stereo
  DSPWrite(SB_STEREO_16BIT_SIGNED_PCM);  // Mode: $30 signed PCM.
  dec(length);
  DSPWrite(lo(length));
  DSPWrite(hi(length));	
end;

{play PCM audio using DMA.
Input should be stero 16-bit, and 44.1kh.}
procedure playPCMData(buffer: array of word);
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


{play PCM audio using direct writes.
Input should be mono, 16-bit, and 44.1khz, however when played
will be converted to 8bit.
This will sound quite bad, a bit like 'pc speaker'.
}
procedure directPCMData(buffer: array of word);
var
  i: int32;
  j: int32;
  startTime: double;
	{used for 16-8bit dithering}
  sample: int32;
  hiSample,loSample: int32;

begin
  startTime := getSec;
  setSampleRate(8000);
  for i := 0 to length(buffer)-1 do begin
  	DSPWrite($10); // direct 8bit mino 'pc speaker'}


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

{----------------------------------------------------------}

{----------------------------------------------------------}

procedure runTests();
var
	buffer: array of byte;
begin
	buffer := nil;
  setLength(buffer, 40000);
  for i := 0 to length(buffer)-1 do
  	buffer[i] := rnd;
	setSampleRate(44100);

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


	res := Global_Dos_Alloc(64*1024);
  dosSelector := word(res);
  dosSegment := word(res shr 16);
  if dossegment = 0 then
  	Error('Failed to allocate dos memory');
  note('Sucessfully allocated dos memory for DMA');

end;

begin

	runTests();
  initSound;

end.
