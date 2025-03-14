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

{this is just a movq version... might not be that much faster that movsd}
procedure blitImage_MMX(dstPage, srcPage: tPage; dstX, dstY: int32; srcRect: tRect);
var
  srcPtr, dstPtr: pointer;
  srcStride, dstStride: dword;
begin
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
  @YLOOP:
    mov ecx, SRCRECT.WIDTH
    shr ecx, 2
    test ecx, ecx
    jz @FINAL

  @XLOOP:
    movq MM0, [esi]
    movq MM1, [esi+8]
    movq [edi], MM0
    movq [edi+8], MM1
    add edi, 16
    add esi, 16
    dec ecx
    jnz @XLOOP

  @FINAL:
    mov ecx, SRCRECT.WIDTH
    and ecx, $3
    rep movsd

    add esi, SRCSTRIDE
    add edi, DSTSTRIDE
    dec ebx
    jnz @YLOOP
    popad
    emms
    sti
  end;
end;

{modulate color, but no blending}
procedure tintImage_MMX(dstPage, srcPage: tPage; dstX, dstY: int32; srcRect: tRect; tint: RGBA);
var
  srcPtr, dstPtr: pointer;
  srcStride, dstStride: dword;
begin

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
    {MM1 <- tintColor as int16}
    movd      MM1, TINT
    punpcklbw MM1, MM0
    {MM3 <- bias}
    mov       eax, $00ff00ff
    movd      MM3, eax
    punpckldq MM3, MM3

  @YLOOP:
    mov       ecx, SRCRECT.WIDTH

  @XLOOP:
    movd      MM2, [esi]
    punpcklbw MM2, MM0    // convert to 16bit.

    pmullw    MM2, MM1    // modulate
    paddw     MM2, MM3    // add bias
    psrlw     MM2, 8      // divide
    packuswb  MM2, MM2
    movd      [edi], MM2

    add edi, 4
    add esi, 4
    dec ecx
    jnz @XLOOP

    add esi, SRCSTRIDE
    add edi, DSTSTRIDE
    dec ebx
    jnz @YLOOP
    popad
    emms
    sti
  end;
end;

procedure blendImage_MMX(dstPage, srcPage: tPage; dstX, dstY: int32; srcRect: tRect; tint: RGBA);
var
  srcPtr, dstPtr: pointer;
  srcStride, dstStride: dword;
begin
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
    {MM1 <- tintColor as int16}
    movd      MM1, TINT
    punpcklbw MM1, MM0
    {MM3 <- bias}
    mov       eax, $00ff00ff
    movd      MM3, eax
    punpckldq MM3, MM3

  @YLOOP:
    mov       ecx, SRCRECT.WIDTH

  @XLOOP:
    {MM2 <- sARGB}
    movd      MM2, [esi]
    punpcklbw MM2, MM0    // convert to 16bit.

    {tint}
    {MM2 <- sARGB * tint}
    pmullw    MM2, MM1    // modulate with tint
    paddw     MM2, MM3    // add bias
    psrlw     MM2, 8      // divide

    {eax <- sA * tint}
    {alpha test}
    movq      MM7, MM2
    psrlq     MM7, 48
    movd      eax, MM7
    cmp       al, 0
    je @SKIP
    cmp       al, 255
    je @BLIT

  @BLEND:

    {MM6 <- dARGB}
    movd      MM6, [edi]
    punpcklbw MM6, MM0    // convert to 16bit.

    {expand alpha}
    {maybe a lookup for this is better?}
    {MM4 <- 0a0a0a0a}
    movd      MM4, eax
    punpcklwd MM4, MM4
    punpckldq MM4, MM4
    {MM5 <- 0(1-a)0(1-a)0(1-a)0(1-a)}
    movq      MM5, MM3      // 255
    psubw     MM5, MM4      // 255-a

    {blend}
    {MM2 <- a * (sARGB * tint) * (1-a) * dARGB) + bias}
    pmullw    MM2, MM4
    pmullw    MM6, MM5
    paddw     MM2, MM6
    paddw     MM2, MM3
    psrlw     MM2, 8

  @BLIT:

    {blit}
    packuswb  MM2, MM2
    movd      [edi], MM2

  @SKIP:

    add edi, 4
    add esi, 4
    dec ecx
    jnz @XLOOP

    add esi, SRCSTRIDE
    add edi, DSTSTRIDE
    dec ebx
    jnz @YLOOP
    popad
    emms
    sti
  end;

end;

procedure blendImage_MMX_fast(dstPage, srcPage: tPage; dstX, dstY: int32; srcRect: tRect);
var
  srcPtr, dstPtr: pointer;
  srcStride, dstStride: dword;
begin
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
    {MM3 <- bias}
    mov       eax, $00ff00ff
    movd      MM3, eax
    punpckldq MM3, MM3

  @YLOOP:
    mov       ecx, SRCRECT.WIDTH

  @XLOOP:
    {MM2 <- sARGB}
    mov       eax, [esi]
    movd      MM2, eax
    shr       eax, 24
    punpcklbw MM2, MM0    // convert to 16bit.

    {alpha test}
    cmp       al, 0
    je @SKIP
    cmp       al, 255
    je @BLIT

  @BLEND:

    {MM6 <- dARGB}
    movd      MM6, [edi]
    punpcklbw MM6, MM0    // convert to 16bit.

    {expand alpha}
    {maybe a lookup for this is better?}
    {MM4 <- 0a0a0a0a}
    movd      MM4, eax
    punpcklwd MM4, MM4
    punpckldq MM4, MM4
    {MM5 <- 0(1-a)0(1-a)0(1-a)0(1-a)}
    movq      MM5, MM3      // 255
    psubw     MM5, MM4      // 255-a

    {blend}
    {MM2 <- a * (sARGB * tint) * (1-a) * dARGB) + bias}
    pmullw    MM2, MM4
    pmullw    MM6, MM5
    paddw     MM2, MM6
    paddw     MM2, MM3
    psrlw     MM2, 8

  @BLIT:

    {blit}
    packuswb  MM2, MM2
    movd      [edi], MM2

  @SKIP:

    add edi, 4
    add esi, 4
    dec ecx
    jnz @XLOOP

    add esi, SRCSTRIDE
    add edi, DSTSTRIDE
    dec ebx
    jnz @YLOOP
    popad
    emms
    sti
  end;
end;

procedure stretchLine_MMX_Blend(linePtr, dstPtr: pointer; tx, tdx, count: int32; tint:RGBA); assembler; pascal;
asm
  cli
  pushad
  {
   optimization:
    we could process two pixels at a time here...
  {

    mm0 = 0
    mm1 = dstColor
    mm2 = -
    mm3 = srcColor
    mm4 = tint color
    mm5 = bias (255)
    mm6 = alpha
    mm7 = 255-alpha


    esi = texture
    edi = screen

    ebx = textureX*65536
    ecx = counter
    edx = textureDX*65536
  }

  mov       esi, LINEPTR
  mov       edi, DSTPTR

  pxor      mm0, mm0

  mov       ecx, count
  mov       ebx, TX
  mov       edx, TDX

  movd      mm4, TINT
  punpcklbw mm4, mm0

  mov       eax, 255
  movd      mm5, eax
  punpcklwd mm5, mm5
  punpckldq mm5, mm5

@XLOOP:

  {MM3 <- sARGB}
  mov       eax, ebx
  shr       eax, 16
  movd      mm3, [esi+eax*4]
  punpcklbw mm3, mm0

  {MM3 <= sARGB*tint}
  pmullw    mm3, mm4
  paddw     mm3, mm5      // add bias
  psrlw     mm3, 8

@BLEND:
  {eax <- alpha*tint}
  movq      mm2, mm3
  psrlq     mm2, 48
  movd      eax, mm2
  cmp      al, 0
  je       @ENDOFLOOP
  cmp       al, 255
  je       @BLIT
  {mm1 <- dstColor}
  movd      mm1, [edi]
  punpcklbw mm1, mm0
  {mm6 <- 0a0a0a0a}
  movd      mm6, eax
  punpcklwd mm6, mm6
  punpckldq mm6, mm6
  {mm7 <- 0(1-a)0(1-a)0(1-a)0(1-a)}
  movq      mm7, mm5      // 255
  psubw     mm7, mm6      // 255-a
  {mm3 <- a * (sARGB * tint) * (1-a) * dARGB) + bias}
  pmullw    mm3, mm6
  pmullw    mm1, mm7
  paddw     mm3, mm1      // +dst
  paddw     mm3, mm5      // bias
  psrlw     mm3, 8

@BLIT:
  packuswb  mm3, mm3
  movd      [edi], mm3

@ENDOFLOOP:
  add   ebx, edx
  add   edi, 4

  dec ecx
  jnz @XLOOP

  popad
  emms
  sti
end;

procedure stretchLine_MMX_Blit(linePtr, dstPtr: pointer; tx, tdx, count: int32; tint:RGBA); assembler; pascal;
asm
  cli
  pushad

  mov       esi, LINEPTR
  mov       edi, DSTPTR

  pxor      mm0, mm0

  mov       ecx, COUNT
  mov       ebx, TX
  mov       edx, TDX

  movd      mm4, TINT
  punpcklbw mm4, mm0

  mov       eax, 255
  movd      mm5, eax
  punpcklwd mm5, mm5
  punpckldq mm5, mm5

@XLOOP:

  {MM3 <- sARGB}
  mov       eax, ebx
  shr       eax, 16
  movd      mm3, [esi+eax*4]
  punpcklbw mm3, mm0

  {MM3 <= sARGB*tint}
  pmullw    mm3, mm4
  paddw     mm3, mm5      // add bias
  psrlw     mm3, 8
@BLIT:
  packuswb  mm3, mm3
  movd      [edi], mm3

@ENDOFLOOP:
  add       ebx, edx
  add       edi, 4

  dec ecx
  jnz @XLOOP

  popad
  emms
  sti
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
begin

  if filter = tfLinear then begin
    {we don't currently support linear filtering...
     it wouldn't be too hard to put in though}
    stretchImage_REF(dstPage, srcPage, dstRect, srcX, srcY, srcDx, srcDy, tint, filter, blendMode);
    exit;
  end;

  needsTint := int32(tint) <> -1;
  tdx := round(srcDx*65536);
  tdy := round(srcDy*65536);

  ty := round(srcY*65536);
  for j := 0 to dstRect.height-1 do begin
    dstPtr := dstPage.getAddress(dstRect.x, dstRect.y+j);
    linePtr := srcPage.getAddress(0, trunc(srcY+(j*srcDy)));
    tx := round((srcX)*65536);
    case blendMode of
      bmBlit: stretchLine_MMX_Blit(linePtr, dstPtr, tx, tdx, dstRect.width, tint);
      bmBlend: stretchLine_MMX_Blend(linePtr, dstPtr, tx, tdx, dstRect.width, tint);
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
