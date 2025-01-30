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

{only slightly faster (due to loop unrolling}
procedure initializeBuffer_ASM(samplePtr: pAudioSample16S; bufSamples: int32);
var
  srcPtr, dstPtr: pointer;
begin
  srcPtr := samplePtr;
  dstPtr := @scratchBufferI32[0];

  asm
    pushad

    mov ecx, bufSamples
    mov esi, srcPtr
    mov edi, dstPtr

  @LOOP:

    {left}
    movsx eax, word ptr [esi]
    shl eax, 8
    mov dword ptr [edi], eax
    {right}
    movsx eax, word ptr [esi+2]
    shl eax, 8
    mov dword ptr [edi+4], eax

    add esi, 4
    add edi, 8
    dec ecx
    jnz @LOOP

    popad

  end;
end;

{returns max(abs(prev-current))}
function clickDetection_ASM(prevSample: tAudioSample16S;samplePtr: pAudioSample16S; bufSamples:dword): int32;
var
  best: dword;
begin
  best := 0;
  asm
    pushad

    mov ecx, bufSamples
    mov esi, samplePtr

    movsx ebx, word ptr [prevSample.left]
    movsx ecx, word ptr [prevSample.right]

  @SampleLoop:

    {
      eax = mp
      ebx = current left
      ecx = current right
      edx = tmp
    }

  @Left:
    movsx edx, word ptr [esi]
    mov eax, edx
    sub eax, ebx      {eax = this-prev}
    mov ebx, edx
    cdq
    xor eax, edx
    sub eax, edx      {eax=abs(this-prev)}
    cmp eax, best
    jbe @SkipLeft
    mov best, eax
  @SkipLeft:

  @Right:
    movsx edx, word ptr [esi+2]
    mov eax, edx
    sub eax, ecx
    mov ecx, edx
    cdq
    xor eax, edx
    sub eax, edx      {eax=abs(eax)}
    cmp eax, best
    jbe @SkipRight
    mov best, eax
  @SkipRight:

    add esi, 4
    dec bufSamples   // just dec directly?
    jnz @SampleLoop

    popad
  end;
  result := best;
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

procedure standard16S(count: int32; samplePtr: pointer; sampleTick: int32; dstPtr: pointer;startVolume, endVolume: int32;pitch:int32);
var
  volumeDelta: int32;
begin
  asm
    pushad

    // eax = tmp
    // ebx = volume
    // ecx = sampleTick
    // edx = tmp


    // edi = destBuffer
    // esi = samplePtr

    mov   edi, dstPtr
    mov   eax, endVolume
    sub   eax, startVolume
    cdq
    mov   ecx, count
    idiv  ecx
    mov   ebx, startVolume
    mov   volumeDelta, eax
    mov   ecx, sampleTick

  @LOOP:

    {sample pos}
    mov   esi, ecx
    shr   esi, 8
    shl   esi, 2
    add   esi, samplePtr

    {volume}
    mov   edx, ebx
    shr   edx, 8

    {left}
    movsx eax, word ptr [esi]
    imul  eax, edx
    add   [edi], eax

    {right}
    movsx eax, word ptr [esi + 2]
    imul  eax, edx
    add   [edi+4], eax

    add   esi, 4
    add   edi, 8
    add   ebx, volumeDelta
    add   ecx, pitch

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

  case af of
    AF_16_STEREO: begin standard16S(count, samplePtr, sampleTick, dstPtr, startVolume, endVolume, pitch); exit(true); end;
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

