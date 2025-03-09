{reference routines for graph32, with full DrawContext support}

{note:
 at this point we assume all clipping and transform is done
}

{very slow blending}
procedure blend_REF(pixels: pRGBA;count: int32;col: RGBA);
var
  i: integer;
  f: single;
begin
  f := (col.a/255);
  for i := 0 to count-1 do begin
    pixels^ := RGBA.Lerp(pixels^, col, f);
    inc(pixels);
  end;
end;

{draw an image segment to screen, no alpha}
procedure blit_REF(dstPage, srcPage: tPage; srcRect: tRect; atX,atY: int32);
var
  srcOfs: dword;
  dstOfs: dword;
  y, y1, y2: int32;
  x1,x2: int32;
  bytesToCopy: word;
  topCrop,leftCrop: int32;
begin

  y1 := max(atY, 0);
  y2 := min(atY+srcRect.height, dstPage.height-1);
  topCrop := y1-atY;

  x1 := max(atX, 0);
  x2 := min(atX+srcRect.width, dstPage.width-1);
  leftCrop := x1-atX;

  {might be off by one here}
  if y2 < y1 then exit;
  if x2 < x1 then exit;

  {todo adjust when cropping y on top}
  srcOfs := 4 * ((srcRect.x + leftCrop) + (srcRect.y+topCrop)*srcPage.width);
  dstOfs := 4 * (x1 + y1*dstPage.width);

  bytesToCopy := 4 * (x2-x1);

  for y := y1 to y2 do begin
    move((srcPage.pixels+srcOfs)^, (dstPage.pixels+dstOfs)^, bytesToCopy);
    srcOfs += srcPage.width * 4;
    dstOfs += dstPage.width * 4;
  end;
end;

