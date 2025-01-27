function readVLCSequence_ASM(stream: tStream; n: int32;outBuffer: tDwords): tDWords;
var
  inPtr, outPtr: pointer;
  nibblesRead: dword;
begin
  inPtr := stream.getCurrentBytesPtr;
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

  stream.advance((nibblesRead + 1) div 2);

end;

procedure unpack_ASM(inBuffer: pByte;outBuffer: pDWord; n: dword;bitsPerCode: byte);
var
  i,j: int32;
  bitBuffer: dword;         { buffer for our bits }
  bitsRemaining: int32;     { number of bits left in the buffer }
  value: dword;             { current value being unpacked}
  mask: dword;              { mask for extracting bits}

  inPtr,outPtr: pointer;

begin

  {we require the following}
  {atleast 1 padding bytes left in buffer}
  {bits must be <= 16}
  if bitsPerCode > 16 then begin
    unpack_REF(inBUffer, outBuffer, n, bitsPerCode);
    exit;
  end;


  inPtr := @inBuffer^;
  outPtr := @outBuffer^;
  mask := (1 shl bitsPerCode) - 1;

  asm
    {
      eax = temp
      ebx = remaining dwords
      ecx = [bitsRemaining] [bitsPerCode] 0 0
      edx = bitBuffer

      esi = inBuffer
      edi = outBuffer
      ebp = mask

    }

    pushad

    xor eax,  eax
    mov ebx,  n
    mov cl,   0     // bitsRemaining=0
    mov ch,   bitsPerCode
    xor edx,  edx   // bitbuffer=0

    mov esi,  inPtr
    mov edi,  outPtr
    mov ebp,  mask

    @LOOP_START:

      {note: could be faster if we read 32 bits at a time.. just need padding bits}
      cmp cl, ch
      jae @SKIP_READ_VALUE

      { read value }
      { note: we assume there is atleast 1 spare bytes at the end of
        this array }
      movzx eax, word ptr ds:[esi]
      shl eax, cl
      or  edx, eax
      add esi, 2
      add cl, 16

    @SKIP_READ_VALUE:

      { extract code }
      mov eax, edx
      and eax, ebp
      mov dword ptr ds:[edi], eax
      add edi, 4

      {remove code from bit buffer}
      xchg cl, ch
      shr edx, cl
      xchg cl, ch
      sub cl, ch

      dec ebx
      jnz @LOOP_START

    popad

  end;
end;
