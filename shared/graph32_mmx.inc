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
procedure blitImage_MMX(dstPixels, srcPixels: pointer; dstX, dstY, srcX, srcY, width, height: int32);
begin
end;

procedure tintImage_MMX(dstPixels, srcPixels: pointer; dstX, dstY, srcX, srcY, width, height: int32; tint: RGBA);
begin
end;

procedure blendImage_MMX(dstPixels, srcPixels: pointer; dstX, dstY, srcX, srcY, width, height: int32; tint: RGBA);
begin
end;

