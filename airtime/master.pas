{read master files and process / compress}
program import;

{$MODE delphi}

uses
  utils,
  test,
  debug,
  graph32,
  crt,
  dos,
  sysPNG,
  lc96;

var
  img: tPage;

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
  if exists(fileName) then
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

type
  // apply some changes to a page, and output a new page
  tProcessProc = function(input: tPage): tPage;

var
  resourceLibrary: tResourceLibrary;

const
  DEFAULT_SRC_FOLDER = 'd:\masters\airtime\';

{e.g. convert('title', 'c:\masters\airtime\title.bmp')}
procedure convertImage(filename: string;srcPath:string;processProc: tProcessProc=nil); overload;
var
  res: tResource;
  id: int32;
  dstPath: string;
begin

  dstPath := 'res\'+filename+'.p96';

  textAttr := $07;
  write(pad(filename,14, ' '));

  {make sure it exists}
  if not exists(srcPath) then begin
    textAttr := $0C;
    writeln('[missing]');
    textAttr := $07;
    exit;
  end;

  {check if this is already done}
  id := resourceLibrary.findResourceIndex(dstPath);
  if id >= 0 then begin
    res := resourceLibrary.resource[id];
    if
      (res.srcFile = srcPath) and
      (res.modifiedTime = fileModifiedTime(res.srcFile)) and
      exists(dstPath)
    then begin
      textAttr := $02;
      writeln('[skip]');
      textAttr := $07;
      exit;
    end;
  end;

  with res do begin
    srcFile := srcPath;
    dstFile := dstPath;
    modifiedTime := fileModifiedTime(srcFile);
    img := tPage.Load(srcFile);
    if assigned(processProc) then
      img := processProc(img);
    saveLC96(dstFile, img);
    textAttr := $0A;
    writeln(format('[%dx%d]',[img.width, img.height]));
    textAttr := $07;
  end;

  resourceLibrary.updateResource(res);
  resourceLibrary.serialize('resources.ini');
end;


{e.g. convert('title.bmp')}
procedure convertImage(filename: string;processProc: tProcessProc=nil); overload;
begin
  convertImage(removeExtension(filename), 'c:\masters\airtime\'+filename, processProc);
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
  convertImage('carSanta.png');


  convertImage('button', 'c:\masters\gui\EC_Button_Pressed.png');
  {gui stuff}
//  convertBMP('ec_frame', 'c:\masters\gui\ec_frame.bmp');
//  convertBMP('panel', 'c:\masters\gui\panel.bmp');
//  convertBMP('font', 'c:\masters\font\font.bmp');
end;

{-------------------------------------------}

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
  runTests();
  resourceLibrary := tResourceLibrary.CreateOrLoad('resources.ini');
  processAll();
  resourceLibrary.serialize('resources.ini');
  writeln('done.');
end.
