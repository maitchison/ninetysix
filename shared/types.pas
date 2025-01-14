unit types;

interface

type
  tBytes = array of byte;
  tWords = array of word;
  tDWords = array of dword;
  tStrings = array of string;

type tDwordsHelper = record helper for tDwords
  procedure append(x: dword);
  end;

implementation

{-------------------------------------------------------------}

procedure tDwordsHelper.append(x: dword);
begin
  setLength(self, length(self)+1);
  self[length(self)-1] := x;
end;

begin
end.

