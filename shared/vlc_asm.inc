procedure readVLC1Sequence_ASM(inPtr,outPtr: pointer; n: int32);
begin
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
end;

procedure readVLC2Sequence_ASM(inPtr, outPtr: pointer;n: int32);
begin

  {
  optimized read VLC

  EAX - 0|0|0|current byte
  EBX - current value
  ECX - loop (n)
  EDX - 0|0|stream byte|tmp

  ESI - stream in
  EDI - stream out
  }

  asm
    pushad

    xor eax, eax
    xor ebx, ebx
    mov ecx, n
    mov esi, inPtr
    mov edi, outPtr

  @VLC_LOOP:

    mov al, byte ptr [esi]
    inc esi

  @DoNibble1:             // this one > 0xxx-0xxx
    mov ah, al            // al = ah = 0f
    shr ah, 4             // ah = 0
    and ah, $07           // ah = 0
    or  bl, ah            // bl = 0
    test al, $80          // 0
    jnz @WriteValue1      // sjup

    inc ebx               // ebx=1
    shl ebx, 3            // ebx=8
    jmp @DoNibble2        // jump

  @WriteValue1:
    mov [edi], ebx
    add edi, 4
    xor ebx, ebx
    dec ecx
    jz @Done

  @DoNibble2:             //            0xxx-0xxx < this one
    and  al, $0f
    mov ah, al
    and al, $07
    or  bl, al
    test ah, $08
    jnz @WriteValue2

    inc ebx
    shl ebx, 3
    jmp @VLC_LOOP

  @WriteValue2:
    mov [edi], ebx
    add edi, 4
    xor ebx, ebx
    dec ecx
    jnz @VLC_LOOP

  @Done:
    popad
  end;
end;

procedure unpack_ASM(inPtr, outPtr: pointer; n: dword;bitsPerCode: byte);
var
  i,j: int32;
  bitBuffer: dword;         { buffer for our bits }
  bitsRemaining: int32;     { number of bits left in the buffer }
  value: dword;             { current value being unpacked}
  mask: dword;              { mask for extracting bits}

begin

  {we require the following}
  {atleast 1 padding bytes left in buffer}
  {bits must be <= 16}
  if bitsPerCode > 16 then begin
    unpack_REF(inPtr, outPtr, n, bitsPerCode);
    exit;
  end;

  mask := (1 shl bitsPerCode) - 1;

  asm
    {
      eax = temp
      ebx = remaining dwords
      ecx = 0 0 [bitsPerCode] [bitsRemaining]
      edx = bitBuffer

      esi = inPtr
      edi = outPtr
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

{-------------------------------------------------------}
{ RICE }
{-------------------------------------------------------}


{fast inline asm rice code reader.
This function can only use the lookup table, which is 16bit, which means
 rice codes longer than this can not be used. For data where that matters
 we'd need to either use VLC2, or to (more likely) just pack the bits.
 the k divisor 15 = 32k, so max code representable would be 32k.
 Reading > 16bits is non-trival as it requires shifting a 64bit integer
 (so we can load 32bits at a time). Although maybe there would be a 20-bit
 hack I could do.
 I think for my case I'm fine as I'm really just using 8-but ulaw anyway.

 Hmm... maybe I should just implement the falt adjustment in asm...
 it's not that hard.
}
procedure ReadRice_ASM(inPtr, outPtr: pointer; n: int32; k: integer);
var
  tablePtr: pointer;
begin
  tablePtr := @RICE_TABLE[k, 0];
  asm

    pushad

    {
      eax   tmp
      ebx   bufferValue
      ecx   0  || tmp | bufferPos
      edx   loop

      esi   inPtr
      edi   outPtr
      ebp   tablePtr
    }

    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx

    mov edx, N

    mov esi, INPTR
    mov edi, OUTPTR

    push ebp
    mov ebp, TABLEPTR

  @DecodeLoop:
    {read word}
    cmp cl, 16
    jge @SkipRead
  @Read:
    movzx eax, word ptr [esi]
    add esi, 2

    shl eax, cl
    or  ebx, eax
    add cl, 16

  @SkipRead:
    movzx eax, bx                  // eax = 0  || next 16 buffer bits
    and ax, RICE_MASK              // should be a constant
    mov eax, dword ptr [ebp+eax*4] // eax = 0 | len || value

    {consume bits}
    mov ch, cl                  // ch = old buf len
    ror eax, 16                 // eax = value || 0 | len
    mov cl, al                  // cl = bits to burn
    shr ebx, cl                 // burn bits from buffer
    neg cl
    add cl, ch                  // ch = pos - bitsRead

    {write value}
    shr eax, 16                 // eax = 0 || value
    mov dword ptr [edi], eax    // outBuffer^ = code

    {end loop}
    add edi, 4
    dec edx
    jnz @DecodeLoop

    pop ebp

    popad

  end;
end;
