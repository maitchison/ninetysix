{reference routines for graph32, with full DrawContext support}

{note:
 at this point we assume all clipping and transform is done
}

{very slow blending}
procedure blendCol_REF(pixels: pRGBA;count: int32;col: RGBA);
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

{draw an image segment to screen, no blending}
procedure blitImage_REF(dstPage, srcPage: tPage; dstX, dstY, srcX, srcY, width, height: int32);
var
  srcPtr: pRGBA;
  dstPtr: pRGBA;
  i: integer;
begin

  srcPtr := srcPage.getAddress(srcX, srcY);
  dstPtr := dstPage.getAddress(dstX, dstY);

  for i := 0 to height-1 do begin
    move(srcPtr^, dstPtr^, width*4);
    inc(srcPtr, srcPage.width);
    inc(dstPtr, dstPage.width);
  end;
end;

