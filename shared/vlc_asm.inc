procedure readVLC1Sequence_ASM(stream: tStream; n: int32;outBuffer: tDwords);
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

procedure readVLC2Sequence_ASM(stream: tStream; n: int32;outBuffer: tDwords);
var
  inPtr, outPtr: pointer;
  nibblesRead: dword;
  bytesRead: dword;
begin
  inPtr := stream.getCurrentBytesPtr;
  outPtr := @outBuffer[0];
  nibblesRead := 0;
  bytesRead := 0;

  {
  optimized read VLC

  EAX - 0|0|midbyte|current byte
  EBX - current value
  ECX - loop (n)
  EDX - 0|0|stream byte|tmp

  ESI - stream in
  EDI - stream out
  }

  //note: we can skip the jumps if we do a lookup table.

  asm
    pushad

    xor eax, eax
    xor ebx, ebx
    mov ecx, n
    mov esi, inPtr
    mov edi, outPtr

  @VLC_LOOP:
    inc nibblesRead
    cmp ah, 0                 //       i.e. when esi changes
    je @notMidByte

  @MidByte:
    mov al, dh
    inc esi
    and al, $0f
    xor ah, ah
    jmp @Process

  @NotMidByte:
    mov dh, byte ptr [esi]
    inc bytesRead
    mov al, dh
    inc ah
    shr al, 4

  @Process:

    // write the value
    mov dl, al
    and dl, $07
    or  bl, dl

    // check if this was the last nibble
    cmp dl, al
    jne @WriteValue

    // otherwise shift and repeat
    shl ebx, 3
    jmp @VLC_LOOP

  @WriteValue:
    mov [edi], ebx
    add edi, 4
    xor ebx, ebx
    mov nibblesRead, ebx  // reset nibbles counter
    loop @VLC_LOOP
  @Done:
    popad
  end;
  stream.advance(bytesRead);
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
