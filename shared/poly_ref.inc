{draw an image stretched to fill poly}
procedure polyDraw_REF(dstPage, srcPage: tPage; src: tRect; p1,p2,p3,p4: tPoint);
var
  x, y: integer;
  t: tPoint;
  f: single;
  sl: tScanLine;
  tl: tTextureLine;
  width: integer;
  t1,t2,t3,t4: tUVCoord;
  x1,x2: integer;
  b: tRect;
begin

  {stub:}
  //note('%s %s %s %s', [p1.toString, p2.toString, p3.toString, p4.toString]);

  {src coords are inclusive-exclusive}
  t1 := UVCoord(src.topLeft) + UVCoord(0.5,0.5);
  t2 := UVCoord(src.topRight) + UVCoord(-0.5,0.5);
  t3 := UVCoord(src.bottomRight) + UVCoord(-0.5,-0.5);
  t4 := UVCoord(src.bottomLeft) + UVCoord(0.5,-0.5);
  polyDraw.scanTextured(
    dstPage.getDC(),
    p1, p2, p3, p4,
    t1, t2, t3, t4
  );
  b := polyDraw.bounds;
  if b.area = 0 then exit;
  for y := b.top to b.bottom-1 do begin
    sl := polyDraw.scanLine[y];
    tl := polyDraw.textLine[y];
    x1 := clamp(sl.xMin, 0, dstPage.width-1);
    x2 := clamp(sl.xMax, 0, dstPage.width-1);
    if (sl.xMax-sl.xMin) = 0 then continue;
    for x := x1 to x2 do begin
      f := (x-sl.xMin)/(sl.xMax-sl.xMin);
      t.x := trunc(lerp(tl.t1.x, tl.t2.x, f) / 65536);
      t.y := trunc(lerp(tl.t1.y, tl.t2.y, f) / 65536);
      dstPage.putPixel(x, y, srcPage.getPixel(t.x, t.y));
    end;
  end;
end;
