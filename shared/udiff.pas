{Unit for finding diffs between two files}
unit uDiff;

{helps a lot with performance}
{$R-,Q-}
{$OPTIMIZATION ON, LEVEL3}

{$MODE delphi}

interface

{todo: support LCS accross a line aswell}

uses
  uDebug,
  uTest,
  uTypes,
  uUtils,
  uFileSystem,
  uList,
  uHashMap;

type

  tScores = array of int16;

  tDiffSolver = class

  private
    a, b: tStringList;

  protected
    scores: tScores;

    function  getScore(i,j: int32): int16; inline;
    procedure setScore(i,j: int32;value: int16); inline;

    procedure init(newLines, oldLines: tStringList);
    function  solve(i,j: int32): int32;
    procedure blockSolve(maxEdits: int32=-1);
    function  extractSolution(): tIntList;

  public

    constructor create();
    function run(oldLines, newLines: tStringList): tIntList;
    function solutionLength(): int16;
    {debug stuff}
    procedure debugPrintPaths();
    procedure debugLogPaths();
    function debugCacheUsed(): int32;
  end;

  tDiffStats = record
    added: int64;
    removed: int64;
    changed: int64;
    unchanged: int64;
    function net: int64;
    function newLen: int64;
    function oldLen: int64;
    procedure clear();
    class operator add(a,b: tDiffStats): tDiffStats;
  end;

function testLines(s: string): tStringList;

function run(oldLines, newLines: tStringList): tIntList;

implementation

{-----------------------------------------------}

function testLines(s: string): tStringList;
var
  i: int32;
begin
  result := tStringList.create(length(s));
  for i := 0 to length(s)-1 do
    result[i] := s[i+1];
end;

function run(oldLines, newLines: tStringList): tIntList;
var
  diff: tDiffSolver;
begin
  diff := tDiffSolver.create();
  result := diff.run(oldLines, newLines);
  diff.free;
end;

{-----------------------------------------------}

constructor tDiffSolver.create();
begin
  scores := nil;
  a.clear();
  b.clear();
end;

function tDiffSolver.getScore(i,j: int32): int16; inline;
begin
  if (i = 0) or (j = 0) then exit(0);
  if (i < 0) or (j < 0) then exit(-1);
  if (i > a.len) or (j > b.len) then exit(-1);
  result := scores[(i-1)+(j-1)*a.len];
end;

procedure tDiffSolver.setScore(i,j: int32;value: int16); inline;
begin
  if (i <= 0) or (j <= 0) then runError(201);
  if (i > a.len) or (j > b.len) then runError(201);
  scores[(i-1)+(j-1)*a.len] := value;
end;

function tDiffSolver.extractSolution(): tIntList;
var
  i,j,k: word;
  option1,option2,option3: int32;
  best: int32;
  sln: tIntList;
  slnLen: int32;
  canMatch: boolean;
begin

  {we start the end and go backwards}
  i := a.len;
  j := b.len;
  k := 0;

  slnLen := getScore(i,j);
  if slnLen < 0 then
    fatal('Call solve first');

  sln := tIntList.create(slnLen);

  while (i>0) and (j>0) do begin

    canMatch := a[i-1] = b[j-1];

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
  result := tIntList.create(k);
  for i := 1 to k do
    result[i-1] := sln[k-i];

end;

procedure tDiffSolver.init(newLines, oldLines: tStringList);
begin
  a := newLines;
  b := oldLines;
  if (b.len > 4*1024) or (b.len > 4*1024) then
    fatal('Max length for diff is 4k');
  scores := nil;
  setLength(scores, a.len*b.len);
  if a.len*b.len > 0 then
    fillword(scores[0], a.len*b.len, word(-1));
end;

function tDiffSolver.solutionLength(): int16;
begin
  result := getScore(a.len, b.len);
end;

{returns the lines that match between new and old
lines numbers are from oldLines
}
function tDiffSolver.run(oldLines, newLines: tStringList): tIntList;
var
  minChanges, maxChanges: int32;
  editLimit: int32;
begin

  {special cases for empty files }
  if (oldLines.len = 0) or (newLines.len = 0) then begin
    {new file, no lines match}
    result.clear();
    exit;
  end;

  init(newLines, oldLines);
  maxChanges := oldLines.len + newLines.len;
  minChanges := max(abs(oldLines.len - newLines.len), 1);
  editLimit := (minChanges + 10) div 2;
  repeat
    editLimit *= 2;
    blockSolve(editLimit);
    if solutionLength >= 0 then break;
  until (editLimit > maxChanges);
  assert(solutionLength >= 0, 'Diff algorithm did not produce a result.');
  result := extractSolution();
end;

{returns the length of the longest common subsequence between a[:i], and b[:j]}
function tDiffSolver.solve(i,j: int32): int32;
var
  u,v: int32;
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
    u := solve(i, j-1);
    v := solve(i-1, j);
    if u > v then result := u else result := v;
  end;

  {...and store the result}
  setScore(i, j, result);
end;

procedure tDiffSolver.blockSolve(maxEdits: int32=-1);
var
  i,j: int32;
  u,v: int32;
  score: int32;
  edits: int32;
  iMin,iMax: int32;
begin
  for j := 1 to b.len do begin

    if maxEdits < 0 then begin
      iMin := 1;
      iMax := a.len;
    end else begin
      iMin := clamp(j - maxEdits, 1, a.len);
      iMax := clamp(j + maxEdits, 1, a.len);
    end;

    for i := iMin to iMax do begin
      if a[i-1] = b[j-1] then begin
        score := getScore(i-1,j-1)+1;
      end else begin
        u := getScore(i, j-1);
        v := getScore(i-1, j);
        if u > v then score := u else score := v;
      end;
      setScore(i,j,score);
    end;
  end;
end;

procedure tDiffSolver.debugPrintPaths();
var
  i,j: int32;
begin
  for j := 1 to b.len do begin
    for i := 1 to a.len do begin
      if getScore(i,j) < 0 then
        write('[ . ]')
      else
        write('[',intToStr(getScore(i,j),3), ']');
    end;
    writeln();
  end;
end;


procedure tDiffSolver.debugLogPaths();
var
  i,j: int32;
  s: string;
begin
  for j := 1 to b.len do begin
    s := '';
    for i := 1 to a.len do begin
      if getScore(i,j) = -1 then
        s += ('[ . ]')
      else
        s += '['+intToStr(getScore(i,j),3)+']';
    end;
    info(s);
  end;
end;

function tDiffSolver.debugCacheUsed(): int32;
var
  i,j: int32;
begin
  result := 0;
  for j := 1 to b.len do
    for i := 1 to a.len do
      if getScore(i,j) >= 0 then
        inc(result);
end;

{-------------------------------------------------------------}

function tDiffStats.net: int64;
begin
  result := added - removed;
end;

function tDiffStats.newLen: int64;
begin
  result := added + unchanged;
end;

function tDiffStats.oldLen: int64;
begin
  result := removed + unchanged;
end;

procedure tDiffStats.clear();
begin
  added := 0;
  removed := 0;
  changed := 0;
  unchanged := 0;
end;

class operator tDiffStats.add(a,b: tDiffStats): tDiffStats;
begin
  result.added := a.added + b.added;
  result.removed := a.removed + b.removed;
  result.changed := a.changed + b.changed;
  result.unchanged := a.unchanged + b.unchanged;
end;

{--------------------------------------------------------------------}

type
  tDiffTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tDiffTest.run();
var
  sln: tIntList;
  diff: tDiffSolver;
begin

  diff := tDiffSolver.create();

  sln := diff.run(testLines(''), testLines(''));
  assertEqual(sln.toString,'[]');

  sln := diff.run(testLines('ABC'), testLines(''));
  assertEqual(sln.toString,'[]');

  sln := diff.run(testLines(''), testLines('ABC'));
  assertEqual(sln.toString,'[]');

  sln := diff.run(testLines('ABC'), testLines('ABC'));
  assertEqual(sln.toString,'[1,2,3]');

  sln := diff.run(testLines('ABXXEDA'), testLines('ABCD'));
  assertEqual(sln.toString,'[1,2,6]');

  diff.free;

end;

{--------------------------------------------------------------------}

initialization
  tDiffTest.create('Diff');
end.
