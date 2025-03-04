{handle bitmap based font rendering}
unit font;

interface

uses
  debug,
  graph2d,
  graph32,
  utils,
  lc96;

type

  tChar = record
    {todo support custom kerning}
    id: byte;
    rect: tRect;
    xoffset, yoffset: integer;
    xadvance: integer;
  end;


  tFont = class
    bitmap: tPage;
    chars: array[0..255] of tChar;
    {a bit wasteful... but I'll just take the hit}
    {note: this means fonts should be passed by reference}
    {todo: put this and chars both on the heep}
    kerning: array[0..255, 0..255] of shortint;
  protected
    function charOut(Page: tPage;atX, atY: integer;c: char;col: RGBA; prevC: char): integer;
  public
    constructor create();
    class function Load(filename: string): tFont; static;

    procedure textOut(page: tPage; atX, atY: integer; s: string;col: RGBA);
    function textExtents(s: string; p: tPoint): tRect; overload;
    function textExtents(s: string): tRect; overload;

  end;

var
  DEFAULT_FONT: tFont;

implementation

uses
  filesystem, bmp;

{---------------------------------------------------------}

function ReadAttribute(line, attributeName: string): integer;
var
  attributePos: integer;
  attributeStr: string;

begin
  attributePos := Pos(attributeName+'=', Line);
  attributeStr := Copy(Line, attributePos + length(attributeName)+1, 3);
  result := StrToInt(Trim(attributeStr));
end;


function ParseCharLine(line: string): TChar;
begin
  result.id := 0;
  result.id := readAttribute(line, 'id');
  result.rect.x := readAttribute(line, 'x');
  result.rect.y := readAttribute(line, 'y');
  result.rect.width := readAttribute(line, 'width');
  result.rect.height := readAttribute(line, 'height');
  result.xoffset := readAttribute(line, 'xoffset');
  result.yoffset := readAttribute(line, 'yoffset');
  result.xadvance := readAttribute(line, 'xadvance');
end;

procedure drawSubImage(page: tPage; atX, atY: integer; image: TPage; rect:TRect; col: RGBA);
var
  x,y: integer;
  texel,blended: RGBA;
begin
  {todo: switch to sprites and use the sprite draw}
  blended := col;
  for y := 0 to rect.height-1 do
    for x := 0 to rect.width-1 do begin
      texel := image.getPixel(x+rect.x, y+rect.y);
      if texel.a = 0 then continue;
      {add bias as we're dividing by 256 instead of 255}
      blended.a := (255 + word(texel.a) * col.a) div 256;
      page.putPixel(x+atX, y+atY, blended);
    end;
end;

{-----------------------------------------------------}

constructor tFont.create();
begin
  inherited create();
  bitmap := nil;
  fillchar(chars, sizeof(chars), 0);
  fillchar(kerning, sizeof(kerning), 0);
end;

class function tFont.Load(filename: string): tFont;
var
  TextFile: Text;
  Line: String;
  Char: TChar;
  a,b: integer;
  x,y: integer;
  bitmap: tPage;
  c: RGBA;
begin

  result := tFont.Create();

  if fs.exists(filename+'.p96') then
    bitmap := LoadLC96(filename+'.p96')
  else if fs.exists(filename+'.bmp') then
    bitmap := LoadBMP(filename+'.bmp')
  else
    fatal('File not found "'+filename+'.[p96|bmp]"');

  {need to convert from format to new alpha format}
  for y := 0 to bitmap.height-1 do
    for x := 0 to bitmap.width-1 do begin
      c := bitmap.getPixel(x,y);
      bitmap.setPixel(x,y,RGB(255,255,255,c.r));
    end;

  result.bitmap := bitmap;

  {$I-}
  Assign(TextFile, filename+'.fnt');
  Reset(TextFile);
  {$I+}

  if IOResult <> 0 then
    fatal('Error loading '+filename+'.fnt');

  while not Eof(TextFile) do begin
    ReadLn(TextFile, Line);
    if Pos('char id=', Line) > 0 then begin
       char := ParseCharLine(Line);
      result.chars[char.id] := char;
    end;
    if Pos('kerning first=', Line) > 0 then begin
      a := readAttribute(line, 'first');
      b := readAttribute(line, 'second');
      result.kerning[a,b] := readAttribute(line, 'amount');
    end;
  end;
end;

function tFont.charOut(Page: tPage;atX, atY: integer;c: char;col: RGBA; prevC: char): integer;
var
  char: tChar;
begin

  atX += kerning[ord(prevc), ord(c)];

  char := chars[ord(c)];
  drawSubImage(page, atX+char.xoffset, atY+char.yoffset, bitmap, char.rect, col);
  atX += char.xadvance;
  result := atX;
end;

procedure tFont.textOut(page: tPage; atX, atY: integer; s: string;col: RGBA);
var
  i: integer;
  prevChar: char;
begin
  if not assigned(self) then exit;
  prevChar := #0;
  for i := 1 to length(s) do begin
    atX := charOut(page, atX, atY, s[i], col, prevChar);
    prevChar := s[i];
  end;
end;

function tFont.textExtents(s: string; p: tPoint): tRect;
var
  i: integer;
  c: TChar;
begin
  if not assigned(self) then exit(Rect(0,0));
  {note: note quite right for characters that have offsets?}
  result.x := p.x;
  result.y := p.y;
  result.width := 0;
  result.height := 16;
  for i := 1 to length(s) do begin
    result.width += chars[ord(s[i])].xadvance;
    if i > 1 then
      result.width += kerning[ord(s[i-1]), ord(s[i])];
  end;
end;

function tFont.textExtents(s: string): tRect;
begin
  if not assigned(self) then exit(Rect(0,0));
  result := textExtents(s, point(0,0));
end;

{-----------------------------------------------------}

begin
  DEFAULT_FONT := tFont.Load('res\font');
end.
