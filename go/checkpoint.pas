{handles git like repo}
unit checkpoint;

interface

uses
  {$I baseunits.inc},
  crt, {remove}
  md5,
  iniFile,
  diff,
  hashMap,
  timer,
  objectStore,
  fileRef,
  dos;

type

  tFileDiffType = (
    FD_ADDED,
    FD_REMOVED,
    FD_MODIFIED,
    FD_RENAMED
  );

  tFileDiff = record
    old, new: tFileRef;
    procedure init(aOld, aNew: tFileRef);
    function  diffType: tFileDiffType;
    function  getMatch(): tIntList;
    function  getStats(): tDiffStats;
    class function MakeRenamed(aOld, aNew: tFileRef): tFileDiff; static;
    class function MakeAdded(aNew: tFileRef): tFileDiff; static;
    class function MakeRemoved(aOld: tFileRef): tFileDiff; static;
    class function MakeModified(aOld, aNew: tFileRef): tFileDiff; static;
  end;

  tCheckpointDiff = record
    fileDiffs: array of tFileDiff;
    procedure clear();
    procedure append(fileDiff: tFileDiff);
    function  getFileStats(): tDiffStats;
    function  getLineStats(): tDiffStats;

  end;


  tCheckpointRepo = class;

  tCheckpoint = class

    fMessage: string;
    fAuthor: string;
    fDate: tDateTime;
    fId: string;

    fileList: tFileRefList;

    repo: tCheckpointRepo;

  protected
    function  objectFactory(s: string): tObject;
    procedure writeObjects();
    procedure addFromFolder(path, root: string;recursive: boolean=True);

  published
    property message: string read fMessage write fMessage;
    property author: string read fAuthor write fAuthor;
    property date: double read fDate write fDate;
    property id: string read fID write fID;

  public

    constructor create(aRepo: tCheckpointRepo); overload;
    constructor create(aRepo: tCheckpointRepo;aPathOrCheckpoint: string); overload;
    destructor destroy(); override;

    procedure clear();

    function  defaultCheckpointPath: string;
    procedure readFromFolder(path: string);
    procedure exportToFolder(path: string);
    procedure load(checkpoint: string);
    procedure save(checkpoint: string);
  end;

  tCheckpointRepo = class

    objectStore: tObjectStore;
    repoRoot: string;

    constructor create(aRepoRoot: string);
    destructor destroy(); override;

    function  generateCheckpointDiff(old, new: tCheckpoint): tCheckpointDiff;

    function  hasCheckpoint(checkpointName: string): boolean;
    function  getCheckpointPath(checkpointName: string): string;
    function  getCheckpointNames(): tStringList;

    function  load(checkpointName: string): tCheckpoint;
    function  loadHead(): tCheckpoint;
    function  verify(checkpoint: tCheckpoint; verbose: boolean=false): boolean;

  end;


implementation

type
  tMergeInfo = record
    oldLen, newLen: int32;
    merge: tIntList;
  end;

var
  CACHE: tStringToStringMap;

{cached diff}
function diff(oldFile, newFile: string): tMergeInfo; forward;

{-------------------------------------------------------------}

constructor tCheckpoint.Create(aRepo: tCheckpointRepo); overload;
begin
  inherited Create();
  fileList := nil;
  if not assigned(aRepo) then error('Repo must be assigned');
  repo := aRepo;
  clear();
end;

constructor tCheckpoint.Create(aRepo: tCheckpointRepo;aPathOrCheckpoint: string); overload;
begin
  Create(aRepo);
  if aPathOrCheckpoint.endsWith('.txt', true) then
    load(aPathOrCheckpoint)
  else
    readFromFolder(aPathOrCheckpoint);
end;

destructor tCheckpoint.Destroy();
begin
  clear();
  inherited Destroy;
end;

procedure tCheckpoint.clear();
var
  fileRef: tFileRef;
begin

  if assigned(fileList) then
    for fileRef in fileList do
      fileRef.free();
  fileList := nil;

  message := '';
  author := '';
  date := 0;
  id:= '';

end;

{returns the default checkpoint path}
function tCheckpoint.defaultCheckpointPath: string;
begin
  result := tMyDateTime(date).YYMMDD('')+'_'+tMyDateTime(date).HHMMSS('')+'.txt'
end;

{loads checkpoint from a standard folder.}
procedure tCheckpoint.readFromFolder(path: string);
begin
  clear();
  if not path.endsWith('\') then path += '\';
  addFromFolder('', path, true);
  {for the moment, just hard code the folder structure}
  {todo: implement .ignore and scan the folders}
  addFromFolder('shared', path);
  addFromFolder('tools', path);
  addFromFolder('go', path);
  addFromFolder('old', path);
  addFromFolder('airtime', path);
end;

{adds files to current checkpoint, but does not clear}
procedure tCheckpoint.addFromFolder(path, root: string; recursive: boolean=true);
var
  fileRef: tFileRef;
  files: tStringList;
  i: integer;
  fullPath: string;
begin

  fullPath := joinPath(root, path);

  // stub:
  writeln('Scanning: ', fullPath);

  // get all files in folder
  // note: for the moment just hard code which files to read
  // eventually support a .git ignore file
  files := fs.listFiles(joinPath(fullPath, '*.pas'));
  files += fs.listFiles(joinPath(fullPath, '*.inc'));
  files += fs.listFiles(joinPath(fullPath, '*.bat'));

  // create file reference for each one (including hash)
  for i := 0 to files.len-1 do begin
    fileRef := tFileRef.create(joinPath(path, files[i]), root);
    if fileRef.fileSize > MAX_FILESIZE then begin
      warn(format('Skipping %s as it is too large (%fkb)',[fileRef.fqn, fileRef.fileSize/1024]));
      fileRef.free;
      continue;
    end;
    {add reference}
    fileList.append(fileRef);
  end;
end;

{writes all files to folder so that others can read them}
procedure tCheckpoint.exportToFolder(path: string);
var
  fileRef: tFileRef;
  dstFile: string;
  srcFile: string;
begin
  fs.mkdir(path);
  for fileRef in fileList do begin
    dstFile := joinPath(path, fileRef.path);
    srcFile := joinPath(fileRef.root, fileRef.hash);
    {todo: support subfolders}
    fs.copyFile(srcFile, dstFile);
    fs.setModified(dstFile, fileRef.modified);
  end;
end;

function tCheckpoint.objectFactory(s: string): tObject;
begin
  if s = 'commit' then exit(self);
  if s = 'file' then exit(tFileRef.create());
  exit(nil);
end;

{read checkpoint metadata from file}
procedure tCheckpoint.load(checkpoint: string);
var
  reader: tINIReader;
  obj: tObject;
  fr: tFileRef;
begin

  if not checkpoint.endsWith('.txt', true) then error(format('Checkpoint must be a .txt file but was "%s"', [checkpoint]));

  if not fs.exists(checkpoint) then
    error(format('Checkpoint "%s" does not exist.', [checkpoint]));

  clear();

  reader := tINIReader.create(checkpoint, objectFactory);

  while not reader.eof do begin
    obj := reader.readObject();
    if obj is tFileRef then begin
      setLength(fileList, length(fileList)+1);
      fr := tFileRef(obj);
      fr.root := '*'+repo.objectStore.root;
      fileList[length(fileList)-1] := fr;
    end;
  end;

end;

{saves the checkpoint to repo}
procedure tCheckpoint.save(checkpoint: string);
var
  t: tINIWriter;
  fileRef: tFileRef;
  commitID: tDigest;
  i: integer;
begin

  if not checkpoint.endsWith('.txt', true) then error('Checkpoint must be a .txt file');

  self.writeObjects();

  {first write out just the files (so we can get the checkpoint hash)}
  t := tINIWriter.create(checkpoint);
  try
    for fileRef in fileList do
      t.writeObject('file', fileRef);
  finally
    t.free();
  end;

  {next hash the ini file for our commit id}
  id := hash(loadString(checkpoint)).toHex;

  {then write out the complete file}
  t := tINIWriter.create(checkpoint);
  try
    t.writeSection('commit');
    t.writeString('message', message);
    t.writeString('id', id);
    t.writeString('author', author);
    t.writeFloat('date', date);
    t.writeBlank();
    for fileRef in fileList do
      t.writeObject('file', fileRef);
  finally
    t.free();
  end;
end;

{writes out objects to object database}
procedure tCheckpoint.writeObjects();
var
  fileRef: tFileRef;
begin
  for fileRef in fileList do
    repo.objectStore.addObject(fileRef.hash, fileRef.fqn);
end;

{-------------------------------------------------------------}

constructor tCheckpointRepo.create(aRepoRoot: string);
begin
  inherited create;
  if not fs.folderExists(aRepoRoot) then error(format('No repo found at "%s"', [aRepoRoot]));
  repoRoot := aRepoRoot;
  objectStore := tObjectStore.create(joinPath(aRepoRoot, 'store'));
end;

destructor tCheckpointRepo.destroy();
begin
  objectStore.free;
  repoRoot := '';
  inherited Destroy;
end;

{checks if originalFile is very similar to any of the other files in
 filesToCheck, and if so returns the matching new filename}
function checkForRename(originalFile: tFileRef; filesToCheck: array of tFileRef): tFileRef;
var
  fileRef: tFileRef;
  filesizeRatio: double;
  changedratio: double;
  stats: tDiffStats;
  diff: tFileDiff;
begin
  result := NULL_FILE;

  // we don't check very small files
  if originalFile.fileSize < 64 then exit;

  for fileRef in filesToCheck do begin
    // do not check ourselves
    if fileRef.path = originalFile.path then continue;
    fileSizeRatio := fileRef.fileSize / originalFile.fileSize;
    //writeln(format('fileSizeRatio %f %s %s ', [fileSizeRatio, originalFile.path, fileRef.path]));
    if (fileSizeRatio > 1.25) or (fileSizeRatio < 0.8) then continue;

    diff.init(originalFile, fileRef);
    stats := diff.getStats();

    changedRatio := stats.unchanged / stats.newLen;
    //writeln(format('changeratio %f %s %s ', [changedRatio, originalFile.path, fileRef.path]));
    if (changedRatio > 1.1) or (changedRatio < 0.9) then continue;
    result := fileRef;
    exit;
  end;
end;

{perform a basic check to make sure objects reference in this checkpoint exist.}
function tCheckpointRepo.verify(checkpoint: tCheckpoint; verbose: boolean=false): boolean;
var
  fileRef: tFileRef;
  missingFileMsg: string;
begin
  result := true;
  for fileRef in checkpoint.fileList do begin
    if not assigned(objectStore.lookupByHash(fileRef.hash)) then begin
      missingFileMsg := format(' - missing object %s referenced by %s', [copy(fileRef.hash, 1, 8), fileRef.path]);
      warn(missingFileMsg);
      if verbose then
        writeln(missingFileMsg);
      result := false;
    end;
  end;
end;

function tCheckpointRepo.generateCheckpointDiff(old, new: tCheckpoint): tCheckpointDiff;
var
  fr, oldFr: tFileRef;
  fd: tFileDiff;
  oldFiles, newFiles,
  addedFiles, removedFiles,
  renamedFiles: tFileRefList;
  i: integer;

begin
  result.clear();

  oldFiles := old.fileList;
  newFiles := new.fileList;

  for fr in newFiles do
    if not oldFiles.contains(fr) then
      addedFiles.append(fr);

  for fr in oldFiles do
    if not newFiles.contains(fr) then
      removedFiles.append(fr);

  {look for renamed files}
  for fr in newFiles do begin
    oldFr := checkForRename(fr, removedFiles);
    if not oldFr.assigned then continue;
    result.append(tFileDiff.MakeRenamed(oldFr, fr));
    renamedFiles.append(oldFr);
    renamedFiles.append(fr);
  end;

  {process files that were added and removed}
  for fr in addedFiles do begin
    if renamedFiles.contains(fr) then continue;
    result.append(tFileDiff.MakeAdded(fr));
  end;
  for fr in removedFiles do begin
    if renamedFiles.contains(fr) then continue;
    result.append(tFileDiff.MakeRemoved(fr));
  end;

  {finally check for modified}
  for fr in newFiles do begin
    if renamedFiles.contains(fr) then continue;
    oldFr := oldFiles.lookup(fr.path);
    if not oldFr.assigned then continue;
    if not fs.wasModified(fr.fqn, oldFr.fqn) then continue;
    {unfortunately we need to do a full comparision here as sometimes
     modified is changed but file is not}
    if fs.compareText(fr.fqn, oldFr.fqn) then continue;
    result.append(tFileDiff.MakeModified(oldFr, fr));
  end;
end;

function tCheckpointRepo.hasCheckpoint(checkpointName: string): boolean;
begin
  result := fs.exists(getCheckpointPath(checkpointName));
end;

{returns list of checkpoint names from most recent to least recent}
function tCheckpointRepo.getCheckpointNames(): tStringList;
var
  i: integer;
begin
  result := fs.listFiles(repoRoot+'\*.txt');
  for i := 0 to result.len-1 do
    result[i] := removeExtension(result[i]);
  result.sort();
  result.reverse();
end;

function tCheckpointRepo.getCheckpointPath(checkpointName: string): string;
begin
  result := joinPath(repoRoot, checkpointName)+'.txt';
end;

function tCheckpointRepo.loadHead(): tCheckpoint;
var
  checkpointNames: tStringList;
begin
  checkpointNames := getCheckpointNames();
  if checkpointNames.len = 0 then error('Repo has no head, as it is empty.');
  result := load(checkpointNames[0]);
end;

function tCheckpointRepo.load(checkpointName: string): tCheckpoint;
begin
  result := tCheckpoint.create(self, getCheckpointPath(checkpointName));
end;

{-------------------------------------------------------------}

function tFileDiff.getMatch(): tIntList;
begin
  result := diff(old.fqn, new.fqn).merge;
end;

function tFileDiff.getStats(): tDiffStats;
var
  mi: tMergeInfo;
begin
  mi := diff(old.fqn, new.fqn);
  result.clear();
  result.removed := mi.oldLen - mi.merge.len;
  result.added := mi.newLen - mi.merge.len;
  result.changed := 0;
  result.unchanged := mi.merge.len;
end;

procedure tFileDiff.init(aOld, aNew: tFileRef);
begin
  self.old := aOld;
  self.new := aNew;
end;

function tFileDiff.diffType: tFileDiffType;
begin
  if self.old.assigned and self.new.assigned then
    if (old.path = new.path) then
      exit(FD_MODIFIED)
    else
      exit(FD_RENAMED);
  if self.old.assigned then exit(FD_REMOVED);
  if self.new.assigned then exit(FD_ADDED);
  error('Neither old nor new was assigned, file as no diff type.');
end;

class function tFileDiff.MakeRenamed(aOld, aNew: tFileRef): tFileDiff;
begin
  result.old := aOld;
  result.new := aNew;
end;

class function tFileDiff.MakeAdded(aNew: tFileRef): tFileDiff;
begin
  result.old := NULL_FILE;
  result.new := aNew;
end;

class function tFileDiff.MakeRemoved(aOld: tFileRef): tFileDiff;
begin
  result.old := aOld;
  result.new := NULL_FILE;
end;

class function tFileDiff.MakeModified(aOld, aNew: tFileRef): tFileDiff;
begin
  if aOld.path <> aNew.path then error('Modified diff should have paths match.');
  if aOld.fqn = aNew.fqn then error('Modified diff have two different files.');
  result.old := aOld;
  result.new := aNew;
end;

{-------------------------------------------------------------}

procedure tCheckpointDiff.clear();
begin
  setLength(self.fileDiffs, 0);
end;

procedure tCheckpointDiff.append(fileDiff: tFileDiff);
begin
  setLength(fileDiffs, length(fileDiffs)+1);
  fileDiffs[length(fileDiffs)-1] := fileDiff;
end;

function tCheckpointDiff.getFileStats(): tDiffStats;
begin
  error('NIY');
end;

function tCheckpointDiff.getLineStats(): tDiffStats;
var
  fd: tFileDiff;
begin
  result.clear();
  for fd in fileDiffs do
    result += fd.getStats();
end;

{-------------------------------------------------------------}

const
  {for the moment just hard code this to the repo folder}
  CACHE_PATH = 'c:\dev\$repo\.cache';

{cached diff}
function diff(oldFile, newFile: string): tMergeInfo;
var
  new, old: tStringList;
  sln: tIntList;
  cacheKey: string;
begin

  startTimer('diff_read_file');
  old := fs.readText(oldFile);
  new := fs.readText(newFile);
  stopTimer('diff_read_file');

  startTimer('diff_cache_key');
  cacheKey := 'new:'+MD5.hash(join(new.data)).toHex+' old:'+MD5.hash(join(old.data)).toHex;
  stopTimer('diff_cache_key');

  if CACHE.hasKey(cacheKey) then begin
    startTimer('diff_cache_hit');
    sln.loadS(cache.getValue(cacheKey));
    stopTimer('diff_cache_hit');
  end else begin
    startTimer('diff_cache_miss');
    sln := run(old, new);
    CACHE.setValue(cacheKey, sln.dumpS);
    stopTimer('diff_cache_miss');
  end;

  result.merge := sln;
  result.oldLen := old.len;
  result.newLen := new.len;
end;

procedure loadCache();
begin
  if fs.exists(CACHE_PATH) then
    CACHE.load(CACHE_PATH);
end;

procedure saveCache();
begin
  if assigned(CACHE) then
    CACHE.save(CACHE_PATH, 100);
end;

initialization
  CACHE := tStringToStringMap.create();
  loadCache();
finalization
  saveCache();
  CACHE.free;
end.
