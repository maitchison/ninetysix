var
  lastTraceCount: dword = 0;

{trace ray at location and direction (in object space)}
function trace_ASM(voxPtr: pointer; pos: V3D;dir: V3D): RGBA;
var
  col: RGBA;
  vx,vy,vz: int32;
  sx,sy,sz: int32;
  depth: byte;
  counter: int32;
  d: int32;
const
  MAX_SAMPLES = 64;
begin

  {todo: switch to V3D16 inputs}
  sx := trunc(256*pos.x);
  sy := trunc(256*pos.y);
  sz := trunc(256*pos.z);
  vx := round(256*dir.x);
  vy := round(256*dir.y);
  vz := round(256*dir.z);

  counter := MAX_SAMPLES;
  depth := 0;

  asm

    pushad

    mov edi, voxPtr
    mov ebx, sx
    mov ecx, sy
    mov edx, sz

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

    mov eax, vx
    imul eax, d
    shr eax, 2
    add ebx, eax

    mov eax, vy
    imul eax, d
    shr eax, 2
    add ecx, eax

    mov eax, vz
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

begin

  for x := xMin to xMax do begin

    col := trace_ASM(voxPtr, pos, dir);
    {show trace count}
    if VX_GHOST_MODE then
       col.init(lastTraceCount,lastTraceCount*4, lastTraceCount*16);

    {AA}
    {
    c1 := trace(pos+cameraX*0.25+cameraY*0.25, cameraZ);
    c2 := trace(pos-cameraX*0.25+cameraY*0.25, cameraZ);
    c3 := trace(pos-cameraX*0.25-cameraY*0.25, cameraZ);
    c4 := trace(pos+cameraX*0.25-cameraY*0.25, cameraZ);
    c := c*0.2+c1*0.2+c2*0.2+c3*0.2+c4*0.2;
    }

    pos += delta;
    if col.a > 0 then
      canvas.putPixel(x, y, col);
  end;
end;
