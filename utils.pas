{Lightweight replacement for SysUtils}
unit utils;

{see freepascal/rt/go32v2/sysutils.pp}

{$MODE DELPHI}

interface

uses
	go32;

{todo:
	my format
  my time (accurate!)
  my sleep
  my conversions

  implement xoshiro128+ (might still be too slow though?)
}

type

	tBytes = array of byte;
  tWords = array of word;
  tDWords = array of dword;

	TMyDateTime = record

  	asDouble: double;

    class function EncodeDate(year, month, day: word): TMyDateTime; static;
    class function EncodeTime(hour, minute, second, ms: word): TMyDateTime; static;

		procedure DecodeDate(var year, month, day: word);
    procedure DecodeTime(var hour, minute, second, ms: word);

    class operator Implicit(AValue: Double): TMyDateTime;
		class operator Implicit(AValue: TMyDateTime): Double;
		class operator Implicit(AValue: TMyDateTime): TDateTime;
    class operator Add(a,b: TMyDateTime): TMyDateTime;

    function YYMMDD(sep: string='-'): string;
    function HHMMSS(sep: string=':'): string;
  end;

{------------------------------------------------}
{ Math replacements}

function min(a,b: int32): int32; overload;
function min(a,b,c: single): single; overload;
function max(a,b: int32): int32; inline; overload;
function max(a,b,c: int32): int32; overload;
function max(a,b,c: single): single; overload;
function Power(Base, Exponent: double): double; inline;
function Log10(x: double): double;

{------------------------------------------------}
{ SysUtils replacements}

function  Now(): TDateTime;
function  Format(fmt: string; args: array of Const): string;
procedure Sleep(ms: integer);

procedure GetDate(var year, month, mday, wday: word);
procedure GetTime(var hour, minute, second, sec100: word);

{------------------------------------------------}
{ crt replacements}
procedure delay(ms: double);

{------------------------------------------------}
{ My custom routines }

function toLowerCase(const s: string): string;
function getExtension(const filename: string): string;

function intToStr(value: int64; width: word=0; padding: char='0'): string;
function binToStr(value: int64; width: word=0; padding: char='0'): string;
function bytesToStr(bytes: tBytes): string;
function bytesToSanStr(bytes: tBytes): string;
function StrToInt(s: string): integer;
function Trim(s: string): string;

function bytesForBits(x: integer): integer;
function toBytes(x: array of dword): tBytes; overload;
function toBytes(x: array of word): tBytes; overload;

procedure Wait(ms: integer);
function  RND(): byte; assembler; register;
function  Quantize(value, levels: byte): byte;
function  Clip(x, a, b: integer): integer;
function  GetRDTSC(): uint64; assembler; register;
function  GetSec(): double;

function  GetTickCount(): int64;
function  GetMSCount(): int64;


implementation

uses
  test,
	debug;

var
	SEED: byte;

const
	CLOCK_FREQ = 166*1000*1000;	
  INV_CLOCK_FREQ: double = 1.0 / CLOCK_FREQ;


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

{----------------------------------------------------------}

{Cut down version of format}
function Format(fmt: string; args: array of Const): string;
var
	i, ArgIndex: Integer;
  InPlaceholder: Boolean;
  s: string;
  a: TVarRec;
begin
	result := '';
  s := '';
  ArgIndex := 0;
  InPlaceholder := False;

  for i := 1 to length(fmt) do begin
  	if fmt[i] = '%' then begin
    	if InPlaceholder then begin
      	result += '%';
        InPlaceholder := False;
      end else begin
      	InPlaceholder := True;
      end;
      continue;
    end;
    if InPlaceholder then begin
    	InPlaceholder := False;
      a := args[ArgIndex];
      case fmt[i] of
      	'd': begin
        	// integer
          case a.VType of
	          vtInteger: result += IntToStr(a.VInteger);
            vtExtended: result += IntToStr(trunc(a.VExtended^));
            else Error('Invalid type:'+IntToStr(a.VType));
          end;
	      end;
      	'f': begin
        	// float
          case a.VType of
	          vtExtended: Str(args[ArgIndex].VExtended^:0:2, s);
            else Error('Invalid type:'+IntToStr(a.VType));
          end;
          result += s;
	      end;
        's': begin
        	case a.VType of
        		vtInteger: result += IntToStr(args[ArgIndex].VInteger);
	        	vtString: result += string(args[ArgIndex].VString^);
            else Error('Invalid type:'+IntToStr(a.VType));
          end;
  	    end;
        'h': begin
        	case a.VType of
	        	vtInteger: result += HexStr(args[ArgIndex].VInteger, 4);
            else Error('Invalid type:'+IntToStr(a.VType));
          end;
  	    end;
        else
        	// ignore invalid
      end;
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

function bytesToStr(bytes: tBytes): string;
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
function getExtension(const filename: string): string;
var
	dotPos: integer;
begin
	dotPos := pos('.', filename);
  if dotPos >= 0 then
  	result := copy(filename, dotPos+1, length(filename) - dotPos)
  else
  	result := '';
  result := toLowerCase(result);
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

function StrToInt(s: string): integer;
var
	value, code: integer;
begin
	{todo: better way to handle errors}
	Val(s, value, code);
  if code <> 0 then debug.Error(Format('Invalid integer "%s"', [s]));
  result := value;
end;

{remove whitespace from begining and end of string.}
function Trim(s: string): string;
var
	i,j: integer;
  l: integer;
begin
	l := length(s);
	i := 1;
  j := l;
  while (s[i] in [' ', #9]) and (i <= l) do inc(i);
  while (s[j] in [' ', #9]) and (i >= i) do dec(j);
  result := copy(s, i, j - i + 1);	
end;

{Returns number of bytes required to encode this many bits}
function bytesForBits(x: integer): integer;
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

  {stub:}
  writeln(MSTarget-GetMsCount());

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

function Clip(x, a, b: integer): integer;
begin
	if x < a then exit(a);
  if x > b then exit(b);
  exit(x);
end;

function GetRDTSC(): uint64; assembler; register;
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

{Get seconds since power on.
Can be used for very accurate timing measurement}
function GetSec(): double; inline;
begin
    result := getRDTSC() * INV_CLOCK_FREQ;
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


function TMyDateTime.YYMMDD(sep: string='-'): string;
var
	y,m,d: word;
begin
	DecodeDate(y,m,d);
	result := IntToStr(y, 2) + sep + IntToStr(m, 2) + sep + IntToStr(d, 2);
end;

function TMyDateTime.HHMMSS(sep: string=':'): string;
var
	h,m,s,ss: word;
begin
	DecodeTime(h,m,s,ss);
	result := IntToStr(h, 2) + sep + IntToStr(m, 2) + sep + IntToStr(s, 2);
end;


{-------------------------------------------------------------------}

procedure UnitTests();
begin
  AssertEqual(StrToInt('123'), 123);
  AssertEqual(StrToInt('7'), 7);
  AssertEqual(Trim(' Fish'), 'Fish');
  AssertEqual(Trim(' Fish    '), 'Fish');
  AssertEqual(Trim('Fish'), 'Fish');

  AssertEqual(Format('%s', [5]), '5');

  AssertEqual(binToStr(5, 8), '00000101');
  AssertEqual(binToStr(0), '0');
  AssertEqual(binToStr(1), '1');  	
end;

begin
	SEED := 97;
	UnitTests();
end.
