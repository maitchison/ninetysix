{Super simple git replacement}
program go;

{todo: support ansi strings I guess...
  well atleast make sure long strings work, or perhaps just ignore?
}

{$MODE delphi}

{

got commit "Comments"
  Commit all changes

got status
  List changes since last commit.

got revert
  Revert back to previous commit. (but save a stash first)

got loc
  Write line counts per day


Block header

[MD5] [Path] [Date] [Comment]

}

uses
  debug,
  test,
  crt, {remove this?}
  diff,
  utils,
  hashMap,
  md5,
  list,
  filesystem,
  dos;

type
  tDiffStats = record
    files: int32;
    added: int64;
    removed: int64;
    changed: int64;
    function net: int64;
    procedure print();
    procedure clear();

    class operator add(a,b: tDiffStats): tDiffStats;
  end;

{--------------------------------------------------------}

var
  newLines, oldLines: tLines;
  totalStats: tDiffStats;

var
  LINES_SINCE_PAGE: byte = 0;
  SILENT: boolean = false;
  USE_PAGING: boolean = true;
  PAUSE_AT_END: boolean = false;

{--------------------------------------------------------}
{ helpers }
{--------------------------------------------------------}

function textRows: byte;
begin
  result := mem[$0040:$0084]+1;
end;

procedure output(s: string);
begin
  {todo: detect line wrap}
  if SILENT then exit;
  write(s);
end;

{outputs a line of text, with support for paging}
procedure outputLn(s: string);
begin
  if SILENT then exit;
  writeln(s);


  if not USE_PAGING then exit;

  inc(LINES_SINCE_PAGE);
  if LINES_SINCE_PAGE+2 >= textRows() then begin
    textAttr := WHITE;
    write('                            ---- Continue -----');
    case readkey of
      'q': USE_PAGING := false;
      // done, or down... i.e. go to bottom and wait.
      'd': begin USE_PAGING := false; PAUSE_AT_END := true; end;
      #27: halt;
    end;
    LINES_SINCE_PAGE := 0;
    writeln();
  end;
end;

procedure outputX(a: string; b: string; c: string; col: byte);
var
  oldTextAttr: byte;
begin
  oldTextAttr := textAttr;
  textAttr := LIGHTGRAY;
  output(a);
  textAttr := col;
  output(b);
  textAttr := LIGHTGRAY;
  outputln(c);
  textAttr := oldTextAttr;
end;

{--------------------------------------------------------}

function tDiffStats.net: int64;
begin
  result := added - removed;
end;

procedure tDiffStats.clear();
begin
  files := 0;
  added := 0;
  removed := 0;
  changed := 0;
end;

procedure tDiffStats.print();
var
  plus: string;
begin
  if net > 0 then plus := '+' else plus := '';
  if added > 0 then
    outputX('Added   ', lpad(intToStr(added), 4),   ' lines.', LIGHTGREEN);
  if removed > 0 then
    outputX('Removed ', lpad(intToStr(removed), 4), ' lines.', LIGHTRED);
  if changed > 0 then
    outputX('Changed ', lpad(intToStr(changed), 4), ' lines.', CYAN);
  outputX('Net     ',   lpad(plus+intToStr(net), 4),' lines.', YELLOW);
end;

class operator tDiffStats.add(a,b: tDiffStats): tDiffStats;
begin
  result.files := a.files + b.files;
  result.added := a.added + b.added;
  result.removed := a.removed + b.removed;
  result.changed := a.changed + b.changed;
end;

{--------------------------------------------------------}

// not sure if needed, but wait for external filesystem to catch up.
procedure fsWait();
begin
  delay(200);
end;

{copies all '.pas' files from current path to destination folder.
if destination folder exists it is renamed, and then a new folder is
created. If back exists, it is removed.}
procedure safeCopy(destinationPath: string);
begin
  //stub
  destinationPath := trim(destinationPath);
  dos.exec(getEnv('COMSPEC'), '/C deltree /y '+destinationPath+'_tmp');
  fsWait;
  dos.exec(getEnv('COMSPEC'), '/C ren '+destinationPath+' '+destinationPath+'_tmp');
  fsWait;
  try
    mkDIR(destinationPath);
  except
    // ignore
  end;
  fsWait;
  dos.exec(getEnv('COMSPEC'), '/C copy *.inc '+destinationPath+' > nul');
  dos.exec(getEnv('COMSPEC'), '/C copy *.pas '+destinationPath+' > nul');
  dos.exec(getEnv('COMSPEC'), '/C copy *.bat '+destinationPath+' > nul');
  dos.exec(getEnv('COMSPEC'), '/C copy message.txt '+destinationPath+' > nul');
  dos.exec(getEnv('COMSPEC'), '/C deltree /y '+destinationPath+'_tmp');
end;


procedure commit(msg: string);
var
  sourcePath, destinationPath, command, folderName: string;
  t: text;
  time: tMyDateTime;
begin
  sourcePath := getENV('CWD');
  if sourcePath = '' then
    sourcePath := '.';

  time := now;

  assign(t,'message.txt');
  rewrite(t);
  writeln(t, msg);
  close(t);

  safeCopy('$rep\'+time.YYMMDD('')+'_'+time.HHMMSS(''));
  safeCopy('$rep\HEAD');

end;

{-----------------------------------------------------}

function readFile(filename: string): tLines;
var
  t: text;
  line: string;
  lines: tLines;
begin

  if not fs.exists(filename) then exit(nil);

  assign(t, filename);
  reset(t);
  lines := nil;
  while not EOF(t) do begin
    readln(t, line);
    setLength(lines, length(lines)+1);
    lines[length(lines)-1] := line;
  end;
  close(t);
  result := lines;
end;

{output the longest common subsequence. Returns stats}
function processDiff(newLines,oldLines: tLines;matching: tIntList): tDiffStats;

var
  i,j,k,z: int32;
  map: tHashMap;
  hash: word;
  oldS,newS: tIntList;
  new,old,cur: string;
  isFirst: boolean;
  plus: string;
  clock: int32;
var
  importantLines: array[0..1024-1] of boolean;

  procedure markImportant(pos: int32);
  var
    i: int32;
  begin
    for i := pos-2 to pos+2 do
      if (i >= 0) and (i < 1024) then
        importantLines[i] := true;
  end;

  function fix(s: string): string;
  var
    i: integer;
    c: byte;
  begin
    result := '';
    for i := 1 to length(s) do begin
      c := ord(s[i]);
      if c = 9 then
        result += '  '
      else if (c < 32) or (c >= 128) then
        result += '#('+intToStr(c)+')'
      else
        result += chr(c);
    end;

    if length(result) > 60 then begin
      setLength(result,60);
      result += '...';
    end;
  end;

  procedure processTail();
  begin
    while (j < length(oldLines)) and (oldLines[j] <> cur) do begin
      textAttr := LIGHTRED;
      outputLn(intToStr(j, 4, '0')+' [-] '+fix(oldLines[j]));
      inc(j);
      inc(result.removed);
    end;

    while (i < length(newLines)) and (newLines[i] <> cur) do begin
      textAttr := LIGHTGREEN;
      outputLn('     [+] '+fix(newLines[i]));
      inc(i);
      inc(result.added);
    end;
  end;

begin

  result.clear();
  result.files := 1;

  {which lines in old file should be shown for context}
  fillchar(importantLines, sizeof(importantLines), false);

  oldS := tIntList.create([]);
  for i := 1 to length(oldLines) do
    oldS.append(i);

  newS := tIntList.create([]);
  for i := 1 to length(newLines) do
    newS.append(i);

  {detect identical files}
  if matching.len = max(oldS.len, newS.len) then begin
    textAttr := WHITE;
    outputLn('Files are identical.');
    exit;
  end;

  {------------------------------------}
  { first pass to get important lines }

  i := 0;
  j := 0;
  k := 0;
  clock := 0;

  while k < matching.len do begin
    inc(clock);
    if clock > 1000 then exit;
    cur := oldLines[matching[k]-1];
    while (newLines[i] = cur) and (oldLines[j] = cur) do begin
      inc(i);
      inc(j);
      inc(k);
      if k < matching.len then begin
        cur := oldLines[matching[k]-1]
      end  else begin
        cur := '';
        break;
      end;
    end;

    while (j < length(oldLines)) and (oldLines[j] <> cur) do begin
      markImportant(j);
      inc(j);
    end;

    while (i < length(newLines)) and (newLines[i] <> cur) do begin
      markImportant(j);
      inc(i);
    end;
  end;

  {------------------------------------}

  i := 0;
  j := 0;
  k := 0;
  clock := 0;

  outputLn('');

  while k < matching.len do begin
    inc(clock);
    if clock > 1000 then exit;

    cur := oldLines[matching[k]-1];
    isFirst := true;

    textAttr := LIGHTGRAY;

    while (newLines[i] = cur) and (oldLines[j] = cur) do begin
      if isFirst then begin
        isFirst := false;
      end;

      if (j > 0) and (j < length(importantLines)) and (not importantLines[j-1]) and (importantLines[j]) then begin
        {chunk header}
        textAttr := DARKGRAY;
        for z := 1 to 14 do
          output(' ');
        for z := 1 to 55 do
          output(chr(196));
        outputLn('');
        textAttr := LIGHTGRAY;
      end;

      if (j < length(importantLines)) and importantLines[j] then
        outputLn(intToStr(j, 4, '0')+' [ ] '+fix(cur));

      inc(i);
      inc(j);
      inc(k);
      if k < matching.len then begin
        cur := oldLines[matching[k]-1]
      end  else begin
        {this will cause trailing blank lines to be ignored.}
        cur := '';
        break;
      end;
    end;
    processTail();
  end;

  processTail();

  outputLn('');
  textAttr := WHITE;

end;

var
  msg: string;

procedure benchmark();
var
  startTime, elapsed: double;
  merge: tIntList;
  sln: tLineRefs;
  new,old: tLines;
  diff: tDiff;
  i: integer;
begin
  {
    sln seems to be +140 / -13 = total of 153 lines
    464 lines match
    start: 14.2
    no writeln: 12.4
    sln from backtrace: 1.6
  }
  new := readFile('sample_new.txt');
  old := readFile('sample_old.txt');

  diff := tDiff.create();

  startTime := getSec;
  sln := diff.run(new, old);
  elapsed := getSec-startTime;

  merge := tIntList.create([]);
  for i := 0 to length(sln)-1 do
    merge.append(sln[i]);
  writeln(merge.toString);

  writeln('final score -> ',diff.scores[(length(new)*length(old))-1]);

  writeln(format('Took %f seconds', [elapsed]));
  writeln(merge.len);
  writeln('new        ',length(new));
  writeln('old        ',length(old));
  writeln('NM         ',length(new)*length(old));
end;

function runDiff(filename: string): tDiffStats;
var
  merge: tIntList;
  sln: tLineRefs;
  new,old: tLines;
  diff: tDiff;
  i: integer;
begin
  new := readFile(filename);
  old := readFile('$rep/head/'+filename);

  diff := tDiff.create();

  sln := diff.run(new, old);
  merge := tIntList.create([]);
  for i := 0 to length(sln)-1 do
    merge.append(sln[i]);
  result := processDiff(new, old, merge);
end;

procedure promptAndCommit();
begin
  write('Message:');
  readln(msg);
  commit(msg);
end;

(*
function filesMatch(file1, file2: string): boolean;
var
  a,b: tLines;
  i: int32;
begin
  a := readLines(file1);
  b := readLines(file2);
  if length(a) <> length(b) exit(false);
  for i := 0 to length(a)-1 do
    if a[i] <> b[i] then
       exit(false);
  exit(true);
end;
*)

function wasModified(file1, file2: string): boolean;
var
  t1,t2: longint;
  f1,f2: file;
begin
  t1 := 0;
  t2 := 0;
  assign(f1, file1);
  assign(f2, file2);
  reset(f1);
  reset(f2);
  getFTime(f1, t1);
  getFTime(f2, t2);
  close(f1);
  close(f2);
  result := t1 <> t2;
end;

function getSourceFiles(path: string): tStringList;
begin
  {todo: proper .gitignore style decision on what to include}
  if (length(path) > 0) and (path[length(path)] <> '\') then
    path += '\';
  result := fs.listFiles(path+'*.pas');
  result += fs.listFiles(path+'*.bat');
  result += fs.listFiles(path+'*.inc');
end;

{show all changed / added / deleted files}
procedure status();
var
  workingSpaceFiles: tStringList;
  headFiles: tStringList;
  filename: string;
  added,removed,changed: int32;
begin
  writeln();
  workingSpaceFiles := getSourceFiles('');
  headFiles := getSourceFIles('$rep\head\');
  added := 0;
  removed := 0;
  changed := 0;

  for filename in workingSpaceFiles do begin
    if not headFiles.contains(filename) then begin
      textattr := 10;
      writeln('[+] added ', filename);
      inc(added);
    end else begin
      if wasModified(filename, '$rep\head\'+filename) then begin
        textattr := 15;
        writeln('[~] modified ', filename);
        inc(changed);
      end;
    end;
  end;

  for filename in headFiles do begin
    if not workingSpaceFiles.contains(filename) then begin
      textattr := 12;
      writeln('removed ', filename);
      inc(removed);
    end;
  end;

  textattr := 15;
  if (added = 0) and (removed = 0) and (changed = 0) then
    writeln('No changes.');
  writeln();
end;

{show all diff on all modified files}
procedure diffOnWorkspace();
var
  workingSpaceFiles: tStringList;
  headFiles: tStringList;
  filename: string;
  fileStats: tDiffStats;
  stats: tDiffStats;
begin

  totalStats.clear();

  workingSpaceFiles := getSourceFiles('');
  headFiles := getSourceFiles('$rep\head\');

  fileStats.clear();

  outputLn('');

  for filename in headFiles do begin
    if workingSpaceFiles.contains(filename) then continue;
    textAttr := WHITE;
    outputLn('----------------------------------------');
    outputX (' Removed ',filename, '', LIGHTRED);
    outputLn('----------------------------------------');
    stats := runDiff(filename);
    inc(fileStats.removed);
  end;

  for filename in workingSpaceFiles do begin
    if not headFiles.contains(filename) then begin
      textAttr := WHITE;
      outputLn('----------------------------------------');
      outputX (' Added ',filename, '', LIGHTGREEN);
      outputLn('----------------------------------------');
      stats := runDiff(filename);
      inc(fileStats.added);
    end else begin
      if wasModified(filename, '$rep\head\'+filename) then begin
        textAttr := WHITE;
        outputLn('----------------------------------------');
        outputX (' Modified ', filename, '', YELLOW);
        outputLn('----------------------------------------');
        stats := runDiff(filename);
        textAttr := WHITE;
        //outputln(filename+':');
        totalStats += stats;
        inc(fileStats.changed);
      end;
    end;
  end;

  {todo: put summary here}

  textAttr := WHITE;
  outputLn('----------------------------------------');
  outputln(' Total');
  outputLn('----------------------------------------');
  totalStats.print();
end;


{--------------------------------------------------}

var
  command: string;

begin

  totalStats.clear();

  // screen is hard to read due to a dosbox-x bug, so we clear it
  // for visibility.
  textAttr := WHITE;
  clrscr;

  if (paramCount = 0) then
    command := 'status'
  else
    command := paramSTR(1);

  if command = 'diff' then
    diffOnWorkspace()
  else if command = 'commit' then
    promptAndCommit()
  else if command = 'benchmark' then
    benchmark()
  else if command = 'status' then
    status()
  else
    Error('Invalid command "'+command+'"');

  textAttr := WHITE;

  if PAUSE_AT_END then readkey;

end.
