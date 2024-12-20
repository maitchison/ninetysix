procedure clipAndConvert_ASM(bufSamples:int32);
var
  srcPtr, dstPtr: pointer;
begin

  srcPtr := @scratchBufferI32[0];
  dstPtr := @scratchBuffer[0];

  asm

    pushad

    mov ecx, bufSamples
    shl ecx, 1
    mov esi, srcPtr
    mov edi, dstPtr

  @LOOP:

    mov eax, [esi]
    sar eax, 8
    cmp eax, 32767
    jng @SkipOver
    mov eax, 32767
  @SkipOver:
    cmp eax, -32768
    jnl @SkipUnder
    mov eax, -32768
  @SkipUnder:
    mov [edi], eax

    add esi, 4
    add edi, 2
    dec ecx
    jnz @LOOP

    popad
  end;
end;

procedure process8S_ASM(sample, firstSample, finalSample: pAudioSample8S;count: dword);
var
  dstPointer: pointer;
begin
  if (pointer(sample) + count*2) >= finalSample then begin
    {we can't handle looping here, yet.}
    process8S_ASM(sample, firstSample, finalSample, count);
    exit;
  end;

  dstPointer := @scratchBufferI32[0];

  asm
    pushad
    mov esi, sample
    mov edi, dstPointer
    mov ecx, count

  @LOOP:

    {left}
    movzx eax, byte ptr [esi]
    sub eax, 128
    shl eax, 16
    add [edi], eax
    {right}
    movzx eax, byte ptr [esi+1]
    sub eax, 128
    shl eax, 16
    add [edi+4], eax

    add esi, 2
    add edi, 8

    dec ecx
    jnz @LOOP

    popad
  end;
end;

procedure process16S_ASM(sample, firstSample, finalSample: pAudioSample16S;count: dword);
var
  dstPointer: pointer;
begin
  if (pointer(sample) + count*4) >= finalSample then begin
    {we can't handle looping here, yet.}
    process16S_ASM(sample, firstSample, finalSample, count);
    exit;
  end;

  dstPointer := @scratchBufferI32[0];

  asm
    pushad
    mov   esi, sample
    mov   edi, dstPointer
    mov   ecx, count
    mov   ebx, 256

  @LOOP:

    {left}
    movsx eax, word ptr [esi]
    shl   eax, 8
    add   [edi], eax

    {right}
    movsx eax, word ptr [esi+2]
    shl   eax, 8
    add   [edi+4], eax

    add   esi, 4
    add   edi, 8

    dec   ecx
    jnz   @LOOP

    popad
  end;
end;
