{reference routines for graph32, with full DrawContext support}

{note:
 at this point we assume all clipping and transform is done
}

procedure blitCol_REF(pixels: pRGBA;count: int32;col: RGBA);
begin
  filldword(pixels^, count, dword(col));
end;

{very slow blending}
procedure blendCol_REF(pixels: pRGBA;count: int32;col: RGBA);
var
  i: int32;
  f: single;
begin
  for i := 0 to count-1 do begin
    pixels^ := RGBA.Blend(pixels^, col, col.a);
    inc(pixels);
  end;
end;

{draw an image segment to screen, no blending}
procedure blitImage_REF(dstPage, srcPage: tPage; dstX, dstY: int32; srcRect: tRect);
var
  srcPtr: pRGBA;
  dstPtr: pRGBA;
  i: integer;
begin

  srcPtr := srcPage.getAddress(srcRect.x, srcRect.y);
  dstPtr := dstPage.getAddress(dstX, dstY);

  for i := 0 to srcRect.height-1 do begin
    move(srcPtr^, dstPtr^, srcRect.width*4);
    inc(srcPtr, srcPage.width);
    inc(dstPtr, dstPage.width);
  end;
end;

procedure drawImage_REF(dstPage, srcPage: tPage; dstX, dstY: int32; srcRect: tRect; tint: RGBA; blendMode: tBlendMode);
var
  i,j: integer;
  srcPtr: pRGBA;
  dstPtr: pRGBA;
  needsTint: boolean;
  src: RGBA;
begin

  needsTint := int32(tint) <> -1;

  if (blendMode = bmBlit) and (not needsTint) then begin
    blitImage_REF(dstPage, srcPage, dstX, dstY, srcRect);
    exit;
  end;

  for j := 0 to srcRect.height-1 do begin
    srcPtr := srcPage.getAddress(srcRect.x, srcRect.y+j);
    dstPtr := dstPage.getAddress(dstX, dstY+j);
    for i := 0 to srcRect.width-1 do begin
      src := srcPtr^;
      if needsTint then src := src * tint;
      case blendMode of
        bmBlit: dstPtr^ := src;
        bmBlend: if src.a <> 0 then
          dstPtr^ := RGBA.Blend(src, dstPtr^, src.a);
      end;
      inc(srcPtr);
      inc(dstPtr);
    end;
  end;
end;

{draw image stretched}
procedure stretchImage_REF(dstPage, srcPage: tPage; dstRect: tRect; srcX, srcY, srcDx, srcDy: single; tint: RGBA; filter: tTextureFilter; blendMode: tBlendMode);
var
  i,j: integer;
  dstPtr: pRGBA;
  needsTint: boolean;
  src: RGBA;
  tx,ty: single;
begin

  needsTint := int32(tint) <> -1;
  ty := srcY;
  for j := 0 to dstRect.height-1 do begin
    dstPtr := dstPage.getAddress(dstRect.x, dstRect.y+j);
    tx := srcX;
    for i := 0 to dstRect.width-1 do begin
      case filter of
        tfNearest: src := srcPage.getPixel(trunc(tx), trunc(ty));
        tfLinear: src := srcPage.getPixelF(tx-0.5, ty-0.5);
        else src.init(255,0,255);
      end;
      if src.a <> 0 then begin
        if needsTint then src := src * tint;
        if (src.a = 255) or (blendMode = bmBlit) then
          dstPtr^ := src
        else
          dstPtr^ := RGBA.Blend(src, dstPtr^, src.a);
      end;
      inc(dstPtr);
      tx += srcDx;
    end;
    ty += srcDy;
  end;
end;
