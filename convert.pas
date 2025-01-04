{convert from go-v1 repo to go-v2}
program convert;

uses
  debug,
  crt, {remove}
  test,
  utils,
  list,
  filesystem,
  md5;

type
  tFileRef = class
  protected
    fPath: string;
    fFileName: string;
    fHash: string;
    fFileSize: int64;
  public

    procedure calculateHash();

    property filename: string read fFileName;
    property hash: string read fHash;
    constructor create(path: string);

    function toString(): string;
  end;

  {a database of object files}
  tObjectDatabase = class
    files: array of tFileRef;
    function lookupByHash(hash: string): tFileRef;
  end;


  tCheckpoint = class
    procedure loadV1(path: string);
  end;

const
  {fine for text files, but don't process large binary files}
  MAX_FILESIZE = 128*1024;

{-------------------------------------------------------------}

constructor tFileRef.create(path: string);
begin
  fFileName := extractFilename(path);
  fPath := extractPath(path);
  fHash := '';
end;

{calculates the hash for this file (not done by default)}
procedure tFileRef.calculateHash();
var
  f: file;
  bytesRead: int32;
  buffer: array of byte;
begin
  assign(f, self.fpath + '\' + self.filename);
  try
    reset(f, 1);
    fFileSize := fileSize(f);
    if (fFileSize > MAX_FILESIZE) then
      error('Tried to process file that was too large');
    setLength(buffer, fFileSize);
    blockread(f, buffer[0], fFileSize, bytesRead);
    if bytesRead <> fFileSize then
      error(format('Did not read the correct number of bytes. Expecting %d but read %d', [fFileSize, bytesRead]));
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
  result := result + fFilename;
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

{loads an old style 'files as they are' V1 checkpoint folder}
procedure tCheckpoint.loadV1(path: string);
var
  fileList: tStringList;
  filename: string;
  fileRef: tFileRef;
begin
  writeln('processing '+path);
  if not path.endsWith('\') then path += '\';

  // get all files in folder
  fileList := fsListFiles(path+'*.*');

  // create file reference for each one (including hash)
  for filename in fileList do begin
    fileRef := tFileRef.create(path+filename);
    fileRef.calculateHash();
    writeln(fileRef.toString);
  end;
  // create hash for every file
  // write new files to object store
  // link each object
end;

var
  cp: tCheckpoint;

begin
  textattr := $07;
  clrscr;
  WRITE_TO_SCREEN := true;
  test.runTestSuites();
  cp := tCheckpoint.create();
  cp.loadV1('$REP\HEAD\');
end.
