{handles files system stuff}
unit filesystem;

interface

uses
  debug,
  test,
  utils,
  list,
  dos;

function fsListFiles(path: string): tStringList;

implementation

{returns a list of all files in filesystem matching path
e.g. c:\src\*.pas}
function fsListFiles(path: string): tStringList;
var
  sr: SearchRec;
begin
  result := tStringList.create([]);
  findFirst(path, AnyFile, sr);
  while DosError = 0 do begin
    if sr.size > 0 then begin
      result += toLowerCase(sr.name);
    end;
    findNext(sr);
  end;
  findClose(sr);
end;

begin
end.
