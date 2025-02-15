{for poly drawing}
unit poly;

interface

uses
  debug,
  test,
  utils,
  graph2d,
  graph32,
  screen;

type
  tScanLine = record
    xMin, xMax: int32;
    t1,t2: tScaledPoint;
    procedure reset(width: integer);
    procedure adjust(x: int32); overload;
    procedure adjust(x: int32; t: tScaledPoint); overload;
  end;

type
  tScanLines = class
  public
    scanLine: array[0..1024-1] of tScanLine;
    backfaceCull: boolean;
    bounds: tRect;
  protected
    procedure prepPoly(page: tPage; p1, p2, p3, p4: tPoint);
  public
    constructor create();
    procedure scanSide(page: tPage; a, b: tPoint);
    procedure scanSideTextured(page: tPage; a, b, t1, t2: tPoint);
    procedure scanTextured(page: tPage; p1, p2, p3, p4, t1, t2, t3, t4: tPoint);
    procedure scanPoly(page: tPage; p1, p2, p3, p4: tPoint);
  end;

const
  POLY_SHOW_CORNERS: boolean = false;

var
  polyDraw: tScanLines;

implementation

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

procedure tScanLine.reset(width: integer); inline;
begin
  xMax := 0;
  xMin := width-1;
end;

procedure tScanLine.adjust(x: int32); inline;
begin
  xMin := min(x, xMin);
  xMax := max(x, xMax);
end;

{adjust with texture co-ord}
procedure tScanLine.adjust(x: int32; t: tScaledPoint); inline;
begin
  if x < xMin then begin
    xMin := x;
    t1 := t;
  end;
  if x > xMax then begin
    xMax := x;
    t2 := t;
  end;
end;

{----------------------------------------------------}

constructor tScanLines.create();
begin
  backfaceCull := false;
end;

{scans sides of poly, returns bounding rect}
procedure tScanLines.scanPoly(page: tPage; p1, p2, p3, p4: tPoint);
begin
  prepPoly(page, p1, p2, p3, p4);
  if bounds.area = 0 then exit;
  scanSide(page, p1, p2);
  scanSide(page, p2, p3);
  scanSide(page, p3, p4);
  scanSide(page, p4, p1);
end;

procedure tScanLines.scanTextured(page: tPage; p1, p2, p3, p4, t1, t2, t3, t4: tPoint);
begin
  prepPoly(page, p1, p2, p3, p4);
  if bounds.area = 0 then exit;
  scanSideTextured(page, p1, p2, t1, t2);
  scanSideTextured(page, p2, p3, t2, t3);
  scanSideTextured(page, p3, p4, t3, t4);
  scanSideTextured(page, p4, p1, t4, t1);
end;

procedure tScanLines.prepPoly(page: tPage; p1, p2, p3, p4: tPoint);
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

  xMin := min4(p1.x, p2.x, p3.x, p4.x);
  yMin := min4(p1.y, p2.y, p3.y, p4.y);
  xMax := max4(p1.x, p2.x, p3.x, p4.x);
  yMax := max4(p1.y, p2.y, p3.y, p4.y);

  bounds.y := yMin;
  bounds.height := yMax-yMin;
  bounds.x := xMin;
  bounds.width := xMax-xMin;

  {do not render offscreen sides}
  if bounds.height <= 0 then exit;
  if bounds.width <= 0 then exit;

  {debuging, show corners}
  if POLY_SHOW_CORNERS then begin
    c := RGB(255,0,255);
    page.setPixel(p1.x, p1.y, c);
    page.setPixel(p2.x, p2.y, c);
    page.setPixel(p3.x, p3.y, c);
    page.setPixel(p4.x, p4.y, c);
  end;

  for y := yMin to yMax do
    scanLine[y].reset(page.width);

end;

procedure tScanLines.scanSide(page: tPage; a, b: tPoint);
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
    if (y >= 0) and (y < page.height) then begin
      scanLine[y].adjust(a.x);
      scanLine[y].adjust(b.x);
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
  yMax := min(b.y, page.height-1);
  for y := yMin to yMax do begin
    scanLine[y].adjust(round(x));
    x += deltaX;
  end;
end;

{scans side of poly with given texture coordinates}
procedure tScanLines.scanSideTextured(page: tPage; a, b, t1, t2: tPoint);
var
  tmp: tPoint;
  y: int32;
  x: single;
  t: tScaledPoint;
  deltaX: single;
  yMin, yMax: integer;
  height: integer;
  uv1,uv2, tmpUV: tScaledPoint;
  deltaT: tScaledPoint;
begin
  {scale texture co-ords to 16.16}
  uv1 := t1.toScaled();
  uv2 := t2.toScaled();

  if a.y = b.y then begin
    {special case}
    y := a.y;
    if (y < 0) or (y >= page.height) then exit;
    if a.x < b.x then begin
      scanLine[y].xMin := a.x;
      scanLine[y].xMax := b.x;
      scanLine[y].t1 := uv1;
      scanLine[y].t2 := uv2;
    end else begin
      scanLine[y].xMin := b.x;
      scanLine[y].xMax := a.x;
      scanLine[y].t1 := uv2;
      scanLine[y].t2 := uv1;
    end;
    exit;
  end;

  if a.y > b.y then begin
    tmp := a; a := b; b := tmp;
    tmpUV := uv1; uv1 := uv2; uv2 := tmpUV;
  end;

  {todo: switch to scaled integer for x (for relabiltiy more than speed)}
  x := a.x;
  height := (b.y-a.y);
  deltaX := (b.x-a.x) / height;
  deltaT.x := (uv2.x - uv1.x) div height;
  deltaT.y := (uv2.y - uv1.y) div height;
  yMin := a.y;
  if yMin < 0 then begin
    x += deltaX * -yMin;
    yMin := 0;
  end;
  yMax := min(b.y, page.height-1);
  t := uv1;
  for y := yMin to yMax do begin
    scanLine[y].adjust(round(x), t);
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
begin
  {todo}
end;

initialization
  polyDraw := tScanLines.create();
  tPolyTest.create('Sprite');
finalization
  polyDraw.free();
end.
