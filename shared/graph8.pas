{8bit template support}
unit graph8;

uses
  test,
  debug,
  resource,
  uColor,
  utils;


interface

type
  {page stored as 8bit lumance}
  tPage8 = class(tResource)
    width, height: word;
    pixels: pointer;
    constructor Create(); overload;
    destructor  destroy(); override;
    constructor create(aWidth, aHeight: word); overload;
    function    getAddress(x, y: integer): pointer; inline;
    procedure   putValue(x, y: integer;v: byte);
    function    getValue(x, y: integer): byte;
    class function Load(filename: string): tPage8;
  end;

implementation

constructor tPage8.create();
begin
  inherited create();
  self.width := 0;
  self.height := 0;
  self.pixels := nil;
end;

destructor tPage8.destroy();
begin
  if assigned(self.pixels) then begin
    freeMem(self.pixels);
    self.pixels := nil;
  end;
  inherited destroy();
end;

constructor tPage8.create(aWidth, aHeight: word);
begin
  create();
  self.width := aWidth;
  self.height := aHeight;
  self.pixels := getMem(aWidth * aHeight);
  fillchar(self.pixels^, aWidth * aHeight, 0);
end;

procedure tPage8.putValue(x, y: integer;v: byte);
begin
  if dword(x) >= width then exit;
  if dword(y) >= height then exit;
  pByte(pixels + (x+y*width))^ := v;
end;

function tPage8.getValue(x, y: integer): byte;
begin
  if dword(x) >= width then exit(0);
  if dword(y) >= height then exit(0);
  result := pByte(pixels + (x+y*width))^;
end;

{returns address in memory of given pixel. If out of bounds, returns nil}
function tPage8.getAddress(x, y: integer): pointer; inline;
begin
  if (dword(x) >= self.width) or (dword(y) >= self.height) then exit(nil);
  result := pixels + (y * width + x);
end;

class function tPage8.Load(filename: string): tPage8;
var
  page: tPage;
  x,y: integer;
begin
  page := tPage.load(filename);
  result := tPage8.create(page.width, page.height);
  for y := 0 to page.height-1 do
    for x := 0 to page.width-1 do
      result.putValue(x, y, page.getPixel(x,y).lumance);
  page.free();
end;

{-------------------------------------------------}

type
  tGraph8Test = class(tTestSuite)
    procedure run; override;
  end;

procedure tGraph8Test.run();
var
  a,b: RGBA;
  page8: tPage8;
begin
  {test RGBA}
  a.init(0, 64, 128);
  b.from16(a.to16);
  assertEqual(a,b);
  {test page 8}
  {just make sure we can allocate and deallocate}
  page8 := tPage8.create(16,16);
  page8.destroy();
end;

{--------------------------------------------------------}

initialization
  tGraph8Test.create('Graph8');
end.
