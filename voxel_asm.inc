var
  lastTraceCount: dword = 0;

{trace ray at location and direction (in object space)}
function trace_ASM(voxPtr: pointer; pos: V3D16;dir: V3D16): RGBA;
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

    mov edi, voxPtr
    movsx ebx, word ptr pos.x
    movsx ecx, word ptr pos.y
    movsx edx, word ptr pos.z

  @LOOP:

    {house keeping}
    inc VX_TRACE_COUNT

    {convert scaled, and check bounds}
    cmp bh,  64
    jae @OUTOFBOUNDS
    cmp ch,  32
    jae @OUTOFBOUNDS
    cmp dh,  18
    jae @OUTOFBOUNDS

    // lookup our value
    xor eax, eax
    mov al, dh
    shl eax, 5
    or al, ch
    shl eax, 6
    or al, bh

    mov eax, [edi + eax*4]

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

  lastTraceCount := depth;
  result := col;

end;

procedure traceScanline_ASM(canvas: tPage; voxPtr: pointer; xMin, xMax: int16; y: int16; pos, dir, delta: V3D);
var
  x: int16;
  col: RGBA;
  p16, v16, d16: V3D16;
  bias: V3D;
begin

  // make256 will use round, this converts it into a trunc}
  bias := V3D.create(0.499/256, 0.499/256, 0.499/256);

  p16 := V3D16.make256(pos-bias);
  v16 := V3D16.make256(dir);
  d16 := V3D16.make256(delta);

  for x := xMin to xMax do begin

    col := trace_ASM(voxPtr, p16, v16);
    {show trace count}
    if VX_GHOST_MODE then
       col.init(lastTraceCount,lastTraceCount*4, lastTraceCount*16);

    {$R-}
    p16.x += d16.x;
    p16.y += d16.y;
    p16.z += d16.z;
    {$R+}

    if col.a > 0 then
      canvas.putPixel(x, y, col);
  end;
end;
