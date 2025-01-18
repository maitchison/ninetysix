{read master files and process / compress}
program import;

{$MODE delphi}

uses
  utils,
  test,
  debug,
  graph32,
  filesystem,
  crt,
  sysPNG,
  lc96;

const
  MASTER_FOLDER = 'c:\dev\masters';

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
  img: tPage;
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

procedure copyFile(filename: string; srcPath:string); overload;
var
  dstPath: string;
begin
  {only copy if needed.}
  textAttr := LightGray;
  write(pad(extractFilename(filename),14, ' '));

  dstPath := joinPath('res', filename);

  if not fs.exists(dstPath) or fs.wasModified(srcPath, dstPath) then begin
    fs.copyFile(srcPath, dstPath);
    textAttr := LightRed;
    writeln('[copied]');
    textAttr := LightGray;
  end else begin
    textAttr := Green;
    writeln('[skip]');
    textAttr := LightGray;
  end;
end;


{e.g. copyFile('fonts\font.fnt')}
procedure copyFile(filePath: string); overload;
begin
  copyFile(extractFilename(filePath), joinPath(MASTER_FOLDER, filePath));
end;


{e.g. convert('title', 'c:\dev\masters\airtime\title.bmp')}
procedure convertImage(filename: string;srcPath:string;processProc: tProcessProc=nil); overload;
var
  res: tResource;
  id: int32;
  dstPath: string;
begin

  dstPath := 'res\'+filename+'.p96';

  textAttr := LightGray;
  write(pad(filename,14, ' '));

  {make sure it exists}
  if not fs.exists(srcPath) then begin
    //stub
    writeln();
    writeln(srcPath);
    textAttr := LightRed;
    writeln('[missing]');
    textAttr := LightGray;
    exit;
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
      textAttr := Green;
      writeln('[skip]');
      textAttr := LightGray;
      exit;
    end;
  end;

  with res do begin
    srcFile := srcPath;
    dstFile := dstPath;
    modifiedTime := fs.getModified(srcFile);
    img := tPage.Load(srcFile);
    if assigned(processProc) then
      img := processProc(img);
    saveLC96(dstFile, img);
    textAttr := LightGreen;
    writeln(format('[%dx%d]',[img.width, img.height]));
    textAttr := LightGray;
  end;

  resourceLibrary.updateResource(res);
  resourceLibrary.serialize('resources.ini');
end;


{e.g. convert('title.bmp')}
procedure convertImage(filename: string;processProc: tProcessProc=nil); overload;
begin
  convertImage(removeExtension(filename), joinPath(MASTER_FOLDER, 'airtime', filename), processProc);
end;

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

  {todo:...}
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
