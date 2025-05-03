{for poly drawing}
unit uPoly;

interface

uses
  uDebug,
  uTest,
  uUtils,
  uColor,
  uRect,
  uGraph32,
  uScreen;

type

  {16.16 scaled uv co-ord}
  tUVCoord = record
    x, y: int32;
    class operator add(a,b: tUVCoord): tUVCoord;
    class operator multiply(a: tUVCoord;b: integer): tUVCoord;
    function toPoint(): tPoint;
    function toString(): string;
  end;

  tScanLine = record
    xMin, xMax: int32; // inclusive
    function len: integer;
    procedure reset();
  end;

  tTextureLine = record
    t1,t2: tUVCoord;
  end;

type
  tScanLines = class
  public
    scanLine: array[0..1024-1] of tScanLine;
    textLine: array[0..1024-1] of tTextureLine;
    backfaceCull: boolean;
    bounds: tRect;
  protected
    procedure prepPoly(const dc: tDrawContext; p1, p2, p3, p4: tPoint);
    procedure adjustLine(y, x: int32); overload;
    procedure adjustLine(y, x: int32; t: tUVCoord); overload;
  public
    constructor create();
    procedure logScan();
    procedure scanSide(const dc: tDrawContext; a, b: tPoint);
    procedure scanSideTextured(const dc: tDrawContext; a, b: tPoint; t1, t2: tUVCoord);
    procedure scanTextured(const dc: tDrawContext; p1, p2, p3, p4: tPoint; t1, t2, t3, t4: tUVCoord);
    procedure scanPoly(const dc: tDrawContext; p1, p2, p3, p4: tPoint);
  end;

var
  polyDraw: tScanLines;

function UVCoord(x, y: single): tUVCoord; overload;
function UVCoord(p: tPoint): tUVCoord; overload;

procedure drawPoly(dc: tDrawContext; srcPage: tPage; src: tRect; p1,p2,p3,p4: tPoint);

implementation

{$i poly_ref.inc}
{$i poly_asm.inc}

{----------------------------------------------------}

{draw an image stretched to fill poly}
procedure drawPoly(dc: tDrawContext; srcPage: tPage; src: tRect; p1,p2,p3,p4: tPoint);
var
  y: integer;
  t: tPoint;
  f: single;
  sl: tScanLine;
  tl: tTextureLine;
  t1,t2,t3,t4: tUVCoord;
  tInitial, tDelta: tUVCoord;
  x1,x2: integer;
  b: tRect;
  {for asm}
  screenPtr, texturePtr: pointer;
  texX, texY, texDeltaX, texDeltaY: int32; // as 16.16
  textureWidth: dword;
  textureSize: dword;
  cnt: int32;
begin

  p1 += dc.offset;
  p2 += dc.offset;
  p3 += dc.offset;
  p4 += dc.offset;

  {src coords are inclusive-exclusive}
  t1 := UVCoord(src.topLeft) + UVCoord(0.5,0.5);
  t2 := UVCoord(src.topRight) + UVCoord(-0.5,0.5);
  t3 := UVCoord(src.bottomRight) + UVCoord(-0.5,-0.5);
  t4 := UVCoord(src.bottomLeft) + UVCoord(0.5,-0.5);
  polyDraw.scanTextured(
    dc,
    p1, p2, p3, p4,
    t1, t2, t3, t4
  );
  b := polyDraw.bounds;
  if b.area = 0 then exit;
  for y := b.top to b.bottom-1 do begin
    sl := polyDraw.scanLine[y];
    tl := polyDraw.textLine[y];
    x1 := clamp(sl.xMin, dc.clip.left, dc.clip.right-1);
    x2 := clamp(sl.xMax, dc.clip.left, dc.clip.right-1);
    cnt := (x2-x1)+1;
    if cnt <= 0 then continue;

    {get initial texture pos (as 16.16}
    if cnt = 1 then
      f := 0
    else
      f := (x1-sl.xMin)/(sl.xMax-sl.xMin);
    {todo: range check error here... I think just switch to simpler TX coord system}
    texX := trunc(lerp(tl.t1.x, tl.t2.x, f));
    texY := trunc(lerp(tl.t1.y, tl.t2.y, f));
    {get delta}
    f := ((x1+1)-sl.xMin)/(sl.xMax-sl.xMin);
    texDeltaX := trunc(lerp(tl.t1.x, tl.t2.x, f)) - texX;
    texDeltaY := trunc(lerp(tl.t1.y, tl.t2.y, f)) - texY;

    screenPtr := dc.page.getAddr(x1, y);
    texturePtr := srcPage.pData;
    textureWidth := srcPage.width;
    textureSize := srcPage.width * srcPage.height;

    if (textureWidth = 256) and (textureSize = 65536) then
      polyLine256_ASM(screenPtr, texturePtr, texX, texY, texDeltaX, texDeltaY, textureWidth, textureSize, cnt)
    else
      polyLine_ASM(screenPtr, texturePtr, texX, texY, texDeltaX, texDeltaY, textureWidth, textureSize, cnt);
  end;
  dc.MarkRegion(b);
end;

{----------------------------------------------------}

function min4(a,b,c,d: int32): int32; inline;
begin
  result := a;
  if b < result then result := b;
  if c < result then result := c;
  if d < result then result := d;
end;

function max4(a,b,c,d: int32): int32; inline;
begin
  result := a;
  if b > result then result := b;
  if c > result then result := c;
  if d > result then result := d;
end;

{----------------------------------------------------}

class operator tUVCoord.add(a,b: tUVCoord): tUVCoord;
begin
  result.x := a.x + b.x;
  result.y := a.y + b.y;
end;

class operator tUVCoord.multiply(a: tUVCoord;b: integer): tUVCoord;
begin
  result.x := a.x * b;
  result.y := a.y * b;
end;

{convert to 16.16 scaled point}
function tUVCoord.toPoint(): tPoint;
begin
  result.x := shiftRight(x, 16);
  result.y := shiftRight(y, 16);
end;

function tUVCoord.toString(): string;
begin
  result := format('(%d,%d)', [x, y]);
end;

function UVCoord(x, y: single): tUVCoord;
begin
  result.x := round(x * 65536);
  result.y := round(y * 65536);
end;

function UVCoord(p: tPoint): tUVCoord;
begin
  result.x := p.x shl 16;
  result.y := p.y shl 16;
end;

{----------------------------------------------------}

procedure tScanLine.reset(); inline;
begin
  xMax := -9999;
  xMin := 9999;
end;

function tScanLine.len: integer;
begin
  result := (xMax-xMin)+1;
end;

{----------------------------------------------------}

constructor tScanLines.create();
begin
  backfaceCull := false;
end;

procedure tScanLines.logScan();
var
  y: integer;
begin
  for y := bounds.top to bounds.bottom-1 do
    note('%d: %d %d', [y, scanLine[y].xMin, scanLine[y].xMax]);
end;

procedure tScanLines.adjustLine(y, x: int32); inline;
begin
  scanLine[y].xMin := min(x, scanLine[y].xMin);
  scanLine[y].xMax := max(x, scanLine[y].xMax);
end;

{adjust with texture co-ord}
procedure tScanLines.adjustLine(y, x: int32; t: tUVCoord); inline;
begin
  if x < scanLine[y].xMin then begin
    scanLine[y].xMin := x;
    textLine[y].t1 := t;
  end;
  if x > scanLine[y].xMax then begin
    scanLine[y].xMax := x;
    textLine[y].t2 := t;
  end;
end;

{scans sides of poly, returns bounding rect}
procedure tScanLines.scanPoly(const dc: tDrawContext; p1, p2, p3, p4: tPoint);
begin
  prepPoly(dc, p1, p2, p3, p4);
  if bounds.area = 0 then exit;
  scanSide(dc, p1, p2);
  scanSide(dc, p2, p3);
  scanSide(dc, p3, p4);
  scanSide(dc, p4, p1);
end;

{
sets up scanLines for a textured poly as follows.

 - destination points (p1..p4) are inclusive.
 - texture coordinates mark the texture points at corners
 - most drawing functions truncate, so it is recommended to use the middle of the texel
}
procedure tScanLines.scanTextured(const dc: tDrawContext; p1, p2, p3, p4: tPoint; t1, t2, t3, t4: tUVCoord);
begin
  prepPoly(dc, p1, p2, p3, p4);
  if bounds.area = 0 then exit;
  scanSideTextured(dc, p1, p2, t1, t2);
  scanSideTextured(dc, p2, p3, t2, t3);
  scanSideTextured(dc, p3, p4, t3, t4);
  scanSideTextured(dc, p4, p1, t4, t1);
end;

procedure tScanLines.prepPoly(const dc: tDrawContext; p1, p2, p3, p4: tPoint);
var
  cross: int32;
  xMin, xMax, yMin, yMax: int32;
  x,y: integer;
  c: RGBA;
begin

  fillchar(bounds, sizeof(bounds), 0);

  if backfaceCull then begin
    cross := ((p2.x-p1.x) * (p3.y - p1.y)) - ((p2.y - p1.y) * (p3.x - p1.x));
    if cross <= 0 then exit;
  end;

  xMin := max(min4(p1.x, p2.x, p3.x, p4.x), dc.clip.left);
  yMin := max(min4(p1.y, p2.y, p3.y, p4.y), dc.clip.top);
  xMax := min(max4(p1.x, p2.x, p3.x, p4.x), dc.clip.right-1);
  yMax := min(max4(p1.y, p2.y, p3.y, p4.y), dc.clip.bottom-1);

  bounds.y := yMin;
  bounds.height := yMax-yMin+1;
  bounds.x := xMin;
  bounds.width := xMax-xMin+1;

  {do not render offscreen sides}
  if bounds.height <= 0 then exit;
  if bounds.width <= 0 then exit;

  for y := yMin to yMax do
    scanLine[y].reset();

end;

procedure tScanLines.scanSide(const dc: tDrawContext; a, b: tPoint);
var
  tmp: tPoint;
  y: int32;
  x: single;
  deltaX: single;
  yMin, yMax: integer;
begin
  if a.y = b.y then begin
    {special case}
    y := a.y;
    if (y >= dc.clip.top) and (y < dc.clip.bottom) then begin
      adjustLine(y, a.x);
      adjustLine(y, b.x);
    end;
    exit;
  end;

  if a.y > b.y then begin
    tmp := a; a := b; b := tmp;
  end;

  x := a.x;
  deltaX := (b.x-a.x) / (b.y-a.y);
  yMin := a.y;
  if yMin < 0 then begin
    x += deltaX * -yMin;
    yMin := 0;
  end;
  yMax := min(b.y, dc.clip.bottom-1);
  for y := yMin to yMax do begin
    adjustLine(y, round(x));
    x += deltaX;
  end;
end;

{scans side of poly with given texture coordinates}
procedure tScanLines.scanSideTextured(const dc: tDrawContext; a, b: tPoint; t1, t2: tUVCoord);
var
  tmp: tPoint;
  y: int32;
  x: single;
  t: tUVCoord;
  deltaX: single;
  yMin, yMax: integer;
  height: integer;
  tmpUV: tUVCoord;
  deltaT: tUVCoord;
begin
  if a.y = b.y then begin
    {special case}
    y := a.y;
    if (y < dc.clip.left) or (y >= dc.clip.right) then exit;
    if a.x < b.x then begin
      scanLine[y].xMin := a.x;
      scanLine[y].xMax := b.x;
      textLine[y].t1 := t1;
      textLine[y].t2 := t2;
    end else begin
      scanLine[y].xMin := b.x;
      scanLine[y].xMax := a.x;
      textLine[y].t1 := t2;
      textLine[y].t2 := t1;
    end;
    exit;
  end;

  if a.y > b.y then begin
    tmp := a; a := b; b := tmp;
    tmpUV := t1; t1 := t2; t2 := tmpUV;
  end;

  {todo: switch to scaled integer for x (for relabiltiy more than speed)}
  x := a.x;
  height := (b.y-a.y);
  deltaX := (b.x-a.x) / height;
  deltaT.x := (t2.x - t1.x) div height;
  deltaT.y := (t2.y - t1.y) div height;

  yMin := a.y;
  yMax := min(b.y, dc.clip.bottom-1);
  t := t1;

  if (yMax < dc.clip.top) or (yMin >= dc.clip.bottom) then exit;

  if yMin < 0 then begin
    x += deltaX * -yMin;
    t += deltaT * -yMin;
    yMin := 0;
  end;

  for y := yMin to yMax do begin
    adjustLine(y, round(x), t);
    x += deltaX;
    t += deltaT;
  end;

end;

{-----------------------------------------------------}

type
  tPolyTest = class(tTestSuite)
    procedure run; override;
  end;

procedure tPolyTest.run();
var
  page: tPage;
  sl: tScanLine;
  tl: tTextureLine;
  dc: tDrawContext;
begin
  page := tPage.create(16,16);
  dc := page.getDC();

  polyDraw.scanTextured(
    dc,
    Point(0,0), point(1,0), Point(1,1), Point(0,1),
    UVCoord(1,2), UVCoord(3,4), UVCoord(5,6), UVCoord(7,8)
  );

  assertEqual(polyDraw.bounds.topLeft, Point(0, 0));
  assertEqual(polyDraw.bounds.bottomRight, Point(2, 2));

  sl := polyDraw.scanLine[0];
  tl := polyDraw.textLine[0];
  assertEqual(sl.xMin, 0);
  assertEqual(sl.xMax, 1);
  assertEqual(tl.t1.toPoint, Point(1,2));
  assertEqual(tl.t2.toPoint, Point(3,4));
  sl := polyDraw.scanLine[1];
  tl := polyDraw.textLine[1];
  assertEqual(sl.xMin, 0);
  assertEqual(sl.xMax, 1);
  assertEqual(tl.t1.toPoint, Point(7,8));
  assertEqual(tl.t2.toPoint, Point(5,6));

  page.free;
end;

initialization
  polyDraw := tScanLines.create();
  tPolyTest.create('Sprite');
finalization
  polyDraw.free();
end.
