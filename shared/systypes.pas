unit sysTypes;

interface

type
  tBytes = array of byte;
  tInt8s = array of int8;
  tWords = array of word;
  tDWords = array of dword;
  tInt16s = array of int16;
  tInt32Array = array of int32;
  tStrings = array of string;

type tStringsHelper = record helper for tStrings
  procedure append(s: string);
  end;

type tDwordsHelper = record helper for tDwords
  procedure append(x: dword);
  function  toString(maxEntries: int32=16): string;
  end;

type tInt32ArrayHelper = record helper for tInt32Array
  procedure append(x: int32);
  function  toString(maxEntries: int32=16): string;
  end;

type tBytesHelper = record helper for tBytes
  procedure append(x: byte);
  function  toString(maxEntries: int32=64): string;
  end;

{constructors}
function Int32Array(s: string): tInt32Array;

implementation

uses
  test, debug,
  utils;

{-------------------------------------------------------------}

procedure tStringsHelper.append(s: string);
begin
  setLength(self, length(self)+1);
  self[length(self)-1] := s;
end;


{-------------------------------------------------------------}

procedure tDwordsHelper.append(x: dword);
begin
  setLength(self, length(self)+1);
  self[length(self)-1] := x;
end;

function tDwordsHelper.toString(maxEntries: int32=16): string;
var
  i: int32;
begin
  result := '[';
  for i := 0 to length(self)-1 do begin
    if i > maxEntries then begin
      result +='...,';
      break;
    end;
    result += intToStr(self[i])+',';
  end;
  if length(result) > 1 then
    {remove comma}
    result := copy(result, 1, length(result)-1);
  result += ']';
end;

{-------------------------------------------------------------}

procedure tInt32ArrayHelper.append(x: int32);
begin
  setLength(self, length(self)+1);
  self[length(self)-1] := x;
end;

function tInt32ArrayHelper.toString(maxEntries: int32=16): string;
var
  i: int32;
begin
  result := '[';
  for i := 0 to length(self)-1 do begin
    if i > maxEntries then begin
      result +='...,';
      break;
    end;
    result += intToStr(self[i])+',';
  end;
  if length(result) > 1 then
    {remove comma}
    result := copy(result, 1, length(result)-1);
  result += ']';
end;

function Int32Array(s: string): tInt32Array;
var
  i: integer;
  start: integer;
  value: integer;
  numberLength: integer;
begin
  setLength(result, 0);
  numberLength := 0;
  for i := 1 to length(s) do begin
    case s[i] of
      '[': continue;
      '-': if numberLength > 0 then fatal('Invalid placement of "-" in :'+s) else inc(numberLength);
      '0'..'9': inc(numberLength);
      ',': begin
        if numberLength = 0 then
          fatal('Invalid tInt32Array string: '+s);
        value := strToInt(copy(s,i-numberLength,numberLength));
        result.append(value);
        numberLength := 0;
      end;
      ']': begin
        if i <> length(s) then fatal('Found characters after ]: '+s);
        {process final number (if any)}
        if numberLength = 0 then exit;
        value := strToInt(copy(s,i-numberLength,numberLength));
        result.append(value);
        exit;
      end;
      else fatal('Invalid character "'+s[i]+'" in tInt32Array string: '+s);
    end;
  end;
  fatal('String missing ]');
end;

{-------------------------------------------------------------}

procedure tBytesHelper.append(x: byte);
begin
  setLength(self, length(self)+1);
  self[length(self)-1] := x;
end;

function tBytesHelper.toString(maxEntries: int32=64): string;
var
  i: int32;
begin
  result := '[';
  for i := 0 to length(self)-1 do begin
    if i > maxEntries then begin
      result +='...,';
      break;
    end;
    result += intToStr(self[i])+',';
  end;
  if length(result) > 1 then
    {remove comma}
    result := copy(result, 1, length(result)-1);
  result += ']';
end;

{--------------------------------------------------------}

type
  tTypesTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tTypesTest.run();
var
  s: string;
  outData: tInt32Array;
const
  inData: tInt32Array = [1,2,9,-1,1000, 1200007];
begin
  s := inData.toString();
  outData := Int32Array(s);
  assertEqual(inData.toString(), outData.toString());
end;

{--------------------------------------------------------}

initialization
  tTypesTest.create('Types');
finalization

end.

