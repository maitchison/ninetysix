{globals for 8-byte alignment}
var
  p16, v16, s16, d16: V3D16;

{
  pos: position in voxelspace at xMin
}
procedure traceScanline_MMX(canvas: tPage; voxSprite: tVoxelSprite; xMin, xMax: int16; y: int16; pos, dir, delta: V3D);
var
  pagePtr, voxPtr: pointer;
  xCounter: int32;
  zCounter: int32;
  shiftCode: word;
  bias: V3D;
  depth: byte;
begin

  {todo: remove these checks, I just want to see what causes the issue}
  {~0.1ms}
  (*
  if dword(@(p16)) and $7 <> 0 then error('Alignment issue');
  if dword(@(v16)) and $7 <> 0 then error('Alignment issue');
  *)

  // add this bias to cause make256 to truncate instead of round.
  bias := V3D.create(-0.495/256, -0.495/256, -0.495/256);

  {0.3ms for these conversions}
  p16 := V3D16.make256(pos+bias);
  v16 := V3D16.make256(dir);
  s16 := V3D16.make(256*voxSprite.fWidth-1, 256*voxSprite.fHeight-1, 256*voxSprite.fDepth-1);
  d16 := V3D16.make256(delta);

  {this is needed due either bugs in my tracer, or precision issues}
  p16.x := clamp(p16.x, 0, s16.x);
  p16.y := clamp(p16.y, 0, s16.y);
  p16.z := clamp(p16.z, 0, s16.z);

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
    MM0    temp

    MM1    px|py|pz|00 (current position in trace)
    MM2    vx|vy|vz|00
    MM3    sx|sy|sz|00 (with bias)
    MM4    qx|qy|qz|00 (position at start of trace)
    MM5    80|80|80|80 (bias for unsigned compare)

    MM6    temp
    MM7    temp
    }

    movq      mm2, qword ptr [v16]
    movq      mm3, qword ptr [s16]
    movq      mm4, qword ptr [p16]

    mov       eax, $80008000
    movd      mm5, eax
    punpckldq mm5, mm5

    pxor      mm3, mm5

    @XLOOP:

      mov       zCounter, MAX_SAMPLES
      mov       depth, 0
      movq      mm1, mm4    // restore pos

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
      mov cl, depth
      shl cl, 1
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

    @FINISH:
      // update pos position
      paddsw    mm4, qword ptr [d16]
      add       edi, 4

      dec       xCounter
      jnz       @XLOOP

  @XLOOPEND:

    popad
    emms
    sti

  end;


end;
