
type
  MMX16 = packed record
    case integer of
      0: (x,y,z,w: int16);
      1: (value: qword);
    end;

const
  c256: single = 256.0;

function toMMX(v: V3D): MMX16; inline;
var
  o: MMX16;
begin
(*
  // not sure why this doesn't work right now
  asm
    // note: could be done with adding to the expontent,
    // but fmul is fast enough.
    fld dword ptr [v.x]
    fmul dword ptr [c256]
    fistp word ptr [o.x]
    fld dword ptr [v.y]
    fmul dword ptr [c256]
    fistp word ptr [o.y]
    fld dword ptr [v.z]
    fmul dword ptr [c256]
    fistp word ptr [o.z]
    mov [o.w], 0
  end;
  result := o;*)
  {$R-,Q-}
  result.x := round(v.x * 256);
  result.y := round(v.y * 256);
  result.z := round(v.z * 256);
  result.w := 0;
  {$R+,Q+}
end;

{
  pos: position in voxelspace at xMin
}
procedure traceScanline_MMX(canvas: tPage; voxPtr: pointer; xMin, xMax: int16; y: int16; pos, dir, delta: V3D);
var
  x: int16;
  p, v, s, d: MMX16;
  col: RGBA;
  depth: byte;
  counter: int32;
  pagePtr: pointer;
begin

  p := toMMX(pos);
  v := toMMX(dir);
  s.x := 64-1; s.y := 32-1; s.z := 18-1; s.w := 0;
  d := toMMX(delta);

  pagePtr := canvas.pixels + ((y * canvas.width) + xMin) * 4;

  for x := xMin to xMax do begin

    counter := MAX_SAMPLES;
    depth := 0;

    asm

      pushad

      mov esi, voxPtr
      mov edi, pagePtr

      {
        MM1    px|py|pz|00
        MM2    vx|vy|vz|00
        MM3    sx|sy|sz|00
        MM4    00|00|00|00
      }

      movq      mm1, qword ptr [p]
      movq      mm2, qword ptr [v]
      movq      mm3, qword ptr [s]
      pxor      mm4, mm4

    @LOOP:

      {house keeping}
      inc VX_TRACE_COUNT

      {convert scaled, and check bounds}
      {this could be much faster I think}
      movq      mm0, mm1
      psraw     mm0, 8
      pcmpgtw   mm0, mm3    // pos > sx?
      movq      mm5, mm0
      pxor      mm0, mm0
      pcmpgtw   mm0, mm1    // 0 > pos?
      por       mm0, mm5    // (pos > sx) or (pos < 0)

      xor       eax, eax
      movd      ebx, mm0
      or        eax, ebx
      psrlq     mm0, 32
      movd      ebx, mm0
      or        eax, ebx

      test      eax, eax
      jnz @OUTOFBOUNDS      // todo: could be much faster


      // lookup our value
      movq      mm0, mm1
      psraw     mm0, 8
      packuswb  mm0, mm0
      movd      col, mm0    // ebx = 0xyz (unscaled)

      xor eax, eax
      mov al, col.r
      shl eax, 5
      or al, col.g
      shl eax, 6
      shr ebx, 8
      or al, col.b

      mov eax, [esi + eax*4]

      // check if we hit something
      cmp eax, 255 shl 24
      jae @HIT

      // ------------------------------
      // perform out step
      shr eax, 24     // get alpha
      not al          // d = 255-c.a
      add depth, al

      mov bx, ax
      shl eax, 16
      mov ax, bx            // eax = 0d|0d

      movd      mm5, eax    // 00|00|0d|0d
      punpckldq mm5, mm5    // 0d|0d|0d|0d

      movq      mm0, mm2
      pmullw    mm0, mm5    // v *= d
      psraw     mm0, 2
      paddw     mm1, mm0    // p += v * (d/4)

      dec counter
      jnz @LOOP

    @OUTOFSAMPLES:
      mov eax, $FFFF00FF    // purple
      mov col, eax
      jmp @FINISH

    @HIT:
      mov col, eax

      // shading
      // only 2ms on benchmark
      // todo: make this MMX
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

      // set pixel(x,y,col)
      // col is in edx
      mov [edi], edx


      jmp @FINISH

    @OUTOFBOUNDS:
      xor eax, eax
      mov col, eax
      jmp @FINISH

    @FINISH:

      // update position
      movq mm0, p
      movq mm1, d
      paddsw mm0, mm1
      movq p, mm0

      add pagePtr, 4

      popad

      // todo: inline the setPixel and retain the MMX registers

    end;


    //if col.a > 0 then
    //  canvas.setPixel(x, y, col);
  end;

  asm
    emms
  end;
end;
