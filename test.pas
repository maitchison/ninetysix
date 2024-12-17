{Quick and dirty test case support}
unit Test;

interface


type
  tBytes = array of byte;

  tTestSuite = class
  private
    tag: string;
  public
    constructor create(aTag: string='');
    procedure run(); virtual;
  end;

procedure assertError(msg: string); overload;

procedure assert(condition: boolean;msg: string); overload;
procedure assertEqual(value, expected: string); overload;
procedure assertEqual(value, expected: int64); overload;
procedure assertEqual(a, b: tBytes); overload;
procedure assertEqualLarge(a, b: tBytes); overload;

procedure runTestSuites();
procedure addTestSuite(suite: tTestSuite);

implementation

uses
  utils,
  debug;

var
  testSuites: array of tTestSuite = nil;

procedure assertError(msg: string); overload;
begin
  error('Test case failed: '+msg);
end;

procedure assert(condition: boolean;msg: string); overload;
begin
  if not condition then assertError(msg);
end;

procedure assertEqual(value, expected: string); overload;
begin
  if value <> expected then
    assertError('Expecting "'+expected+'" but found "'+value+'".');
end;

procedure assertEqual(a, b: tBytes); overload;
var
  i: integer;
  strA, strB: string;
begin
  strA := bytesToSanStr(a);
  strB := bytesToSanStr(b);
  if length(a) <> length(b) then
    assertError('Expecting "'+strb+'" but found "'+stra+'".');
  for i := 0 to length(a)-1 do
    if a[i] <> b[i] then
      assertError('Expecting "'+#13#10+strb+'" but found "'+#13#10+stra+'".');
end;

procedure assertEqualLarge(a, b: tBytes); overload;
var
  i: int32;
begin
  if length(a) <> length(b) then
    assertError('Expecting "'+intToStr(length(b))+'" but found "'+intToStr(length(a))+'".');
  for i := 0 to length(a)-1 do
    if a[i] <> b[i] then
      assertError('Expecting "'+intToStr(b[i])+'" but found "'+intToStr(a[i])+' at pos '+intToStr(i)+'".');
end;

procedure assertEqual(value, expected: int64); overload;
begin
  if value <> expected then
    assertError('Expecting '+IntToStr(expected)+' but found '+intToStr(value)+'.');
end;

{--------------------------------------------------------}

constructor tTestSuite.create(aTag: string='');
begin
  inherited create();
  tag := aTag;
end;

procedure tTestSuite.run();
begin
  error('Empty test suite!');
end;

procedure addTestSuite(suite: tTestSuite);
begin
  setLength(testSuites, length(testSuites) + 1);
  testSuites[length(testSuites)-1] := suite;
end;

procedure runTestSuites();
var
  i: int32;
begin
  note('Running test cases...');
  for i := 0 to length(testSuites)-1 do begin
    note('  [test] '+testSuites[i].tag);
    testSuites[i].run();
  end;
  note('Finished running test cases.');
end;

begin
end.
