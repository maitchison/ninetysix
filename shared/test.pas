{Quick and dirty test case support}
unit test;

interface

uses
  sysTypes;

type

  tTestSuite = class
  private
    tag: string;
  public
    constructor create(aTag: string='');
    procedure run(); virtual;
  end;


procedure assertError(msg: string); overload;

{todo: move these to testSuite}
procedure assert(condition: boolean;msg: string); overload;
procedure assertClose(value, expected: extended;epsilon: extended=1e-6);
procedure assertEqual(value, expected: string); overload;
procedure assertEqual(value, expected: int64); overload;
procedure assertEqual(value, expected: extended); overload;
procedure assertEqual(a, b: tBytes); overload;
procedure assertEqualLarge(a, b: tBytes); overload;

procedure runTestSuites();

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

procedure assertClose(value, expected: extended;epsilon: extended=1e-6);
begin
  if abs(value-expected) > epsilon then
    assertError(format(
      'Expecting %.7f to be close to %.7f but differed by %.7f which is more than %.7f.',
      [value, expected, abs(value-expected), epsilon]
    ));
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

procedure assertEqual(value, expected: extended); overload;
begin
  if value <> expected then
    assertError('Expecting '+fltToStr(expected)+' but found '+fltToStr(value)+'.');
end;

{--------------------------------------------------------}

procedure addTestSuite(suite: tTestSuite);
begin
  setLength(testSuites, length(testSuites) + 1);
  testSuites[length(testSuites)-1] := suite;
end;

procedure runTestSuites();
var
  i: int32;
begin
  info('Running test cases...');
  for i := 0 to length(testSuites)-1 do begin
    note('  [test] '+testSuites[i].tag);
    testSuites[i].run();
  end;
  note('   (finished running test cases)');
end;


{--------------------------------------------------------}

constructor tTestSuite.create(aTag: string='');
begin
  inherited create();
  tag := aTag;
  addTestSuite(self);
end;

procedure tTestSuite.run();
begin
  error('Empty test suite!');
end;

var i: integer;

initialization

finalization
  for i := 0 to length(testSuites)-1 do begin
    testSuites[i].free();
  end;
end.
