unit uSprite;

{$MODE delphi}
{$Interfaces corba}

interface

uses
  uTest,
  uDebug,
  uVgaDriver,
  uUtils,
  uIniFile,
  uGraph32,
  uTypes,
  uColor,
  uRect,
  uVertex;

type

  tBorder = record
    top, left, bottom, right: int32;
    procedure init(aLeft, aTop, aRight, aBottom: Integer);
    procedure setDefault();
    function  isDefault: boolean;
    function  toString(): string;
    function  inset(rect: tRect): tRect;
    procedure writeToIni(ini: tIniWriter; tag: string='Border');
    procedure readFromIni(ini: tIniReader; tag: string='Border');
    function  horizontal: integer;
    function  vertical: integer;
  end;

  tSprite = class(tObject, iIniSerializable)
  public
    tag: string;
    page: tPage;
    pivot2x: tPoint;  // the origin
    srcRect: tRect;   // location of sprite on page
    border: tBorder;  // border inset (not really used yet)
    innerBlendMode: int8; // blend used for center during nine-slice (or -1 for none)
  protected
    procedure setPivot(x,y: single);
  public
    constructor create(aPage: tPage); overload;
    constructor create(aPage: tPage; aRect: tRect); overload;
    destructor destroy(); override;

    function  width: int32; inline;
    function  height: int32; inline;

    function  clone(): tSprite;

    function  getPixel(atX, atY: integer): RGBA;
    procedure trim();

    procedure draw(const dc: tDrawContext; atX, atY: int32);
    procedure drawRot90(const dc: tDrawContext; pos: tPoint; numRotations: integer);
    procedure drawFlipped(const dc: tDrawContext; atX, atY: int32);
    procedure drawStretched(const dc: tDrawContext; dstRect: tRect);
    procedure drawScaled(const dc: tDrawContext; atX, atY: int32; scale: single);
    procedure drawRotated(const dc: tDrawContext; atPos: tPoint;zAngle: single; scale: single=1.0);
    procedure drawTransformed(const dc: tDrawContext; pos: V3D;transform: tMatrix4x4);
    procedure drawNineSlice(const dc: tDrawContext; dstRect: tRect);

    {iIniSerializable}
    procedure writeToIni(ini: tIniWriter);
    procedure readFromIni(ini: tIniReader);

  end;

  tSpriteSheet = class
  protected
    function byVar(tag: variant): tSprite;
  public
    page: tPage;
    sprites: array of tSprite;
    function byTag(tag: string): tSprite;
    function byIndex(idx: integer): tSprite;
  public
    constructor Create(aPage: tPage);
    procedure append(sprite: tSprite);
    procedure load(filename: string);
    procedure grid(cellWidth, cellHeight: word;centered: boolean=false;trim: boolean=true);
    property items[tag: Variant]: tSprite read byVar; default;
  end;

function Border(aLeft, aTop, aRight, aBottom: Integer): tBorder;

implementation

uses
  uPoly,
  uKeyboard, //stub
  uMath,
  uFileSystem;

function Border(aLeft, aTop, aRight, aBottom: Integer): tBorder;
begin
  result.init(aLeft, aTop, aRight, aBottom);
end;

{---------------------------------------------------------------------}

procedure tBorder.init(aLeft, aTop, aRight, aBottom: Integer);
begin
  self.left := aLeft;
  self.top := aTop;
  self.right := aRight;
  self.bottom := aBottom;
end;

function tBorder.isDefault: boolean;
begin
  result := (left=0) and (right=0) and (top=0) and (bottom=0);
end;

procedure tBorder.setDefault();
begin
  left := 0; right := 0; top := 0; bottom := 0;
end;

function tBorder.toString(): string;
begin
  result := format('(%d %d %d %d)', [left, top, right, bottom]);
end;

function tBorder.inset(rect: tRect): tRect;
begin
  result := rect;
  result.width -= horizontal;
  result.height -= vertical;
  result.pos.x += left;
  result.pos.y += top;
end;

procedure tBorder.writeToIni(ini: tIniWriter; tag: string='Border');
begin
  ini.writeArray(tag, [left, top, right, bottom]);
end;

function tBorder.horizontal: integer;
begin
  result := left + right;
end;

function tBorder.vertical: integer;
begin
  result := top + bottom;
end;

procedure tBorder.readFromIni(ini: tIniReader; tag: string='Border');
var
  data: tInt32Array;
begin
  data := ini.readIntArray(tag);
  left := data[0];
  top := data[1];
  right := data[2];
  bottom := data[3];
end;

{---------------------------------------------------------------------}

constructor tSprite.Create(aPage: tPage);
begin
  inherited create();
  self.tag := 'sprite';
  self.page := aPage;
  self.srcRect := Rect(aPage.width, aPage.height);
  self.pivot2x := Point(0,0);
  self.border.init(0, 0, 0, 0);
  self.innerBlendMode := -1;
end;

constructor tSprite.Create(aPage: tPage; aRect: tRect);
begin
  create(aPage);
  self.srcRect := aRect;
end;

procedure tSprite.setPivot(x,y: single);
begin
  pivot2x.x := round(x*2);
  pivot2x.y := round(y*2);
end;

function tSprite.width: int32;
begin
  result := srcRect.Width;
end;

function tSprite.height: int32;
begin
  result := srcRect.Height;
end;

{trim bounds to fit non-transparient pixels}
procedure tSprite.trim();
var
  x,y: integer;
  xMin,xMax, yMin, yMax: integer;
  oldRect: tRect;
begin
  xMin := width; yMin := height; xMax := 0; yMax := 0;
  for y := 0 to height-1 do begin
    for x := 0 to width-1 do begin
      if getPixel(x,y).a > 0 then begin
        xMax := max(x, xMax);
        yMax := max(y, yMax);
        xMin := min(x, xMin);
        yMin := min(y, yMin);
      end;
    end;
  end;

  if (xMax-xMin) < 0 then begin
    // special case, sprite is empty.
    srcRect.width := 0;
    srcRect.height:= 0;
    exit;
  end;

  oldRect := srcRect;

  pivot2x.x -= xMin*2;
  pivot2x.y -= yMin*2;

  srcRect.pos.x += xMin;
  srcRect.pos.y += yMin;
  srcRect.width := (xMax-xMin)+1;
  srcRect.height := (yMax-yMin)+1;

  //note('Sprite trim: old:%s new:%s', [oldRect.toString, srcRect.toString]);
end;

function tSprite.getPixel(atX, atY: integer): RGBA;
begin
  fillchar(result, sizeof(result), 0);
  if (atX < 0) or (atY < 0) or (atX >= srcRect.width) or (atY >= srcRect.height) then exit;
  result := page.getPixel(atX+srcRect.x, atY+srcRect.y);
end;

{Draw sprite at given location.}
procedure tSprite.draw(const dc: tDrawContext; atX, atY: integer);
begin
  atX -= pivot2x.x div 2;
  atY -= pivot2x.y div 2;
  dc.drawSubImage(page, Point(atX, atY), srcRect);
end;

{Draw sprite rotated around topleft by multiples of 90 degrees}
procedure tSprite.drawRot90(const dc: tDrawContext; pos: tPoint; numRotations: integer);
var
  x,y: integer;
  dx,dy: integer;
  c: RGBA;
begin
  assert(pivot2x.x = 0);
  assert(pivot2x.y = 0);
  numRotations := (numRotations + 4) mod 4;
  if numRotations = 0 then begin draw(dc, pos.x, pos.y); exit; end;
  {slow for the moment}
  for y := 0 to height-1 do
    for x := 0 to width-1 do begin
      c := getPixel(x,y);
      if (c.a = 0) and (dc.blendMode <> bmBlit) then continue;
      case numRotations of
        0: begin dx := x; dy := y; end;
        1: begin dx := height-y-1; dy := x; end;
        2: begin dx := width-x-1; dy := height-y-1; end;
        3: begin dx := y; dy := width-x-1; end;
      end;
      dc.putPixel(Point(pos.x+dx, pos.y+dy), c);
    end;
end;

{Draws sprite flipped on x-axis}
procedure tSprite.drawFlipped(const dc: tDrawContext; atX, atY: integer);
begin
  atX -= pivot2x.x div 2;
  atY -= pivot2x.y div 2;
  drawPoly(dc, page, srcRect,
    Point(atX + srcRect.width - 1, atY),
    Point(atX, atY),
    Point(atX, atY + srcRect.height - 1),
    Point(atX + srcRect.width - 1, atY + srcRect.height - 1)
  );
  dc.MarkRegion(Rect(atX, atY, srcRect.width, srcRect.height));
end;

{Draws sprite stetched to cover destination rect}
procedure tSprite.drawStretched(const dc: tDrawContext; dstRect: tRect);
begin
  dc.stretchSubImage(page, dstRect, srcRect);
end;

procedure tSprite.drawScaled(const dc: tDrawContext; atX, atY: int32; scale: single);
begin
  self.drawStretched(dc, Rect(atX, atY, round(width*scale), round(height*scale)));
end;

procedure tSprite.drawRotated(const dc: tDrawContext; atPos: tPoint;zAngle: single; scale: single=1.0);
var
  transform: tMatrix4x4;
begin
  {todo: switch to a 3x2 matrix for this stuff}
  transform.setIdentity();
  transform.translate(V3(-pivot2x.x/2, -pivot2x.y/2, 0));
  transform.rotateXYZ(0, 0, zAngle * DEG2RAD);
  transform.scale(scale);
  drawTransformed(dc, V3(atPos.x, atPos.y, 0), transform);
end;

{identity transform will the centered on sprite center...
 todo: implement a default anchor}
procedure tSprite.drawTransformed(const dc: tDrawContext; pos: V3D;transform: tMatrix4x4);
var
  p1,p2,p3,p4: tPoint;
  minX, minY, maxX, maxY: integer;

  function xform(delta: tPoint): tPoint;
  var
    d, v, r: V3D;
  begin
    {note: locked to midpoint pivot for the moment}
    d := V3(delta.x, delta.y, 0) - V3(srcRect.width / 2, srcRect.height / 2, 0);
    v := transform.apply(d);
    { no perspective for the moment }
    { round towards center}
    r := V3(v.x-sign(v.x)*0.50, v.y-sign(v.y)*0.50, 0);
    result.x := trunc(r.x+pos.x);
    result.y := trunc(r.y+pos.y);

    minX := min(result.x, minX);
    maxX := max(result.x, maxX);
    minY := min(result.y, minY);
    maxY := max(result.y, maxY);
  end;

begin
  {todo: clipping}
  minX := page.width;
  maxX := 0;
  minY := page.height;
  maxY := 0;
  drawPoly(dc, page, srcRect,
    xform(Point(0,0)),
    xform(Point(srcRect.width, 0)),
    xform(Point(srcRect.width, srcRect.height)),
    xform(Point(0, srcRect.height))
  );
end;

{Draw sprite using nine-slice method}
procedure tSprite.drawNineSlice(const dc: tDrawContext; dstRect: tRect);
var
  oldRect: tRect;
  oldMode: tBlendMode;
  insetRect: tRect;
begin

  oldRect := srcRect;

  {top part}
  srcRect := tRect.inset(oldRect, 0, 0, border.left, border.top);
  draw(dc, dstRect.x, dstRect.y);
  srcRect := tRect.inset(oldRect, Border.Left, 0, -Border.Right, Border.Top);
  drawStretched(dc, tRect.Inset(dstRect, border.left, 0, -border.right, border.top));
  srcRect := tRect.Inset(oldRect,-Border.Right, 0, 0, Border.Top);
  draw(dc, dstRect.x+dstRect.width-Border.right, dstRect.y);

  {middle part}
  srcRect := tRect.Inset(oldRect, 0, Border.Top, Border.Left, -Border.Bottom);
  drawStretched(dc, tRect.Inset(dstRect, 0, Border.Top, Border.Left, -Border.Bottom));

  {special case for center piece}
  srcRect := tRect.Inset(oldRect, border.left, border.top, -border.right, -border.bottom);
  insetRect := tRect.Inset(dstRect, border.left, border.top, -border.right, -border.bottom);
  if innerBlendMode >= 0 then
    drawStretched(dc.asBlendMode(tBlendMode(innerBlendMode)), insetRect)
  else
    drawStretched(dc, insetRect);

  srcRect := tRect.Inset(oldRect,-Border.Right, Border.Top, 0, -Border.Bottom);
  drawStretched(dc, tRect.Inset(dstRect,-Border.Right, Border.Top, 0, -Border.Bottom));

  {bottom part}
  srcRect := tRect.Inset(oldRect,0, -Border.Bottom, Border.Left, 0);
  draw(dc, dstRect.x, dstRect.y+dstRect.height-Border.Bottom);
  srcRect := tRect.Inset(oldRect,Border.Left, -Border.Bottom, -Border.Right, 0);
  drawStretched(dc, TRect.Inset(dstRect,Border.Left, -Border.Bottom, -Border.Right, 0));
  srcRect := tRect.Inset(oldRect,-Border.Right, -Border.Bottom, 0, 0);
  draw(dc, dstRect.x+dstRect.width-Border.Right, dstRect.y+dstRect.height-Border.Bottom);

  srcRect := oldRect;
end;

{create a shallow copy of the sprite}
function tSprite.clone(): tSprite;
begin
  result := tSprite.create(self.page);
  result.tag := self.tag;
  result.srcRect := self.srcRect;
  result.border := self.border;
  result.innerBlendMode := self.innerBlendMode;
end;

destructor tSprite.destroy();
begin
  self.tag := '';
  self.page := nil;
  inherited destroy();
end;

{---------------------}

procedure tSprite.writeToIni(ini: tIniWriter);
begin
  ini.writeString('Tag', tag);
  ini.writeRect('Rect', srcRect);
  // todo: support skipping default values
  //if not border.isDefault then
  border.writeToIni(ini);
end;

procedure tSprite.readFromIni(ini: tIniReader);
begin
  tag := ini.readString('Tag');
  srcRect := ini.readRect('Rect');
  if ini.peekKey.toLower = 'border' then
    border.readFromIni(ini)
  else
    border.setDefault();
end;

{-----------------------------------------------------}

constructor tSpriteSheet.Create(aPage: tPage);
begin
  setLength(sprites, 0);
  page := aPage;
end;

procedure tSpriteSheet.append(sprite: tSprite);
begin
  sprite.page := self.page;
  setLength(sprites, length(sprites)+1);
  sprites[length(sprites)-1] := sprite;
end;

procedure tSpriteSheet.load(filename: string);
var
  reader: tIniReader;
  sprite: tSprite;
begin
  reader := tIniReader.create(filename);
  while not reader.eof do begin
    sprite := tSprite.create(page);
    sprite.readFromIni(reader);
    append(sprite);
  end;
  reader.free();
  note(' - loaded sprite sheet "%s" with %d sprites.', [filename, length(sprites)]);
end;

{create sprites using a grid}
procedure tSpriteSheet.grid(cellWidth,cellHeight: word;centered: boolean=false;trim: boolean=true);
var
  sprite: tSprite;
  x, y: integer;
begin
  for y := 0 to (page.height div cellHeight)-1 do begin
    for x := 0 to (page.width div cellWidth)-1 do begin
      sprite := tSprite.create(page);
      sprite.srcRect := Rect(x*cellWidth, y*cellHeight, cellWidth, cellHeight);
      if centered then begin
        sprite.pivot2x.x := cellWidth;
        sprite.pivot2x.y := cellHeight;
      end;
      if trim then sprite.trim();
      append(sprite);
    end;
  end;
  note('Loaded %d sprites from %s',[length(sprites), page.tag]);
end;

{---------------}

function tSpriteSheet.byVar(tag: Variant): tSprite;
begin
  case tVarData(tag).vType of
    vtInteger: result := byIndex(tag.VInteger);
    vtInt64: result := byIndex(tag.VInt64);
    vtString: result := byTag(tag.VString);
    else raise ValueError('Invalid index type');
  end;
end;

function tSpriteSheet.byTag(tag: string): tSprite;
var
  sprite: tSprite;
begin
  {linear scan for moment}
  for sprite in sprites do
    if assigned(sprite) and (sprite.tag = tag) then exit(sprite);
  fatal('Sprite sheet contains no sprite named "'+tag+'"');
end;

function tSpriteSheet.byIndex(idx: integer): tSprite;
begin
  result := sprites[idx];
end;

{-----------------------------------------------------}

type
  tSpriteTest = class(tTestSuite)
    procedure testDraw();
    procedure run; override;
  end;

procedure tSpriteTest.testDraw();
var
  page: tPage;
  spritePage: tPage;
  sprite: tSprite;
  c: array[0..4] of RGBA;
  x,y: integer;
  dc: tDrawContext;

type tSln = array[0..3,0..3] of byte;

var
  sln: array of tSln = [
    {draw with clip}
   ((0, 0, 0, 0),
    (0, 1, 2, 0),
    (0, 3, 4, 0),
    (0, 0, 0, 0)),
   ((4, 0, 0, 0),
    (0, 0, 0, 0),
    (0, 0, 0, 0),
    (0, 0, 0, 0)),
   ((0, 0, 0, 0),
    (0, 0, 0, 0),
    (0, 0, 0, 0),
    (0, 0, 0, 1)),
    {rotation}
   ((0, 0, 0, 0),
    (0, 3, 1, 0),
    (0, 4, 2, 0),
    (0, 0, 0, 0)),
    {scaling}
   ((1, 1, 2, 2),
    (1, 1, 2, 2),
    (3, 3, 4, 4),
    (3, 3, 4, 4))
  ];

  function whichColor(aC: RGBA): string;
  var
    i: integer;
  begin
    result := '?';
    for i := 0 to 4 do
      if aC = c[i] then exit(intToStr(i));
  end;

  procedure testSln(aPage: tPage; sln: tSln);
  var
    i,j: integer;
    wasError: boolean;
    foundStr, expectedStr: string;
  begin
    wasError := false;
    for i := 0 to 3 do
      for j := 0 to 3 do
        if aPage.getPixel(i,j) <> c[sln[j,i]] then wasError := true;
    if not wasError then exit;
    for j := 0 to 3 do begin
      foundStr := '';
      expectedstr := '';
      for i := 0 to 3 do foundStr += whichColor(aPage.getPixel(i,j));
      for i := 0 to 3 do expectedStr += intToStr(sln[j,i]);
      note('  '+foundStr+' '+expectedStr);
    end;
    fatal('Colors do not match');
  end;

begin

  page := tPage.create(4,4);
  spritePage := tPage.create(2,2);
  c[0] := RGB(0,0,0); c[1] := RGB(255,0,0); c[2] := RGB(0,255,0); c[3] := RGB(0,0,255); c[4] := RGB(255,0,255);
  spritePage.putPixel(0,0,c[1]);
  spritePage.putPixel(1,0,c[2]);
  spritePage.putPixel(0,1,c[3]);
  spritePage.putPixel(1,1,c[4]);
  sprite := tSprite.create(spritePage);

  dc := page.getDC(bmBlit);

  {standard draw with clipping}
  page.clear(c[0]);
  sprite.draw(dc, 1, 1);
  testSln(page, sln[0]);
  page.clear(c[0]);
  sprite.draw(dc, -1, -1);
  testSln(page, sln[1]);
  page.clear(c[0]);
  sprite.draw(dc, 3, 3);
  testSln(page, sln[2]);


  {scaling}
  page.clear(c[0]);
  sprite.drawStretched(dc, Rect(0,0,4,4));
  testSln(page, sln[4]);

  (*
  {these are not implemented yet}
  {rotation}
  sprite.setPivot(1,1);
  page.clear(c[0]);
  sprite.drawRotated(page, Point(2, 2), 0);
  testSln(page, sln[0]);
  page.clear(c[0]);
  sprite.drawRotated(page, Point(2, 2), 90);
  testSln(page, sln[3]);
  *)

  page.free;
  spritePage.free;
  sprite.free;

end;

procedure tSpriteTest.run();
var
  sprite1, sprite2: tSprite;
  iniWriter: tIniWriter;
  iniReader: tIniReader;
  page: tPage;
begin
  page := tPage.create(64,64);
  sprite1 := tSprite.create(page);
  sprite1.tag := 'Fish';
  sprite1.srcRect := Rect(8,12,30,34);
  sprite1.border.init(2,3,4,1);

  iniWriter := tIniWriter.create('test.ini');
  iniWriter.writeObject('Sprite', sprite1);
  iniWriter.free();

  sprite2 := tSprite.create(page);
  iniReader := tIniReader.create('test.ini');
  sprite2.readFromINI(iniReader);
  iniReader.free();

  assertEqual(sprite2.tag, sprite1.tag);
  assertEqual(sprite2.srcRect.toString, sprite1.srcRect.toString);
  assertEqual(sprite2.border.toString, sprite1.border.toString);

  fileSystem.delFile('test.ini');

  sprite1.free;
  sprite2.free;
  page.free;

  testDraw();
end;

initialization
  tSpriteTest.create('Sprite');
end.
