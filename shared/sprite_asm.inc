{draw an image segment to screen, no alpha}
procedure blit_ASM(dstPage, srcPage: TPage; srcRect: tRect; atX,atY: int16);
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
procedure stretchDraw_ASM(dstPage, srcPage: TPage; src, dst: tRect);
var
  deltaX, deltaY: int32;
  x,y: uint32;
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
  if (src.height <= 0) or (src.width <= 0) then
    fatal('Tried drawing sprite with invalid bounds: '+src.toString);

  {for debugging...}
  //Info(ShortString(src)+' '+ShortString(dst));

  {todo: maybe only support power of 2 images...}
  {todo: linear interpolation with MMX, if we can...}
  deltaX := round(65536.0 * src.width / dst.width);
  deltaY := round(65536.0 * src.height / dst.height);

  if deltaX >= 0 then
    sx := src.left * 65536 + (65536 div 2)
  else
    sx := src.right * 65536  - (65536 div 2);
  if deltaY >= 0 then
    sy := src.top * 65536
  else
    sy := src.bottom * 65536;

  dx1 := min(dst.left, dst.right);
  dx2 := max(dst.left, dst.right);
  dy1 := min(dst.top, dst.bottom);
  dy2 := max(dst.top, dst.bottom);

  {clipping}
  if dx1 < 0 then begin
    sx += deltaX * -dx1;
    dx1 := 0;
  end;

  cnt := (dx2-dx1)-1;
  if cnt <= 0 then exit;

  dstPixels := dstPage.Pixels;

  for y := dy1 to dy2-1 do begin
    if y > videoDriver.height then exit;
    if y < 0 then continue;
    v := (y - dy1) / (dy2 - dy1);
    screenOfs := y * videoDriver.width + dx1;
    imageOfs := min(src.top, src.bottom) + round(src.height * v);
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


{draw an image stretched to fill poly}
function polyDraw_ASM(dstPage, srcPage: tPage; src: tRect; p1,p2,p3,p4: tPoint): tRect;
var
  x, y: integer;
  t: tPoint;
  f: single;
  sl: tScanLine;
  tl: tTextureLine;
  t1,t2,t3,t4: tUVCoord;
  tInitial, tDelta: tUVCoord;
  x1,x2: integer;
  b: tRect;
  {for asm}
  cnt: integer;
  screenPtr, texturePtr: pointer;
  texPos, texDelta: int32; // as 8.8 | 8.8
  texX, texY, texDeltaX, texDeltaY: int32; // as 16.16
begin

  assertEqual(srcPage.width, 256);

  {stub:}
  //note('%s %s %s %s', [p1.toString, p2.toString, p3.toString, p4.toString]);

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
    x1 := clamp(sl.xMin, 0, dstPage.width-1);
    x2 := clamp(sl.xMax, 0, dstPage.width-1);
    if (sl.xMax-sl.xMin) = 0 then continue;

    {get initial texture pos (as 16.16}
    f := (x-sl.xMin)/(sl.xMax-sl.xMin);
    texX := trunc(lerp(tl.t1.x, tl.t2.x, f));
    texY := trunc(lerp(tl.t1.y, tl.t2.y, f));
    texPos := (texX div 256) + (texY div 256) shl 8;
    {get delta}
    f := ((x+1)-sl.xMin)/(sl.xMax-sl.xMin);
    texDeltaX := trunc(lerp(tl.t1.x, tl.t2.x, f)) - texX;
    texDeltaY := trunc(lerp(tl.t1.y, tl.t2.y, f)) - texY;
    texDelta := (texX div 256) + (texY div 256) shl 8;
                                             {
    screenPtr := dstPage.pixels + (x1 + (y * dstPath.width)) * 4;
    texturePtr := scr.pixels;
    cnt := sl.xMax-sl.xMin;                   }
    exit;
    (*
    asm
      pushad

      {todo: MMX version, four pixels at a time :) }

      {
        EAX   temp
        EBX   texPos      Y.Y | X.X
        EDX   texDelta

        ECX   counter

        EDI   screen
        ESI   texture


      }

      mov edi, screenPtr
      mov esi, texturePtr

      mov ebx, texPos
      mov edx, texY
      mov ecx, cnt

    @LOOP:

      {get our texture location (EAX)}
      mov al,  bh
      ror ebx, 16
      mov ah,  bh
      ror ebx, 16

      {lookup texel}
      mov eax, [esi+eax*4]


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
      *)
    {
    for x := x1 to x2 do begin
      f := (x-sl.xMin)/(sl.xMax-sl.xMin);
      t.x := trunc(lerp(sl.t1.x, sl.t2.x, f) / 65536);
      t.y := trunc(lerp(sl.t1.y, sl.t2.y, f) / 65536);
      dstPage.putPixel(x, y, srcPage.getPixel(t.x, t.y));
    end;
    }
  end;
end;
