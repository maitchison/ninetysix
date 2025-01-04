{Unit for finding diffs between two files}
unit diff;

{$MODE delphi}

interface

{todo: support LCS accross a line aswell}

uses
  debug,
  test,
  types,
  utils;

type

  {todo: switch to tStringList}
  tLines = array of string;
  tLineRefs = array of int32;
  tScores = array of int16;

  tDiff = class

  private
    a, b: tLines;

  {stub}
  public
    scores: tScores;

    function getScore(i,j: int32): int16; inline;
    procedure setScore(i,j: int32;value: int16); inline;

    procedure init(newLines, oldLines: tLines);
    function solve(i,j: int32): int32;
    function extractSolution(): tLineRefs;

  public
    constructor create();
    function run(newLines, oldLines: tLines): tLineRefs;
    {debug stuff}
    procedure debugPrintPaths();
    procedure debugLogPaths();
    function debugCacheUsed(): int32;
  end;

function testLines(s: string): tLines;

implementation

function testLines(s: string): tLines;
var
  i: int32;
begin
  result := nil;
  setLength(result, length(s));
  for i := 0 to length(s)-1 do
    result[i] := s[i+1];
end;


constructor tDiff.create();
begin
  scores := nil;
  a := nil;
  b := nil;
end;

function tDiff.getScore(i,j: int32): int16; inline;
begin
  if (i = 0) or (j = 0) then exit(0);
  if (i < 0) or (j < 0) then exit(-1);
  if (i > length(a)) or (j > length(b)) then exit(-1);
  result := scores[(i-1)+(j-1)*length(a)];
end;

procedure tDiff.setScore(i,j: int32;value: int16); inline;
begin
  if (i <= 0) or (j <= 0) then runError(201);
  if (i > length(a)) or (j > length(b)) then runError(201);
  scores[(i-1)+(j-1)*length(a)] := value;
end;

function tDiff.extractSolution(): tLineRefs;
var
  i,j,k: word;
  matchCost: word;
  option1,option2,option3: int32;
  current, best: int32;
  sln: tLineRefs;
  slnLen: int32;
  canMatch: boolean;
begin
  {we start the end and go backwards}
  i := length(a);
  j := length(b);
  k := 0;

  slnLen := getScore(i,j);
  if slnLen < 0 then
    Error('Call solve first');

  sln := nil;
  setLength(sln, slnLen);

  while (i>0) and (j>0) do begin

    canMatch := a[i-1] = b[j-1];

    current := getScore(i,j);
    option1 := getScore(i-1,j-1);
    option2 := getScore(i,j-1);
    option3 := getScore(i-1,j);
    best := max(option1, option2, option3);

    if (option1 = best) and canMatch then begin
      sln[k] := j;
      inc(k);
      dec(i);
      dec(j);
    end else if option2 = best then
      dec(j)
    else
      dec(i);
  end;

  {reverse order to get solution.}
  result := nil;
  setLength(result, k);
  for i := 1 to k do
    result[i-1] := sln[k-i];

end;

procedure tDiff.init(newLines, oldLines: tLines);
begin
  a := newLines;
  b := oldLines;
  if (length(b) > 4*1024) or (length(b) > 4*1024) then
    Error('Max length for diff is 4k');
  scores := nil;
  setLength(scores, length(a)*length(b));
  if length(a)*length(b) > 0 then
    fillword(scores[0], length(a)*length(b), word(-1));
end;

{returns the lines that match between new and old
lines numbers are from oldLines
}
function tDiff.run(newLines, oldLines: tLines): tLineRefs;
var
  m,n: int32;
begin
  init(newLines, oldLines);
  solve(length(a), length(b));
  result := extractSolution();
end;

{returns the length of the longest common subsequence between a[:i], and b[:i]}
function tDiff.solve(i,j: int32): int32;
begin

  {lookup cache}
  result := getScore(i,j);
  if result >= 0 then
    exit(result);

  {trivial cases}
  if (i = 0) or (j = 0) then begin
     setScore(i, j, 0);
    exit(0);
  end;

  {check our cases...}
  if a[i-1] = b[j-1] then begin
    result := solve(i-1,j-1)+1;
  end else begin
    result := max(solve(i, j-1), solve(i-1, j));
  end;

  {...and store the result}
  setScore(i, j ,result);
end;


procedure tDiff.debugPrintPaths();
var
  i,j: int32;
begin
  for j := 1 to length(b) do begin
    for i := 1 to length(a) do begin
      if getScore(i,j) < 0 then
        write('[ . ]')
      else
        write('[',intToStr(getScore(i,j),3), ']');
    end;
    writeln();
  end;
end;


procedure tDiff.debugLogPaths();
var
  i,j: int32;
  s: string;
begin
  for j := 1 to length(b) do begin
    s := '';
    for i := 1 to length(a) do begin
      if getScore(i,j) = -1 then
        s += ('[ . ]')
      else
        s += '['+intToStr(getScore(i,j),3)+']';
    end;
    info(s);
  end;
end;

function tDiff.debugCacheUsed(): int32;
var
  i,j: int32;
begin
  result := 0;
  for j := 1 to length(b) do
    for i := 1 to length(a) do
      if getScore(i,j) >= 0 then
        inc(result);
end;

{--------------------------------------------------------------------}

function toBytes(refs: tLineRefs): tBytes;
var
  i: int32;
begin
  result := nil;
  setLength(result, length(refs));
  for i := 0 to length(refs)-1 do
    result[i] := refs[i];
end;

procedure runTests();
var
  new,old: tLines;
  sln: tLineRefs;
  diff: tDiff;
begin

  diff := tDiff.create();

  sln := diff.run(testLines(''), testLines(''));
  assertEqual(toBytes(sln),[]);

  sln := diff.run(testLines('ABC'), testLines(''));
  assertEqual(toBytes(sln),[]);

  sln := diff.run(testLines(''), testLines('ABC'));
  assertEqual(toBytes(sln),[]);

  sln := diff.run(testLines('ABC'), testLines('ABC'));
  assertEqual(toBytes(sln),[1,2,3]);

  sln := diff.run(testLines('ABCD'), testLines('ABXXEDA'));
  assertEqual(toBytes(sln),[1,2,6]);

  diff.free;

end;

begin
  runTests();
end.
