{trace ray at location and direction (in object space)}
function trace_ASM(voxPtr: pointer; pos: V3D16;dir: V3D16;size: V3D16;logWidth,logHeight: byte): RGBA;
var
  col: RGBA;
  depth: byte;
  counter: int32;
  d: int32;
begin

  counter := MAX_SAMPLES;
  depth := 0;

  asm

    pushad

    mov esi, voxPtr
    movsx ebx, word ptr pos.x
    movsx ecx, word ptr pos.y
    movsx edx, word ptr pos.z

    {
      EAX - tmp
      EBX - x * 256
      ECX - y * 256
      EDX - z * 256
      ESI - voxPixels
      EDI - tmp
    }

  @LOOP:

    {house keeping}
    inc VX_TRACE_COUNT

    {convert scaled, and check bounds}
    cmp bh,  byte ptr [size.x]
    jae @OUTOFBOUNDS
    cmp ch,  byte ptr [size.y]
    jae @OUTOFBOUNDS
    cmp dh,  byte ptr [size.z]
    jae @OUTOFBOUNDS

    // lookup our value
    push cx         // shift needs cl so we borrow it
    xor eax, eax
    mov al, dh
    mov cl, logHeight
    shl eax, cl
    or al, ch
    mov cl, logWidth
    shl eax, cl
    or al, bh
    pop cx

    mov eax, [esi + eax*4]

    // check if we hit something
    cmp eax, 255 shl 24
    jae @HIT


    // ------------------------------
    // mul step
    shr eax, 24     // get alpha
    not al          // d = 255-c.a
    mov d, eax
    add depth, al

    movsx eax, word ptr dir.x
    imul eax, d
    shr eax, 2
    add ebx, eax

    movsx eax, word ptr dir.y
    imul eax, d
    shr eax, 2
    add ecx, eax

    movsx eax, word ptr dir.z
    imul eax, d
    shr eax, 2
    add edx, eax

    dec counter
    jnz @LOOP

  @OUTOFSAMPLES:
    mov eax, $FFFF00FF
    mov col, eax
    jmp @FINISH

  @HIT:
    mov col, eax

    // shading
    mov cl, depth
    shl cl, 1
    not cl            // cl = (255-(depth*2))

    mov dl, $ff


    mov al, col.r
    mul cl
    shl edx, 8
    mov dl, ah
    mov al, col.g
    mul cl
    shl edx, 8
    mov dl, ah
    mov al, col.b
    mul cl
    shl edx, 8
    mov dl, ah      // r,g,b *= bl/256

    mov col, edx
    jmp @FINISH

  @OUTOFBOUNDS:
    xor eax, eax
    mov col, eax
    jmp @FINISH

  @FINISH:
    popad
  end;

  LAST_TRACE_COUNT := depth;
  result := col;

end;

procedure traceScanline_ASM(canvas: tPage; voxSprite: tVoxelSprite; xMin, xMax: int16; y: int16; pos, dir, deltaX, deltaY: V3D);
var
  x: int16;
  col: RGBA;
  p16, v16, d16, s16: V3D16;
begin

  p16 := V3D16.trunc(pos*256);
  v16 := V3D16.round(dir*256);
  d16 := V3D16.round(deltaX*256);
  s16 := voxSprite.getSize;

  for x := xMin to xMax-1 do begin

    col := trace_ASM(voxSprite.vox.pixels, p16, v16, s16, voxSprite.fLog2Width, voxSprite.fLog2Height);

    {show trace count}
    if VX_GHOST_MODE then
       col.init(LAST_TRACE_COUNT,LAST_TRACE_COUNT*4, LAST_TRACE_COUNT*16);

    {$R-}
    p16.x += d16.x;
    p16.y += d16.y;
    p16.z += d16.z;
    {$R+}

    if col.a > 0 then
      canvas.putPixel(x, y, col);
  end;
end;
