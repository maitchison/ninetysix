{handles files system stuff}
unit uFileSystem;

interface

uses
  uDebug,
  uTest,
  uUtils,
  uList,
  uTypes,
  dos;

type
  {file mode, from DOS I think}
  tFileMode = (FM_READ=0, FM_WRITE=1, FM_READWRITE=2);

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
    procedure delFile(path: string);

    function  mkDir(path: string): boolean;
    procedure mkDirs(path: string);
    function  listFiles(path: string): tStringList;
    function  listFolders(path: string): tStringList;

    procedure openFile(path: string;var f: file; fileMode: tFileMode=FM_READ);
  end;

var
  fileSystem: tFilesystem;

implementation

procedure tFileSystem.rename(a,b: string);
begin
  dos.exec(getEnv('COMSPEC'), format('/C ren %s %s > nul', [a, b]));
end;

procedure tFileSystem.delFolder(path: string);
begin
  dos.exec(getEnv('COMSPEC'), format('/C deltree /y %s > nul', [path]));
end;

procedure tFileSystem.delFile(path: string);
var
  f: file;
  error: word;
begin
  {$i-}
  assign(f, path);
  erase(f);
  error := ioResult;
  {$i+}
  if error in [0,2] then exit else raise Exception.create('Error [%d] deleting file %s.', [error, path]);
end;

function tFileSystem.exists(filename: string): boolean;
var
  f: file;
begin
  IOResult; // just in case there was a previous error;
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
  if not exists(fileA) then fatal('File not found '+fileA);
  if not exists(fileB) then fatal('File not found '+fileB);
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

{create fold and any required subfolders}
procedure tFileSystem.mkDirs(path: string);
var
  dir: string;
  lhs,rhs: string;
begin


  dir := '';

  if not split(path, '\', lhs, rhs) then exit;

  repeat
    dir := dir + lhs + '\';
    path := rhs;
    // silly ..why does c:\ come up as not exists?
    if (not fileSystem.folderExists(dir)) and (dir <> 'c:\') then begin
      note('>>'+dir);
      system.mkDir(dir);
    end;
    if not split(path, '\', lhs, rhs) then exit;
  until false;
end;

{returns a list of all files in filesystem matching path
e.g. c:\src\*.pas}
function tFileSystem.listFiles(path: string): tStringList;
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
function tFileSystem.listFolders(path: string): tStringList;
var
  sr: SearchRec;
begin
  result := tStringList.create([]);
  if not path.endsWith('\') then path += '\';
  findFirst(path+'*', AnyFile, sr);
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
  assign(t2, fileB);

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

  if not self.exists(filename) then fatal(format('File "%s" not found.', [filename]));

  assign(t, filename);
  reset(t);
  while not EOF(t) do begin
    readln(t, line);
    result.append(line);
  end;
  close(t);
end;

{opens file, raises exception on error}
procedure tFileSystem.openFile(path: string;var f: file; fileMode: tFileMode=FM_READ);
var
  oldFileMode: word;
  errorCode: word;
begin

  oldFileMode := system.fileMode;
  system.fileMode := byte(fileMode);

  system.IOResult; // clear previous error, if any.

  {$i-}
  case fileMode of
    FM_READ: begin
      system.assign(f, path);
      system.reset(f,1);
    end;
    FM_WRITE: begin
      system.assign(f, path);
      system.rewrite(f,1);
    end;
    FM_READWRITE: begin
      if self.exists(path) then begin
        system.assign(f, path);
        system.rewrite(f,1);
        system.reset(f,1);
      end else begin
        system.assign(f, path);
        system.rewrite(f,1);
      end;
    end;
    else raise GeneralError('Invalid fileMode %d', [fileMode]);
  end;

  system.fileMode := oldFileMode;
  errorCode := system.IOResult;

  {$i+}

  case errorCode of
    0: ;
    2: raise tFileNotFoundError.create('File not found "%s"', [path]);
    else raise tIOError.create('Could not open file "%s", Error:%s', [path, getIOErrorString(errorCode)]);
  end;

end;

{--------------------------------------------------------------}
begin
end.
