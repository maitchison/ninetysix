{draw an image segment to screen, no alpha}
procedure blit_ASM(dstPage, srcPage: tPage; srcRect: tRect; atX,atY: int16);
var
  srcOfs: dword;
  dstOfs: dword;
  y, y1, y2: int32;
  x1,x2: int32;
  bytesToCopy: word;
  topCrop,leftCrop: int32;
begin

  {todo: make this asm}

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

{draw an image segment, stretched}
{todo: needs a bit rewrite, I think just make it a generic stretch like
 voxel does (with scanline)}
{todo: remove this and just use polyDraw}
procedure stretchDraw_ASM(dstPage, srcPage: TPage; src, dst: tRect);
var
  deltaX, deltaY: int32;
  x,y: int32;
  v: single;
  sx, sy: uint32;
  screenOfs: uint32;
  imageOfs: uint32;
  cnt: uint16;
  dstPixels: pointer;
  dx1,dx2: integer;
  dy1,dy2: integer;

begin
  {todo: implement proper clipping}

  {for debugging...}
  //info(src.toString+' '+dst.toString);

  if (src.height <= 0) or (src.width <= 0) then
    exit;
  if (dst.height <= 0) or (dst.width <= 0) then
    exit;

  {todo: maybe only support power of 2 images...}
  {todo: linear interpolation with MMX, if we can...}
  deltaX := round(65536.0 * src.width / (dst.width));
  deltaY := round(65536.0 * src.height / (dst.height));

  if deltaX >= 0 then
    sx := src.left * 65536 + (65536 div (dst.width))
  else
    sx := src.right * 65536  - (65536 div (dst.width));
  if deltaY >= 0 then
    sy := src.top * 65536 + (65536 div (dst.height))
  else
    sy := src.bottom * 65536 - (65536 div (dst.height));

  dx1 := min(dst.left, dst.right);
  dx2 := max(dst.left, dst.right);
  dy1 := min(dst.top, dst.bottom);
  dy2 := max(dst.top, dst.bottom);

  {clipping}
  if dx1 < 0 then begin
    sx += deltaX * -dx1;
    dx1 := 0;
  end;

  cnt := dx2-dx1;
  if cnt <= 0 then exit;

  dstPixels := dstPage.Pixels;

  for y := dy1 to dy2-1 do begin
    if y >= dstPage.height then exit;
    imageOfs := sy div 65536;
    sy += deltaY;
    if y < 0 then continue;
    screenOfs := y * dstPage.width + dx1;
    imageOfs *= srcPage.width * 4;
    imageOfs += dword(srcPage.pixels);
    asm
      pushad

      mov edi, screenOfs
      shl edi, 2
      add edi, dstPixels

      movzx ecx, cnt

      mov edx, sx

    @LOOP:

      mov esi, edx
      shr esi, 16
      shl esi, 2
      add esi, imageOfs

      mov eax, ds:[esi]
      mov bl, ds:[esi+3]

      cmp bl, 0
      je @Skip
      cmp bl, 255
      je @Blit

    @Blend:

      push edx

      xor edx, edx
      mov bh, 255
      sub bh, bl

      {note: switch to MMX later}
      mov al, byte ptr ds:[esi+2]
      mul bl
      mov dl, ah
      mov al, byte ptr [edi+2]
      mul bh
      add dl, ah
      shl edx, 8

      mov al, byte ptr ds:[esi+1]
      mul bl
      mov dl, ah
      mov al, byte ptr [edi+1]
      mul bh
      add dl, ah
      shl edx, 8

      mov al, byte ptr ds:[esi+0]
      mul bl
      mov dl, ah
      mov al, byte ptr [edi+0]
      mul bh
      add dl, ah

      mov eax, edx
      pop edx
    @Blit:
      mov dword ptr [edi], eax
    @Skip:
      add edi, 4
      add edx, deltaX

      dec ecx
      jnz @LOOP

      popad
    end;
  end;
end;


procedure polyLine_ASM(screenPtr, texturePtr: pointer; texX, texY, texDeltaX, texDeltaY: int32;textureWidth, textureSize, cnt: dword);
asm
  pushad

  {todo: MMX version, four pixels at a time :) }

  {
    EAX   temp
    EBX   texX      X.X
    ECX   counter
    EDX   texY      Y.Y

    EDI   screen
    ESI   texture
  }

  mov edi, SCREENPTR
  mov esi, TEXTUREPTR

  xor eax, eax
  mov ebx, TEXX
  mov ecx, CNT
  mov edx, TEXY

@LOOP:

  {get our texel}
  {this would be much faster if texture width was 256}
  push edx
  xor eax, eax
  ror edx, 16
  mov ax, dx
  ror edx, 16
  mul dword ptr TEXTUREWIDTH    // eax = y * srcWidth
  ror ebx, 16
  add ax, bx                    // eax = y * srcWidth + x
  ror ebx, 16
  cmp eax, TEXTURESIZE
  jae @Skip
  mov eax, [esi+eax*4]
@Blit:
  mov dword ptr [edi], eax
@Skip:
  pop edx
  add edi, 4
  add ebx, TEXDELTAX
  add edx, TEXDELTAY

  dec ecx
  jnz @LOOP

  popad
end;

{
optimized version of polyLine when dims are 256x256
notes:
 - uses 8.8 instead of 16.16
 - always uses wrap method for out of bounds.
 - blit only (no alpha check)
}
procedure polyLine256_ASM(screenPtr, texturePtr: pointer; texX, texY, texDeltaX, texDeltaY: int32;textureWidth, textureSize, cnt: dword);
begin
  assertEqual(textureWidth, 256);
  assertEqual(textureSize, 65536);
asm
  pushad

  {
    EAX   temp
    EBX   texX      0|0|X.X
    ECX   counter
    EDX   texY      0|0|Y.Y

    EDI   screen
    ESI   texture
  }

  mov edi, SCREENPTR
  mov esi, TEXTUREPTR

  xor eax, eax
  mov ebx, TEXX
  sar ebx, 8
  mov ecx, CNT
  mov edx, TEXY
  sar edx, 8

  // convert from 16.16 to 8.8
  mov eax, texDeltaX
  sar eax, 8
  mov texDeltaX, eax
  mov eax, texDeltaY
  sar eax, 8
  mov texDeltaY, eax
  xor eax, eax
@PIXELLOOP:
  {get our texel}
  movzx eax, bh
  mov ah, dh
  mov eax, [esi+eax*4]
@ALPHATEST:
  rol eax,8
  cmp al, 0
  je @Skip
  cmp al, 255
  je @Blit
@Mix:

  {perform mixing (slow without MMX!)}
  push ebx
  push ecx
  push edx

  mov cl,  al
  mov ch,  255
  sub ch,  al

  // setup:

  ror eax, 8
  mov ebx, dword ptr [edi]

  // eax = sA|sR|sG|sB
  // ebx = dA|dR|dG|sB
  // ecx = ? | ? | 255 - alpha | alpha
  // edx = (used to store mixed result)

  {blue}
  mul cl                    // (al*cl->ax) -> ax = sR*alpha
  mov dl,  ah               // store results
  mov al,  bl
  mul ch
  add dl,  ah               // we now have src + dst
  ror eax, 8
  ror ebx, 8
  ror edx, 8
  {green}
  mul cl                    // (al*cl->ax) -> ax = sR*alpha
  mov dl,  ah               // store results
  mov al,  bl
  mul ch
  add dl,  ah               // we now have src + dst
  ror eax, 8
  ror ebx, 8
  ror edx, 8
  {red}
  mul cl                    // (al*cl->ax) -> ax = sR*alpha
  mov dl,  ah               // store results
  mov al,  bl
  mul ch
  add dl,  ah               // we now have src + dst
  ror eax, 8
  ror ebx, 8
  ror edx, 8

  // edx = r|g|b|-
  // last ror8 will be done by blit
  mov dl, 255
  mov eax, edx

  pop edx
  pop ecx
  pop ebx

@Blit:
  ror eax,8
  mov dword ptr [edi], eax
@Skip:
  add edi, 4
  add ebx, TEXDELTAX
  add edx, TEXDELTAY

  dec ecx
  jnz @PIXELLOOP

  popad
end;
end;

{draw an image stretched to fill poly}
procedure polyDraw_ASM(dstPage, srcPage: tPage; src: tRect; p1,p2,p3,p4: tPoint);
var
  y: integer;
  t: tPoint;
  f: single;
  sl: tScanLine;
  tl: tTextureLine;
  t1,t2,t3,t4: tUVCoord;
  tInitial, tDelta: tUVCoord;
  x1,x2: integer;
  b: tRect;
  {for asm}
  screenPtr, texturePtr: pointer;
  texX, texY, texDeltaX, texDeltaY: int32; // as 16.16
  textureWidth: dword;
  textureSize: dword;
  cnt: int32;
begin

  {src coords are inclusive-exclusive}
  t1 := UVCoord(src.topLeft) + UVCoord(0.5,0.5);
  t2 := UVCoord(src.topRight) + UVCoord(-0.5,0.5);
  t3 := UVCoord(src.bottomRight) + UVCoord(-0.5,-0.5);
  t4 := UVCoord(src.bottomLeft) + UVCoord(0.5,-0.5);
  polyDraw.scanTextured(
    dstPage,
    p1, p2, p3, p4,
    t1, t2, t3, t4
  );
  b := polyDraw.bounds;
  if b.area = 0 then exit;
  for y := b.top to b.bottom-1 do begin
    sl := polyDraw.scanLine[y];
    tl := polyDraw.textLine[y];
    x1 := clamp(sl.xMin, 0, dstPage.width-1);
    x2 := clamp(sl.xMax, 0, dstPage.width-1);
    cnt := (x2-x1)+1;
    if cnt <= 0 then continue;

    {get initial texture pos (as 16.16}
    if cnt = 1 then
      f := 0
    else
      f := (x1-sl.xMin)/(sl.xMax-sl.xMin);
    {todo: range check error here... I think just switch to simpler TX coord system}
    texX := trunc(lerp(tl.t1.x, tl.t2.x, f));
    texY := trunc(lerp(tl.t1.y, tl.t2.y, f));
    {get delta}
    f := ((x1+1)-sl.xMin)/(sl.xMax-sl.xMin);
    texDeltaX := trunc(lerp(tl.t1.x, tl.t2.x, f)) - texX;
    texDeltaY := trunc(lerp(tl.t1.y, tl.t2.y, f)) - texY;

    screenPtr := dstPage.pixels + (x1 + (y * dstPage.width)) * 4;
    texturePtr := srcPage.pixels;
    textureWidth := srcPage.width;
    textureSize := srcPage.width * srcPage.height;

    if (textureWidth = 256) and (textureSize = 65536) then
      polyLine256_ASM(screenPtr, texturePtr, texX, texY, texDeltaX, texDeltaY, textureWidth, textureSize, cnt)
    else
      polyLine_ASM(screenPtr, texturePtr, texX, texY, texDeltaX, texDeltaY, textureWidth, textureSize, cnt);

  end;
end;
