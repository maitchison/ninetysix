unit types;

interface

type
  tBytes = array of byte;
  tWords = array of word;
  tDWords = array of dword;
  tStrings = array of string;

type tDwordsHelper = record helper for tDwords
  procedure append(x: dword);
  function  toString(maxEntries: int32=16): string;
  end;

implementation

uses
  utils;

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


begin
end.

