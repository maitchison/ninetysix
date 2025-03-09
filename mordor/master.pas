
program master;

{
todo: full auto mode
- [ ] Detect file changes
- [ ] Long audio gets auto ETA
}

uses
  debug,
  utils,
  graph32,
  crt,
  sound,
  stream,
  la96,
  lc96,
  sysPNG,
  iniFile,
  uResLib,
  filesystem;

var
  {force processing of all files}
  FORCE: boolean = false;
  resLib: tResourceLibrary;

const
  {TODO: from CWD}
  SRC_ROOT = 'c:\masters\romdor';
  DST_ROOT = 'c:\dev\romdor\res';

procedure updateEncodeProgress(frameOn: int32; samplePtr: pAudioSample16S; frameLength: int32);
begin
  {todo: do something fancy here, like eta, speed etc}
  if frameOn mod 16 = 15 then write('.');
end;

{checks if we need to process file}
function preProcess(srcFile, dstFile: string): boolean;
var
  tag: string;
  needsUpdate: boolean;
begin
  tag := extractFilename(srcFile);
  if tag.startsWith('_') then exit(false);
  textAttr := LightGray;
  write(pad(tag, 40));
  needsUpdate := resLib.needsUpdate(dstFile);
  textAttr := Green;
  if not needsUpdate then writeln('[Skip]');
  textAttr := White;
  exit(needsUpdate);
end;

procedure postProcess(srcFile, dstFile: string);
var
  res: tResourceInfo;
begin
  res.srcFile := srcFile;
  res.dstFile := dstFile;
  res.modifiedTime := fs.getModified(srcFile);
  resLib.updateResource(res);
  resLib.serialize('resources.ini');
end;

procedure convertPNG(filename: string);
var
  srcPath, dstPath: string;
  img: tPage;
begin
  srcPath := joinPath(SRC_ROOT, filename+'.png');
  dstPath := joinPath(DST_ROOT, filename+'.p96');

  if not preProcess(srcPath, dstPath) then exit;

  img := tPage.Load(srcPath);
  saveLC96(dstPath, img);
  textAttr := LightGreen;
  writeLn(format('[%dx%d]',[img.width, img.height]));
  textAttr := White;
  img.free();

  postProcess(srcPath, dstPath);
end;

procedure convertWave(filename: string);
var
  srcPath, dstPath: string;
  writer: tLA96Writer;
  sfx: tSoundEffect;
begin
  srcPath := joinPath(SRC_ROOT, filename+'.wav');
  dstPath := joinPath(DST_ROOT, filename+'.a96');

  if not preProcess(srcPath, dstPath) then exit;

  sfx := tSoundEffect.Load(srcPath);

  writer := tLA96Writer.create();
  writer.open(dstPath);
  writer.writeA96(sfx, ACP_HIGH);
  writer.free();

  textAttr := Green;
  writeLn(format('[%.2fs]',[sfx.length/441000]));
  textAttr := White;
  sfx.free();

  postProcess(srcPath, dstPath);
end;

procedure masterGFX();
var
  filename,tag: string;
begin
  writeln('Processing GFX');
  for filename in fs.listFiles(joinPath(SRC_ROOT, '\*.png')) do begin
    tag := removeExtension(extractFilename(filename));
    convertPNG(tag);
  end;
end;

{create compressed copies of master music tracks}
procedure masterSFX();
var
  filename: string;
  tag: string;
  root: string;
begin
  writeln('Processing SFX');
  for filename in fs.listFiles(joinPath(SRC_ROOT, '\*.wav')) do begin
    tag := removeExtension(extractFilename(filename));
    convertWave(tag);
  end;
end;

begin
  if (paramcount = 1) and (paramStr(1).toLower() = '--force') then
    resLib := tResourceLibrary.Create()
  else
    resLib := tResourceLibrary.CreateOrLoad('resources.ini');

  masterGFX();
  masterSFX();

  resLib.free();
end.
