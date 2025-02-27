{read netFonts from destruct}
unit netFont;

interface

uses
  debug,
  test,
  font,
  sprite,
  graph2d,
  graph32;

function loadNetFont(filename: string): tFont;

implementation

{read in font from a p96 file}
function loadNetFont(filename: string): tFont;
var
  page: tPage;
  font: tFont;
  b: RGBA;

  {returns bounds for char with (x,y) at topleft corner}
  function readChar(x,y: integer): tRect;
  begin
    result.init(x,y,0,0);
    {not a valid char}
    if page.getPixel(x-1,y-1) <> b then exit;
    while page.getPixel(x+result.width,y+result.height) <> b do
      inc(result.width);
    while page.getPixel(x+result.width,y+result.height) <> b do
      inc(result.height);
  end;

  procedure readLine(cIdx: integer; y: integer);
  var
    c, b: RGBA;
    x: integer;
    cRect: tRect;
  begin
    x := 0;
    b := page.getPixel(x, y);
    inc(y);
    while cIdx < 256 do begin
      cRect := readChar(x,y);
      if (cRect.width = 0) then exit;
      font.chars[cIdx].rect := cRect;
      x += cRect.width -1;
      inc(cIdx);
    end;
  end;

begin
  page := tPage.Load(filename);
  font := tFont.create();
  result := font;
  font.bitmap := page;
  readLine(ord(' '), 0);
end;

begin
end.