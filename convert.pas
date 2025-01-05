{convert from go-v1 repo to go-v2}
program convert;

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

    property path: string read fPath;
    property hash: string read fHash;
    property size: int64 read fSize;
    property modified: int32 read fModified;

  public

    constructor create(aPath: string;aRoot: string = '');
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

  tCheckpointManager = class

    objectStore: tObjectStore;

    messageText: string;
    author: string;
    date: tDateTime;
    fileList: array of tFileRef;

    {where our files came from}
    sourceFolder: string;
    {where our repo is stored}
    repoFolder: string;

  protected
    procedure writeObjects();
  public

    constructor create(aRepoFolder: string);
    destructor destroy();

    procedure clear();

    function  hasCheckpoint(checkpointName: string): boolean;
    function  getCheckpointPath(checkpointName: string): string;

    procedure readFromFolder(path: string);
    procedure exportToFolder(path: string);
    procedure load(checkpointName: string);
    procedure save(checkpointName: string);
  end;

const
  {fine for text files, but don't process large binary files}
  MAX_FILESIZE = 128*1024;

{-------------------------------------------------------------}

constructor tFileRef.create(aPath: string;aRoot: string='');
var
  f: file;
begin
  inherited create();
  fPath := aPath;
  fRoot := aRoot;
  fHash := ''; //hash is defered.
  fSize := 0;
  fModified := 0;

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
  result := concatPath(fRoot, fPath);
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
  note(format(' -adding object %s <-- %s',[copy(hash, 1, 8), objectPath]));
  srcFile := objectPath;
  dstFile := concatPath(root, hash);
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
  fs.mkdir(aPath);
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
  fileList := FS.listFiles(concatPath(root, '*.*'));
  setLength(files, fileList.len);
  for i := 0 to fileList.len-1 do begin
    files[i] := tFileRef.create(fileList[i], root);
    files[i].fHash := fileList[i]; //hash is stored in name.
  end;
end;

{-------------------------------------------------------------}

constructor tCheckpointManager.create(aRepoFolder: string);
begin
  inherited create();
  fileList := nil;
  sourceFolder := '';
  repoFolder := aRepoFolder;
  objectStore := tObjectStore.create(concatPath(repoFolder, 'store'));
end;

destructor tCheckpointManager.destroy();
begin
  clear();
  objectStore.free;
  inherited destroy;
end;

procedure tCheckpointManager.clear();
var
  fileRef: tFileRef;
begin
  if assigned(fileList) then
    for fileRef in fileList do
      fileRef.free();
  fileList := nil;
  sourceFolder := '';
end;

{loads checkpoint from a standard folder (i.e. how V1 worked)}
procedure tCheckpointManager.readFromFolder(path: string);
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
    messageText := loadString(path+'message.txt');
    author := 'matthew';
    date := tMyDateTime.FromDosTC(FS.getModified(concatPath(path, 'message.txt')));
  end else begin
    messageText := '- no message text - ';
  end;

  // create file reference for each one (including hash)
  for i := 0 to files.len-1 do begin
    if files[i] = 'message.txt' then continue;
    {not: no subfolder support yet, but we'll add it here}
    fileRef := tFileRef.create(files[i], path);
    if fileRef.size > MAX_FILESIZE then begin
      warn(format('Skipping %s as it is too large (%fkb)',[fileRef.fqn, fileRef.size/1024]));
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
procedure tCheckpointManager.exportToFolder(path: string);
begin
  error('NIY');
end;

{read checkpoint metadata from file}
procedure tCheckpointManager.load(checkpointName: string);
begin
  error('NIY');
end;

function tCheckpointManager.hasCheckpoint(checkpointName: string): boolean;
begin
  result := fs.exists(getCheckpointPath(checkpointName));
end;

{returns path to checkpoint file}
function tCheckpointManager.getCheckpointPath(checkpointName: string): string;
begin
  result := concatPath(repoFolder, checkpointName)+'.txt';
end;

{saves the checkpoint to repo}
procedure tCheckpointManager.save(checkpointName: string);
var
  t: tINIFile;
  fileRef: tFileRef;
  commitID: tDigest;
  lines: tStringList;
  i: integer;
begin

  {save objects first, just in case anything goes wrong}
  {this way we won't have an ini file already}
  writeObjects();

  {then write out the files, just so we can get the hash}
  t := tIniFile.create(getCheckpointPath(checkpointName));
  try
    for fileRef in fileList do
      t.writeObject('file', fileRef);
  finally
    t.free();
  end;

  {next hash the ini file for our commit id}
  commitID := hash(loadString(getCheckpointPath(checkpointName)));

  {then write out the complete file}
  t := tIniFile.create(getCheckpointPath(checkpointName));
  try
    t.writeSection('commit');
    t.writeString('message', messageText);
    t.writeString('id', commitID.toHex);
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
procedure tCheckpointManager.writeObjects();
var
  fileRef: tFileRef;
begin
  for fileRef in fileList do
    objectStore.addObject(fileRef.hash, fileRef.fqn);
end;

procedure processOldRepo();
var
  checkpoint: tCheckpointManager;
  folders: tStringList;
  folder: string;
begin
  checkpoint := tCheckpointManager.create('repo');

  folders := FS.listFolders('$REP');
  folders.sort();
  for folder in folders do begin

    {exclude any folders not matching the expected format}
    {expected format is yyyymmdd_hhmmss
    {which I had regex here...}
    if length(folder) <> 15 then continue;
    if folder[9] <> '_' then continue;

    if checkpoint.hasCheckpoint(folder) then continue;

    checkpoint.readFromFolder('$REP\'+folder);
    checkpoint.save(folder);
  end;

  checkpoint.free;
end;

begin
  textattr := $07;
  clrscr;
  WRITE_TO_SCREEN := true;
  test.runTestSuites();

  processOldRepo();

end.
