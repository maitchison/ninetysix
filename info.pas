{print information about the current system}
program info;

{$MODE delphi}

uses
	utils,
	crt;

var
	infoStr: string;

type
	tProcedure = procedure;


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

{hide debug.error for the moment}
procedure error(s: string);
begin	
	writeln(s);
  halt;
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
  assertEqual('No literal coruption bug', a, 4);

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

{emulators tend to give inaccurate results for RDTSC}
procedure testTiming();
var
	tick: int64;
  startTSC, endTSC: uint64;
  estimatedMHZ: double;
begin
	testInfo(
  	'Test Timing',
  	'RDTSC will not be accurate under emulation, so check that here.'
  );
	tick := getTickCount;
  while getTickCount() = tick do;
  if getTickCount() <> tick+1 then error('tick incremented by more than 1');
  startTSC := getTSC;
  while getTickCount() = tick+1 do;
  endTSC := getTSC;
  if getTickCount() <> tick+2 then error('tick incremented by more than 1');

  if endTSC = startTSC then error('TSC did not update');

  estimatedMHZ := (endTSC - startTSC) / (1/18.2065);

  info(format('RDTSC runs at %fMHZ', [estimatedMHZ/1000/1000]));

end;

{returns seconds taken to run procedure}
function bench(var proc: tProcedure): single;
begin
	proc();
  result := 0;		
end;

{get a sense of how fast CPU is}
procedure benchCPU();
var	
	s: array of single;
  d: array of double;
	b: array of byte;
  i16: array of int16;
  i32: array of int32;
  i64: array of int64;
  i: int32;

const
	LEN = 1024;
begin
	setLength(s, LEN);
  setLength(d, LEN);
  setLength(b, LEN);
  setLength(i16, LEN);
  setLength(i32, LEN);
  setLength(i64, LEN);

  for i := 0 to LEN-1 do begin
  	s[i] := rnd;
    d[i] := rnd;
    b[i] := rnd;
    i16[i] := rnd;
    i32[i] := rnd;
    i64[i] := rnd;
  end;
	
  for i := 0 to LEN-1 do begin
  	i32[i] := i32[i] + 5;
  end;
	
end;

begin
	gotoxy(1,1);
  clrscr;
	textAttr := $07;
	testFloat80();
  testCompilerCorruption();
  testTiming();
end.

