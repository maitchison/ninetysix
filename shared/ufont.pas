{handle bitmap based font rendering}
unit uFont;

interface

uses
  uDebug,
  uColor,
  uRect,
  uGraph32,
  uUtils,
  uList,
  uP96;

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
    fHeight: integer; {typical height of font}
  protected
    function  charOut(const dc: tDrawContext;atX, atY: integer;c: char;col: RGBA; prevC: char): integer;
  public
    constructor Create();
    class function Load(filename: string): tFont; static;

    function  textOut(const dc: tDrawContext; atX, atY: integer; s: string;col: RGBA): tRect;
    function  textExtents(s: string; p: tPoint): tRect; overload;
    function  textExtents(s: string): tRect; overload;
    property  height: integer read fHeight;

  end;

var
  DEFAULT_FONT: tFont;

implementation

uses
  uFileSystem,
  uBmp;

{---------------------------------------------------------}

function readAttribute(line, attributeName: string): integer;
var
  attributePos: integer;
  attributeStr: string;

begin
  attributePos := Pos(attributeName+'=', Line);
  attributeStr := Copy(Line, attributePos + length(attributeName)+1, 3);
  result := StrToInt(Trim(attributeStr));
end;


function parseCharLine(line: string): TChar;
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

{todo: remove and use standard sprite drawing}
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

constructor tFont.Create();
begin
  inherited create();
  bitmap := nil;
  fillchar(chars, sizeof(chars), 0);
  fillchar(kerning, sizeof(kerning), 0);
  fHeight := -1;
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

  if fileSystem.exists(filename+'.p96') then
    bitmap := LoadLC96(filename+'.p96')
  else if fileSystem.exists(filename+'.bmp') then
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
    readLn(TextFile, Line);
    if Pos('char id=', Line) > 0 then begin
       char := parseCharLine(Line);
      result.chars[char.id] := char;
    end;
    if Pos('kerning first=', Line) > 0 then begin
      a := readAttribute(line, 'first');
      b := readAttribute(line, 'second');
      result.kerning[a,b] := readAttribute(line, 'amount');
    end;
  end;

  result.fHeight := result.chars[ord('I')].rect.height;
end;

function tFont.charOut(const dc: tDrawContext;atX, atY: integer;c: char;col: RGBA; prevC: char): integer;
var
  char: tChar;
begin
  atX += kerning[ord(prevc), ord(c)];
  char := chars[ord(c)];
  if not dc.isNull then
    dc.asTint(col).drawSubImage(bitmap, Point(atX+char.xoffset, atY+char.yoffset), char.rect);
  atX += char.xadvance;
  result := atX;
end;

{output text, return bounds rect. If DC is null then does not draw but still returns extents}
function tFont.textOut(const dc: tDrawContext; atX, atY: integer; s: string;col: RGBA): tRect;
var
  pos: integer;
  c, prevC: char;
  tag: string;

  {our current font state}
  currentColor: RGBA;
  currentShadow: boolean;
  currentBold: boolean;

  inEscape: boolean;
  inBrackets: boolean;

  values: tIntList;

  procedure outputChar();
  begin
    if currentShadow then begin
      charOut(dc, atX+1, atY+1, c, RGB(0,0,0,currentColor.a * 3 div 4), prevC);
      if currentBold then
        charOut(dc, atX+2, atY+1, c, RGB(0,0,0,currentColor.a * 3 div 4), prevC);
    end;
    if currentBold then begin
      charOut(dc, atX, atY, c, currentColor, prevC);
      inc(atX);
    end;
    atX := charOut(dc, atX, atY, c, currentColor, prevC);
    prevC := c;
  end;

  function readTag(): string;
  begin
    result := '';
    while pos <= length(s) do begin
      if (s[pos] = '>') then exit;
      result += s[pos];
      inc(pos);
    end;
    raise ValueError('Text "%s" missing closing bracket at position %d (%s)', [s,pos,tag]);
  end;

begin
  if not assigned(self) then exit;

  prevC := #0;

  inBrackets := false;
  inEscape := false;
  currentColor := col;
  currentShadow := false;
  currentBold := false;

  result.x := atX;
  result.y := atY;

  pos := 1;

  while pos <= length(s) do begin

    if inBrackets then begin
      tag := readTag().toLower();
      //note('Tag:>%s<', [tag]);
      if tag.startsWith('rgb(') then begin
        values.loadS('['+copy(tag, 5, length(tag)-5)+']');
        if (not values.len in [3,4]) then raise ValueError('Invalid format for RGB');
        currentColor.r := values[0];
        currentColor.g := values[1];
        currentColor.b := values[2];
        if values.len = 4 then
          currentColor.a := values[3]
        else
          currentColor.a := 255;
      end else if tag = 'shadow' then begin
        currentShadow := true;
      end else if tag = '/rgb' then begin
        currentColor := col;
      end else if tag = '/shadow' then begin
        currentShadow := false;
      end else if tag = 'bold' then begin
        currentBold := true;
      end else if tag = '/bold' then begin
        currentBold := false;
      end;
      inBrackets := false;
      if s[pos] <> '>' then raise ValueError('Missing "<"');
      inc(pos);
      continue;
    end;

    {consume next token}
    c := s[pos];
    inc(pos);

    if inEscape then begin
      outputChar();
      inEscape := false;
      continue;
    end;

    case c of
      '<': begin
        if inBrackets then raise ValueError('Invalid character "<"');
        inBrackets := true;
        {todo: process all brackets here}
      end;
      '>': begin
        if not inBrackets then raise ValueError('Invalid character ">"');
        inBrackets := false;
        end;
      '\': inEscape := true;
      else outputChar();
    end;
  end;

  // guess on height...
  result.bottomRight := Point(atX, atY+self.height);
end;

function tFont.textExtents(s: string; p: tPoint): tRect;
var
  nullDC: tDrawContext;
begin
  nullDC.page := nil;
  result := textOut(nullDC, p.x, p.y, s, RGBA.White);
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
