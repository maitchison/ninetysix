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
  timer,
  dos;

{--------------------------------------------------------}

var
  LINES_SINCE_PAGE: byte = 0;
  USE_PAGING: boolean = true;
  PAUSE_AT_END: boolean = false;

const
  ROOT = '$repo';

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
  destinationPath := trim(destinationPath);
  dos.exec(getEnv('COMSPEC'), '/C deltree /y '+destinationPath+'_tmp > nul');
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
  t: text;
  time: tMyDateTime;
  repo: tCheckpointRepo;
  old,new: tCheckpoint;
  checkpointName: string;
  checkpointTime: tMyDateTime;

begin

  time := now;

  repo := tCheckpointRepo.create(ROOT);
  old := tCheckpoint.create(repo, joinPath(ROOT, 'HEAD'));
  new := tCheckpoint.create(repo, '.');

  outputln();
  outputDiv();
  outputln(' SUMMARY');
  outputDiv();
  outputLn();

  repo.generateCheckpointDiff(old, new).showStatus;

  checkpointTime := now;

  new.author := 'Matthew';
  new.date := now();
  new.message := msg;

  new.save(joinPath(ROOT, new.defaultCheckpointPath));

  safeCopy(joinPath(ROOT, 'HEAD'));

end;

{-----------------------------------------------------}

{output the longest common subsequence. Returns stats}
procedure showDiff(oldLines, newLines: tStringList;matching: tIntList);

var
  i,j,k,z: int32;
  oldS,newS: tIntList;
  cur: string;
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
  new := fs.readText('sample_new.txt');
  old := fs.readText('sample_old.txt');

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

function getSourceFiles(path: string): tStringList;
begin
  {todo: proper .gitignore style decision on what to include}
  if (length(path) > 0) and (path[length(path)] <> '\') then
    path += '\';
  result := fs.listFiles(path+'*.pas');
  result += fs.listFiles(path+'*.bat');
  result += fs.listFiles(path+'*.inc');
end;

{present to user the diff between current workspace and head}
procedure showDiffOnWorkspace();
var
  repo: tCheckpointRepo;
  old,new: tCheckpoint;
  checkpointDiff: tCheckpointDiff;
begin
  repo := tCheckpointRepo.create(ROOT);
  old := tCheckpoint.create(repo, joinPath(ROOT, 'HEAD'));
  new := tCheckpoint.create(repo, '.');
  checkpointDiff := repo.generateCheckpointDiff(old, new);
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
const
  ROOT = '$repo';
begin
  repo := tCheckpointRepo.create(ROOT);
  old := tCheckpoint.create(repo, joinPath(ROOT, 'HEAD'));
  new := tCheckpoint.create(repo, '.');
  checkpointDiff := repo.generateCheckpointDiff(old, new);
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

var
  csvFile: text;
begin

  textAttr := WHITE;

  repo := tCheckpointRepo.create('$repo');

  checkpoints := repo.getCheckpoints();
  checkpoints.reverse(); // we want these old to new

  counter := 0;

  assign(csvFile, 'stats.csv');

  csvEntries := tStringToStringMap.create();

  if fs.exists('stats.csv') then begin
    csvLines := fs.readText('stats.csv');
    for line in csvLines do begin
      split(line, ',', key, value);
      if length(key) < 2 then continue;
      key := copy(key, 2, length(key)-6); {remove ".txt"}
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

  for checkpoint in checkpoints do begin

    write(pad(checkpoint, 40, ' '));

    if csvEntries.hasKey(checkpoint) then begin
      writeln('[skip]');
      didSkip := true;
      previousCheckpoint := checkpoint;
      continue;
    end;

    if previousCheckpoint = '' then begin
      new := repo.load(checkpoint);
      old := tCheckpoint.create(repo); // an empty one
    end else begin
      if assigned(old) then old.free;
      if didSkip then
        // if we skipped we must reload both
        old := repo.load(previousCheckpoint)
      else
        old := new;
      new := repo.load(checkpoint);
      didSkip := false;
    end;

    stats := repo.generateCheckpointDiff(old, new).getLineStats();
    stats.printShort(6);
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
  repo := tCheckpointRepo.create(ROOT);
  checkpoint := tCheckpoint.create(repo);
  for checkpointName in repo.getCheckpoints() do begin
    checkpoint.load(joinPath(ROOT, checkpointName)+'.txt');
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
      FD_MODIFIED: outputX (' Modified ', fileDiff.old.path, '', YELLOW);
      FD_ADDED:    outputX (' Added ',   fileDiff.new.path, '', LIGHTGREEN);
      FD_REMOVED:  outputX (' Removed ', fileDiff.old.path, '', LIGHTRED);
      FD_RENAMED:  outputX (' Renamed ', fileDiff.old.path+' -> '+fileDiff.new.path, '', LIGHTBLUE);
    end;
    outputDiv();

    old := fs.readText(fileDiff.old.fqn);
    new := fs.readText(fileDiff.new.fqn);
    matches := fileDiff.getMatch();
    stats := fileDiff.getStats();

    showDiff(old, new, matches);

  end;

  outputDiv();
  outputLn(' SUMMARY');
  outputDiv();
  outputLn();


  {show footer}
  self.showStatus();

  textattr := oldTextAttr;
end;

{--------------------------------------------------}

var
  command: string;

begin

  // screen is hard to read due to a dosbox-x bug, so we clear it
  // for visibility.
  textAttr := WHITE;
  clrscr;

  if (paramCount = 0) then
    command := 'status'
  else
    command := paramSTR(1);

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
  else if command = 'verify' then
    doVerify()
  else
    Error('Invalid command "'+command+'"');

  textAttr := WHITE;

  if PAUSE_AT_END then readkey;

end.
