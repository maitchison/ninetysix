{convert from old repo to new one}
program convert;

uses
  checkpoint,
  debug,
  crt, {remove}
  test,
  utils,
  list,
  filesystem,
  md5,
  iniFile,
  dos;

procedure processOldRepo();
var
  cpm: tCheckpointManager;
  folders: tStringList;
  folder: string;
begin
  cpm := tCheckpointManager.create('$repo');

  folders := FS.listFolders('$REP');
  folders.sort();
  for folder in folders do begin

    {exclude any folders not matching the expected format}
    {expected format is yyyymmdd_hhmmss
    {which I had regex here...}
    if length(folder) <> 15 then continue;
    if folder[9] <> '_' then continue;

    if cpm.hasCheckpoint(folder) then continue;

    cpm.readFromFolder('$REP\'+folder);
    cpm.save(folder);
  end;

  cpm.free;
end;

procedure viewCheckpoint();
var
  cpm: tCheckpointManager;
begin
  cpm := tCheckpointManager.create('$repo');

  cpm.load('20241129_093958');
  cpm.exportToFolder('tmp');

  cpm.free;
end;

{go through each checkpoint and work out the change between each checkpoint}
procedure generateCheckpointStats();
begin
end;

begin
  textattr := $07;
  clrscr;
  WRITE_TO_SCREEN := true;
  test.runTestSuites();

  processOldRepo();

end.
