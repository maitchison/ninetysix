{stores HDR 16-bit mono-chromatic buffers}
unit hdr;

{
HDR buffer maps from 16bit integers (0..65535) to RGB values, where
typically the brigness is proportional to sqrt(value). I.e. closer to
linear space than to gamma space.
}

interface

uses
  graph32,
  utils;

type
  tHDRPage = class
  private
    data: pWord;
    width,height: integer;
  public
    constructor create(aWidth, aHeight: integer);
    destructor destroy(); override;
    function  getRGB(x, y: int16): RGBA;
    procedure setPixel(x, y: int16;value: word);
    procedure addPixel(x, y: int16;value: integer);
    procedure blitTo(page: tPage;atX, atY: int16);
    procedure fade();
  end;

implementation

var
  LUT: array[0..4096-1] of RGBA;

constructor tHDRPage.create(aWidth, aHeight: integer);
begin
  inherited create();
  self.width := width;
  self.height := height;
  data := getMem(width*height*2);
end;

destructor tHDRPage.destroy();
begin
  freemem(data);
  inherited destroy();
end;

procedure tHDRPage.setPixel(x, y: int16;value: word);
begin
  if (word(x) >= width) or (word(y) >= height) then exit;
  data[x+y*width] := value;
end;

function tHDRPage.getRGB(x, y: int16): RGBA;
var
  value: word;
begin
  if (word(x) >= width) or (word(y) >= height) then exit;
  result := LUT[data[x+y*width] shr 16];
end;

procedure tHDRPage.addPixel(x, y: int16;value: integer);
var
  ofs: integer;
begin
  if (word(x) >= width) or (word(y) >= height) then exit;
  ofs := x+y*width;
  data[ofs] := clamp(data[ofs]+value, 0, 65535);
end;

procedure tHDRPage.blitTo(page: tPage;atX, atY: int16);
var
  x, y: integer;
begin
  for y := 0 to height-1 do
    for x := 0 to width-1 do
      page.putPixel(x+atX, y+atY, getRGB(x, y));
end;

{reduce intensity of page}
procedure tHDRPage.fade();
var
  ofs: integer;
begin
  for ofs := 0 to (width*height)-1 do
    data[ofs] := data[ofs] shr 1;
end;

var
  i: integer;
  v: single;

begin
  for i := 0 to 4096-1 do begin
    v := sqrt(i/4096);
    LUT[i].init(round(v), round(v*2), round(v*1.5));
  end;
end.