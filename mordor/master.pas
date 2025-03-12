
program master;

{
todo: full auto mode
- [ ] Detect file changes
- [ ] Long audio gets auto ETA
}

uses
  uDebug,
  uUtils,
  crt,
  sysUtils,
  uGraph32,
  uSound,
  uStream,
  uLA96,
  uLP96,
  uPNG,
  uIniFile,
  uResLib,
  uFilesystem;

var
  {force processing of all files}
  FORCE: boolean = false;
  resLib: tResourceLibrary;

const
  {TODO: from CWD}
  GUI_ROOT = 'c:\masters\gui';
  SRC_ROOT = 'c:\masters\mordor';
  DST_ROOT = 'c:\dev\mordor\';

type
  tConvertProc = procedure(srcPath, dstPath: string);
  tFileType = (ftPNG, ftWAVE);

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
  res.modifiedTime := fileSystem.getModified(srcFile);
  resLib.updateResource(res);
  resLib.serialize('resources.ini');
end;

procedure convertPNG(srcPath, dstPath: string);
var
  img: tPage;
begin

  if not preProcess(srcPath, dstPath) then exit;

  img := tPage.Load(srcPath);
  saveLC96(dstPath, img);
  textAttr := LightGreen;
  writeLn(format('[%dx%d]',[img.width, img.height]));
  textAttr := White;
  img.free();

  postProcess(srcPath, dstPath);
end;

procedure convertWave(srcPath, dstPath: string);
var
  writer: tLA96Writer;
  sfx: tSound;
begin

  if not preProcess(srcPath, dstPath) then exit;

  sfx := tSound.Load(srcPath);

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

procedure processFolder(srcPath, dstPath: string; fileType: tFileType);
var
  filename, tag: string;
  srcExtension, dstExtension: string;
  convert: tConvertProc;
begin

  case fileType of
    ftPNG: begin
      srcExtension := 'png';
      dstExtension := 'p96';
      convert := convertPNG;
    end;
    ftWAVE: begin
      srcExtension := 'wav';
      dstExtension := 'a96';
      convert := convertWave;
    end;
    else raise ValueError('Invalid filetype');
  end;

  writeln(format('Processing %s -> %s [%s]', [srcPath, dstPath, srcExtension]));

  for filename in fileSystem.listFiles(joinPath(srcPath, '\*.'+srcExtension)) do begin
    tag := removeExtension(extractFilename(filename));
    try
      convert(joinPath(srcPath, filename), joinPath(dstPath, tag+'.'+dstExtension));
    except
      on e: sysUtils.Exception do begin
        textAttr := Red;
        writeln('[Error]');
        textAttr := White;
        warning(format('Error processing %s: %s', [tag, e.message]));
      end;
    end;

  end;
end;

begin
  if (paramcount = 1) and (paramStr(1).toLower() = '--force') then
    resLib := tResourceLibrary.Create()
  else
    resLib := tResourceLibrary.CreateOrLoad('resources.ini');

  processFolder(GUI_ROOT, joinPath(DST_ROOT, 'gui'), ftPNG);
  processFolder(joinPath(SRC_ROOT, 'gfx'), joinPath(DST_ROOT, 'res'), ftPNG);
  processFolder(joinPath(SRC_ROOT, 'music'), joinPath(DST_ROOT, 'music'), ftWAVE);
  processFolder(GUI_ROOT, joinPath(DST_ROOT, 'sfx'), ftWAVE);

  resLib.free();
end.
