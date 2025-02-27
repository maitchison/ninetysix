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
    constructor create();

    {todo: move draw commands in here}

  end;

procedure textOut(page: tPage; atX, atY: integer; s: string;col: RGBA);
function textExtents(s: string; p: tPoint): tRect; overload;
function textExtents(s: string): tRect; overload;

{temp}
procedure textOutHalf(page: tPage; atX, atY: integer; s: string;col: RGBA);
function textExtentsHalf(s: string; p: tPoint): tRect; overload;
function textExtentsHalf(s: string): tRect; overload;

implementation

uses
  filesystem, bmp;

var
  font1: tFont;

{---------------------------------------------------------}

constructor tFont.create();
begin
  inherited create();
  bitmap := nil;
  fillchar(chars, sizeof(chars), 0);
  fillchar(kerning, sizeof(kerning), 0);
end;

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

function LoadFont(filename: string): tFont;
var
  TextFile: Text;
  Line: String;
   Char: TChar;
  a,b: integer;

begin

  result := tFont.create();

  if fs.exists(filename+'.p96') then
    result.bitmap := LoadLC96(filename+'.p96')
  else if fs.exists(filename+'.bmp') then
    result.bitmap := LoadBMP(filename+'.bmp')
  else
    fatal('File not found "'+filename+'.[p96|bmp]"');

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

procedure drawSubImage(page: tPage; atX, atY: integer; image: TPage; rect:TRect; col: RGBA);
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

function charOut(Page: tPage;atX, atY: integer;c: char;col: RGBA; prevC: char): integer;
var
  char: TChar;
  kerning: integer;
begin

  {apply kerning}
  kerning := font1.kerning[ord(prevc), ord(c)];
  atX += kerning;

  char := font1.chars[ord(c)];
  drawSubImage(page, atX+char.xoffset, atY+char.yoffset, font1.bitmap, char.rect, col);
  atX += char.xadvance;
  result := atX;
end;

procedure textOut(page: tPage; atX, atY: integer; s: string;col: RGBA);
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

function textExtents(s: string; p: tPoint): tRect;
var
  i: integer;
  c: TChar;
begin
  {note: note quite right for characters that have offsets?}
  result.x := p.x;
  result.y := p.y;
  result.width := 0;
  result.height := 16;
  for i := 1 to length(s) do begin
    result.width += font1.chars[ord(s[i])].xadvance;
    if i > 1 then
      result.width += font1.kerning[ord(s[i-1]), ord(s[i])];
  end;
end;

function textExtents(s: string): tRect;
begin
  result := textExtents(s, point(0,0));
end;

{-----------------------------------------------------}
{ half font: temp until we get proper font support}
{-----------------------------------------------------}

procedure drawSubImageHalf(page: tPage; atX, atY: integer; image: TPage; rect:TRect; col: RGBA);
var
  x,y: integer;
  z: integer;
  c,putcol: RGBA;
  v: integer;
  i,j: integer;
begin
  {todo: switch to sprites and use the sprite draw}
  putcol := col;
  for y := 0 to ((rect.height+1) div 2)-1 do begin
    for x := 0 to ((rect.width+1) div 2)-1 do begin
      v := 0;
      for i := 0 to 1 do begin
        for j := 0 to 1 do begin
          z := image.getPixel((x*2)+i+rect.x, (y*2)+j+rect.y).r;
          v += z*z;
        end;
      end;
      {something a bit like gamma correction}
      v := round(sqrt(v/4));
      {todo: load font with correct alpha channel}
      {for the moment map r channel to alpha}
      if v < 2 then continue;
      putcol.a := (v * col.a div 255);
      page.putPixel(x+atX, y+atY, putcol);
    end;
  end;
end;


function charOutHalf(Page: tPage;atX, atY: integer;c: char;col: RGBA; prevC: char): integer;
var
  char: TChar;
  kerning: integer;
  r: tRect;
begin

  {apply kerning}
  kerning := font1.kerning[ord(prevc), ord(c)];
  atX += kerning div 2;

  char := font1.chars[ord(c)];
  drawSubImageHalf(page, atX+(char.xoffset+1) div 2, atY+(char.yoffset+1) div 2, font1.bitmap, char.rect, col);
  atX += (char.xadvance+1) div 2;
  result := atX;
end;

procedure textOutHalf(page: tPage; atX, atY: integer; s: string;col: RGBA);
var
  i: integer;
  prevChar: char;
begin
  prevChar := #0;
  for i := 1 to length(s) do begin
    atX := charOutHalf(page, atX, atY, s[i], col, prevChar);
    prevChar := s[i];
  end;
end;

function textExtentsHalf(s: string; p: tPoint): tRect;
var
  i: integer;
  c: TChar;
begin
  {note: note quite right for characters that have offsets?}
  result.x := p.x;
  result.y := p.y;
  result.width := 0;
  result.height := 16 div 2;
  for i := 1 to length(s) do begin
    result.width += (font1.chars[ord(s[i])].xadvance+1) div 2;
    if i > 1 then
      result.width += (font1.kerning[ord(s[i-1]), ord(s[i])]+1) div 2;
  end;
end;

function textExtentsHalf(s: string): tRect;
begin
  result := textExtentsHalf(s, point(0,0));
end;

{-----------------------------------------------------}

begin
  Info('[init] Font');
  font1 := LoadFont('res/font');
end.
