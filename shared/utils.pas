{Lightweight replacement for SysUtils}
unit utils;

{see freepascal/rt/go32v2/sysutils.pp}

{$MODE DELPHI}

interface

uses
  sysinfo,
  dos,
  sysTypes,
  go32;

{todo:
  my format
  my time (accurate!)
  my sleep
  my conversions

  implement xoshiro128+ (might still be too slow though?)
}

type

  {todo: make this a record helper}
  tMyDateTime = record

    asDouble: double;

    class function EncodeDate(year, month, day: word): TMyDateTime; static;
    class function EncodeTime(hour, minute, second, ms: word): TMyDateTime; static;

    procedure DecodeDate(var year, month, day: word);
    procedure DecodeTime(var hour, minute, second, ms: word);

    class operator Implicit(AValue: Double): TMyDateTime;
    class operator Implicit(AValue: TMyDateTime): Double;
    class operator Implicit(AValue: TMyDateTime): TDateTime;
    class operator Add(a,b: TMyDateTime): TMyDateTime;

    class function FromDosTC(dosTime: dword): tMyDateTime; static;

    function YYYYMMDD(sep: string='-'): string;
    function YYMMDD(sep: string='-'): string;
    function HHMMSS(sep: string=':'): string;
  end;

type
  tStringHelper = record helper for string
    function startsWith(const prefix: string; ignoreCase: boolean = false): boolean;
    function endsWith(const suffix: string; ignoreCase: boolean = false): boolean;
    function toLower(): string;
    function contains(substring: string; ignoreCase: boolean=false): boolean;
    function trim(): string;
  end;

{------------------------------------------------}
{ Math replacements}

function min(a,b: int32): int32; overload;
function min(a,b: single): single; overload;
function min(a,b,c: single): single; overload;
function max(a,b: int32): int32; inline; overload;
function max(a,b,c: int32): int32; overload;
function max(a,b,c: single): single; overload;
function power(Base, Exponent: double): double; inline;
function log10(x: double): double;
function log2(x: double): double;
function roundUpToPowerOfTwo(x: dword): dword;

{------------------------------------------------}
{ SysUtils replacements}

function  Now(): TDateTime;
function  format(fmt: string; args: array of Const): string;
procedure Sleep(ms: integer);

procedure GetDate(var year, month, mday, wday: word);
procedure GetTime(var hour, minute, second, sec100: word);

{------------------------------------------------}
{ crt replacements}
procedure delay(ms: double);

{------------------------------------------------}
{ My custom routines }

{path stuff}
function toLowerCase(const s: string): string;
function extractExtension(const path: string): string;
function extractFilename(const path: string): string;
function extractPath(const path: string): string;
function joinPath(const path, filename: string): string; overload;
function joinPath(const path, subpath, filename: string): string; overload;
function removeExtension(const filename: string): string;

function comma(value: int64; width: word=0; padding: char=' '): string;
function fltToStr(value: extended): string;
function intToStr(value: int64; width: word=0; padding: char='0'): string;
function binToStr(value: int64; width: word=0; padding: char='0'): string;
function bytesToStr(bytes: array of byte): string;
function bytesToSanStr(bytes: tBytes): string;
function strToInt(s: string): int64;
function strToFlt(s: string): double;
function strToBool(s: string): boolean;

{string functions}
function trim(s: string): string;
function pad(s: string;len: int32;padding: char=' '): string;
function lpad(s: string;len: int32;padding: char=' '): string;
function split(s: string; c: char; var left: string; var right: string): boolean;
function nextWholeWord(line: string;var pos:integer; out len:integer): boolean;
function subStringMatch(s: string; sOfs: integer; subString: string): boolean;
function join(lines: array of string;seperator: string=#13#10): string;

function  negDecode(x: dword): int32; inline;
function  negEncode(x: int32): dword; inline;
function  encodeByteDelta(a,b: byte): byte; inline;

function  sign(x: int32): int32; overload;
function  sign(x: single): single; overload;

function  bytesForBits(x: int32): int32;
function  toBytes(x: array of dword): tBytes; overload;
function  toBytes(x: array of word): tBytes; overload;

procedure Wait(ms: integer);
function  RND(): byte; assembler; register;
function  Quantize(value, levels: byte): byte;
function  clamp(x, a, b: int32): int32; inline; overload;
function  clamp(x, a, b: single): single; inline; overload;
function  clamp16(x: int32): int32; inline; overload;
function  clamp16(x: int32;padding: int32): int32; inline; overload;
function  clamp16(x: single): int32; inline; overload;
function  GetTSC(): uint64; assembler; register;
function  GetSec(): double;

function  dosExecute(s: string; showOutput: boolean=false): word;

procedure dumpString(s: string; filename: string);
function  loadString(filename: string): string;

function  getTickCount(): int64;
function  getMSCount(): int64;

{heap stuff}
procedure setFixedHeapSize(size: int64);
procedure autoHeapSize();


const
  WORD_CHARS: set of char = ['a'..'z','A'..'Z','0'..'9'];


implementation

uses
  debug,
  test;

var
  SEED: byte;
  programStartTSC: uint64 = 0;

{----------------------------------------------------------}

function max(a,b: int32): int32; inline; overload;
begin
  if a > b then exit(a);
  exit(b);
end;

function max(a,b,c: int32): int32; overload;
begin
  result := max(max(a,b), c);
end;

function max(a,b,c: single): single; overload;
begin
  if (a > b) and (a > c) then exit(a);
  if (b > a) and (b > c) then exit(b);
  exit(c);
end;

function min(a,b: int32): int32; inline; overload;
begin
  if a < b then exit(a);
  exit(b);
end;

function min(a,b: single): single; inline; overload;
begin
  if a < b then exit(a);
  exit(b);
end;

function min(a,b,c: single): single; overload;
begin
  if (a < b) and (a < c) then exit(a);
  if (b < a) and (b < c) then exit(b);
  exit(c);
end;


function Power(Base, Exponent: double): double; inline;
begin
  result := Exp(Exponent * Ln(Base));
end;

function Log10(x: double): double; inline;
begin
  result := ln(x) / ln(10);
end;

function Log2(x: double): double; inline;
begin
  result := ln(x) / ln(2);
end;

function roundUpToPowerOfTwo(x: dword): dword;
begin
  if x = 0 then exit(0);
  dec(x);
  x := x or (x shr 1);
  x := x or (x shr 2);
  x := x or (x shr 4);
  x := x or (x shr 8);
  x := x or (x shr 16);
  inc(x);
  result := x;
end;

{----------------------------------------------------------}

{Cut down version of format}
function format(fmt: string; args: array of Const): string;
var
  i, ArgIndex: Integer;
  InPlaceholder: Boolean;
  places: word;
  s: string;
  a: TVarRec;
begin
  result := '';
  s := '';
  ArgIndex := 0;
  places := 1;
  InPlaceholder := False;

  for i := 1 to length(fmt) do begin
    if fmt[i] = '%' then begin
      if inPlaceholder then begin
        inPlaceholder := False;
        result += '%';
      end else
        inPlaceholder := True;
        places := 1;
      continue;
    end;
    if inPlaceholder then begin
      inPlaceholder := False;
      a := args[ArgIndex];
      case fmt[i] of
        '.': begin
            // very basic for the moment
            if (i = length(fmt)) or (not (fmt[i+1] in ['0'..'9']))  then
              error('invalid formatting, decimal expected after "."');
            inPlaceholder := true;
          end;
        '0'..'9': begin
          places := strToInt(fmt[i]);
          inPlaceholder := true;
        end;
        'd': begin
          // integer
          case a.VType of
            vtInteger: result += IntToStr(a.VInteger);
            vtInt64: result += IntToStr(a.VInt64^);
            vtExtended: result += IntToStr(trunc(a.VExtended^));
            else Error('Invalid type for %d:'+IntToStr(a.VType));
          end;
        end;
        ',': begin
          // integer
          case a.VType of
            vtInteger: result += comma(a.VInteger);
            vtInt64: result += comma(a.VInt64^);
            vtExtended: result += comma(trunc(a.VExtended^));
            else Error('Invalid type for %,:'+IntToStr(a.VType));
          end;
        end;
        'f': begin
          // float
          case a.VType of
            vtExtended: Str(args[ArgIndex].VExtended^:0:places, s);
            else Error('Invalid type for %f:'+IntToStr(a.VType));
          end;
          result += s;
        end;
        's': begin
          case a.VType of
            vtInteger: result += IntToStr(args[ArgIndex].VInteger);
            vtString: result += string(args[ArgIndex].VString^);
            vtAnsiString: result += AnsiString(args[ArgIndex].VAnsiString);
            else Error('Invalid type for %s:'+IntToStr(a.VType));
          end;
        end;
        'h': begin
          case a.VType of
            vtInteger: result += HexStr(args[ArgIndex].VInteger, 4);
            else Error('Invalid type for %h:'+IntToStr(a.VType));
          end;
        end;
        else
          // ignore invalid
      end;
      if not inPlaceholder then
        inc(ArgIndex);
    end else
      result += fmt[i];
  end;

end;


function IsLeepYear(year: word): boolean;
begin
  result := (Year mod 4 = 0) and ((Year mod 100 <> 0) or (Year mod 400 = 0));
end;

function DaysInYear(year: word): integer;
begin
  if IsLeepYear(year) then
    result := 366
  else
    result := 365;
end;

{Returns the number of days in given month, in given year}
function DaysInMonth(year, month:word): integer;
const
  DaysPerMonth: array[1..12] of Byte = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
begin
  result := DaysPerMonth[Month];
  if (Month = 2) and IsLeepYear(Year) then
    Inc(result);
end;

{--------------------------------------------------------------------}

function Now(): TDateTime;
var
  year, month, mday, wday: word;
  hour, minute, second, sec100: word;
  i : integer;
  date: double;
begin

  GetDate(year, month, mday, wday);
  GetTime(hour, minute, second, sec100);

  result :=
    TMyDateTime.EncodeDate(year, month, mday) +
    TMyDateTime.EncodeTime(hour, minute, second, sec100*10);
end;

{Busy wait for given number of ms.}
procedure delay(ms: double);
var
  targetSec: double;
begin
  targetSec := getSec + ms/1000;
  while getSec < targetSec do;
end;

{Put CPU into idle for give number of ms}
procedure sleep(ms: integer);
var
  targetMS: int64;
  safety: integer;
begin

  {unfortunately this isn't working.
  I think it's because hlt can't be called if interuupts are disabled
  and also maybe that dos does not support it}
  delay(ms);
  exit;

  {We have a safety counter to make sure we don't wait too
   long. This would happen if the ticks overflow, which is
   very unlikely}
  targetMs := getMSCount + ms;
  safety := (ms div 40); {use 40 as a buffer instead of 55}

  {note: this is bugged if we press keys, but that's kind of good
   as we can keypress our way through it}

  while (getMSCount < targetMs) and ( safety > 0) do begin
    {Give up timeslices in ~55ms blocks}
    asm
      hlt
      end;
    dec(safety);
  end;
end;


procedure GetDate(var year, month, mday, wday: word);
var
  regs: TRealRegs;
begin
  regs.ax := $2A00;
  realintr($21, regs);
  year := regs.cx;
  month := regs.dh;
  mday := regs.dl;
  wday := regs.al;
end;

procedure GetTime(var hour, minute, second, sec100: word);
var
  regs: TRealRegs;
begin
  regs.ax := $2C00;
  realintr($21, regs);
  hour := regs.ch;
  minute := regs.cl;
  second := regs.dh;
  sec100 := regs.dl;
end;


{-------------------------------------------------------}

function bytesToStr(bytes: array of byte): string;
var
  i: int32;
begin
  result := '[';
  for i := 0 to length(bytes)-1 do
    result += intToStr(bytes[i])+',';
  result[length(result)] := ']';
end;

function bytesToSanStr(bytes: tBytes): string;
var
  i: int32;
  b: byte;
begin
  result := '';
  for i := 0 to length(bytes)-1 do begin
    b := bytes[i];
    if (b >= 32) and (b < 128) then
      result += chr(b)
    else
      result += '#('+intToStr(b)+')';
  end;
end;

function toLowerCase(const s: string): string;
var
  i: integer;
begin
  result := s;
  for i := 1 to length(s) do
    if (s[i] >= 'A') and (s[i] <= 'Z') then
      result[i] := chr(ord(s[i])+32);
end;

{return a filename extension}
function extractExtension(const path: string): string;
var
  dotPos: integer;
begin
  dotPos := pos('.', path);
  if dotPos >= 0 then
    result := copy(path, dotPos+1, length(path) - dotPos)
  else
    result := '';
end;

function removeExtension(const filename: string): string;
var
  dotPos: integer;
  i: int32;
begin
  for i := length(filename) downto 1 do
    if filename[i] = '.' then
      exit(copy(filename, 1, i-1));
  exit(filename);
end;

{return a filename from path}
function extractFilename(const path: string): string;
var
  i: integer;
begin
  for i := length(path) downto 1 do
    if path[i] in ['\', '/'] then
      exit(copy(path, i+1, length(path)));
  exit(path);
end;

{return a path without filename.}
function extractPath(const path: string): string;
var
  filename: string;
begin
  filename := extractFilename(path);
  result := copy(path, 1, length(path) - length(filename));
end;

function joinPath(const path, filename: string): string; overload;
begin
  if path = '' then exit(filename);
  if filename = '' then exit(path);
  if path.endswith('\') or path.endswith('/') then
    result := path+filename
  else
    result := path+'\'+filename;
end;

function joinPath(const path, subpath, filename: string): string; overload;
begin
  result := joinPath(joinPath(path, subpath), filename);
end;

function comma(value: int64; width: word; padding: char=' '): string;
var
  s: string;
  i, j: int32;
begin
  s := intToStr(abs(value), width, padding);
  result := '';
  for i := length(s) downto 1 do begin
    j := length(s) - i;
    result := s[i] + result;
    if (j mod 3 = 2) and (i <> 1) then
      result := ',' + result;
  end;
  if value < 0 then result := '-'+result;
end;

function fltToStr(value: extended): string;
begin
  str(value, result);
end;

function intToStr(value: int64; width: word; padding: char='0'): string;
begin
  str(value, result);
  while length(result) < width do
    result := padding + result;
end;

function binToStr(value: int64; width: word; padding: char='0'): string;
begin
  if (value < 0) then
    {todo: support this}
    Error('value for binary was negative');
  if value = 0 then result := '0' else result := '';
  while value > 0 do begin
    if value and 1 = 1 then
      result += '1'
    else
      result += '0';
    value := value shr 1;
  end;
  while length(result) < width do
    result := padding + result;
end;

function strToInt(s: string): int64;
var
  value: longint;
  code: word;
begin
  {todo: better way to handle errors}
  val(s, value, code);
  if code <> 0 then debug.Error(Format('Invalid integer "%s"', [s]));
  result := value;
end;

function strToFlt(s: string): double;
var
  value: double;
  code: word;
begin
  {todo: better way to handle errors}
  val(s, value, code);
  if code <> 0 then debug.Error(Format('Invalid float "%s"', [s]));
  result := value;
end;

function strToBool(s: string): boolean;
var
  value: double;
  code: word;
begin
  result := false; {to make compiler happy}
  s := s.toLower;
  if s = 'false' then exit(false);
  if s = 'true' then exit(true);
  error(format('Invalid boolean literal %s expecting [true, false]', [s]));
end;

{remove whitespace from begining and end of string.}
function trim(s: string): string;
var
  i,j: integer;
  l: integer;
begin
  l := length(s);
  if l = 0 then exit('');
  i := 1;
  j := l;
  while (s[i] in [' ', #9]) and (i < l) do inc(i);
  while (s[j] in [' ', #9]) and (j >= i) do dec(j);
  result := copy(s, i, j - i + 1);
end;

function pad(s: string;len: int32;padding: char=' '): string;
begin
  while length(s) < len do
    s += padding;
  result := s;
end;


function lpad(s: string;len: int32;padding: char=' '): string;
begin
  while length(s) < len do
    s := padding + s;
  result := s;
end;

function split(s: string; c: char; var left: string; var right: string): boolean;
var
  charPos: int32;
begin
  charPos := pos(c, s);
  if charPos < 0 then exit(false);
  left := Copy(s, 1, charPos-1);
  right := Copy(s, charPos+1, length(s)-charPos);
  exit(true);
end;

{Returns number of bytes required to encode this many bits}
function bytesForBits(x: int32): int32;
begin
  result := (x + 7) div 8;
end;

function toBytes(x: array of dword): tBytes; overload;
var
  i: int32;
begin
  result := nil;
  setLength(result, length(x));
  for i := 0 to length(x)-1 do
    result[i] := x[i];
end;

function toBytes(x: array of word): tBytes; overload;
var
  i: int32;
begin
  result := nil;
  setLength(result, length(x));
  for i := 0 to length(x)-1 do
    result[i] := x[i];
end;

{A more accurate version of sleep, espcially for short durations.
Puts CPU into idle until we a~55 MS remain, then performs a busy wait.}
procedure Wait(ms: integer);
var
  MSTarget: qword;
begin
  {approximate only..., we divide by 1024 instead of 1000}
  MSTarget := GetMsCount() + ms;

  {We sleep for the first period, then do a busy wait to get the exact
   time.}
  if ms > 60 then
    sleep(ms-55);

  while GetMsCount() < MSTarget do begin
    {pass}
  end;
end;


{A simple 8bit random number generator
Can be used for generating random colors etc.
Fast, but non-determanistic (due to 'entropy' from RDTSC call)}
function RND(): byte; assembler; register;
asm
  RDTSC
  mul ah
  // this is needed to remove patterns caused by exact timing
  // of certian operations.
  add al, SEED
  mov SEED, ah
  // result is in al
  end;

{quantize an input value.
Input is 0..255
Output is 0..levels-1
}
function Quantize(value, levels: byte): byte;
var
  z: uint16;
  quotient, remainder: uint16;
  roll: uint16;
begin
  z := value * (levels-1);
  quotient := z shr 8;
  remainder := z and $FF;
  roll := 0;
  if rnd < remainder then roll := 1;
  result := (quotient + roll)
end;

function clamp(x, a, b: int32): int32; inline; overload;
begin
  if x < a then exit(a);
  if x > b then exit(b);
  exit(x);
end;

function clamp16(x: int32): int32; inline; overload;
begin
  result := clamp(x, -32768, +32767);
end;

function clamp16(x: int32;padding: int32): int32; inline; overload;
begin
  result := clamp(x, -32768+padding, +32767-padding);
end;

function clamp16(x: single): int32; inline; overload;
begin
  result := clamp(round(x), -32768, +32767);
end;

function clamp(x, a, b: single): single; inline; overload;
begin
  if x < a then exit(a);
  if x > b then exit(b);
  exit(x);
end;

function GetTSC(): uint64; assembler; register;
asm
  rdtsc
  {result will already be in EAX:EDX, so nothing to do}
  end;

{ticks since arbitary time}
function GetTickCount(): int64;
begin
  result := int64(MemL[$40:$6c]);
end;

{ms since arbitary time (accurate to 55ms)}
function GetMSCount(): int64;
begin
  result := int64(MemL[$40:$6c]) * 55;
end;

{Get seconds since program start.
Can be used for very accurate timing measurement}
function GetSec(): double;
begin
  result := (getTSC()-programStartTSC) * CPUInfo.INV_CLOCK_FREQ;
end;

procedure dumpString(s: string; filename: string);
var
  t: text;
begin
  assign(t, filename);
  rewrite(t);
  writeln(t, s);
  close(t);
end;

function loadString(filename: string): string;
var
  t: text;
  s: string;
begin
  assign(t, filename);
  reset(t);
  readln(t, s);
  close(t);
  result := s;
end;

{interleave pos and negative numbers into a whole number}
function negDecode(x: dword): int32; inline;
begin
  result := ((x+1) shr 1);
  if x and $1 = $0 then result := -result;
end;

{interleave pos and negative numbers into a whole number
 0 -> 0
+1 -> 1
-1 -> 2
...
}
function negEncode(x: int32): dword; inline;
begin
  result := abs(x)*2;
  if x > 0 then dec(result);
end;

{generates code representing delta to go from a to b}
function encodeByteDelta(a,b: byte): byte; inline;
var
  delta: int32;
begin
  {take advantage of 256 wrap around on bytes}
  delta := int32(b)-a;
  if delta > 128 then
    exit(negEncode(delta-256))
  else if delta < -127 then
    exit(negEncode(delta+256))
  else
    exit(negEncode(delta));
end;

{-------------------------------------------------------}
{ string functions }
{-------------------------------------------------------}

{returns start position of next whole word, returns false if none.}
function nextWholeWord(line: string;var pos:integer; out len:integer): boolean;
var
  inWord, isWordChar: boolean;
  initialPos, i: integer;
  c: char;
begin
  {break line into words}
  inWord := false;
  len := 0;
  initialPos := pos;
  for i := initialPos to length(line) do begin
    c := line[i];
    isWordChar := c in WORD_CHARS;
    if inWord then begin
      if isWordChar then
        inc(len)
      else
        exit(true);
    end else begin
      if isWordChar then begin
        inWord := true;
        pos := i;
        len := 1;
      end;
    end;
  end;
  exit(false);
end;

{returns copy(s, i, n) = substr, but without a mem copy
 sOfs: position of substring in s, 1 = first character }
function subStringMatch(s: string; sOfs: integer; subString: string): boolean;
var
  i: integer;
begin
  if length(s)+sOfs-1 < length(subString) then exit(false);
  for i := 0 to length(subString)-1 do begin
    if s[i+sOfs] <> subString[i+1] then exit(false);
  end;
  exit(true);
end;


function join(lines: array of string;seperator: string=#13#10): string;
var
  i, idx: integer;
  totalLength: int32;
begin
  if length(lines) = 0 then exit('');

  totalLength := 0;
  for i := low(lines) to high(lines)-1 do
    totalLength += length(lines[i]) + length(seperator);
  totalLength += length(lines[high(lines)]);

  idx := 1;
  setLength(result, totalLength);
  for i := low(lines) to high(lines) do begin
    if length(lines[i]) > 0 then
      move(lines[i][1], result[idx], length(lines[i]));
    idx += length(lines[i]);
    if i < high(lines) then begin
      move(seperator[1], result[idx], length(seperator));
      idx += length(seperator);
    end;
  end;
end;

{execute a command in dos with blocking. Returns dos error code.}
function dosExecute(s: string; showOutput: boolean=false): word;
var
  postfix: string;
begin
  if showOutput then
    postfix := ''
  else
    postfix := ' > nul';
  dos.exec(getEnv('COMSPEC'), '/C '+s+postfix);
  result := dosExitCode;
end;

function sign(x: int32): int32; overload;
begin
  if x < 0 then exit(-1);
  if x > 0 then exit(1);
  exit(0);
end;

function sign(x: single): single; overload;
begin
  if x < 0 then exit(-1);
  if x > 0 then exit(1);
  exit(0);
end;

{-------------------------------------------------------------------}

class operator TMyDateTime.Implicit(AValue: Double): TMyDateTime;
begin
  result.asDouble := AValue;
end;

class operator TMyDateTime.Add(a,b: TMyDateTime): TMyDateTime;
begin
  result.asDouble := a.asDouble + b.asDouble;
end;

class operator TMyDateTime.Implicit(AValue: TMyDateTime): Double;
begin
  result := AValue.asDouble;
end;

class operator TMyDateTime.Implicit(AValue: TMyDateTime): TDateTime;
begin
  result := AValue.asDouble;
end;

class function TMyDateTime.EncodeDate(year, month, day: word): TMyDateTime; static;
var
  c,ya: Cardinal;
  date: int64;
begin

  {this arcane magic is more or less a copy of the routine from
   rtl/objpas/sysutils/datai.inc}
  if month > 2 then
    dec(month,3)
  else begin
    inc(month,9);
    dec(year);
  end;

  c := year div 100;
  ya := year - 100*c;
  date := (146097*c) shr 2 + (1461*ya) shr 2 + (153 * cardinal(month)+2) div 5 + cardinal(day) - 693900;
  result := date;
end;

procedure TMyDateTime.DecodeDate(var year, month, day: word);
var
  ly,ld,lm,j: cardinal;
begin

  {this arcane magic is more or less a copy of the routine from
   rtl/objpas/sysutils/datai.inc}

  j := pred((longint(trunc(System.Int(self.asDouble))) + 693900) shl 2);

  ly := j div 146097;
  j  := j - 146097 * cardinal(ly);
  ld := j shr 2;
  j  := (ld shl 2 + 3) div 1461;
  ld := (cardinal(ld) shl 2 + 7 - 1461*j) shr 2;
  lm := (5 * ld-3) div 153;
  ld := (5*ld+2 - 153 * lm) div 5;
  ly := 100 * cardinal(ly) + j;
  if lm < 10 then
    inc(lm, 3)
  else begin
    dec(lm, 9);
    inc(ly);
  end;

  day := ld;
  month := lm;
  year := ly;
end;

class function TMyDateTime.EncodeTime(hour, minute, second, ms: word): TMyDateTime; static;
var
  time: double;
begin
  time := 0;
  time += ms;
  time /= 1000;
  time += second;
  time /= 60;
  time += minute;
  time /= 60;
  time += hour;
  time /= 24;
  result := Time;
end;

procedure TMyDateTime.DecodeTime(var hour, minute, second, ms: word);
var
  time: uint64;
begin
  time := trunc(frac(self.asDouble) * uint64(24*60*60*1000));
  ms := time mod 1000;
  time := time div 1000;
  second := time mod 60;
  time := time div 60;
  minute := time mod 60;
  time := time div 60;
  hour := time mod 24;
end;

class function TMyDateTime.FromDosTC(dosTime: dword): tMyDateTime;
var
  DosDate, DosTimePart: Word;
  Year, Month, Day: Word;
  Hour, Minute, Second: Word;

begin
  {todo: switch to unpacktime}
  DosDate := dosTime shr 16;
  DosTimePart := dosTime and $ffff;

  // Decode the date
  Year := 1980 + (DosDate shr 9);       // Bits 15-9
  Month := (DosDate shr 5) and $0F;     // Bits 8-5
  Day := DosDate and $1F;               // Bits 4-0

  // Decode the time
  Hour := DosTimePart shr 11;           // Bits 15-11
  Minute := (DosTimePart shr 5) and $3F;// Bits 10-5
  Second := (DosTimePart and $1F) * 2;  // Bits 4-0

  result := encodeDate(Year, Month, Day) + encodeTime(Hour, Minute, Second, 0);
end;

function TMyDateTime.YYYYMMDD(sep: string='-'): string;
var
  y,m,d: word;
begin
  DecodeDate(y,m,d);
  result := IntToStr(y, 4, '0') + sep + IntToStr(m, 2, '0') + sep + IntToStr(d, 2, '0');
end;

{ops.. old had a bug where it was yyyymmdd, will rename and fixup later}
function TMyDateTime.YYMMDD(sep: string='-'): string;
var
  y,m,d: word;
begin
  DecodeDate(y,m,d);
  result := IntToStr(y mod 100, 2, '0') + sep + IntToStr(m, 2, '0') + sep + IntToStr(d, 2, '0');
end;

function TMyDateTime.HHMMSS(sep: string=':'): string;
var
  h,m,s,ss: word;
begin
  DecodeTime(h,m,s,ss);
  result := IntToStr(h, 2, '0') + sep + IntToStr(m, 2, '0') + sep + IntToStr(s, 2, '0');
end;


{--------------------------------------------------------}
{ String helpers}
{--------------------------------------------------------}

function tStringHelper.endsWith(const suffix: string; ignoreCase: boolean): boolean;
var
  MainStr, SubStr: string;
begin
  if Length(Suffix) > Length(Self) then
    Exit(False);
  if IgnoreCase then begin
    MainStr := toLowerCase(Self);
    SubStr := toLowerCase(Suffix);
  end else begin
    MainStr := Self;
    SubStr := Suffix;
  end;
  result := copy(MainStr, Length(MainStr) - Length(SubStr) + 1, Length(SubStr)) = SubStr;
end;


function tStringHelper.startsWith(const prefix: string; ignoreCase: boolean): boolean;
var
  MainStr, SubStr: string;
begin
  if length(prefix) > length(Self) then
    exit(false);
  if ignoreCase then begin
    mainStr := toLowerCase(Self);
    subStr := toLowerCase(prefix);
  end else begin
    mainStr := self;
    subStr := prefix;
  end;
  result := copy(mainStr, 1, length(subStr)) = subStr;
end;

function tStringHelper.toLower(): string;
begin
  result := utils.toLowerCase(self);
end;

function tStringHelper.contains(substring: string; ignoreCase: boolean=false): boolean;
var
  s: string;
begin
  if ignoreCase then
    result := pos(substring.toLower, self.toLower) > 0
  else
    result := pos(substring, self) > 0;
end;

function tStringHelper.trim(): string;
begin
  result := utils.trim(self);
end;

{--------------------------------------------------------}

{Attempts to set a fixed size for the heap
I've found dynamic FPC heap growth does not work well under go32 so
it's best to just set the heapsize to something large upfront, and
then never go over this.
}

procedure setFixedHeapSize(size: int64);
var
  p: pointer;
begin
  getMem(p, size);
  freemem(p);
end;

{set heap size to max memory, minus a little, with a reasonable upper limit}
procedure autoHeapSize();
var
  freeMemMB: int64;
begin
  freeMemMB := (getFreeSystemMemory-(512*1024)) div (1024*1024);
  freeMemMB := clamp(freeMemMB, 1, 64);
  log(format('Allocating fixed heap with size %d MB', [freeMemMB]));
  setFixedHeapSize(freeMemMB*1024*1024);
end;

{--------------------------------------------------------}

type
  tUtilsTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tUtilsTest.run();
var
  a,b,s: string;
  i,n: int32;
begin
  assertEqual(StrToFlt('123'), 123);
  assertClose(StrToFlt('-7.2'), -7.2);
  assert(strToBool('True'));
  assert(not strToBool('False'));
  assertEqual(StrToInt('123'), 123);
  assertEqual(StrToInt('7'), 7);
  assertEqual(Trim(' Fish'), 'Fish');
  assertEqual(Trim(' Fish    '), 'Fish');
  assertEqual(Trim('Fish'), 'Fish');
  assertEqual(Trim('    '), '');
  assertEqual(Trim(''), '');

  assertEqual(join(['a','b']), 'a'+#13#10+'b');

  assertEqual(Format('%s', [5]), '5');

  assertEqual(binToStr(5, 8), '00000101');
  assertEqual(binToStr(0), '0');
  assertEqual(binToStr(1), '1');

  split('fish=good', '=', a, b);
  assertEqual(a,'fish');
  assertEqual(b,'good');

  {test negEncode neg}
  for i := -256 to +256 do
    assertEqual(negDecode(negEncode(i)), i);

  assertEqual(extractExtension('fish.com'), 'com');
  assertEqual(extractExtension('FISH.COM'), 'COM');

  assertEqual(extractFilename('fish.com'), 'fish.com');
  assertEqual(extractFilename('FISH.COM'), 'FISH.COM');
  assertEqual(extractFilename('c:\FISH.COM'), 'FISH.COM');
  assertEqual(extractFilename('c:\src\airtime.exe'), 'airtime.exe');
  assertEqual(extractPath('c:\src\airtime.exe'), 'c:\src\');

  assertEqual(removeExtension('fish.com'), 'fish');
  assertEqual(removeExtension('fish'), 'fish');
  assertEqual(removeExtension('.'), '');
  assertEqual(removeExtension('A.'), 'A');

  assertEqual(comma(5), '5');
  assertEqual(comma(100), '100');
  assertEqual(comma(1200), '1,200');
  assertEqual(comma(987654321), '987,654,321');
  assertEqual(comma(-987654321), '-987,654,321');

  assertEqual(joinPath('c:\dos', 'go.exe'), 'c:\dos\go.exe');
  assertEqual(joinPath('c:\dos\', 'go.exe'), 'c:\dos\go.exe');
  assertEqual(joinPath('c:\dos/', 'go.exe'), 'c:\dos/go.exe');

  {test string helpers}
  assert('fish'.endsWith('sh'));
  assert(not 'fish'.endswith('ash'));
  assert('fish'.endswith('fish'));
  assert(not 'fish'.endswith('fishy'));

  assert('fish'.startsWith('fi'));
  assert('fish'.startsWith('fish'));
  assert(not 'fish'.startsWith('fishy'));
  assert(not 'fish'.startsWith('fia'));

  assert('fish'.contains('fish'));
  assert('fish'.contains('fi'));
  assert('fish'.contains('sh'));
  assert('fish'.contains('is'));
  assert(not 'fish'.contains('fash'));

  assert(not 'fish'.startsWith('fia'));

  assertEqual(join(['a','b'],','), 'a,b');

  {power of two}
  assertEqual(roundUpToPowerOfTwo(0), 0);
  assertEqual(roundUpToPowerOfTwo(1), 1);
  assertEqual(roundUpToPowerOfTwo(2), 2);
  assertEqual(roundUpToPowerOfTwo(3), 4);
  assertEqual(roundUpToPowerOfTwo(4), 4);
  assertEqual(roundUpToPowerOfTwo(5), 8);

  {whole word}
  i := 1;
  s := 'The cat with 33 lives.';
  assert(nextWholeWord(s, i, n));
  assertEqual(i, 1); assertEqual(n, 3);
  assert(nextWholeWord(s, i, n));
  assertEqual(i, 5); assertEqual(n, 3);
  assert(nextWholeWord(s, i, n));
  assertEqual(i, 9); assertEqual(n, 4);
  assert(nextWholeWord(s, i, n));
  assertEqual(i, 14); assertEqual(n, 2);
  assert(nextWholeWord(s, i, n));
  assertEqual(i, 17); assertEqual(n, 5);
  assert(not nextWholeWord(s, i, n));

  {substring}
  assert(subStringMatch(s, 1, 'the'));
  assert(not subStringMatch(s, 2, 'the'));
  assert(subStringMatch(s, 22, '.'));
  assert(subStringMatch(s, 1, s));

end;

{--------------------------------------------------------}

initialization
  programStartTSC := getTSC();
  SEED := 97;
  tUtilsTest.create('Utils');
finalization

end.
