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
  checkpoint,
  md5,
  list,
  filesystem,
  dos;

type
  tDiffStats = record
    added: int64;
    removed: int64;
    changed: int64;
    newLen: int64;
    function net: int64;
    function unchanged: int64;
    procedure print();
    procedure printShort(padding: integer=3);
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

var
  WORKSPACE: string = '';
  HEAD: string = '$rep\HEAD\';

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

function tDiffStats.unchanged: int64;
begin
  result := newLen - added - changed;
end;

procedure tDiffStats.clear();
begin
  added := 0;
  removed := 0;
  changed := 0;
  newLen := 0;
end;

procedure tDiffStats.print();
var
  plus: string;
begin
  if net > 0 then plus := '+' else plus := '';
  if added > 0 then
    outputX('Added     ', lpad(intToStr(added), 4),     ' lines.', LIGHTGREEN);
  if removed > 0 then
    outputX('Removed   ', lpad(intToStr(removed), 4),   ' lines.', LIGHTRED);
  if changed > 0 then
    outputX('Changed   ', lpad(intToStr(changed), 4),   ' lines.', CYAN);
  //if unchanged > 0 then
  //  outputX('Unchanged ', lpad(intToStr(unchanged), 4), ' lines.', DARKGRAY);
  outputX  ('Net       ', lpad(plus+intToStr(net), 4),  ' lines.', YELLOW);
end;

procedure tDiffStats.printShort(padding: integer=3);
var
  plus: string;
  oldTextAttr: byte;
begin
  oldTextAttr := textAttr;
  textAttr := LIGHTGRAY;
  output('(');
  textAttr := LIGHTGREEN;
  output(intToStr(added, padding, ' ')+' ');
  textAttr := LIGHTRED;
  output(intToStr(removed, padding, ' ')+' ');
  {textAttr := CYAN;
  if changed > 0 then output(intToStr(changed, padding, ' ')+' ');}
  textAttr := YELLOW;
  if net > 0 then plus := '+' else plus := '';
  output(lpad(plus+intToStr(net), padding, ' '));
  textAttr := LIGHTGRAY;
  output(')');
  textAttr := oldTextAttr;
end;

class operator tDiffStats.add(a,b: tDiffStats): tDiffStats;
begin
  result.added := a.added + b.added;
  result.removed := a.removed + b.removed;
  result.changed := a.changed + b.changed;
  result.newLen := a.newLen + b.newLen;
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

begin

  result.clear();
  result.newLen := length(newLines);

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

  {handle the added / deleted cases, which don't work for some reason}
  {note: this might indicate a big with changes at the end being missing}
  if matching.len = 0 then begin
    for i := 0 to length(oldLines)-1 do begin
      textAttr := LIGHTRED;
      outputLn(intToStr(i+1, 4, '0')+' [-] '+fix(oldLines[i]));
      inc(result.removed);
    end;
    for i := 0 to length(newLines)-1 do begin
      textAttr := LIGHTGREEN;
      outputLn(intToStr(i+1, 4, '0')+' [+] '+fix(newLines[i]));
      inc(result.added);
    end;
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
        outputLn(intToStr(j+1, 4, '0')+' [ ] '+fix(cur));

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

    while (j < length(oldLines)) and (oldLines[j] <> cur) do begin
      textAttr := LIGHTRED;
      outputLn(intToStr(j+1, 4, '0')+' [-] '+fix(oldLines[j]));
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

{todo: make paths fully qualified, and drop HEAD, WORKSPACE here}
function runDiff(filename: string; otherFilename: string=''; printOutput: boolean=true): tDiffStats;
var
  merge: tIntList;
  sln: tLineRefs;
  new,old: tLines;
  diff: tDiff;
  i: integer;
  oldSilent: boolean;
begin

  oldSilent := SILENT;
  if not printOutput then
    SILENT := true;

  if otherFilename = '' then otherFilename := filename;

  new := readFile(joinPath(WORKSPACE, filename));
  old := readFile(joinPath(HEAD, otherFilename));

  diff := tDiff.create();

  sln := diff.run(new, old);
  merge := tIntList.create([]);
  for i := 0 to length(sln)-1 do
    merge.append(sln[i]);
  result := processDiff(new, old, merge);

  SILENT := oldSilent;
end;

procedure promptAndCommit();
begin
  write('Message:');
  readln(msg);
  commit(msg);
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

{checks if originalFile is very similar to any of the other files in
 filesToCheck, and if so returns the matching new filename}
function checkForRename(originalFile: string; filesToCheck: tStringList): string;
var
  filename: string;
  ourFileSize: int64;
  filesizeRatio: double;
  changedratio: double;
  stats: tDiffStats;
begin
  result := '';

  ourFileSize := fs.fileSize(joinPath(WORKSPACE, originalFile));

  // we don't check very small files
  if ourFileSize < 64 then exit;

  for filename in filesToCheck do begin
    // do not check ourselves
    if filename = originalFile then continue;
    fileSizeRatio := fs.fileSize(joinPath(HEAD, filename)) / ourFileSize;
    //outputln(format('fileSizeRatio %f %s %s ', [fileSizeRatio, originalFile, filename]));
    if (fileSizeRatio > 1.25) or (fileSizeRatio < 0.8) then continue;
    stats := runDiff(originalFile, filename, false);
    changedRatio := stats.unchanged / stats.newLen;
    //outputln(format('changeratio %f %s %s ', [changedRatio, originalFile, filename]));
    if (changedRatio > 1.1) or (changedRatio < 0.9) then continue;
    result := filename;
    exit;
  end;
end;


{show all changed / added / deleted files}
procedure status();
var
  workingSpaceFiles: tStringList;
  renamedFiles: tStringList;
  headFiles: tStringList;
  filename, renamedFile: string;
  added,removed,changed,renamed: int32;
  stats: tDiffStats;
begin

  outputln('');
  renamedFiles.clear();
  workingSpaceFiles := getSourceFiles(WORKSPACE);
  headFiles := getSourceFiles(HEAD);
  added := 0;
  removed := 0;
  changed := 0;
  renamed := 0;

  // look for files that were renamed
  for filename in workingSpaceFiles do begin
    if headFiles.contains(filename) then continue;
    renamedFile := checkForRename(filename, headFiles);
    if renamedFile <> '' then begin
      textattr := LIGHTBLUE;
      stats := runDiff(filename, renamedFile, false);
      output(pad('[>] renamed '+filename+' to '+renamedFile, 40, ' '));
      stats.printShort();
      outputln('');
      inc(renamed);
    end;
    renamedFiles += filename;
    renamedFiles += renamedFile;
  end;

  for filename in workingSpaceFiles do begin
    if renamedFiles.contains(filename) then continue;
    if not headFiles.contains(filename) then begin
      textattr := LIGHTGREEN;
      stats := runDiff(filename, filename, false);
      output(pad('[+] added ' + filename, 40, ' '));
      stats.printShort();
      outputln('');
      inc(added);
    end else begin
      if fs.wasModified(joinPath(WORKSPACE, filename), joinPath(HEAD, filename)) then begin
        textattr := WHITE;
        stats := runDiff(filename, filename, false);
        output(pad('[~] modified ' + filename, 40, ' '));
        stats.printShort();
        outputln('');
        inc(changed);
      end;
    end;
  end;

  for filename in headFiles do begin
    if renamedFiles.contains(filename) then continue;
    if not workingSpaceFiles.contains(filename) then begin
      textattr := LIGHTRED;
      stats := runDiff(filename, filename, false);
      output(pad('[-] removed ' + filename, 40, ' '));
      stats.printShort();
      outputln('');
      inc(removed);
    end;
  end;

  textattr := WHITE;
  if (added = 0) and (removed = 0) and (changed = 0) and (renamed = 0) then
    outputLn('No changes.');
  outputLn('');

end;

{show all diff on all modified files}
function diffOnWorkspace(): tDiffStats;
var
  workingSpaceFiles: tStringList;
  headFiles: tStringList;
  filename: string;
  fileStats: tDiffStats;
  stats: tDiffStats;
  renamedFile: string;
  renamedFiles: tStringList;
begin

  totalStats.clear();

  workingSpaceFiles := getSourceFiles(WORKSPACE);
  headFiles := getSourceFiles(HEAD);

  fileStats.clear();

  outputLn('');

  renamedFiles.clear();

  // look for files that were renamed
  for filename in workingSpaceFiles do begin
    if headFiles.contains(filename) then continue;
    renamedFile := checkForRename(filename, headFiles);
    if renamedFile = '' then continue;
    // we found a renamed file
    textAttr := WHITE;
    outputLn('----------------------------------------');
    outputX (' Renamed ',filename+' -> '+renamedFile, '', LIGHTBLUE);
    outputLn('----------------------------------------');
    stats := runDiff(filename, renamedFile);
    totalStats += stats;
    inc(fileStats.added);
    renamedFiles += filename;
    renamedFiles += renamedFile;
  end;

  for filename in headFiles do begin
    if workingSpaceFiles.contains(filename) then continue;
    if renamedFiles.contains(filename) then continue;
    textAttr := WHITE;
    outputLn('----------------------------------------');
    outputX (' Removed ',filename, '', LIGHTRED);
    outputLn('----------------------------------------');
    stats := runDiff(filename);
    totalStats += stats;
    inc(fileStats.removed);
  end;

  for filename in workingSpaceFiles do begin
    if renamedFiles.contains(filename) then continue;
    if not headFiles.contains(filename) then begin
      textAttr := WHITE;
      outputLn('----------------------------------------');
      outputX (' Added ',filename, '', LIGHTGREEN);
      outputLn('----------------------------------------');
      stats := runDiff(filename);
      totalStats += stats;
      inc(fileStats.added);
    end else begin
      if not fs.wasModified(joinPath(WORKSPACE, filename), joinPath(HEAD, filename)) then continue;
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

  textAttr := WHITE;
  outputLn('----------------------------------------');
  status();
  outputLn('----------------------------------------');
  outputln(' Total');
  outputLn('----------------------------------------');
  totalStats.print();

  result := totalStats;

end;

{--------------------------------------------------}

{generate per commit stats. Quite slow}
procedure stats();
var
  cpm: tCheckpointManager;
  checkpoints: tStringList;
  checkpoint: string;
  previousCheckpoint: string;
  folderA, folderB: string;
  counter: int32;
  stats: tDiffStats;
var
  csvFile: text;
begin

  textAttr := WHITE;

  cpm := tCheckpointManager.create('$repo');

  checkpoints := fs.listFiles('$repo\*.txt');
  checkpoints.sort();

  previousCheckpoint := '';
  folderA := joinPath('$repo', 'a');
  folderB := joinPath('$repo', 'b');
  fs.delFolder(folderA);
  fs.delFolder(folderB);
  fs.mkdir(folderA);

  WORKSPACE := folderA;
  HEAD := folderB;

  counter := 0;

  assign(csvFile, 'stats.csv');
  rewrite(csvFile);

  writeln(csvFile, 'Checkpoint, Date, Added, Removed, Changed');

  for checkpoint in checkpoints do begin

    write(pad(checkpoint, 40, ' '));
    {exclude any folders not matching the expected format}
    {expected format is yyyymmdd_hhmmss
    {which I had regex here...}
    if not checkpoint.endsWith('.txt', True) then continue;

    {folderA is the newer checkpoint}

    {del old folder}
    fs.delFolder(folderB);

    {swap new to old}
    fs.rename(folderA, folderB);
    fs.mkdir(folderA);

    {export new folder}
    cpm.load(removeExtension(checkpoint));
    cpm.exportToFolder(folderA);

    SILENT := true;
    stats := diffOnWorkspace();
    SILENT := false;
    stats.printShort(6);
    writeln();

    // write stats to file
    writeln(csvFile,
      format('"%s", %.9f, %d, %d, %d', [checkpoint, cpm.date, stats.added, stats.removed, stats.changed])
    );

    counter += 1;

  end;
  close(csvFile);
  cpm.free;
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
  else if command = 'stats' then
    stats()
  else
    Error('Invalid command "'+command+'"');

  textAttr := WHITE;

  if PAUSE_AT_END then readkey;

end.
