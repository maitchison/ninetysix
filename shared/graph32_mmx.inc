{$link graph32_nasm.obj}
procedure drawLine_Tint_Blend_MMX(); cdecl; external name 'drawLine_Tint_Blend_MMX';
procedure drawLine_Tint_MMX(); cdecl; external name 'drawLine_Tint_MMX';
procedure drawLine_Blend_MMX(); cdecl; external name 'drawLine_Blend_MMX';
procedure drawLine_MMX(); cdecl; external name 'drawLine_MMX';

procedure stretchLine_Tint_Blend_Nearest_MMX(); cdecl; external name 'stretchLine_Tint_Blend_Nearest_MMX';
procedure stretchLine_Blend_Nearest_MMX(); cdecl; external name 'stretchLine_Blend_Nearest_MMX';
procedure stretchLine_Tint_Nearest_MMX(); cdecl; external name 'stretchLine_Tint_Nearest_MMX';
procedure stretchLine_Nearest_MMX(); cdecl; external name 'stretchLine_Nearest_MMX';

procedure blitCol_MMX(pixels: pRGBA;count: int32;col: RGBA);
asm

  {this is almost 2x faster on real hardware}

  cli

  push edi
  push ecx
  push eax

  mov edi, PIXELS
  mov ecx, COUNT
  shr ecx, 2
  test ecx, ecx
  jz @FINAL

  mov   eax, COL
  movd  MM0, eax
  punpckldq MM0, MM0

@XLOOP:
  movq [edi], MM0
  movq [edi+8], MM0
  add edi, 16
  dec ecx
  jnz @XLOOP

@FINAL:
  mov ecx, COUNT
  and ecx, $3
  rep stosd

  pop eax
  pop ecx
  pop edi

  emms
  sti
end;

procedure blendCol_MMX(pixels: pointer;count: int32;col: RGBA);
asm
  // if mixer interrupt runs during the timer then we'll have
  // fpu in invalid state, so block them during the hline
  cli

  pushad

  mov edi, PIXELS

  {we need a zero register to expand from byte to word}
  pxor       mm0, mm0        // MM0 <-  0 0 0 0 | 0 0 0 0

  mov eax, COL
  bswap eax
  mov cl, al
  bswap eax

  {replicate alpha across the words}
  mov        ch, cl
  shl        ecx, 8
  mov        cl, ch
  movd       mm3, ecx
  punpcklbw  mm3, mm0        // MM3 <- 0 0 0 A | 0 A 0 A

  {replicate = 255-alpha accross the words}
  mov        cl, 255
  sub        cl, ch
  mov        ch, cl
  shl        ecx, 8
  mov        cl, ch
  movd       mm4, ecx
  punpcklbw  mm4, mm0      // MM4 <- 0 `A 0 `A | 0 `A 0 `A}

  {expand and premultiply our source color}
  movd       mm2, eax      // MM2 <-  0  0  0  0|  0 Rs Gs Bs
  punpcklbw  mm2, mm0      // MM2 <-  0  0  0 Rs|  0 Gs  0 Bs
  pmullw     mm2, mm3      // MM2 <-  0  A*Rs A*Gs A*bs

  mov       ecx, COUNT

@LOOP:
  {read source pixel}
  mov       edx, [edi]

  {do the blend}
  movd      mm1, edx      // MM1 <-  0  0  0  0|  0 Rd Gd Bd
  punpcklbw mm1, mm0      // MM1 <-  0  0  0 Rd|  0 Gd  0 Bd
  pmullw    mm1, mm4      // MM1 <-  0  (255-A)*Rd (255-A)*Gd (255-A)*bd
  paddw     mm1, mm2      // MM1 <- A*Rs+(255-A)*Rd ...
  psrlw     mm1, 8        // MM1 <- (A*Rs+(255-A)*Rd) / 256

  { note, we should have divided by 255 instead of 255 but I don't think
   anyone will notice. To reduce the error we could do a saturated subtract of 128
   which makes the expected error 0 over uniform input}
  packuswb  mm1, mm1      // MM1 = 0 0 0 0 | 0 R G B
  movd      eax, mm1

  mov dword ptr [edi], eax

  add edi, 4

  dec ecx
  jnz @LOOP

  popad

  emms

  sti

end;

procedure drawImage_MMX(dstPage, srcPage: tPage; dstX, dstY: int32; srcRect: tRect; tint: RGBA; blendMode: tBlendMode);
var
  srcPtr, dstPtr: pointer;
  srcStride, dstStride: dword;
  callProc: procedure cdecl;
  needsTint: boolean;
begin
  srcPtr := srcPage.getAddress(srcRect.x, srcRect.y);
  dstPtr := dstPage.getAddress(dstX, dstY);
  srcStride := (srcPage.width - srcRect.width) * 4;
  dstStride := (dstPage.width - srcRect.width) * 4;
  needsTint := int32(tint) <> -1;

  case blendMode of
    bmNone: exit;
    bmBlit: begin
      if needsTint then
        callProc := drawLine_Tint_MMX
      else
        callProc := drawLine_MMX;
    end;
    bmBlend: begin
      if needsTint then
        callProc := drawLine_Tint_Blend_MMX
      else
        callProc := drawLine_Blend_MMX;
    end;
  end;

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
    call      callProc
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
  needsTint: boolean;
  src: RGBA;
  tx,ty: dword;
  tdx,tdy: int32;
  linePtr: pointer;
  callProc: procedure cdecl;
begin

  if filter = tfLinear then begin
    {we don't currently support linear filtering...
     it wouldn't be too hard to put in though}
    stretchImage_REF(dstPage, srcPage, dstRect, srcX, srcY, srcDx, srcDy, tint, filter, blendMode);
    exit;
  end;

  needsTint := int32(tint) <> -1;

  {dispatch}
  {todo: build dispatch into nasm code}
  case blendMode of
    bmNone: exit;
    bmBlit: begin
      if needsTint then
        callProc := stretchLine_Tint_Nearest_MMX
      else
        callProc := stretchLine_Nearest_MMX;
    end;
    bmBlend: begin
      if needsTint then
        callProc := stretchLine_Tint_Blend_Nearest_MMX
      else
        callProc := stretchLine_Blend_Nearest_MMX;
    end;
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
      call callProc
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
