
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

{create compressed copies of master music tracks}
procedure masterSongs();
var
  verbose: boolean;
  sourceFiles: array of string = ['sunshine', 'clowns', 'crazy', 'blue'];
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

  for filename in sourceFiles do begin
    srcPath := joinPath('c:\dev\masters\player', filename+'.wav');
    if not fs.exists(srcPath) then begin
      warning('File not found '+srcPath);
      continue;
    end;

    dstPath := joinPath('music', filename+'.a96');
    if (not FORCE) and fs.exists(dstPath) then begin
      note('Skipping '+srcPath);
      continue;
    end;

    {compress it}
    writeln();
    write(filename+': ');
    srcMusic := tSoundEffect.loadFromWave(srcPath);
    outStream := encodeLA96(srcMusic, ACP_HIGH, verbose);
    outStream.writeToFile(dstPath);
    outStream.free;
  end;

  writeln('Done.');
end;

procedure convertPNG(filename: string);
var
  srcPath, dstPath: string;
  img: tPage;
begin
  srcPath := joinPath('c:\dev\masters\player', filename+'.png');
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
  convertPNG('background');
  convertPNG('background_800x600');
  convertPNG('font');
end;

begin
  if (paramcount = 1) and (paramStr(1).toLower() = '--force') then
    FORCE := true;
  masterGFX();
  masterSongs();
end.
