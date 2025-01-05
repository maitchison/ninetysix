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
    function fqp: string;

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

  protected
    procedure writeObjects();
  public

    constructor create();
    destructor destroy();

    procedure clear();

    procedure readFromFolder(path: string);
    procedure exportToFolder(path: string);
    procedure load(path: string);
    procedure save(path: string);
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
  assign(f, self.fqp);
  reset(f,1);
  {$I+}
  if ioResult <> 0 then
    error('Could not create file reference for file '+fqp);

  try
    getFTime(f, fModified);
    fSize := fileSize(f);
  finally
    close(f);
  end;
end;

{full path to file}
function tFileRef.fqp: string;
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
  assign(f, fqp);
  try
    reset(f, 1);
    if (fSize > MAX_FILESIZE) then
      error('Tried to process file that was too large');
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

constructor tCheckpointManager.create();
begin
  inherited create();
  fileList := nil;
  sourceFolder := '';
  objectStore := tObjectStore.create('repo\store');
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
  setLength(fileList, files.len);

  if files.contains('message.txt') then begin
    messageText := loadString(path+'message.txt');
    author := 'matthew';
    date := tMyDateTime.FromDosTC(FS.getModified(concatPath(path, 'message.txt')));
  end else begin
    messageText := '- no message text - ';
  end;

  // create file reference for each one (including hash)
  for i := 0 to files.len-1 do begin
    {not: no subfolder support yet, but we'll add it here}
    fileRef := tFileRef.create(files[i], path);
    fileRef.calculateHash();
    fileList[i] := fileRef;
  end;
end;

{writes all files to folder so that others can read them}
procedure tCheckpointManager.exportToFolder(path: string);
begin
  error('NIY');
end;

{read checkpoint metadata from file}
procedure tCheckpointManager.load(path: string);
begin
  error('NIY');
end;

{saves the checkpoint to repo}
procedure tCheckpointManager.save(path: string);
var
  t: tINIFile;
  fileRef: tFileRef;
begin
  t := tIniFile.create(path);
  try
    t.writeSection('commit');
    t.writeString('message', messageText);
    t.writeString('author', author);
    t.writeFloat('date', date);
    t.writeBlank();

    for fileRef in fileList do begin
      t.writeObject('file', fileRef);
    end;
  finally
    t.free();
  end;

  writeObjects();
end;

{writes out objects to object database}
procedure tCheckpointManager.writeObjects();
var
  fileRef: tFileRef;
begin
  for fileRef in fileList do
    objectStore.addObject(fileRef.hash, fileRef.fqp);
end;

procedure processRepo();
var
  checkpoint: tCheckpointManager;
  folders: tStringList;
  folder: string;
  counter: integer;
begin
  checkpoint := tCheckpointManager.create();

  folders := FS.listFolders('$REP');
  counter := 0;
  for folder in folders do begin
    checkpoint.readFromFolder('$REP\'+folder);
    checkpoint.save('repo\'+folder+'.txt');
    inc(counter);
    if counter > 10 then exit;
  end;

  checkpoint.free;
end;

begin
  textattr := $07;
  clrscr;
  WRITE_TO_SCREEN := true;
  test.runTestSuites();

  processRepo();

end.
