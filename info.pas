{print information about the current system}
program info;

{$MODE delphi}

uses
	cpu,
	utils,
	crt;

var
	infoStr: string;
  timerStartTime: double = -1;
  timerEndTime: double = -1;

type
	tProcedure = procedure;

{hide debug.error for the moment}
procedure error(s: string);
begin	
	writeln(s);
  halt;
end;

{------------------------------------------------------------}

type tTimerMode = (
	TM_MIPS			// reports millions of itterations per second.
);

{simple timer for measuring how long something takes}
type tTimer = object
	mode: tTimerMode;
	postfix: string;
	name: string;
  count: int64;
	startTime, endTime: double;
  bias: double;

  constructor create();

  procedure start(aName: string='';aCount: int64=1); inline;
	function  elapsed(): double; inline;
  procedure stop(); inline;
  procedure print();
end;

constructor tTimer.create();
begin
	mode := TM_MIPS;
	postfix := '';
	startTime := -1;
  endTime := -1;
  bias := 0;
end;

procedure tTimer.start(aName: string='';aCount: int64=1); inline;
begin
  name := aName;
  count := aCount;
	startTime := getSec();
end;

function tTimer.elapsed(): double; inline;
begin
	if startTime = -1 then error('Please call timer.start first');
	if endTime = -1 then error('Please call timer.stop first');
	result := (endTime - startTime) - bias;
end;

procedure tTimer.stop(); inline;
begin
	endTime := getSec();
end;

procedure tTimer.print();
begin
	write(pad(name, 40));
  case mode of
  	TM_MIPS: writeln(format('%fM '+POSTFIX, [(count / elapsed) / 1000 / 1000]));
    else writeln(format('%fs', [elapsed]));
  end;
end;

{------------------------------------------------------------}

procedure testInfo(name: string; description: string);
begin
	textAttr := $0F;
  writeln();
	writeln('[',name,']');
	textAttr := $07;
	infoStr := description;
end;

{hide debug.info for the moment}
{todo: use debug.info, but have it print out when in text mode}
procedure info(s: string);
begin
	writeln(s);
end;

procedure assertTrue(testName: string; value: boolean;msg: string = '');
begin
	textAttr := $07;
	write(pad(''+testName, 40));
  if value then begin
  	textAttr := $03;
  	writeln('[PASS]');
  	textAttr := $07;
  end else begin
  	textAttr := $04;
  	writeln('[FAIL]');
  	textAttr := $07;
    if msg <> '' then
	    writeln(' - ', msg);
  end;
end;

procedure assertEqual(testName: string; value: int64; expected: int64;msg: string=''); overload;
begin
	msg := format('expecting %d but found %d', [expected, value]);
	assertTrue(testName, value = expected, msg);
end;

procedure assertEqual(testName: string; value: tBytes; expected: tBytes;msg: string=''); overload;
var
	i: integer;
begin
	msg := format('expecting %s but found %s', [bytesToStr(expected), bytesToStr(value)]);
	if length(value) <> length(expected) then begin
  	assertTrue(testName, false, msg);
    exit;
  end;

	for i := 0 to length(value)-1 do
  	if value[i] <> expected[i] then begin
	  	assertTrue(testName, false, msg);
  	  exit;
    end;

	assertTrue(testName, true, msg);
end;

procedure assertNotEqual(testName: string; value: int64; notExpected: int64;msg: string=''); overload;
begin
	msg := format('expecting value to not be %d', [notExpected]);
	assertTrue(testName, value <> notExpected, msg);
end;

procedure assertEqual(testName: string; value: extended; expected: extended;msg: string=''); overload;
begin
	msg := format('expecting %f but found %f', [expected, value]);
	assertTrue(testName, value = expected);
end;

procedure assertNotEqual(testName: string; value: extended; notExpected: extended;msg: string=''); overload;
begin
	msg := format('expecting value to not be %f', [notExpected, value]);
	assertTrue(testName, value <> notExpected);
end;

procedure testCompilerCorruption();
var
	d: double;
  a: int64;

procedure testMove(len: int32);
var
  data: tbytes;
  dataCopy: tBytes;
  i: integer;
begin
	setLength(data, len);
	setLength(dataCopy, len);
  for i := 0 to len-1 do begin
  	data[i] := rnd;
    dataCopy[i] := 255;
  end;
	move(data[0], dataCopy[0], len);
  assertEqual('Move n='+intToStr(len), dataCopy, data);
end;

begin
	testInfo(
  	'FPC Corruption',
  	'FPC uses the FPU to perform moves. If run under limited precision FPU emulation, this results in corpution. Two concequences that come up are. 1) Programs compiled under this bug have float literals corupted. 2) Programs run under this bug have MOVE corruption.'
  );
	d := 4;
	asm
  	fld qword ptr [d]
    fistp a
  end;
  assertEqual('No literal corruption bug', a, 4);

  testMove(1);
  testMove(4);
  testMove(8);
  testMove(32);
  testMove(64);
  testMove(128);
end;

procedure testFloat80();
var
	s: single;
  d: double;
	x: extended;
  a,b: int64;
begin
	testInfo(
  	'Limited Precision FPU',
  	'Some emmulators (e.g. em-dosbox) use 64-bit javascript floats to emulate the 80-bit IEEE spec. This causes a loss of precision. We check for that here.'
  );
	a := high(int64);
  b := 0;
	asm  	
  	fild qword a
    fistp qword b
  end;
  assertEqual('FILD Move', a, b);
  asm
  	fldpi	
    fst dword ptr [s]
    fst qword ptr [d]
    fstp tbyte ptr [x]
  end;

  assertNotEqual('80bit float is not 32bit', x-s, 0);
  assertNotEqual('80bit float is not 64bit', x-d, 0);
end;

{waits until the start of the next tick.}
procedure waitForNextTick();
var
	tick: int64;
begin
	tick := getTickCount();
  while getTickCount() = tick do;
  if getTickCount() <> tick+1 then error('tick incremented by more than 1');
end;

{emulators tend to give inaccurate results for RDTSC}
procedure testTiming();
var
  startTSC, endTSC: uint64;
  startSec, endSec: double;
  startTick, endTick: double;
  estimatedMHZ: double;
begin
	testInfo(
  	'Test Timing',
  	'RDTSC will not be accurate under emulation, so check that here.'
  );
  waitForNextTick();
  startTSC := getTSC;
  waitForNextTick();
  endTSC := getTSC;

  if endTSC = startTSC then error('TSC did not update');

  estimatedMHZ := (endTSC - startTSC) / (1/18.2065);

  info(format('RDTSC runs at %fMHZ', [estimatedMHZ/1000/1000]));

  {Measure time using both RDTSC and TickCounter, and make sure we don't drift}
  waitForNextTick();
  startTick := getTickCount() * 0.0549254;
  startSec := getSec();
  delay(1000);
  endTick := getTickCount() * 0.0549254;
  endSec := getSec();

  info(format('RDTSC drift is %f%%', [(100 * (endSec-startSec) / (endTick-startTick)) - 100]));

end;

procedure showFlag(flag: string; value: string); overload;
begin
	textAttr := $07;
	writeln(pad(flag,40), value);
end;

procedure benchRAM();
var
  timer: tTimer;
  a,b: tBytes;
const
	LEN = 64*1024;

begin
	setLength(a, LEN);
  setLength(b, LEN);

	testInfo('RAM Benchmark', '' );
end;

{get a sense of how fast CPU is}
procedure benchCPU();
var
  timer: tTimer;
const
	LEN = 1024;
begin

	timer.create();

	testInfo('CPU Benchmark', '');

  timer.start('Empty Loop', LEN);	
  asm
  	pushad
  	mov ecx, LEN
  @LOOP:
  	loop @LOOP
    popad
   end;
  timer.stop(); timer.print();
	{subtract empty loop for for all subsequent tests}
  timer.bias := timer.elapsed;
	
  timer.start('ADD (I32)', LEN);	
  asm
  	pushad
  	mov ecx, LEN
  @LOOP:
  	add eax, eax
  	loop @LOOP
    popad
   end;
   timer.stop(); timer.print();

  timer.start('MUL (I32)', LEN);	
  asm
  	pushad
  	mov ecx, LEN
  @LOOP:
  	imul eax
  	loop @LOOP
    popad
   end;
   timer.stop(); timer.print();

  timer.start('DIV (I32)', LEN);	
  asm
  	pushad
  	mov ecx, LEN
  @LOOP:
  	idiv eax
  	loop @LOOP
    popad
   end;
   timer.stop(); timer.print();


end;

procedure showFlag(flag: string; value: boolean); overload;
begin
	textAttr := $07;
	write(pad(flag, 40));
  if value then begin
		textAttr := $05;
  	writeln('[YES]')
  end else begin
	  textAttr := $04;
  	writeln('[NO]');
  end;
  textAttr := $07;
end;

function getCPUName(): string;
var
	reax: dword;
  cpuName: string;
  family, model, stepping: word;
begin
  if not cpu.cpuid_support then exit('');

	asm
  	pushad
  	mov eax, 1
    cpuid
    mov [reax], eax
    popad
	  end;	
  		
  family := (reax shr 8) and $f;
  model := (reax shr 4) and $f;
  stepping :=(reax shr 0) and $f;

  case family of
  	3: cpuName := '386';
  	4: case model of
    	0,1,4: cpuName := '486DX';
    	2: cpuName := '486SX';
    	3: cpuName := '486DX2';
    	5: cpuName := '486SX2';
    	7: cpuName := '486DX4';
    	else cpuName := '486';
    end;
  	5: case model of
    	3: cpuName := 'Pentium Overdrive';
    	4: cpuName := 'Pentium MMX';
      else cpuName := 'Pentium';
    end;
  	6: case model of
    	1: cpuName := 'Pentium Pro';
    	3: cpuName := 'Pentium II';
    	6: cpuName := 'Pentium III';
    	else cpuName := 'Pentium Pro/II/III';
    end;
    else cpuName := 'Unknown ('+intToStr(family)+')';
  end;
	result := cpuName;
end;

procedure printCpuInfo();
var
  cpuBrand: string;
begin	
	cpuBrand := cpu.CPUBrandString;
  if cpuBrand = '' then cpuBrand := '<blank>';
	showFlag('CPUID' ,cpu.cpuid_support);
  showFlag('CPU Name' ,getCPUName());
  showFlag('CPU Brand' ,cpuBrand);
  showFlag('CMOV', cpu.CMOVSupport);
  showFlag('MMX', cpu.MMXSupport);
  showFlag('SSE3', cpu.SSE3Support);
  showFlag('AVX', cpu.AVXSupport);
end;

begin
	gotoxy(1,1);
  clrscr;
	textAttr := $07;
  printCpuInfo();
	benchCPU();
  testFloat80();
  testCompilerCorruption();
  testTiming();
end.

