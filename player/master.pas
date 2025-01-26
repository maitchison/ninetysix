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

{create compressed copies of master music tracks}
procedure masterSongs();
var
  verbose: boolean;
  sourceFiles: array of string = ['sunshine', 'clowns', 'crazy', 'blue'];
  filename: string;
  srcPath, dstPath: string;
  srcMusic: tSoundEffect;
  outStream: tStream;
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

    dstPath := joinPath('res', filename+'.a96');
    if fs.exists(dstPath) then begin
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
end;

begin
  masterGFX();
  masterSongs();
end.
