procedure clipAndConvert_MMX(bufSamples:int32);
var
  srcPtr, dstPtr, noisePtr: pointer;
  dummy: dword;
  {$align 16}
  // needs to be aligned to 16byte boundary, but I don't think
  // I can do that, so just pad some bytes and hope for the best.
  FPUState: array[0..108-1] of byte;
  dummy2: dword;
begin

  srcPtr := @scratchBufferI32[0];
  dstPtr := @scratchBuffer[0];
  noisePtr := @mixer.noiseBuffer[0];

  asm

    add noiseCounter, 1997

    pushad

    fsave FPUState
    fwait

    mov ecx, bufSamples
    mov esi, srcPtr
    mov edi, dstPtr

  @LOOP:

    {noise}
    mov ebx, noiseCounter
    and ebx, $FFFF
    shl ebx, 2
    add ebx, noisePtr
    movq mm1, qword ptr [ebx]

    add noiseCounter, 97

    {convert and clip}
    movq   mm0, [esi]            // mm0 = LEFT|RIGHT
    paddd mm0, mm1              // mm0 = LEFT+noise|RIGHT+noise}
    psrad  mm0, 8                // mm0 = (LEFT+noise)/256|(RIGHT+noise)/256
    packssdw mm0, mm0            // mm0 = left|right|left|right (16bit)

    movd [edi], mm0

    add esi, 8
    add edi, 4
    dec ecx
    jnz @LOOP

    frstor FPUState
    popad
  end;
end;