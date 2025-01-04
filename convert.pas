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
  public
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


{-------------------------------------------------------------}

constructor tFileRef.create(path: string);
begin
  fFileName := extractFilename(path);
  fPath := extractPath(path);
  fHash := '';
end;

function tFileRef.toString(): string;
begin
  result := fFilename;
  if hash <> '' then
    result += ' 0x'+copy(fHash, 1, 8);
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
