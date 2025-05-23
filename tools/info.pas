{print information about the current system}
program info;

{$MODE delphi}

uses
  crt,
  uTypes,
  uInfo,
  uUtils;

var
  infoStr: string;
  timerStartTime: double = -1;
  timerEndTime: double = -1;

{hide debug.error for the moment}
procedure fatal(s: string);
begin
  writeln(s);
  halt;
end;

{------------------------------------------------------------}

type tTimerMode = (
  TM_S,          // time in seconds.
  TM_MS,        // time in milliseconds.
  TM_CYCLES,    // estimated number of cycles per iteration.
  TM_MIPS,      // millions of iterations per second.
  TM_MIPS_CYCLES,  // show both MIPS and cycle estimate.
  TM_MBPS       // megabytes per second.
);

{simple timer for measuring how long something takes}
type tTimer = object
  mode: tTimerMode;
  postfix: string;
  tag: string;
  value: int64;
  startTime, endTime: double;
  bias: double;

  constructor create(aMode: tTimerMode=TM_S; aValue: int64=1);

  procedure start(aTag: string=''); inline;
  function  elapsed(): double; inline;
  procedure stop(); inline;
  procedure print();
end;

constructor tTimer.create(aMode: tTimerMode=TM_S; aValue: int64=1);
begin
  mode := aMode;
  value := aValue;
  postfix := '';
  startTime := -1;
  endTime := -1;
  bias := 0;
end;

procedure tTimer.start(aTag: string=''); inline;
begin
  tag := aTag;
  startTime := getSec();
end;

function tTimer.elapsed(): double; inline;
begin
  if startTime = -1 then fatal('Please call timer.start first');
  if endTime = -1 then fatal('Please call timer.stop first');
  result := (endTime - startTime) - bias;
end;

procedure tTimer.stop(); inline;
begin
  endTime := getSec();
end;

procedure tTimer.print();
var
  cycles: string;
  mips: string;
begin

  write(pad(tag, 40));

  cycles := lpad(format('~%f', [elapsed/value*(cpuInfo.mhz*1000*1000)]), 6)+' cycles';
  mips := lpad(format('%f', [(value / elapsed) / 1000 / 1000]), 6)+' M';

  case mode of
    TM_S:     writeln(format('%f s', [elapsed]));
    TM_MS:     writeln(format('%f ms', [elapsed*1000]));
    TM_CYCLES: writelN(cycles);
    TM_MIPS:   writeln(mips);
    TM_MIPS_CYCLES: writeln(cycles + ' ' + mips);
    TM_MBPS:   writeln(format('%f MB/S '+POSTFIX, [(value / elapsed) / 1000 / 1000]));
    else fatal('Invalid timer mode');
  end;
end;

{------------------------------------------------------------}

procedure showFlag(flag: string; value: string); overload;
begin
  textAttr := $07;
  writeln(pad(flag,40), value);
end;

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
    'FPC uses the FPU to perform moves. '+
    'If run under limited precision FPU emulation, this results in corpution.' +
    'Two concequences that come up are. '+
    '1) Programs compiled under this bug have float literals corupted.'+
    '2) Programs run under this bug have MOVE corruption'
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
  i: integer;
  q1,q2: qword;
  maxMantissa: integer;
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

  assertNotEqual('80bit float is not reduced to 32bit', x-s, 0);
  assertNotEqual('80bit float is not reduced to 64bit', x-d, 0);

  maxMantissa := 0;
  for i := 1 to 64 do begin
    q1 := (qword(1) shl i)-1;
    x := q1;
    q2 := round(x);
    if q1 <> q2 then
      break
    else
      maxMantissa := i;
  end;

  showFlag('Mantisaa' ,intToStr(maxMantissa)+'bits');

end;

{waits until the start of the next tick.}
procedure waitForNextTick();
var
  tick: int64;
begin
  tick := getTickCount();
  while getTickCount() = tick do;
  if getTickCount() <> tick+1 then fatal('tick incremented by more than 1');
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

  if endTSC = startTSC then fatal('TSC did not update');

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

procedure benchRAM();
var
  timer: tTimer;
  a,b: tBytes;
  aPtr, bPtr: pointer;
const
  LEN = 64*1024;

begin
  setLength(a, LEN);
  setLength(b, LEN);
  aPtr := @a[0];
  bPtr := @b[0];

  timer.create(TM_MBPS, LEN);

  testInfo('RAM Benchmark', '');
  timer.start('Move - FPC');
  move(a[0], b[0], LEN);
  timer.stop(); timer.print();

  timer.start('Move - Loop');
  asm
    pushad
    mov ecx, LEN
    shr ecx, 2
    mov esi, aPtr
    mov edi, bPtr
  @LOOP:
    mov eax, [esi]
    mov [edi], eax
    add edi, 4
    loop @LOOP
    popad
   end;
  timer.stop(); timer.print();

  timer.start('Move - REP MOVSD');
  asm
    pushad
    mov ecx, LEN
    shr ecx, 2
    mov esi, aPtr
    mov edi, bPtr
    rep movsd
    popad
   end;
  timer.stop(); timer.print();

end;

{get a sense of how fast CPU is}
procedure benchCPU();
var
  timer: tTimer;
const
  LEN = 1024;
begin

  timer.create(TM_MIPS_CYCLES, LEN);

  testInfo('CPU Benchmark', '');

  {subtract empty loop for for all subsequent tests}
  timer.start('Empty Loop');
  asm
    pushad
    mov ecx, LEN
  @LOOP:
    loop @LOOP
    popad
   end;
  timer.stop();
  timer.bias := timer.elapsed;

  { Integer }

  timer.start('IADD');
  asm
    pushad
    mov ecx, LEN
  @LOOP:
    add eax, eax
    loop @LOOP
    popad
   end;
  timer.stop(); timer.print();

  timer.start('IMUL');
  asm
    pushad
    mov ecx, LEN
  @LOOP:
    imul eax
    loop @LOOP
    popad
   end;
  timer.stop(); timer.print();

  timer.start('IDIV');
  asm
    pushad
    mov ecx, LEN
    mov eax, 1
    mov edx, 0
    mov ebx, 1
  @LOOP:
    idiv ebx
    loop @LOOP
    popad
   end;
  timer.stop(); timer.print();

  { Float }

  timer.start('FADD');
  asm
    pushad
    mov ecx, LEN
    fld1
    fld1
  @LOOP:
    fadd st(0), st(1)
    loop @LOOP
    fstp st(0)
    fstp st(0)
    popad
   end;
  timer.stop(); timer.print();

  writeln('                                              --------------');

  timer.start('FMUL');
  asm
    pushad
    mov ecx, LEN
    fld1
    fld1
  @LOOP:
    fmul st(0), st(1)
    loop @LOOP
    fstp st(0)
    fstp st(0)
    popad
   end;
  timer.stop(); timer.print();

  timer.start('FDIV');
  asm
    pushad
    mov ecx, LEN
    fld1
    fld1
  @LOOP:
    fdiv st(0), st(1)
    loop @LOOP
    fstp st(0)
    fstp st(0)
    popad
   end;
  timer.stop(); timer.print();

  {this should be just a few cycles}
  if uInfo.getMMXSupport then begin
    timer.mode := TM_CYCLES;
    timer.start('EMMS');
    asm
      pushad
      mov ecx, LEN
    @LOOP:
      emms
      loop @LOOP
      popad
     end;
    timer.stop(); timer.print();
  end;
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


procedure printCpuInfo();
var
  cpuBrand: string;
begin
  testInfo('CPUINFO','');
  showFlag('CPUID' ,uInfo.getCPUIDSupport);
  showFlag('CPU Name' ,getCPUName());
  showFlag('MMX', uInfo.getMMXSupport);
end;

procedure benchCache();
var
  i, n: integer;
  p: pointer;
  bytes: dword;
  timer: tTimer;
begin
  getMem(p, 1 shl 20);

  for n := 13 to 20 do begin
    bytes := 1 shl n;
    filldword(p^, bytes div 4, 0);
    timer.create(TM_MBPS, 256*bytes);
    timer.start('READ '+intToStr(bytes div 1024)+'kb');
    for i := 1 to 256 do begin
      asm
        pushad
        mov edi, p
        mov esi, p
        mov ecx, bytes
        shr ecx, 2
        rep lodsd
        popad
      end;
    end;
    timer.stop(); timer.print();
  end;
  freemem(p);
end;

begin
  gotoxy(1,1);
  clrscr;
  textAttr := $07;
  printCpuInfo();
  benchCPU();
  benchRAM();
  benchCache();
  testFloat80();
  testCompilerCorruption();
  testTiming();
end.
