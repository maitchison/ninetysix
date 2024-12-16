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

  TChar = object
    {todo support custom kerning}
    id: byte;
    rect: TRect;
    xoffset, yoffset: integer;
    xadvance: integer;
  end;


  tFont = object
    bitmap: tPage;
    chars: array[0..255] of tChar;
    {a bit wasteful... but I'll just take the hit}
    {note: this means fonts should be passed by reference}
    {todo: put this and chars both on the heep}
    kerning: array[0..255, 0..255] of shortint;
  end;

procedure textOut(page: TPage; atX, atY: integer; s: string;col: RGBA);
function textExtents(s: string): TRect;

implementation

var
  font1: TFont;

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

function LoadFont(filename: string): TFont;
var
  TextFile: Text;
  Line: String;
   Char: TChar;
  a,b: integer;

begin
  fillchar(result.chars, sizeof(result.chars), 0);
  fillchar(result.kerning, sizeof(result.kerning), 0);
  result.bitmap := LoadLC96(filename+'.p96');
  {$I-}
  Assign(TextFile, filename+'.fnt');
  Reset(TextFile);
  {$I+}

  if IOResult <> 0 then
    error('Error loading '+filename+'.fnt');

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

procedure drawSubImage(page: TPage; atX, atY: integer; image: TPage; rect:TRect; col: RGBA);
var
  x,y: integer;
  c,putcol: RGBA;
begin
  {todo: switch to sprites and use the sprite draw}
  putcol := col;
  for y := 0 to rect.height-1 do
    for x := 0 to rect.width-1 do begin
      c := image.getPixel(x+rect.x, y+rect.y);
      {todo: load font with correct alpha channel}
      {for the moment map r channel to alpha}
      if c.a < 2 then continue;
      putcol.a := (integer(c.r) * col.a div 255);
      page.putPixel(x+atX, y+atY, putcol);
    end;
end;


function charOut(Page: TPage;atX, atY: integer;c: char;col: RGBA; prevC: char): integer;
var
  char: TChar;
  kerning: integer;
begin

  {apply kerning}
  kerning := font1.kerning[ord(prevc), ord(c)];
  atX += kerning;

  char := font1.chars[ord(c)];
  drawSubImage(Page, atX+char.xoffset, atY+char.yoffset, font1.bitmap, char.rect, col);
  atX += char.xadvance;
  result := atX;
end;

procedure textOut(page: TPage; atX, atY: integer; s: string;col: RGBA);
var
  i: integer;
  prevChar: char;
begin
  prevChar := #0;
  for i := 1 to length(s) do begin
    atX := charOut(page, atX, atY, s[i], col, prevChar);
    prevChar := s[i];
  end;
end;

function TextExtents(s: string): TRect;
var
  i: integer;
  c: TChar;
begin
  {note: note quite right for characters that have offsets?}
  result.x := 0;
  result.y := 0;
  result.width := 0;
  result.height := 16;
  for i := 1 to length(s) do begin
    result.width += font1.chars[ord(s[i])].xadvance;
    if i > 1 then
      result.width += font1.kerning[ord(s[i-1]), ord(s[i])];
  end;
end;


begin
  Info('[init] Font');
  font1 := LoadFont('res/font');
end.
