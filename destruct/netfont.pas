{read netFonts from destruct}
unit netFont;

interface

uses
  debug,
  test,
  font,
  utils,
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
    if page.getPixel(x,y-1) <> b then exit;
    while (x < page.width) and (page.getPixel(x+1,y) <> b) do inc(x);
    while (y < page.height) and (page.getPixel(x,y+1) <> b) do inc(y);
    result.bottomRight := Point(x+1,y+1);
  end;

  procedure readLine(cIdx: integer; x,y: integer);
  var
    c: RGBA;
    cRect: tRect;
    xlp,ylp: integer;
    charHeight: integer;
  begin
    charHeight := 0;
    while cIdx < 256 do begin
      cRect := readChar(x,y);
      //note('Read char %s as %s', [chr(cIdx), cRect.toString]);
      if (cRect.width = 0) then break;
      if (cRect.width > 32) or (cRect.height > 32) then break;
      font.chars[cIdx].rect := cRect;
      font.chars[cIdx].xAdvance := cRect.width;
      charHeight := cRect.height;
      x += cRect.width+1;
      inc(cIdx);
    end;
    {apply conversion}
    for ylp := y to y + charHeight do begin
      for xlp := 0 to x do begin
        c := page.getPixel(xlp,ylp);
        c.a := max(c.r, c.g, c.b);
        c.r := 255;
        c.g := 255;
        c.b := 255;
        page.setPixel(xlp,ylp,c);
      end;
    end;

  end;

begin
  page := tPage.Load(filename);
  font := tFont.create();
  result := font;
  font.bitmap := page;
  b := page.getPixel(0, 0);
  readLine(ord(' '), 1, 1);
  readLine(ord('@'), 1, 8);
  readLine(ord('a'), 1, 15);
end;

begin
end.
