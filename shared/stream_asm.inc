function readVLCSequence_ASM(stream: tStream; n: int32;outBuffer: tDwords): tDWords;
var
  inPtr, outPtr: pointer;
  nibblesRead: dword;
begin
  inPtr := @stream.bytes[stream.pos];
  outPtr := @outBuffer[0];
  nibblesRead := 0;

  {
  optimized read VLC

  EAX - 0|0|midbyte|current byte
  EBX - current value
  ECX - 0|0|0|shift
  EDX - tmp

  ESI - stream in
  EDI - stream out
  }

  //note: we can skip the jumps if we do a lookup table.
  //note: it's a shame we don't store these in the opposite order
  //      I might fix that later on (e.g. so we always just shift the
  //      value, rather than shifting the new bits and adding

  asm
    pushad

    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    mov esi, inPtr
    mov edi, outPtr

  @VLC_LOOP:

    inc nibblesRead
    mov al, byte ptr [esi]    // todo: could do this read only as needed
    cmp ah, 0                 //       i.e. when esi changes
    je @notMidByte

  @MidByte:
    shr al, 4
    xor ah, ah
    inc esi
    jmp @Process

  @NotMidByte:
    and al, $0f
    inc ah

  @Process:
    xor edx, edx
    mov dl, al
    and dl, $07
    shl edx, cl
    add cl, 3
    add ebx, edx
    cmp al, $08
    jb  @WriteValue
    jmp @VLC_LOOP

  @WriteValue:
    mov [edi], ebx
    add edi, 4
    xor cl, cl
    xor ebx, ebx
    dec n
    jnz @VLC_LOOP

  @Done:

    popad

  end;

  stream.pos += (nibblesRead + 1) div 2;

end;
