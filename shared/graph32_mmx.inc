{$link graph32_nasm.obj}
procedure drawLine_MMX(); cdecl; external name 'DrawLine_MMX';
procedure colLine_MMX(); cdecl; external name 'ColLine_MMX';
procedure stretchLineNearest_MMX(); cdecl; external name 'StretchLineNearest_MMX';

function getCallCode(blendMode: tBlendMode; tint: RGBA): int32;
begin
  result := 0;
  case blendMode of
    bmNone: exit(-1);
    bmBlend: result += 1;
  end;
  if int32(tint) <> -1 then result += 2;
end;

procedure drawRect_MMX(dstPage: tPage; aRect: tRect; col: RGBA; blendMode: tBlendMode);
var
  dstPtr: pointer;
  dstStride: dword;
  callCode: int32;
begin

  callCode := getCallCode(blendMode, RGBA.White);
  if callCode < 0 then exit;

  dstPtr := dstPage.getAddress(aRect.pos.x, aRect.pos.y);
  dstStride := (dstPage.width - aRect.width) * 4;

  asm
    cli
    pushad
    mov       edi, DSTPTR
    mov       ebx, ARECT.HEIGHT
    pxor      mm0, mm0
    mov       eax, $00ff00ff
    movd      mm3, eax
    punpckldq mm3, mm3
  @YLOOP:
    mov       ecx, ARECT.WIDTH
    push      ebx
    mov       eax, CALLCODE
    mov       ebx, COL
    call      colLine_MMX
    pop       ebx
    add       edi, DSTSTRIDE
    dec       ebx
    jnz      @YLOOP
    popad
    emms
    sti
  end;
end;


procedure drawImage_MMX(dstPage, srcPage: tPage; dstX, dstY: int32; srcRect: tRect; tint: RGBA; blendMode: tBlendMode);
var
  srcPtr, dstPtr: pointer;
  srcStride, dstStride: dword;
  callCode: int32;
begin

  callCode := getCallCode(blendMode, tint);
  if callCode < 0 then exit;

  srcPtr := srcPage.getAddress(srcRect.x, srcRect.y);
  dstPtr := dstPage.getAddress(dstX, dstY);
  srcStride := (srcPage.width - srcRect.width) * 4;
  dstStride := (dstPage.width - srcRect.width) * 4;

  asm
    cli
    pushad
    mov esi, SRCPTR
    mov edi, DSTPTR
    mov ebx, SRCRECT.HEIGHT

    {MM0 <- 0}
    pxor      MM0, MM0
    {MM2 <- tintColor as int16}
    movd      MM2, TINT
    punpcklbw MM2, MM0
    {MM3 <- bias}
    mov       eax, $00ff00ff
    movd      MM3, eax
    punpckldq MM3, MM3

  @YLOOP:
    mov       ecx, SRCRECT.WIDTH
    push      ebx
    mov       eax, CALLCODE
    call      drawLine_MMX
    pop       ebx

    add esi, SRCSTRIDE
    add edi, DSTSTRIDE
    dec ebx
    jnz @YLOOP
    popad
    emms
    sti
  end;
end;

{draw image stretched}
procedure stretchImage_MMX(dstPage, srcPage: tPage; dstRect: tRect; srcX, srcY, srcDx, srcDy: single; tint: RGBA; filter: tTextureFilter; blendMode: tBlendMode);
var
  i,j: integer;
  dstPtr: pRGBA;
  src: RGBA;
  tx,ty: dword;
  tdx,tdy: int32;
  linePtr: pointer;
  callCode: dword;
begin

  callCode := getCallCode(blendMode, tint);
  if callCode < 0 then exit;

  if filter = tfLinear then begin
    {we don't currently support linear filtering...
     it wouldn't be too hard to put in though}
    stretchImage_REF(dstPage, srcPage, dstRect, srcX, srcY, srcDx, srcDy, tint, filter, blendMode);
    exit;
  end;

  tdx := round(srcDx*65536);
  tdy := round(srcDy*65536);
  tx := round((srcX)*65536);
  ty := round(srcY*65536);

  for j := 0 to dstRect.height-1 do begin
    dstPtr := dstPage.getAddress(dstRect.x, dstRect.y+j);
    linePtr := srcPage.getAddress(0, trunc(srcY+(srcDy*j)));

    {todo: setup once and don't call emms every line}
    asm
      cli
      pushad
      mov       esi, LINEPTR
      mov       edi, DSTPTR
      mov       ecx, DSTRECT.WIDTH
      mov       ebx, TX
      mov       edx, TDX
      pxor      mm0, mm0
      movd      mm2, TINT
      punpcklbw mm2, mm0
      mov       eax, 255
      movd      mm3, eax
      punpcklwd mm3, mm3
      punpckldq mm3, mm3
      mov       eax, CALLCODE
      call      stretchLineNearest_MMX
      popad
      emms
      sti
    end;
  end;
end;

{bilinear sampling with MMX
 seems to not be much faster though?
}
(*
  asm
    cli

    {MM0 <- 0}
    pxor      MM0, MM0
    {MM6 <- acc (set to bias)}
    mov       eax, 255
    movd      MM6, eax
    punpcklwd MM6, MM6
    punpckldq MM6, MM6
  @Pixel1:
    movd      MM1, C1
    punpcklbw MM1, MM0
    mov       eax, P1
    add       eax, 255
    shr       eax, 8
    movd      MM5, eax
    punpcklwd MM5, MM5
    punpckldq MM5, MM5
    pmullw    MM1, MM5
    paddusw   MM6, MM1
  @Pixel2:
    movd      MM1, C2
    punpcklbw MM1, MM0
    mov       eax, P2
    add       eax, 255
    shr       eax, 8
    movd      MM5, eax
    punpcklwd MM5, MM5
    punpckldq MM5, MM5
    pmullw    MM1, MM5
    paddusw   MM6, MM1
  @Pixel3:
    movd      MM1, C3
    punpcklbw MM1, MM0
    mov       eax, P3
    add       eax, 255
    shr       eax, 8
    movd      MM5, eax
    punpcklwd MM5, MM5
    punpckldq MM5, MM5
    pmullw    MM1, MM5
    paddusw   MM6, MM1
  @Pixel4:
    movd      MM1, C4
    punpcklbw MM1, MM0
    mov       eax, P4
    add       eax, 255
    shr       eax, 8
    movd      MM5, eax
    punpcklwd MM5, MM5
    punpckldq MM5, MM5
    pmullw    MM1, MM5
    paddusw   MM6, MM1

    {write out value}
    psrlw     MM6, 8
    packuswb  MM6, MM6

    movd      eax, MM6
    mov       SLN, eax

    emms
    sti
  end;
  *)
