{Quick and dirty test case support}
unit Test;

interface


type
	tBytes = array of byte;

procedure AssertEqual(value, expected: string); overload;
procedure AssertEqual(value, expected: int64); overload;
procedure AssertEqual(a, b: tBytes); overload;
procedure AssertEqualLarge(a, b: tBytes); overload;

implementation

uses
	utils,
	debug;

procedure AssertEqual(value, expected: string); overload;
begin
	if value <> expected then
  	Error('Test case failed, expecting "'+expected+'" but found "'+value+'".');
end;

procedure AssertEqual(a, b: tBytes); overload;
var
	i: integer;
  strA, strB: string;
begin
	strA := bytesToSanStr(a);
  strB := bytesToSanStr(b);
	if length(a) <> length(b) then
		Error('Test case failed, expecting "'+strb+'" but found "'+stra+'".');
  for i := 0 to length(a)-1 do
  	if a[i] <> b[i] then
    	Error('Test case failed, expecting "'+strb+'" but found "'+stra+'".');
end;

procedure AssertEqualLarge(a, b: tBytes); overload;
var
	i: int32;
begin
	if length(a) <> length(b) then
		Error('Test case failed, expecting "'+intToStr(length(b))+'" but found "'+intToStr(length(a))+'".');
  for i := 0 to length(a)-1 do
  	if a[i] <> b[i] then
    	Error('Test case failed, expecting "'+intToStr(b[i])+'" but found "'+intToStr(a[i])+' at pos '+intToStr(i)+'".');
end;

procedure AssertEqual(value, expected: int64); overload;
begin
	if value <> expected then
  	Error('Test case failed, expecting '+IntToStr(expected)+' but found '+IntToStr(value)+'.');
end;

begin
end.
