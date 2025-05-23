{Super simple git replacement}
program go;

{todo: support ansi strings I guess...
  well atleast make sure long strings work, or perhaps just ignore?
}

{$MODE delphi}

{

go commit "Comments"
  Commit all changes
go status
  List changes since last commit.
go revert
  Revert back to previous commit. (but save a stash first)
go loc
  Write line counts per day

}

uses
  {$I baseunits.inc},
  crt,
  uDiff,
  uHashMap,
  uMD5,
  uTimer,
  objectStore,
  checkpoint,
  fileRef;

{--------------------------------------------------------}

var
  LINES_SINCE_PAGE: byte = 0;
  USE_PAGING: boolean = true;
  PAUSE_AT_END: boolean = false;

const
  WORKSPACE = 'c:\dev\';
  REPO_PATH = 'c:\dev\';

  {ignores modified date}
  FORCE = false;

type
  tDiffStatsHelper = record helper for tDiffStats
    procedure print();
    procedure printShort(padding: integer=4);
  end;

  tCheckpointHelper = class helper for tCheckpoint
    procedure print();
  end;

  tCheckpointDiffHelper = record helper for tCheckpointDiff
    procedure showStatus(withStats: boolean=true);
    procedure showChanges();
  end;

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
  write(s);
end;

{outputs a line of text, with support for paging}
procedure outputLn(s: string='');
begin
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
      #3: halt;
    end;
    LINES_SINCE_PAGE := 0;
    writeln();
  end;
end;

procedure outputDiv();
begin
  outputLn('----------------------------------------');
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

procedure tDiffStatsHelper.print();
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

procedure tDiffStatsHelper.printShort(padding: integer=4);
var
  plus: string;
  oldTextAttr: byte;
begin
  oldTextAttr := textAttr;
  textAttr := LIGHTGRAY;
  //output('(');
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
  //output(')');
  textAttr := oldTextAttr;
end;

{--------------------------------------------------------}

procedure tCheckpointHelper.print();
var
  fileRef: tFileRef;
begin
  for fileRef in fileList do
    outputLn(fileRef.toString);
end;

{--------------------------------------------------------}

procedure commit(msg: string);
var
  repo: tCheckpointRepo;
  old,new: tCheckpoint;

begin

  repo := tCheckpointRepo.create(REPO_PATH);
  old := repo.loadHead();
  new := tCheckpoint.create(repo, WORKSPACE);

  textAttr := White;
  outputln();
  outputDiv();
  outputln(' SUMMARY');
  outputDiv();
  outputLn();

  repo.generateCheckpointDiff(old, new, FORCE).showStatus;

  new.author := 'Matthew';
  new.date := now();
  new.message := msg;

  new.save(joinPath(repo.repoDataPath, new.defaultCheckpointPath));

end;

{-----------------------------------------------------}

{output the longest common subsequence. Returns stats}
procedure showDiff(oldLines, newLines: tStringList;matching: tIntList);

var
  i,j,k,z: int32;
  oldS,newS: tIntList;
  cur: string;
  isFirst: boolean;
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

  {which lines in old file should be shown for context}
  fillchar(importantLines, sizeof(importantLines), false);

  oldS := tIntList.create([]);
  for i := 1 to oldLines.len do
    oldS.append(i);

  newS := tIntList.create([]);
  for i := 1 to newLines.len do
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
    for i := 0 to oldLines.len-1 do begin
      textAttr := LIGHTRED;
      outputLn(intToStr(i+1, 4, '0')+' [-] '+fix(oldLines[i]));
    end;
    for i := 0 to newLines.len-1 do begin
      textAttr := LIGHTGREEN;
      outputLn(intToStr(i+1, 4, '0')+' [+] '+fix(newLines[i]));
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

    while (j < oldLines.len) and (oldLines[j] <> cur) do begin
      markImportant(j);
      inc(j);
    end;
    while (i < newLines.len) and (newLines[i] <> cur) do begin
      markImportant(j);
      inc(i);
    end;
  end;

  {------------------------------------}

  i := 0;
  j := 0;
  k := 0;
  clock := 0;

  outputLn();

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
        outputLn();
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

    while (j < oldLines.len) and (oldLines[j] <> cur) do begin
      textAttr := LIGHTRED;
      outputLn(intToStr(j+1, 4, '0')+' [-] '+fix(oldLines[j]));
      inc(j);
    end;

    while (i < newLines.len) and (newLines[i] <> cur) do begin
      textAttr := LIGHTGREEN;
      outputLn('     [+] '+fix(newLines[i]));
      inc(i);
    end;
  end;

  outputLn();
  textAttr := WHITE;

end;

var
  msg: string;

procedure benchmark();
var
  startTime, elapsed: double;
  merge: tIntList;
  sln: tIntList;
  new,old: tStringList;
  diff: tDiffSolver;
  i: integer;
begin
  {
    sln seems to be +140 / -13 = total of 153 lines
    464 lines match
    start: 14.2
    no writeln: 12.4
    sln from backtrace: 1.6
  }
  new := fileSystem.readText('sample_new.txt');
  old := fileSystem.readText('sample_old.txt');

  diff := tDiffSolver.create();

  startTime := getSec;
  sln := diff.run(old, new);
  elapsed := getSec-startTime;

  merge := tIntList.create([]);
  for i := 0 to sln.len-1 do
    merge.append(sln[i]);

  writeln('final score -> ', diff.solutionLength);

  writeln(format('Took %f seconds', [elapsed]));
  writeln(merge.len);
  writeln('new        ',new.len);
  writeln('old        ',old.len);
  writeln('delta      ',(new.len-sln.len)+(old.len-sln.len));
  writeln('NM         ',new.len*old.len);
end;

procedure promptAndCommit();
begin
  write('Message:');
  readln(msg);
  commit(msg);
end;

{present to user the diff between current workspace and head}
procedure showDiffOnWorkspace();
var
  repo: tCheckpointRepo;
  old,new: tCheckpoint;
  checkpointDiff: tCheckpointDiff;
begin
  startTimer('Scan');
  repo := tCheckpointRepo.create(REPO_PATH);
  old := repo.loadHead();
  new := tCheckpoint.create(repo, WORKSPACE);
  stopTimer('Scan');

  startTimer('Diff');
  checkpointDiff := repo.generateCheckpointDiff(old, new, FORCE);
  stopTimer('Diff');
  logTimers();
  checkpointDiff.showChanges();

  new.free;
  old.free;
  repo.free;
end;

procedure showStatus();
var
  repo: tCheckpointRepo;
  old,new: tCheckpoint;
  checkpointDiff: tCheckpointDiff;
begin
  startTimer('Scan');
  repo := tCheckpointRepo.create(REPO_PATH);
  stopTimer('Scan');

  startTimer('Load');
  old := repo.loadHead();
  stopTimer('Load');


  startTimer('ScanWorkspace');
  new := tCheckpoint.create(repo, WORKSPACE);
  stopTimer('ScanWorkspace');

  startTimer('Diff');
  checkpointDiff := repo.generateCheckpointDiff(old, new, FORCE);
  stopTimer('Diff');

  logTimers();

  checkpointDiff.showStatus();

  new.free;
  old.free;
  repo.free;
end;

{show all diff on all modified files
This is the old version that has many issues,
 - printing of diff and generating of diff stats are combined for some reason.
 - uses the old 'folder' system instead of the new objectstore
 - caching is done in go rather than in checkpoint
 - it does work though.
}

{--------------------------------------------------}

{show how many lines of code per day}
procedure showLoc();
var
  i: integer;

  currentDT: tMyDateTime;
  dateCode, prevDateCode: string;
  currentLoc, prevDayLoc, prevMonthLoc: int32;
  dayCounter: integer;

  repo: tCheckpointRepo;
  checkpointNames: tStringList;
  checkpointName: string;

  skippedCheckpointName: string;

  startDateCode: string;
  nextDateCode: string;

  totalLoc, totalDays: integer;

  function countLoC(checkpointName: string): int32;
  var
    checkpoint: tCheckpoint;
  begin
    checkpoint := repo.load(checkpointName);
    result := checkpoint.countLoC();
    checkpoint.free;
  end;

begin

  repo := tCheckpointRepo.create(REPO_PATH);
  checkpointNames := repo.getCheckpointNames();
  checkpointNames.reverse();

  currentDT := now();
  startDateCode := copy(currentDT.YYYYMMDD(''), 1, 6);

  dateCode := '';
  prevDateCode := '';
  prevDayLoc := -1;
  prevMonthLoc := -1;
  totalLoC := 0;

  dayCounter := 0;

  writeln('Daily LOC');
  writeln('-------------------------------------');
  writeln('Date            LoC       Daily');

  for i := 0 to checkpointNames.len-1 do begin

    if keypressed then case readkey of
      #3: break;
    end;

    {this this and next date code}
    checkpointName := checkpointNames[i];
    if i = checkpointNames.len-1 then
      nextDateCode := ''
    else
      nextDateCode := copy(checkpointNames[i+1], 1, 8);
    dateCode := copy(checkpointName, 1, 8);

    if not dateCode.startsWith(startDateCode) then begin
      skippedCheckpointName := checkpointName;
      continue;
    end;

    {only show last checkpoint each day}
    if not (dateCode <> nextDateCode) then continue;

    if prevDayLoc < 0 then
      {get loc from just before the first entry we print out}
      prevDayLoc := countLoC(skippedCheckpointName);

    currentLoc := countLoC(checkpointName);

    writeln(format('%s     %s       %s', [
      copy(checkpointName, 1, 8),
      intToStr(currentLoc, 6, ' '),
      intToStr(currentLoC-prevDayLoC, 5, ' ')
      ]));

    dayCounter += 1;
    totalLoc += currentLoC-prevDayLoC;
    prevDateCode := dateCode;
    prevDayLoC := currentLoC;
  end;

  writeln('-------------------------------------');

  if dayCounter > 0 then
    writeln(format('AVG: %d (per day)', [totalLoC / dayCounter]));

  repo.free;
end;

{generate per commit stats. Quite slow}
procedure showStats();
var
  repo: tCheckpointRepo;
  checkpoints: tStringList;
  checkpoint: string;
  previousCheckpoint: string;
  counter: int32;
  stats: tDiffStats;
  old, new: tCheckpoint;

  csvLines: tStringList;
  csvEntries: tStringToStringMap;
  line: string;
  key,value: string;
  didSkip: boolean;

  dayTotal: tDiffStats;
  dateCode, prevDateCode: string;

  dayLoC, monthLoc, totalLoc: int32;

var
  csvFile: text;
begin

  textAttr := WHITE;

  repo := tCheckpointRepo.create(REPO_PATH);
  checkpoints := repo.getCheckpointNames();

  counter := 0;

  assign(csvFile, 'stats.csv');

  csvEntries := tStringToStringMap.create();

  key := '';
  value := '';

  if fileSystem.exists('stats.csv') then begin
    csvLines := fileSystem.readText('stats.csv');
    for line in csvLines do begin
      split(line, ',', key, value);
      if length(key) < 2 then continue;
      key := copy(key, 2, length(key)-2); {remove "}
      csvEntries.setValue(key, value);
    end;
    append(csvFile);
  end else begin
    rewrite(csvFile);
    writeln(csvFile, '"Checkpoint","Date","Added","Removed","Changed"');
  end;

  previousCheckpoint := '';
  didSkip := false;

  old := nil;
  new := nil;

  dayTotal.clear();
  dateCode := '';
  prevDateCode := '';

  for checkpoint in checkpoints do begin

    dateCode := copy(checkpoint, 1, 8);

    if (dateCode <> prevDateCode) and (dayTotal.net <> 0) then begin
      outputDiv();
      output(dateCode+' ');dayTotal.printShort(8);
      outputLn();
      outputDiv;
      dayTotal.clear();
      prevDateCode := dateCode;
    end;

    write(pad(checkpoint, 40, ' '));

    if csvEntries.hasKey(checkpoint) then begin
      writeln('[skip]');
      didSkip := true;
      previousCheckpoint := checkpoint;
      continue;
    end;

    if previousCheckpoint = '' then begin
      {this is the first checkpoint}
      {do diff against current workspace}
      old := repo.load(checkpoint);
      new := tCheckpoint.create(repo, WORKSPACE);
      new.date := now();
    end else begin
      if assigned(new) then new.free;
      if didSkip then
        // if we skipped we must reload both
        new := repo.load(previousCheckpoint)
      else
        new := old;
      old := repo.load(checkpoint);
      didSkip := false;
    end;

    stats := repo.generateCheckpointDiff(old, new, FORCE).getLineStats();
    stats.printShort(6);
    dayTotal += stats;
    writeln();

    // write stats to file
    writeln(csvFile,
      format('"%s", %.9f, %d, %d, %d', [checkpoint, new.date, stats.added, stats.removed, stats.changed])
    );
    flush(csvFile);

    if keypressed then case readkey of
      #3: break;
    end;

    counter += 1;

    previousCheckpoint := checkpoint;

  end;
  close(csvFile);
  repo.free;
end;

{make sure our checkpoints look ok}
procedure doVerify();
var
  checkpointName: string;
  checkpoint: tCheckpoint;
  repo: tCheckpointRepo;
begin
  repo := tCheckpointRepo.create(REPO_PATH);
  checkpoint := tCheckpoint.create(repo);

  {check object store}
  outputLn('Verifying object store');
  repo.objectStore.verify();
  outputLn(' - done');

  {check checkpoints}
  for checkpointName in repo.getCheckpointNames() do begin
    checkpoint.load(joinPath(REPO_PATH, '$REPO', checkpointName+'.txt'));
    textAttr := LIGHTGRAY;
    output(pad(checkpointName, 40));
    if repo.verify(checkpoint, false) then begin
      textAttr := LIGHTGREEN;
      outputLn('[OK]');
    end else begin
      textAttr := LIGHTRED;
      outputLn('[BAD]');
      repo.verify(checkpoint, true);
    end;
    textAttr := WHITE;

    if keypressed then case readkey of
      #3: break;
    end;
  end;
  checkpoint.free;
end;

procedure runTests();
var
  t: textFile;
  testFiles: tStringList;
  unitName, filename: string;
  code: word;
begin

  testFiles := fileSystem.listFiles('.\*_test.pas');

  fileSystem.delFile('_runtest.pas');
  fileSystem.delFile('_runtest.exe');

  outputLn(format('Found %d unit tests.', [testFiles.len]));

  if testFiles.len = 0 then exit;

  {generate our file}
  assign(t,'_runtest.pas');
  rewrite(t);
  writeln(t, '{auto generated file}');
  writeln(t, 'program runtests;');
  writeln(t, '');
  writeln(t, 'uses');
  writeln(t, '  test,');
  for filename in testFiles do begin
    unitName := copy(filename, 1, length(filename)-4);
    writeln(t, '  '+unitName+',');
  end;
  writeln(t, '  debug;');
  writeln(t, '');
  writeln(t, 'begin');
  writeln(t, '  debug.WRITE_TO_SCREEN := true;');
  writeln(t, '  test.runTestSuites();');
  writeln(t, 'end.');
  close(t);

  {compile it}
  textAttr := YELLOW;
  outputln();
  outputDiv();
  outputln('Building');
  outputDiv();
  textAttr := LIGHTGRAY;
  code := dosExecute('fpc @fp.cfg -dDEBUG -v1 _runtest.pas', true);
  if code <> 0 then fatal('Failed to build test cases.');

  {run it}
  textAttr := LIGHTGREEN;
  outputln();
  outputDiv();
  outputln('Running Tests');
  outputDiv();
  textAttr := LIGHTGRAY;
  code := dosExecute('_runtest.exe', true);
  if code <> 0 then fatal('Failed to run unit tests.');

  fileSystem.delFile('_runtest.pas');
  fileSystem.delFile('_runtest.exe');

end;

{--------------------------------------------------}

procedure tCheckpointDiffHelper.showStatus(withStats: boolean=true);
var
  fileDiff: tFileDiff;
  oldTextAttr: byte;
  filesStats, totalStats, stats: tDiffStats;
  wasChanges: boolean;
begin

  stats.clear();
  totalStats.clear();
  filesStats.clear();

  oldTextattr := textAttr;

  for fileDiff in fileDiffs do begin
    case fileDiff.diffType of
      FD_ADDED: begin
        textattr := LIGHTGREEN;
        output(pad('[+] added ' + fileDiff.new.path, 50));
        inc(filesStats.added);
      end;
      FD_REMOVED: begin
        textattr := LIGHTRED;
        output(pad('[-] removed ' + fileDiff.old.path, 50));
        inc(filesStats.removed);
      end;
      FD_MODIFIED: begin
        textattr := WHITE;
        output(pad('[~] modified ' + fileDiff.new.path, 50));
        inc(filesStats.changed);
      end;
      FD_RENAMED: begin
        textattr := LIGHTBLUE;
        output(pad('[>] renamed '+fileDiff.old.path+' to '+fileDiff.new.path, 50));
        inc(filesStats.changed);
      end;
    end;
    if withStats then begin
      stats := fileDiff.getStats();
      stats.printShort();
      totalStats += stats;
    end;
    outputln();
  end;

  {show footer}

  textattr := WHITE;
  wasChanges := (stats.added > 0) or (stats.removed > 0) or (stats.changed > 0);

  if wasChanges and withStats then begin
    outputln();
    outputln('Total:');
    totalStats.print();
  end;

  if not wasChanges then
    outputLn('No changes.');

  outputLn();

  textattr := oldTextAttr;
end;

procedure tCheckpointDiffHelper.showChanges();
var
  fileDiff: tFileDiff;
  oldTextAttr: byte;
  stats: tDiffStats;
  matches: tIntList;
  old, new: tStringList;
begin

  stats.clear();
  oldTextattr := textAttr;

  for fileDiff in fileDiffs do begin

    textAttr := WHITE;
    outputDiv();
    case fileDiff.diffType of
      FD_MODIFIED: outputX(' Modified ', fileDiff.old.path, '', YELLOW);
      FD_ADDED:    outputX(' Added ',   fileDiff.new.path, '', LIGHTGREEN);
      FD_REMOVED:  outputX(' Removed ', fileDiff.old.path, '', LIGHTRED);
      FD_RENAMED:  outputX(' Renamed ', fileDiff.old.path+' -> '+fileDiff.new.path, '', LIGHTBLUE);
    end;
    outputDiv();

    old := fileSystem.readText(fileDiff.old.fqn);
    new := fileSystem.readText(fileDiff.new.fqn);
    matches := fileDiff.getMatch();
    stats := fileDiff.getStats();

    if fileDiff.diffType <> FD_REMOVED then
      showDiff(old, new, matches);
  end;

  textAttr := White;
  outputDiv();
  outputLn(' SUMMARY');
  outputDiv();
  outputLn();


  {show footer}
  self.showStatus();

  textattr := oldTextAttr;
end;

{
Export *every* checkpoint within the repo into a history folder.
Used to import into github.
}
procedure doExport();
var
  checkpointName: string;
  checkpoint: tCheckpoint;
  repo: tCheckpointRepo;
  checkpointDateCode: string;
const
  EXPORT_PATH: string = 'c:\dev\history';
begin
  repo := tCheckpointRepo.create(REPO_PATH);
  checkpoint := tCheckpoint.Create(repo);

  {check object store}
  outputLn('Exporting Repo to '+EXPORT_PATH);
  fileSystem.mkDir(EXPORT_PATH);

  for checkpointName in repo.getCheckpointNames() do begin
    checkpoint.load(joinPath(REPO_PATH, '$REPO', checkpointName+'.txt'));
    textAttr := LIGHTGRAY;
    output(pad(checkpointName, 40));
    checkpoint.exportToFolder(joinPath(EXPORT_PATH, checkpointName));
    break;
  end;
  checkpoint.free;
end;

{--------------------------------------------------}

var
  command: string;

begin

  // screen is hard to read due to a dosbox-x bug, so we clear it
  // for visibility.
  textAttr := WHITE;
  clrscr;

  {todo: proper parameter handling}
  if (paramCount = 0) then
    command := 'status'
  else
    command := paramSTR(1);

  if (paramCount = 2) then
    if paramSTR(2) = '-v' then begin
      {verbose mode}
      uDebug.VERBOSE_SCREEN := llDebug;
    end;

  if command = 'diff' then
    showDiffOnWorkspace()
  else if command = 'commit' then
    promptAndCommit()
  else if command = 'benchmark' then
    benchmark()
  else if command = 'status' then
    showStatus()
  else if command = 'stats' then
    showStats()
  else if command = 'loc' then
    showLOC()
  else if command = 'test' then
    runTests()
  else if command = 'verify' then
    doVerify()
  else if command = 'export' then
    doExport()
  else
    fatal('Invalid command "'+command+'"');

  textAttr := WHITE;

  if PAUSE_AT_END then readkey;

end.
