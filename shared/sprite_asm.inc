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
