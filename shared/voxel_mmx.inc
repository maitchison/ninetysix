{globals for 8-byte alignment}
var
  v16, s16: V3D16;
  p32, d32, s32: V3D32;

{
  pos: position in voxelspace at xMin
}
procedure traceScanline_MMX(canvas: tPage; voxSprite: tVoxel; xMin, xMax: int16; y: int16; pos, dir, deltaX, deltaY: V3D);
var
  pagePtr, voxPtr: pointer;
  xCounter: int32;
  zCounter: int32;
  shiftCode: word;
  depth: byte;
begin

  {todo: remove these checks, I just want to see what causes the issue}
  {~0.1ms}
  (*
  if dword(@(p16)) and $7 <> 0 then error('Alignment issue');
  if dword(@(v16)) and $7 <> 0 then error('Alignment issue');
  *)

  {0.3ms for these conversions}
  v16 := V3D16.round(dir*256);
  s16 := V3D16.make(256*voxSprite.fWidth-1, 256*voxSprite.fHeight-1, 256*voxSprite.fDepth-1);

  // higher precision
  p32 := V3D32.round(pos*65536);
  d32 := V3D32.round(deltaX*65536);

  {this is needed due either bugs in my tracer, or precision issues}
  p32.x := clamp(p32.x, 0, 65536*256*voxSprite.fWidth-1);
  p32.y := clamp(p32.y, 0, 65536*256*voxSprite.fHeight-1);
  p32.z := clamp(p32.z, 0, 65536*256*voxSprite.fDepth-1);

  //stub
  if keyDown(key_i) then begin
    p32.x := p32.x div 65536 * 65536;
    p32.y := p32.y div 65536 * 65536;
    p32.z := p32.z div 65536 * 65536;
    d32.x := d32.x div 65536 * 65536;
    d32.y := d32.y div 65536 * 65536;
    d32.z := d32.z div 65536 * 65536;
  end;

  shiftCode := voxSprite.fLog2Height + voxSprite.fLog2Width * 256;

  pagePtr := canvas.pixels + ((y * canvas.width) + xMin) * 4;
  voxPtr := voxSprite.vox.pixels;

  xCounter := (xMax-xMin); // exlusive of final pixel
  if xCounter <= 0 then exit;

  asm
    // if an interupt occurs the FPU will be in an invalid state.
    cli
    pushad

    {x-loop setup}
    mov esi, voxPtr
    mov edi, pagePtr

    // todo: move all memory values into registers

    {
      EAX tmp
      EBX tmp
      ECX tmp
      EDX tmp
      ESI srcVoxels
      EDI dstPixels

      (not in registers)
      shiftcode       - move to register and use xchg
      depth           - move to register
      zCounter        - move to register
      VX_TRACE_COUNT  - can do this once at the end

    }

    {
    //todo: move tmp to last 4 registers?
    MM0    tmp
    MM1    px|py|pz|00 (current position in trace)
    MM2    vx|vy|vz|00 (veloictiy within trace)
    MM3    sx|sy|sz|00 (with bias)
    MM4    tmp
    MM5    80|80|80|80 (bias for unsigned compare)
    MM6    tmp
    MM7    tmp
    }

    movq      mm2, qword ptr [v16]
    movq      mm3, qword ptr [s16]

    mov       eax, $80008000
    movd      mm5, eax
    punpckldq mm5, mm5

    pxor      mm3, mm5

    @XLOOP:

      mov       zCounter, MAX_SAMPLES
      mov       depth, 0

      // get the high words from our 32bit position
      movq      mm1, qword ptr [p32]
      movq      mm6, qword ptr [p32+8]
      psrad     mm1, 8
      psrad     mm6, 8
      packssdw  mm1, mm6     // mm1 = pos

      // clamping.. such a shame
      pxor      mm0, mm0
      pcmpgtw   mm0, mm1     // mm0 = (pos < 0)
      pandn     mm0, mm1     // mm0 = (pos >= 0) * pos
      movq      mm1, mm0     // mm1 = (pos >= 0) * pos

      movq      mm0, mm1     // mm0 = pos
      movq      mm6, qword ptr [s16] // mm6 = size
      movq      mm7, mm6     // mm7 = size
      pcmpgtw   mm6, mm0     // mm6 = (pos < size)
      movq      mm4, mm6     // mm4 = (pos < size)

      pand      mm0, mm6     // mm0 = (pos < size) * pos

      pandn     mm4, mm7     // mm4 = (pos >= size) * size
      paddw     mm0, mm4     // mm0 = (pos >= size) * size + (pos < size) * pos

      movq      mm1, mm0     // mm1 = clamped position


    @ZLOOP:

      {house keeping}
      inc VX_TRACE_COUNT

      {check bounds}
      movq      mm0, mm1
      pxor      mm0, mm5    // perform unsigned compare
      pcmpgtw   mm0, mm3    // is pos > sx or pos < 0 ?
      psrlq     mm0, 1      // shift right by 1 bit so that lower 32 bits
                            // contains a little of each of RGB masks.
      movd      eax, mm0
      test      eax, eax
      jnz @FINISH

      // lookup our value
      movq      mm0, mm1
      psrlw     mm0, 8
      packuswb  mm0, mm0
      movd      eax, mm0    // eax = 0xyz (unscaled)

      mov ebx, eax          // ax = yz
      shr ebx, 16           // bx = 0x

      mov cx, shiftCode
      xor edx, edx
      or dl, bl
      shl edx, cl
      shr cx, 8
      or dl, ah
      shl edx, cl
      or dl, al

      mov eax, [esi + edx*4]

      // check if we hit something
      cmp eax, 255 shl 24
      jae @HIT

      // perform our step
      shr eax, 24     // get alpha
      not al          // d = 255-c.a
      add depth, al

      mov bx, ax
      shl eax, 16
      mov ax, bx            // eax = 0d|0d

      movd      mm6, eax    // 00|00|0d|0d
      punpckldq mm6, mm6    // 0d|0d|0d|0d

      movq      mm0, mm2
      pmullw    mm0, mm6    // v *= d
      psraw     mm0, 2
      paddsw    mm1, mm0    // p += v * (d/4)

      dec zCounter
      jnz @ZLOOP

    @OUTOFSAMPLES:
      mov eax, $FFFF00FF    // write purple to indicate an issue
      mov [edi], eax
      jmp @FINISH

    @HIT:
      // shading
      // we'll use this for depth based shading
      (*
      mov cl, depth
      shl cl, 1             // todo: shading as part of sprite
      not cl                // cl = v = (255-(depth*2))

      mov ch, cl
      mov bx, cx
      shl ecx, 16
      mov cx, bx            // ecx = vv|vv

      pxor      mm0, mm0    // 00|00|00|00

      movd      mm6, ecx    // 00|00|vv|vv
      punpcklbw mm6, mm0    // 0v|0v|0v|0v

      movd      mm7, eax    // 00|00|ar|gb
      punpcklbw mm7, mm0    // 0a|0r|0g|0b

      pmullw    mm6, mm7    // aa|rr|gg|bb
      psrlw     mm6, 8      // 0a|0r|0g|0b

      packuswb  mm6, mm6    // 00|00|ar|gb
      movd      eax, mm6
      mov       [edi], eax
      *)
      mov       [edi], eax

    @FINISH:

      // update position
      movq      mm6, qword ptr [p32]
      paddd     mm6, qword ptr [d32]
      movq      qword ptr [p32], mm6
      movq      mm7, qword ptr [p32+8]
      paddd     mm7, qword ptr [d32+8]
      movq      qword ptr [p32+8], mm7

      add       edi, 4

      dec       xCounter
      jnz       @XLOOP

  @XLOOPEND:

    popad
    emms
    sti

  end;


end;
