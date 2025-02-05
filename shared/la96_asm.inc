procedure process_ASM(sfxSamplePtr: pAudioSample16S; midCode, difCode: int16; midCodes,difCodes: tWords; frameSpec: pFrameSpec);
var
  maxCounter: dword;
  shiftCode: word;
  left, right: word;
  midCodePtr, difCodePtr: pointer;
  midUTable,difUTable: pointer;
  MC,DC: int32;
  i: integer;
begin

  maxCounter := frameSpec^.length-1;
  shiftCode := frameSpec^.midShift + (frameSpec^.difShift shl 8);
  midCodePtr := @midCodes[0];
  difCodePtr := @difCodes[0];
  left := 0; right := 0; // make compiler happy
  MC := midCode;
  DC := difCode;
  if assigned(frameSpec^.difUTable) then difUTable := frameSpec^.difUTable^.tableCenterPtr else difUTable := nil;
  if assigned(frameSpec^.midUTable) then midUTable := frameSpec^.midUTable^.tableCenterPtr else midUTable := nil;

  {not yet supported
    Clipping (will implement in MMX version..)
  }

  asm

    pushad

    {note: mmx would help a bit here with the register issues, and with
     saturation}

    {
      eax   tmp
      ebx   tmp
      ecx   counter
      edx   tmp

      esi   tmp
      edi   samplePtr
    }

    mov eax, 0
    mov ebx, 0
    mov ecx, 0
    mov edx, 0

    mov esi, 0
    mov edi, sfxSamplePtr

    {
    MMX would look like this...

    MM0   tmp
    MM1   [difCode]  [midCode]
    MM2   [dMidCode] [d
    MM5   [left]     [right]

    process is

    Read and pack deltaCodes (it's a shame there are not interleaved)
    MMX addition
    MMX shift

    MMX shift
    MMX mid+dif -> left right
    MMX clamp
    }


  @SAMPLE_LOOP:

    {
      eax = free
      ebx = tmp
      ecx = reserved (i)
      edx = tmp
    }

    {process midcode}
    mov esi, midCodePtr
    movzx eax, word ptr [esi+ecx*2]     // ebx = abs(midCode[i])
    mov edx, eax
    shr eax, 1
    and edx, 1
    neg edx
    xor eax, edx
    add eax, MC
    mov MC, eax                        // eax = MC + delta

    {process difcode}
    mov esi, difCodePtr
    movzx bx, word ptr [esi+ecx*2]     // ebx = abs(midCode[i])
    mov edx, ebx
    shr ebx, 1
    and edx, 1
    neg edx
    xor ebx, edx
    add ebx, DC
    mov DC, ebx                        // ebx = DC + delta

    {
      eax=mid
      ebx=dif
    }

    {note: we could make the lookup table include negative numbers and make
     this a bit faster}

    {------------------------}
    {ULAW}

    mov esi, MIDUTABLE
    test esi, esi
    jz @Skip
    mov eax, dword ptr [esi+eax*4]
    mov esi, DIFUTABLE
    mov ebx, dword ptr [esi+ebx*4]
  @Skip:

    {at this point
      eax = mid
      ebx = dif
    }

    {multiply mid and shift by our quantization level, and adjust for centering}
    push cx
    mov cx, SHIFTCODE

    shl eax, cl
    xchg cl, ch
    shl ebx, cl

    mov edx, eax
    add edx, ebx
    mov LEFT, dx

    mov edx, eax
    sub edx, ebx
    mov RIGHT, dx
    pop cx

    {write out sample}
    {
      eax = tmp
      edi = samplePtr
    }

    mov ax, RIGHT
    shl eax, 16
    mov ax, LEFT
    mov dword ptr [edi+ecx*4], eax

    inc ecx
    cmp ecx, maxCounter
    jl @SAMPLE_LOOP

    popad
  end;

end;
