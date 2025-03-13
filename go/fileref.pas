unit fileref;

interface

uses
  {$I baseunits.inc},
  uIniFile,
  uMD5;

type
  tFileRef = class(iIniSerializable)
  protected

    {ok some documentation... I might need to rename some of these


    path is the 'source' of the file, i.e the handle of the file in the repo.
    fqn is what to load to get the file contents
    root is where the repo folder is...

    e.g..

    root = 'dev\src'
    path = 'airtime.pas'
    fqn -> 'dev\src\airtime.pas'

    However a head reference would look like

    root = '\dev\$repo\HEAD
    path = 'airtime.pas'
    fqn -> 'dev\$repo\HEAD\airtime.pas'

    and a checkpoint reference would look like

    root = '*dev\$repo\objectstore\'
    path = 'airtime.pas'
    fqn -> 'dev\$repo\objectstore\e1f1ae8cac8dda7f5c52a3dbe135'

    also.. please make a record and have another way to seralize
    }


    fRoot: string; // repo root folder, not saved.
    fPath: string; // relative path from repo root folder
    fHash: string;
    fSize: int64;
    fModified: int32;

    function getHash(): string;
    function getFileSize(): int64;
    function getModified(): int32;

  public
    procedure updateHash();
    function fqn: string;
    function assigned: boolean;
    property fileSize: int64 read getFileSize write fSize;
    property root: string read fRoot write fRoot;

  public
    {iIniSerializable}
    procedure writeToIni(ini: tINIWriter);
    procedure readFromIni(ini: tINIReader);
  public
    property path: string read fPath write fPath;
    property hash: string read getHash write fHash;
    property modified: int32 read getModified write fModified;
  public

    constructor create(); overload;
    constructor create(aPath: string;aRoot: string = ''); overload;
    function toString(): string; override;
  end;

  tFileRefList = array of tFileRef;

  tFileRefListHelper = record helper for tFileRefList
    procedure append(x: tFileRef);
    function contains(x: tFileRef): boolean;
    function lookup(path: string): tFileRef;
  end;

var
  NULL_FILE: tFileRef;

const
  {fine for text files, but don't process large binary files}
  MAX_FILESIZE = 128*1024;

implementation


constructor tFileRef.create(); overload;
begin
  inherited create();
  fPath := '';
  fRoot := '';
  fHash := '';
  fSize := -1; // these are defered
  fModified := -1; // these are deffered
end;

constructor tFileRef.create(aPath: string;aRoot: string=''); overload;
var
  f: file;
begin
  create();
  fPath := aPath;
  fRoot := aRoot;
end;

procedure tFileRef.writeToIni(ini: tINIWriter);
begin
  ini.writeString('path', path);
  ini.writeString('hash', hash);
  ini.writeInteger('modified', modified);
end;

procedure tFileRef.readFromIni(ini: tINIReader);
begin
  path := ini.readString('path');
  hash := ini.readString('hash');
  modified := ini.readInteger('modified');
end;

{full path to file}
function tFileRef.fqn: string;
begin
  if fRoot.startsWith('*') then
    result := joinPath(copy(fRoot, 2, length(fRoot)-1), fHash)
  else
    result := joinPath(fRoot, fPath);
end;

function tFileRef.assigned: boolean;
begin
  result := path <> '';
end;


{returns the hash, calculates it if needed.}
function tFileRef.getHash(): string;
begin
  if fHash = '' then updateHash();
  result := fHash;
end;

{returns the hash, calculates it if needed.}
function tFileRef.getFilesize(): int64;
begin
  if fSize < 0 then
    fSize := fileSystem.getFileSize(self.fqn);
  result := fSize;
end;

{returns the hash, calculates it if needed.}
function tFileRef.getModified(): int32;
begin
  if fModified < 0 then
    fModified := fileSystem.getModified(self.fqn);
  result := fModified;
end;

{calculates the hash for this file (not done by default)}
procedure tFileRef.updateHash();
var
  f: file;
  bytesRead: int32;
  buffer: array of byte;
begin

  if self.fileSize = 0 then begin
    fHash := uMD5.NULL_HASH.toHex;
    exit;
  end;

  buffer := nil;
  bytesRead := 0;
  assign(f, self.fqn);
  try
    reset(f, 1);
    if (fileSize > MAX_FILESIZE) then
      fatal(format('Tried to process file that was too large. File size: %fkb File name: %s', [fileSize/1024, fqn]));
    setLength(buffer, fileSize);
    blockread(f, buffer[0], fileSize, bytesRead);
    if bytesRead <> fileSize then
      fatal(format('Did not read the correct number of bytes. Expecting %d but read %d', [fileSize, bytesRead]));
    fHash := uMD5.hash(buffer).toHex;
  finally
    close(f);
  end;
end;

function tFileRef.toString(): string;
begin
  if hash <> '' then
    result := copy(hash, 1, 8)+ ' '
  else
    result := '';
  result := result + fPath;
end;

{-------------------------------------------------------------}

procedure tFileRefListHelper.append(x: tFileRef);
begin
  setLength(self, length(self)+1);
  self[length(self)-1] := x;
end;

function tFileRefListHelper.contains(x: tFileRef): boolean;
var
  fr: tFileRef;
begin
  for fr in self do
    if fr.path = x.path then exit(true);
  exit(false);
end;

function tFileRefListHelper.lookup(path: string): tFileRef;
var
  fr: tFileRef;
begin
  for fr in self do
    if path = fr.path then exit(fr);
  exit(NULL_FILE);
end;

{-------------------------------------------------------------}

begin
  NULL_FILE := tFileRef.create();
end.
