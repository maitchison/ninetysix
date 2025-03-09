{reference routines for graph32, with full DrawContext support}

procedure putPixel_REF(const dc: tDrawContext; pos: tPoint;col: RGBA);
var
  pixels: pRGBA;
begin
  pos := dc.transform(pos);
  if not dc.clip.isInside(pos.x, pos.y) then exit;
  pixels := dc.page.getAddress(pos.x, pos.y);
  case dc.blendMode of
    bmBlit: pixels^ := col;
    bmBlend: begin
      if col.a = 0 then exit;
      if col.a = 255 then
        pixels^ := col
      else
        pixels^ := RGBA.Lerp(pixels^, col, col.a/255);
    end;
  end;
end;

                (*
{Draw line from (x1,y) to (x2,y) inclusive at start and exclusive at end.}
procedure hLine_REF(const dc: tDrawContext; x1,y,x2: int16; c: RGBA); pascal;
var
  x: int32;
  count: int32;
  ofs: dword;
begin

  if c.a = 0 then exit;

  {clipping}
  if word(y) >= self.Height then exit;
  if x1 < 0 then x1 := 0;
  if x2 > self.width then x2 := self.width;
  count := x2-x1;
  if count <= 0 then exit;

  ofs := (y * self.Width + x1) * 4;

  if c.a = 255 then begin
    {fast, no blending, path}
    filldword((self.pixels+ofs)^, count, dword(c));
    exit;
  end;

  if not cpuInfo.hasMMX then begin
    for x := x1 to x2 do
      putPixel(x, y, c);
    exit;
  end;

  {MMX blending path}
  asm

    // if mixer interrupt runs during thi timer then we'll have
    // fpu in invalid state, so block them during the hline
    cli

    pushad

    mov esi, self

    mov edi, [esi].Pixels
    add edi, ofs

    {we need a zero register to expand from byte to word}
    pxor       mm0, mm0        // MM0 <-  0 0 0 0 | 0 0 0 0

    mov eax, c
    mov cl, c[3]

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

    mov       ecx, count

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

end;

{draw line from (x,y1) to (x,y2) inclusive at start and exclusive at end.}
procedure vLine_REF(const dc: tDrawContext; x,y1,y2: int16; c: RGBA);
var
  y: int32;
  tmp: int32;
begin
  y1 := clamp(y1, 0, height);
  y2 := clamp(y2, 0, height);
  if y1 > y2 then begin
    tmp := y1; y1 := y2; y2 := tmp;
  end;
  // +1 should be wrong... but we need it for some reason?
  for y := y1 to y2+1 do
    putPixel(x, y, c);

end;

procedure fillRect_REF(aRect: TRect; c: RGBA);
var
  y: integer;
begin
  for y := aRect.top to aRect.bottom-1 do
    self.Hline(aRect.left, y, aRect.right, c);
end;

procedure drawRect_REF(aRect: TRect; c: RGBA);
var
  x,y: integer;
begin
  for x := aRect.left to aRect.right-1 do begin
    PutPixel(x,aRect.top,c);
    PutPixel(x,aRect.bottom-1,c);
  end;
  for y := aRect.top to aRect.bottom-1 do begin
    PutPixel(aRect.left,y,c);
    PutPixel(aRect.right-1,y,c);
  end;
end;
                  *)