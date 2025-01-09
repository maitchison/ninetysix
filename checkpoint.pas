{handles git like repo}
unit checkpoint;

interface

uses
  debug,
  crt, {remove}
  test,
  utils,
  list,
  filesystem,
  md5,
  iniFile,
  dos;

type
  tFileRef = class
  protected
    fRoot: string; //root folder, not saved.
    fPath: string;
    fHash: string;
    fSize: int64;
    fModified: int32;
  public

    procedure calculateHash();
    function fqn: string;

  published

    property path: string read fPath write fPath;
    property hash: string read fHash write fHash;
    property modified: int32 read fModified write fModified;

  public

    constructor create(); overload;
    constructor create(aPath: string;aRoot: string = ''); overload;
    function toString(): string; override;
  end;

  {a database of object files}
  tObjectStore = class
    root: string;
    files: array of tFileRef;

    function lookupByHash(hash: string): tFileRef;
    function addObject(hash: string;objectPath: string): boolean;
    procedure reload();
    procedure clear();

    constructor create(aPath: string);
    destructor destroy(); override;
  end;

  tDiffStats = record
    added: int64;
    removed: int64;
    changed: int64;
    newLen: int64;
    function net: int64;
    function unchanged: int64;
    procedure clear();
    class operator add(a,b: tDiffStats): tDiffStats;
  end;

  tFileDiff = record
    old, new: tStringList;
    match: tIntList;
    stats: tDiffStats;
  end;

  tCheckpointDiff = record
    files: array of tFileDiff;
    stats: tDiffStats;
  end;

  tCheckpointRepo = class;

  tCheckpoint = class

    fMessage: string;
    fAuthor: string;
    fDate: tDateTime;
    fId: string;

    fileList: array of tFileRef;

    {where our files came from}
    sourceFolder: string;

  protected
    repo: tCheckpointRepo;
    procedure writeObjects();
    function objectFactory(s: string): tObject;

  published
    property message: string read fMessage write fMessage;
    property author: string read fAuthor write fAuthor;
    property date: double read fDate write fDate;
    property id: string read fID write fID;

  public

    constructor create(aRepo: tCheckpointRepo); overload;
    constructor create(aRepo: tCheckpointRepo; path: string); overload;
    destructor destroy();

    procedure clear();

    procedure readFromFolder(path: string);
    procedure exportToFolder(path: string);
    procedure load(path: string);
    procedure save(path: string);
  end;

  tCheckpointRepo = class

    objectStore: tObjectStore;
    repoRoot: string;

    constructor create(aRepoRoot: string);
    destructor destroy();

    function  generateDiff(checkpointOld, checkpointNew: string): tCheckpointDiff;

    function  hasCheckpoint(checkpointName: string): boolean;
    function  getCheckpointPath(checkpointName: string): string;

    function  load(checkpointName: string): tCheckpoint;

  end;


implementation

const
  {fine for text files, but don't process large binary files}
  MAX_FILESIZE = 128*1024;

{-------------------------------------------------------------}

constructor tFileRef.create(); overload;
begin
  inherited create();
  fPath := '';
  fRoot := '';
  fHash := '';
  fSize := 0;
  fModified := 0;
end;

constructor tFileRef.create(aPath: string;aRoot: string=''); overload;
var
  f: file;
begin

  create();

  fPath := aPath;
  fRoot := aRoot;

  {$I-}
  assign(f, self.fqn);
  reset(f,1);
  {$I+}
  if ioResult <> 0 then
    error('Could not create file reference for file '+fqn);

  try
    getFTime(f, fModified);
    fSize := fileSize(f);
  finally
    close(f);
  end;
end;

{full path to file}
function tFileRef.fqn: string;
begin
  result := joinPath(fRoot, fPath);
end;

{calculates the hash for this file (not done by default)}
procedure tFileRef.calculateHash();
var
  f: file;
  bytesRead: int32;
  buffer: array of byte;
begin
  assign(f, fqn);
  try
    reset(f, 1);
    if (fSize > MAX_FILESIZE) then
      error(format('Tried to process file that was too large. File size: %fkb File name: %s', [fSize/1024, fqn]));
    setLength(buffer, fSize);
    blockread(f, buffer[0], fSize, bytesRead);
    if bytesRead <> fSize then
      error(format('Did not read the correct number of bytes. Expecting %d but read %d', [fSize, bytesRead]));
    fHash := MD5.hash(buffer).toHex;
  finally
    close(f);
  end;
end;

function tFileRef.toString(): string;
begin
  if hash <> '' then
    result := copy(fHash, 1, 8)+ ' '
  else
    result := '';
  result := result + fPath;
end;

{-------------------------------------------------------------}

{adds object to storage, returns if it was added}
function tObjectStore.addObject(hash: string;objectPath: string): boolean;
var
  srcFile: string;
  dstFile: string;
  fileRef: tFileRef;
begin
  if assigned(lookupByHash(hash)) then
    exit(false);
  note(format(' -adding object %s <- %s',[copy(hash, 1, 8), objectPath]));
  srcFile := objectPath;
  dstFile := joinPath(root, hash);
  fs.copyFile(srcFile, dstFile);
  fs.setModified(dstFile, fs.getModified(srcFile));

  {add to our list of files}
  fileRef := tFileRef.create(hash, root);
  fileRef.fHash := hash;
  setLength(files, length(files)+1);
  files[length(files)-1] := fileRef;
end;

function tObjectStore.lookupByHash(hash: string): tFileRef;
var
  fRef: tFileRef;
begin
  for fRef in files do
    if fRef.hash = hash then exit(fref);
  exit(nil);
end;

constructor tObjectStore.create(aPath: string);
begin
  root := aPath;
  if not fs.exists(aPath) then begin
    note(format('Object store folder "%s" was not found, so creating it.', [aPath]));
    fs.mkdir(aPath);
  end;
  files := nil;
  self.reload();
end;

destructor tObjectStore.destroy();
begin
  clear();
  inherited destroy();
end;

procedure tObjectStore.clear();
var
  fileRef: tFileRef;
begin
  for fileRef in files do
    fileRef.free;
  files := nil;
end;

{reload file references from disk}
procedure tObjectStore.reload();
var
  fileList: tStringList;
  filename: string;
  i: integer;
begin
  clear();
  fileList := FS.listFiles(joinPath(root, '*.*'));
  setLength(files, fileList.len);
  for i := 0 to fileList.len-1 do begin
    files[i] := tFileRef.create(fileList[i], root);
    files[i].fHash := fileList[i]; //hash is stored in name.
  end;
end;

{-------------------------------------------------------------}

constructor tCheckpoint.Create(aRepo: tCheckpointRepo); overload;
begin

  if not assigned(aRepo) then error('repo was nil');

  inherited Create();
  repo := aRepo;
  fileList := nil;
  clear();
end;

constructor tCheckpoint.Create(aRepo: tCheckpointRepo;path: string); overload;
begin

  if not assigned(aRepo) then error('repo was nil');

  Create(aRepo);
  load(path);
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

  sourceFolder := '';
  message := '';
  author := '';
  date := 0;
  id:= '';

end;

{loads checkpoint from a standard folder (i.e. how V1 worked)}
procedure tCheckpoint.readFromFolder(path: string);
var
  filename: string;
  fileRef: tFileRef;
  files: tStringList;
  i: integer;
begin

  clear();

  self.sourceFolder := path;

  writeln('processing '+path);
  if not path.endsWith('\') then path += '\';

  // get all files in folder
  files := FS.listFiles(path+'*.*');

  if files.contains('message.txt') then begin
    message := loadString(path+'message.txt');
    author := 'matthew';
    date := tMyDateTime.FromDosTC(FS.getModified(joinPath(path, 'message.txt')));
  end else begin
    message := '- no message text - ';
  end;

  // create file reference for each one (including hash)
  for i := 0 to files.len-1 do begin
    if files[i] = 'message.txt' then continue;
    {not: no subfolder support yet, but we'll add it here}
    fileRef := tFileRef.create(files[i], path);
    if fileRef.fSize > MAX_FILESIZE then begin
      warn(format('Skipping %s as it is too large (%fkb)',[fileRef.fqn, fileRef.fSize/1024]));
      fileRef.free;
      continue;
    end;
    fileRef.calculateHash();
    {add reference}
    setLength(fileList, length(fileList)+1);
    fileList[length(filelist)-1] := fileRef;
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
    srcFile := joinPath(repo.objectStore.root, fileRef.hash);
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
procedure tCheckpoint.load(path: string);
var
  lines: tStringList;
  line: string;
  currentSection: string;
  currentFileRef: tFileRef;
  reader: tINIReader;
  obj: tObject;
  checkpointPath: string;

begin

  if not path.endsWith('.txt', true) then error('Path must be a checkpoint .txt file');

  if not fs.exists(path) then
    error(format('Checkpoint "%s" does not exist.', [path]));

  currentFileRef := nil;

  clear();

  reader := tINIReader.create(checkpointPath, objectFactory);

  while not reader.eof do begin
    obj := reader.readObject();
    if obj is tFileRef then begin
      setLength(fileList, length(fileList)+1);
      fileList[length(fileList)-1] := tFileRef(obj);
    end;
  end;

end;

{saves the checkpoint to repo}
procedure tCheckpoint.save(path: string);
var
  t: tINIWriter;
  fileRef: tFileRef;
  commitID: tDigest;
  i: integer;
begin

  if not path.endsWith('.txt', true) then error('Path must be a checkpoint .txt file');

  {save objects first, just in case anything goes wrong}
  {this way we won't have an ini file already}
  writeObjects();

  {then write out the files, just so we can get the hash}
  t := tINIWriter.create(path);
  try
    for fileRef in fileList do
      t.writeObject('file', fileRef);
  finally
    t.free();
  end;

  {next hash the ini file for our commit id}
  id := hash(loadString(path)).toHex;

  {then write out the complete file}
  t := tINIWriter.create(path);
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
  if not fs.exists(aRepoRoot) then error(format('No repo found at "%s"', [aRepoRoot]));
  repoRoot := aRepoRoot;
  objectStore := tObjectStore.create(joinPath(aRepoRoot, 'store'));
end;

destructor tCheckpointRepo.destroy();
begin
  objectStore.free;
  repoRoot := '';
  inherited Destroy;
end;

function tCheckpointRepo.generateDiff(checkpointOld, checkpointNew: string): tCheckpointDiff;
begin
  error('NIY');
end;

function tCheckpointRepo.hasCheckpoint(checkpointName: string): boolean;
begin
  result := fs.exists(getCheckpointPath(checkpointName));
end;

function tCheckpointRepo.getCheckpointPath(checkpointName: string): string;
begin
  result := joinPath(repoRoot, checkpointName)+'.txt';
end;

function tCheckpointRepo.load(checkpointName: string): tCheckpoint;
begin
  result := tCheckpoint.create(self, getCheckpointPath(checkpointName));
end;

{-------------------------------------------------------------}

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

class operator tDiffStats.add(a,b: tDiffStats): tDiffStats;
begin
  result.added := a.added + b.added;
  result.removed := a.removed + b.removed;
  result.changed := a.changed + b.changed;
  result.newLen := a.newLen + b.newLen;
end;

{-------------------------------------------------------------}

begin
end.
