{convert from go-v1 repo to go-v2}
program convert;

uses
  utils,
  tools,
  myHash;

type


  tFileReference = class
  protected
    fFileName: string;
    fHash: string;
  public
    property filename: string read fFileName;
    property hash: string read fHash;
  end;

  {a database of object files}
  tObjectDatabase = class
    files: array of tFileReference;
    function lookupByHash(hash: string): tFileReference;
  end;


  tCheckpoint = class

    procedure loadV1(path: string);

  end;


{-------------------------------------------------------------}

function tObjectDatabase.lookupByHash(hash: string): tFileReference;
begin
  for fref in files do
    if fref.hash = hash then exit(fref);
  exit(nil);
end;

{-------------------------------------------------------------}

{loads an old style 'files as they are' V1 checkpoint folder}
procedure loadV1(oldPath: string);
begin
  // get all files (using a .gitignore style thing?)
  // create hash for every file
  // write new files to object store
  // link each object
end;

begin
end.
