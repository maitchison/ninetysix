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
  sound,
  crt,
  sysPNG,
  la96,
  lc96;

const
  MASTER_FOLDER = 'c:\dev\masters';
  VERBOSE: boolean = true;

{-----------------------------------------------}

type

  tResource = record
    srcFile: string;
    dstFile: string;
    modifiedTime: int64;
  end;

  tResourceLibrary = class

    numResources: word;

    resource: array[0..63] of tResource;

    procedure addResource(res: tResource);

    constructor Create(); overload;
    constructor Create(filename: string); overload;
    constructor CreateOrLoad(filename: string); overload;
    destructor Destroy;



    procedure serialize(fileName: string);
    procedure deserialize(fileName: string);

    function findResourceIndex(dstFile: string): integer;
    procedure updateResource(res: tResource);

  end;

type
  // apply some changes to a page, and output a new page
  tProcessProc = function(input: tPage): tPage;

var
  resourceLibrary: tResourceLibrary;

{-----------------------------------------------}

constructor tResourceLibrary.Create(); overload;
begin
  inherited Create();
  numResources := 0;
  fillchar(resource, sizeOf(resource), 0);
end;

constructor tResourceLibrary.Create(fileName: string); overload;
begin
  Create();
  deserialize(fileName);
end;

constructor tResourceLibrary.CreateOrLoad(fileName: string);
begin
  if fs.exists(fileName) then
    Create(fileName)
  else
    Create();
end;

destructor tResourceLibrary.Destroy();
begin
  inherited Destroy();
end;

procedure tResourceLibrary.addResource(res: tResource);
begin
  if numResources = length(resource) then
    error('Too many resources, limit is '+intToStr(length(resource)));
  resource[numResources] := res;
  inc(numResources);
end;

{returns index of resource, or -1 of not found}
function tResourceLibrary.findResourceIndex(dstFile: string): integer;
var
  i: int32;
begin
  for i := 0 to numResources-1 do
    if resource[i].dstFile = dstFile then exit(i);
  exit(-1);
end;

{updates or adds resource}
procedure tResourceLibrary.updateResource(res: tResource);
var
  id: int32;
begin
  id := findResourceIndex(res.dstFile);
  if id < 0 then
    addResource(res)
  else
    resource[id] := res;
end;

procedure tResourceLibrary.serialize(fileName: string);
var
  t: text;
  ioError: word;
  res: tResource;
  i: integer;
begin
  assign(t, filename);
  {$I-}
  rewrite(t);
  {$I+}
  ioError := ioResult;
  if ioError <> 0 then error('Error writing '+fileName+' (error:'+intToStr(ioError)+')');

  {todo: update to new inifile unit}
  try
    for i := 0 to numResources-1 do begin
      res := resource[i];
      writeln(t, '[resource]');
      writeln(t, 'srcFile=',res.srcFile);
      writeln(t, 'dstFile=',res.dstFile);
      writeln(t, 'modifiedTime=',res.modifiedTime);
      writeln(t);
    end;
  finally
    close(t);
  end;

end;

procedure tResourceLibrary.deserialize(fileName: string);
var
  t: text;
  s,k,v: string;
  ioError: word;
  res: tResource;
begin
  assign(t, filename);
  {$I-}
  reset(t);
  {$I+}
  ioError := ioResult;
  if ioError <> 0 then error('Error reading '+fileName+' (error:'+intToStr(ioError)+')');

  try

    numResources := 0;

    while not eof(t) do begin
      readln(t, s);
      s := trim(s);
      if s = '[resource]' then begin
        if numResources > 0 then
          resource[numResources-1] := res;
        fillchar(res, sizeof(res), 0);
        inc(numResources);
        continue;
      end;
      split(s, '=', k, v);
      if k = 'srcFile' then begin
        res.srcFile := v;
      end else if k = 'dstFile' then begin
        res.dstFile := v;
      end else if k = 'modifiedTime' then begin
        res.modifiedTime := strToInt(v);
      end else begin
        {ignore all others}
      end;
    end;

    {write final}
    if numResources > 0 then
      resource[numResources-1] := res;

  finally
    close(t);
  end;

end;

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
  if not fs.exists(srcPath) then begin
    outputLn('[missing]', LightRed);
    exit(false);
  end;

  {check if this is already done}
  id := resourceLibrary.findResourceIndex(dstPath);
  if id >= 0 then begin
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
  s: tStream;
  ss,mm: word;
begin

  if extractExtension(srcPath).toLower() <> 'wav' then
    error(format('Source file should be .wav file, but was %s', [srcPath]));

  dstPath := 'res\'+filename+'.a96';

  if preProcess(dstPath, srcPath) then begin
    sfx := tSoundEffect.loadFromWave(srcPath);
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
  convertAudio('loop_0.wav');
  //convertAudio('skid.wav');
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

{todo: declare this as a test suite}
procedure runTests();
var
  rl: tResourceLibrary;
  res: tResource;
begin
  rl := tResourceLibrary.Create();

  res.srcFile := 'a';
  res.dstFile := 'b';
  res.modifiedTime := 123;
  rl.addResource(res);
  res.srcFile := 'x';
  res.dstFile := 'y';
  res.modifiedTime := 321;
  rl.addResource(res);
  rl.serialize('_test.ini');
  rl.Destroy;

  rl := tResourceLibrary.Create('_test.ini');
  assertEqual(rl.numResources, 2);
  res := rl.resource[0];
  assertEqual(res.srcFile, 'a');
  assertEqual(res.dstFile, 'b');
  assertEqual(res.modifiedTime, 123);
  assertEqual(rl.findResourceIndex('b'), 0);
  assertEqual(rl.findResourceIndex('c'), -1);

  rl.Destroy;

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

  runTests();
  resourceLibrary := tResourceLibrary.CreateOrLoad('resources.ini');
  processAll();
  resourceLibrary.serialize('resources.ini');
  writeln('------------------');
  writeln('Done.');
  delay(2000);
end.
