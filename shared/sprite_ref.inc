{draw an image segment to screen}
procedure blit_REF(dstPage, srcPage: tPage; srcRect: tRect; atX,atY: int32);
var
  x,y: int32;
  dst: tRect;
begin
  dst := Rect(atX, atY, srcRect.width, srcRect.height);
  dst.clipTo(Rect(0, 0, videoDriver.width, videoDriver.height));
  for y := dst.top to dst.bottom-1 do
    for x := dst.left to dst.right-1 do
      dstPage.setPixel(x, y, srcPage.getPixel(x+srcRect.x-atX, y+srcRect.y-atY));
end;

{draw an image segment to screen}
procedure draw_REF(dstPage, srcPage: tPage; srcRect: tRect; atX,atY: int32);
var
  x,y: int32;
  dst: tRect;
begin
  dst := Rect(atX, atY, srcRect.width, srcRect.height);
  dst.clipTo(Rect(0, 0, videoDriver.width, videoDriver.height));
  for y := dst.top to dst.bottom-1 do
    for x := dst.left to dst.right-1 do
      dstPage.putPixel(x, y, srcPage.getPixel(x+srcRect.x-atX, y+srcRect.y-atY));
end;

{draw an image stretched to fill poly}
function polyDraw_REF(dstPage, srcPage: tPage; src: tRect; p1,p2,p3,p4: tPoint): tRect;
var
  x, y: integer;
  t: tPoint;
  z: single;
  sl: tScanLine;
  width: integer;
  t1,t2,t3,t4: tUVCoord;
  b: tRect;
begin

  {src coords are inclusive-exclusive}
  t1 := UVCoord(src.topLeft) + UVCoord(0.5,0.5);
  t2 := UVCoord(src.topRight) + UVCoord(-0.5,0.5);
  t3 := UVCoord(src.bottomRight) + UVCoord(-0.5,-0.5);
  t4 := UVCoord(src.bottomLeft) + UVCoord(0.5,-0.5);
  polyDraw.scanTextured(
    dstPage,
    p1, p2, p3, p4,
    t1, t2, t3, t4
  );
  b := polyDraw.bounds;
  if b.area = 0 then exit;
  for y := b.top to b.bottom-1 do begin
    sl := polyDraw.scanLine[y];
    width := (sl.xMax - sl.xMin) + 1;
    for x := 0 to width-1 do begin
      z := x / (width-1);
      t.x := trunc(lerp(sl.t1.x, sl.t2.x, z) / 65536);
      t.y := trunc(lerp(sl.t1.y, sl.t2.y, z) / 65536);
      dstPage.putPixel(x + sl.xMin, y, srcPage.getPixel(t.x, t.y));
    end;
  end;
end;

