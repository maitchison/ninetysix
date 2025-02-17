
program master;

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
  filesystem;

var
  {force processing of all files}
  FORCE: boolean = false;

procedure updateEncodeProgress(frameOn: int32; samplePtr: pAudioSample16S; frameLength: int32);
begin
  {todo: do something fancy here, like eta, speed etc}
  if frameOn mod 16 = 15 then write('.');
end;

procedure convertPNG(filename: string);
var
  srcPath, dstPath: string;
  img: tPage;
begin
  srcPath := joinPath('c:\dev\masters\destruct', filename+'.png');
  dstPath := 'res\'+filename+'.p96';
  if (not FORCE) and fs.exists(dstPath) then exit;
  img := tPage.Load(srcPath);
  saveLC96(dstPath, img);
  textAttr := Green;
  writeLn(format('[%dx%d]',[img.width, img.height]));
  textAttr := White;
  img.free;
end;

procedure masterGFX();
begin
  convertPNG('title');
  convertPNG('sprites');
  convertPNG('netfont1');
  convertPNG('netfont2');
  convertPNG('font');
end;

{create compressed copies of master music tracks}
procedure masterSFX();
var
  verbose: boolean;
  sourceFiles: array of string = ['explode', 'shoot', 'plasma', 'rocket'];
  writer: tLA96Writer;
  filename: string;
  srcPath, dstPath: string;
  srcMusic: tSoundEffect;
  outStream: tMemoryStream;
begin
  LA96_ENABLE_STATS := false;
  verbose := true;

  writer := tLA96Writer.create();

  for filename in sourceFiles do begin
    srcPath := joinPath('c:\dev\masters\destruct', filename+'.wav');
    if not fs.exists(srcPath) then begin
      warning('File not found '+srcPath);
      continue;
    end;

    dstPath := joinPath('res', filename+'.a96');
    if (not FORCE) and fs.exists(dstPath) then begin
      note('Skipping '+srcPath);
      continue;
    end;

    {compress it}
    writeln();
    write(filename+': ');
    srcMusic := tSoundEffect.Load(srcPath);
    writer.open(dstPath);
    writer.frameWriteHook := updateEncodeProgress();
    writer.writeA96(srcMusic, ACP_HIGH);
  end;

  writer.free();

  writeln();
  writeln('Done.');
end;


{create compressed copies of master music tracks}
procedure masterMusic();
var
  verbose: boolean;
  sourceFiles: array of string = ['dance1'];
  writer: tLA96Writer;
  filename: string;
  srcPath, dstPath: string;
  srcMusic: tSoundEffect;
  outStream: tMemoryStream;
begin
  writeln();
  writeln('--------------------------');
  writeln('Compressing');
  writeln('--------------------------');
  LA96_ENABLE_STATS := false;
  verbose := true;

  writer := tLA96Writer.create();

  for filename in sourceFiles do begin
    srcPath := joinPath('c:\dev\masters\destruct', filename+'.wav');
    if not fs.exists(srcPath) then begin
      warning('File not found '+srcPath);
      continue;
    end;

    dstPath := joinPath('res', filename+'.a96');
    if (not FORCE) and fs.exists(dstPath) then begin
      note('Skipping '+srcPath);
      continue;
    end;

    {compress it}
    writeln();
    write(filename+': ');
    srcMusic := tSoundEffect.Load(srcPath);
    writer.open(dstPath);
    writer.frameWriteHook := updateEncodeProgress();
    writer.writeA96(srcMusic, ACP_HIGH);
  end;

  writer.free();

  writeln();
  writeln('Done.');
end;


begin
  if (paramcount = 1) and (paramStr(1).toLower() = '--force') then
    FORCE := true;
  masterGFX();
  masterSFX();
  masterMusic();
end.
