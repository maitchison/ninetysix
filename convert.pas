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
    fPath: string;
    fName: string;
    fHash: string;
    fSize: int64;
    fModified: int32;
  public

    procedure calculateHash();

  published

    property name: string read fName;
    property path: string read fPath;
    property hash: string read fHash;
    property size: int64 read fSize;
    property modified: int32 read fModified;

  public

    constructor create(path: string);
    function toString(): string;
  end;

  {a database of object files}
  tObjectDatabase = class
    files: array of tFileRef;
    function lookupByHash(hash: string): tFileRef;
  end;

  tCheckpoint = class
    fileList: array of tFileRef;
    constructor create();
    procedure reset();
    procedure loadV1(path: string);
    procedure writeOut(path: string);
  end;

const
  {fine for text files, but don't process large binary files}
  MAX_FILESIZE = 128*1024;

{-------------------------------------------------------------}

constructor tFileRef.create(path: string);
var
  f: file;
begin
  inherited create();
  fName := extractFilename(path);
  fPath := extractPath(path);
  fHash := ''; //hash is defered.
  fSize := 0;
  fModified := 0;
  try
    assign(f, path);
    system.reset(f,1);
    getFTime(f, fModified);
    fSize := fileSize(f);
  finally
    close(f);
  end;
end;

{calculates the hash for this file (not done by default)}
procedure tFileRef.calculateHash();
var
  f: file;
  bytesRead: int32;
  buffer: array of byte;
begin
  assign(f, self.fPath + '\' + self.fName);
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
  result := result + fName;
end;

{-------------------------------------------------------------}

function tObjectDatabase.lookupByHash(hash: string): tFileRef;
var
  fRef: tFileRef;
begin
  for fRef in files do
    if fRef.hash = hash then exit(fref);
  exit(nil);
end;

{-------------------------------------------------------------}

constructor tCheckpoint.create();
begin
  fileList := nil;
end;

procedure tCheckpoint.reset();
var
  fileRef: tFileRef;
begin
  if assigned(fileList) then
    for fileRef in fileList do
      fileRef.free();
  fileList := nil;
end;

{loads an old style 'files as they are' V1 checkpoint folder}
procedure tCheckpoint.loadV1(path: string);
var
  filename: string;
  fileRef: tFileRef;
  files: tStringList;
  t: tIniFile;
  i: integer;
begin

  reset();

  writeln('processing '+path);
  if not path.endsWith('\') then path += '\';

  // get all files in folder
  files := fsListFiles(path+'*.*');
  setLength(fileList, files.len);

  // create file reference for each one (including hash)
  for i := 0 to files.len-1 do begin
    fileRef := tFileRef.create(path+files[i]);
    fileRef.calculateHash();
    fileList[i] := fileRef;
  end;
  // create hash for every file
  // write new files to object store
  // link each object

end;

procedure tCheckpoint.writeOut(path: string);
var
  t: tINIFile;
  fileRef: tFileRef;
begin
  t := tIniFile.create(path);
  for fileRef in fileList do
    t.writeObject('file', fileRef);
  t.free();
end;

procedure processRepo();
var
  checkpoint: tCheckpoint;
  folders: tStringList;
  folder: string;
begin
  checkpoint := tCheckpoint.create();

  folders := fsListFolders('$REP');
  for folder in folders do begin
    checkpoint.loadV1('$REP\'+folder);
    checkpoint.writeOut('repo\'+folder+'.txt');
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
