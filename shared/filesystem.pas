{handles files system stuff}
unit filesystem;

interface

uses
  debug,
  test,
  utils,
  list,
  types,
  dos;

type
  tFileSystem = class

    function  folderExists(path: string): boolean;
    function  exists(filename: string): boolean;
    procedure copyFile(srcFile, dstFile: string);
    function  getFileSize(fileName: string): int64;
    procedure setModified(fileName: string;time: dword);
    function  getModified(fileName: string): dword;

    function  readText(filename: string): tStringList;
    function  compareText(fileA, fileB: string): boolean;

    function  wasModified(fileA, fileB: string): boolean;

    procedure rename(a,b: string);
    procedure delFolder(path: string);

    function  mkDir(path: string): boolean;
    function  listFiles(path: string): tStringList;
    function  listFolders(path: string): tStringList;
  end;

var
  fs: tFilesystem;

implementation

procedure tFileSystem.rename(a,b: string);
begin
  dos.exec(getEnv('COMSPEC'), format('/C ren %s %s > nul', [a, b]));
end;

procedure tFileSystem.delFolder(path: string);
begin
  dos.exec(getEnv('COMSPEC'), format('/C deltree /y %s > nul', [path]));
end;

function tFileSystem.exists(filename: string): boolean;
var
  f: file;
begin
  assign(f, filename);
  {$I-}
  reset(f);
  {$I+}
  if IOResult = 0 then begin
    close(f);
    exit(True);
  end else
    exit(False);
end;

function tFileSystem.folderExists(path: string): boolean;
var
  sr: SearchRec;
begin
  findFirst(path, dos.DIRECTORY, sr);
  result := (dosError = 0) and ((sr.attr and dos.DIRECTORY) <> 0);
  findClose(sr);
end;

procedure tFileSystem.copyFile(srcFile, dstFile: string);
begin
  {not sure this is the best way to do this?}
  dos.exec(getEnv('COMSPEC'), format('/C copy %s %s > nul', [srcFile, dstFile]));
end;

{return filesize of file or 0 if not found.}
function tFileSystem.getFileSize(fileName: string): int64;
var
  f: file;
begin
  assign(f, fileName);
  {$I-}
  reset(f, 1);
  {$I+}
  if IOResult <> 0 then
    exit(0);
  result := system.FileSize(f);
  close(f);
end;

procedure tFileSystem.setModified(fileName: string;time: dword);
var
  f: file;
begin
  assign(f, fileName);
  {$I-}
  reset(f);
  {$I+}
  if IOResult <> 0 then
    exit;
  dos.setFTime(f, time);
  close(f);
end;

{checks if two files share the same modified timestamp}
function tFileSystem.wasModified(fileA, fileB: string): boolean;
begin
  if not exists(fileA) then error('File not found '+fileA);
  if not exists(fileB) then error('File not found '+fileB);
  result := getModified(fileA) <> getModified(fileB);
end;

{returns timestamp for file modified time, or 0 if file not found.}
function tFileSystem.getModified(fileName: string): dword;
var
  f: file;
  t: longint;
begin
  assign(f, fileName);
  {$I-}
  reset(f);
  {$I+}
  if IOResult <> 0 then
    exit(0);
  dos.getFTime(f, t);
  close(f);
  exit(t);
end;


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
      result.append(toLowerCase(sr.name));
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

{returns if two text files are identical}
function tFileSystem.compareText(fileA, fileB: string): boolean;
var
  t1, t2: text;
  line1, line2: string;
begin

  result := true;

  if getFileSize(fileA) <> getFileSize(fileB) then exit(false);

  assign(t1, fileA);
  assign(t2, fileA);

  reset(t1);
  reset(t2);

  while not eof(t1) and not eof(t2) do begin
    readln(t1, line1);
    readln(t2, line2);
    if line1 <> line2 then begin
      result := false;
      break;
    end;
  end;

  if (not eof(t1)) or (not eof(t2)) then result := false;

  close(t1);
  close(t2);

end;

function tFileSystem.readText(filename: string): tStringList;
var
  t: text;
  line: string;
begin

  result.clear();

  if filename = '' then exit;

  if not self.exists(filename) then error(format('File "%s" not found.', [filename]));

  assign(t, filename);
  reset(t);
  while not EOF(t) do begin
    readln(t, line);
    result.append(line);
  end;
  close(t);
end;


begin
end.
