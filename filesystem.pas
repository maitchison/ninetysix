{handles files system stuff}
unit filesystem;

interface

uses
  debug,
  test,
  utils,
  list,
  dos;

type
  tFileSystem = class
    function mkDir(path: string): boolean;
    function listFiles(path: string): tStringList;
    function listFolders(path: string): tStringList;
  end;

var
  FS: tFilesystem;

implementation

{create folder. returns if it was created or not}
function tFileSystem.mkDir(path: string): boolean;
begin
  {$I-}
  system.mkDir(path);
  {$I+}
  result := (IoResult = 0);
end;

{returns a list of all files in filesystem matching path
e.g. c:\src\*.pas}
function tFileSystem.ListFiles(path: string): tStringList;
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

{returns a list of all folders in path}
function tFileSystem.ListFolders(path: string): tStringList;
var
  sr: SearchRec;
begin
  result := tStringList.create([]);
  findFirst(path+'\*', AnyFile, sr);
  while DosError = 0 do begin
    if ((sr.attr and Directory) = Directory) and (sr.name <> '.') and (sr.name <> '..') then
      result += toLowerCase(sr.name);
    findNext(sr);
  end;
  findClose(sr);
end;

begin
end.
