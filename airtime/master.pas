{read master files and process / compress}
program import;

{$MODE delphi}

uses
  utils,
  test,
  debug,
  graph32,
  stream,
  filesystem,
  resLib,
  sound,
  crt,
  sysPNG,
  la96,
  lc96;

const
  MASTER_FOLDER = 'c:\dev\masters';
  VERBOSE: boolean = true;
  FORCE: boolean = false;

type
  // apply some changes to a page, and output a new page
  tProcessProc = function(input: tPage): tPage;

var
  resourceLibrary: tResourceLibrary;

{-----------------------------------------------}
{ Helpers }
{-----------------------------------------------}

procedure output(s: string=''; col: byte=LightGray);
var
  oldTextAttr: byte;
begin
  if not VERBOSE then exit;
  oldTextAttr := textAttr;
  textAttr := col;
  write(s);
  textAttr := oldTextAttr;
end;

procedure outputLn(s: string=''; col: byte=LightGray);
begin
  output(s+#13#10, col);
end;

{returns if a resource needs to be processed (with printing)}
function preProcess(dstPath: string;srcPath:string): boolean;
var
  res: tResource;
  id: int32;

begin

  output(pad(extractFilename(dstPath),14, ' '), LightGray);

  {make sure it exists}
  if not fileSystem.exists(srcPath) then begin
    outputLn('[missing]', LightRed);
    exit(false);
  end;

  {check if this is already done}
  id := resourceLibrary.findResourceIndex(dstPath);
  if (id >= 0) and (not FORCE) then begin
    res := resourceLibrary.resource[id];
    if
      (res.srcFile = srcPath) and
      (res.modifiedTime = fs.getModified(res.srcFile)) and
      fs.exists(dstPath)
    then begin
      outputLn('[skip]', LightGreen);
      exit(false);
    end;
  end;

  exit(true);
end;


{handle resource file update after processing (with printing)}
function postProcess(dstPath: string;srcPath:string): boolean;
var
  res: tResource;
begin
  res.srcFile := srcPath;
  res.dstFile := dstPath;
  res.modifiedTime := fs.getModified(srcPath);
  resourceLibrary.updateResource(res);
  resourceLibrary.serialize('resources.ini');
end;

{-----------------------------------------------}

procedure copyFile(filename: string; srcPath:string); overload;
var
  dstPath: string;
begin

  dstPath := joinPath('res', filename);

  if preProcess(dstPath, srcPath) then begin
    fs.copyFile(srcPath, dstPath);
    outputln('[copied]', LightGreen);
    postProcess(dstPath, srcPath);
  end;
end;

{----------------------------------------------------}

{e.g. convert('title', 'c:\dev\masters\airtime\title.bmp')}
procedure convertImage(filename: string;srcPath:string;processProc: tProcessProc=nil); overload;
var
  dstPath: string;
  img: tPage;
begin
  dstPath := 'res\'+filename+'.p96';
  if preProcess(dstPath, srcPath) then begin
    img := tPage.Load(srcPath);
    if assigned(processProc) then
      img := processProc(img);
    saveLC96(dstPath, img);
    outputLn(format('[%dx%d]',[img.width, img.height]), Green);
    img.free;
    postProcess(dstPath, srcPath);
  end;
end;

{e.g. convert('title', 'c:\dev\masters\airtime\title.bmp')}
procedure convertAudio(filename: string;srcPath:string); overload;
var
  dstPath: string;
  sfx: tSoundEffect;
  s: tMemoryStream;
  ss,mm: word;
begin

  if extractExtension(srcPath).toLower() <> 'wav' then
    fatal(format('Source file should be .wav file, but was %s', [srcPath]));

  dstPath := 'res\'+filename+'.a96';

  if preProcess(dstPath, srcPath) then begin
    sfx := tSoundEffect.Load(srcPath);
    ss := (sfx.length div 44100) mod 60;
    mm := (sfx.length div 44100 div 60) mod 60;
    s := encodeLA96(sfx, ACP_HIGH);
    s.writeToFile(dstPath);
    s.free;
    sfx.free;
    outputLn(format('[%s:%s]',[intToStr(mm, 2), intToStr(ss, 2)]), Green);
    postProcess(dstPath, srcPath);
  end;
end;


{-----------------------------------------------}
{ These just make life a bit simpler }
{-----------------------------------------------}

{e.g. copyFile('fonts\font.fnt')}
procedure copyFile(filePath: string); overload;
begin
  copyFile(extractFilename(filePath), joinPath(MASTER_FOLDER, filePath));
end;

{e.g. convert('music.wav')}
procedure convertAudio(filename: string); overload;
begin
  convertAudio(removeExtension(filename), joinPath(MASTER_FOLDER, 'airtime', filename));
end;

{e.g. convert('title.bmp')}
procedure convertImage(filename: string;processProc: tProcessProc=nil); overload;
begin
  convertImage(removeExtension(filename), joinPath(MASTER_FOLDER, 'airtime', filename), processProc);
end;

{-------------------------------------------------------}

function mapTerrainColors(page: tPage): tPage;
var
  x,y: int32;
  col: RGBA;

  {sets each RGB to 0, 128, or 255 (rounded to nearest)}
  function quantise(x: integer): integer;
  begin
    exit(round(2*x / 256)*128);
  end;

begin
  for y := 0 to page.height-1 do
    for x := 0 to page.width-1 do begin
      col := page.getPixel(x,y);
      col.init(quantise(col.r), quantise(col.g), quantise(col.b), quantise(col.a));
      page.setPixel(x, y, col);
    end;
  exit(page);
end;

procedure processAll();
begin

  {game stuff}
  convertImage('title.bmp');
  convertImage('track1.png');
  convertImage('track2.png');
  convertImage('track2h.bmp');
  convertImage('track2t.bmp', mapTerrainColors);
  convertImage('carRed.png');
  convertImage('carPol.png');
  convertImage('carBox.png');
  convertImage('wheel.png');

  {christmas variation}
  convertImage('titleX.bmp');
  convertImage('carSan.png');

  convertImage('button', joinPath(MASTER_FOLDER, 'gui', 'EC_Button_Pressed.png'));

  {gui stuff}
  convertImage('ec_frame',joinPath(MASTER_FOLDER, 'gui',    'ec_frame.bmp'));
  convertImage('panel',   joinPath(MASTER_FOLDER, 'gui',    'panel.bmp'));
  convertImage('font',    joinPath(MASTER_FOLDER, 'fonts',  'font.bmp'));

  {sound stuff}
  convertAudio('engine2.wav');
  convertAudio('skid.wav');
  convertAudio('slaybells.wav');
  convertAudio('start.wav');
  convertAudio('land.wav');
  convertAudio('boost.wav');
  convertAudio('bell.wav');
  convertAudio('music1.wav');
  convertAudio('music2.wav');

  {other stuff}
  copyFile(joinPath('fonts', 'font.fnt'));
end;

{-------------------------------------------}

begin
  textAttr := LightGray;
  clrscr;
  {make sure everything is ok}
  runTestSuites();
  assert(fs.folderExists('res'), 'We were expecting a "res" folder, but could not find it. Are you in the right path?');
  assert(fs.folderExists(MASTER_FOLDER), format('Could not open masters folder "%s"', [MASTER_FOLDER]));
  assert(fs.folderExists(joinPath(MASTER_FOLDER, 'airtime')), format('Could not open "%s"', [joinPath(MASTER_FOLDER, 'airtime')]));

  resourceLibrary := tResourceLibrary.CreateOrLoad('resources.ini');
  processAll();
  resourceLibrary.serialize('resources.ini');
  writeln('------------------');
  writeln('Done.');
  delay(2000);
end.
