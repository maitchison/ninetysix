unit glob;

interface

uses
  utils,
  inifile,
  debug,
  list,
  fileSystem;

type

  {scans a folder and returns list of files matching constraints}
  tGlob = class
  protected
    ignoreFolders: tStringList;
    ignoreExtensions: tStringList;
    ignoreFiles: tStringList;
    function isFileIgnored(filename: string): boolean;
    function isFolderIgnored(folderName: string): boolean;
  public
    procedure loadIgnoreFile(filename: string);
    function getFiles(path: string; pattern: string='*.*'; recursive: boolean=true): tStringList;
  end;

implementation

function tGlob.isFileIgnored(filename: string): boolean;
begin
  if ignoreFiles.contains(filename.toLower()) then exit(true);
  if ignoreExtensions.contains(extractExtension(filename).toLower()) then exit(true);
  exit(false);
end;

function tGlob.isFolderIgnored(folderName: string): boolean;
begin
  if ignoreFolders.contains(folderName.toLower()) then exit(true);
  exit(false);
end;

procedure tGlob.loadIgnoreFile(filename: string);
var
  t: tINIReader;
  line: string;
begin
  {not really an ini file, but this will do for the moment}
  t := tINIReader.create(filename);
  while not t.eof do begin
    line := t.nextLine();
    if line = '' then continue;
    if line.startsWith('.') then begin
      ignoreExtensions.append(copy(line, 2, length(line)-1));
    end else if line.contains('.') then begin
      ignoreFiles.append(line);
    end else begin
      ignoreFolders.append(line);
    end;
  end;
  t.free;
end;

{get files. out paths will be relative to path}
function tGlob.getFiles(path: string; pattern: string = '*.*'; recursive: boolean=true): tStringList;
var
  filename, subfolder: string;
  subfolderFiles: tStringList;
begin

  result.clear();

  for filename in fs.listFiles(joinPath(path, pattern)) do begin
    if isFileIgnored(filename) then continue;
    result.append(filename);
  end;

  if not recursive then exit;

  for subfolder in fs.listFolders(path) do begin
    if isFolderIgnored(subfolder) then continue;
    subfolderFiles := getFiles(joinPath(path, subfolder), pattern, true);
    for filename in subfolderFiles do
      result.append(joinPath(subfolder, filename));
  end;

end;

begin
end.
