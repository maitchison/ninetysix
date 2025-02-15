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
begin
  polyDraw.scanPoly(dstPage, p1, p2, p3, p4);
  if polyDraw.bounds.area = 0 then exit;
  for y := polyDraw.bounds.top to polyDraw.bounds.bottom-1 do begin
    for x := polyDraw.scanLine[y].xMin to polyDraw.scanline[y].xMax do begin
      dstPage.putPixel(x, y, RGB(255,0,255));
    end;
  end;

end;

