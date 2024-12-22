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

procedure direct16S(count: int32; srcPtr, dstPtr: pointer);
begin
  {direct copy case}
  asm
    pushad
    mov   esi, srcPtr
    mov   edi, dstPtr
    mov   ecx, count
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

procedure direct8S(count: int32; srcPtr, dstPtr: pointer);
begin
  {direct copy case}
  asm
    pushad
    mov   esi, srcPtr
    mov   edi, dstPtr
    mov   ecx, count
  @LOOP:
    {left}
    movzx eax, byte ptr [esi]
    sub   eax, 128
    shl   eax, 16
    add   [edi], eax
    {right}
    movzx eax, byte ptr [esi+1]
    sub   eax, 128
    shl   eax, 16
    add   [edi+4], eax
    add   esi, 2
    add   edi, 8
    dec   ecx
    jnz   @LOOP
    popad
  end;
end;

procedure standard16S(count: int32; srcPtr, dstPtr: pointer;startVolume, endVolume: int32);
begin
  {standard case (but no pitch ... yet)}
  asm
    pushad

    mov   esi, srcPtr
    mov   edi, dstPtr

    // ebx = startVolume
    // ecx = volumeDelta
    mov   eax, endVolume
    sub   eax, startVolume
    cdq
    mov   ecx, count
    idiv  ecx
    mov   ebx, startVolume
    mov   ecx, eax

  @LOOP:

    {left}
    movsx eax, word ptr [esi]
    mov   edx, ebx
    shr   edx, 8
    imul  eax, edx
    add   [edi], eax

    {right}
    movsx eax, word ptr [esi+2]
    mov   edx, ebx
    shr   edx, 8
    imul  eax, edx
    add   [edi+4], eax

    add   esi, 4
    add   edi, 8
    add   ebx, ecx

    dec   count
    jnz   @LOOP

    popad
  end;
end;

function processAudio_ASM(
  af: tAudioFormat;
  sampleTick: int32; samplePtr: pointer; sampleLength: dword;
  bufferPos: int32; count: int32;
  startVolume: int32 = 256*256;
  endVolume: int32 = 256*256;
  pitch: int32 = 256
): boolean;
var
  srcPtr, dstPtr: pointer;
begin

  if count <= 0 then exit(true);
  if AF_SIZE[af] = 0 then exit(false);

  srcPtr := samplePtr + (sampleTick div 256) * AF_SIZE[af];
  dstPtr := @scratchBufferI32[bufferPos];

  if (startVolume = 65536) and (endVolume = 65536) and (pitch = 256) then begin
    case af of
      AF_16_STEREO: begin direct16S(count, srcPtr, dstPtr); exit(true); end;
      AF_8_STEREO: begin direct8S(count, srcPtr, dstPtr); exit(true); end;
    end;
  end;

  if (pitch = 256) then begin
    case af of
      AF_16_STEREO: begin standard16S(count, srcPtr, dstPtr, startVolume, endVolume); exit(true); end;
    end;
  end;

  {fall back to reference in cases we don't handle}
  result := processAudio_REF(
    af,
    sampleTick, samplePtr, sampleLength,
    bufferPos, count,
    startVolume, endVolume,
    pitch
  );
end;

