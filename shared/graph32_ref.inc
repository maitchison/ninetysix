{reference routines for graph32, with full DrawContext support}

{note:
 at this point we assume all clipping and transform is done
}

procedure drawRect_REF(dstPage: tPage;aRect: tRect;col: RGBA;blendMode: tBlendMode);
var
  i,j: integer;
  dstPtr: pRGBA;
begin

  for j := 0 to aRect.height-1 do begin
    dstPtr := dstPage.getAddress(aRect.x, aRect.y+j);
    case blendMode of
      bmNone: ;
      bmBlit: filldword(dstPtr^, aRect.width, dword(col));
      bmBlend: for i := 0 to aRect.width-1 do begin
        dstPtr^ := RGBA.Blend(dstPtr^, col, col.a);
        inc(dstPtr);
      end;
    end;
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

  for j := 0 to srcRect.height-1 do begin
    srcPtr := srcPage.getAddress(srcRect.x, srcRect.y+j);
    dstPtr := dstPage.getAddress(dstX, dstY+j);
    case blendMode of
      bmNone: ;
      bmBlit:
        if not needsTint then begin
          move(srcPtr^, dstPtr^, srcRect.width*4);
        end else for i := 0 to srcRect.width-1 do begin
          dstPtr^ := srcPtr^ * tint;
          inc(srcPtr);
          inc(dstPtr);
        end;
      bmBlend:
        for i := 0 to srcRect.width-1 do begin
          src := srcPtr^;
          if needsTint then src := src * tint;
          if src.a <> 0 then dstPtr^ := RGBA.Blend(src, dstPtr^, src.a);
          inc(srcPtr);
          inc(dstPtr);
        end;
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
