unit objectstore;

interface

uses
  {$I baseunits.inc},
  fileRef;

type
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

implementation

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
  fileRef.hash := hash;
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
  if not fs.folderExists(aPath) then begin
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
  i: integer;
begin
  clear();
  fileList := fs.listFiles(joinPath(root, '*.*'));
  setLength(files, fileList.len);
  for i := 0 to fileList.len-1 do begin
    files[i] := tFileRef.create(fileList[i], root);
    files[i].hash := fileList[i]; //hash is stored in name.
  end;
end;

begin
end.
