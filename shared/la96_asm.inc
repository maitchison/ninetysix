procedure process_ASM(sfxSamplePtr: pAudioSample16S; midCode, difCode: int32; midCodes,difCodes,midSigns,difSigns: tDwords; frameSpec: pFrameSpec);
var
  maxCounter: dword;
  shiftCode: word;
  centerMask: dword;
  left, right: word;
  midCodePtr, midSignPtr: pointer;
  difCodePtr, difSignPtr: pointer;
  midUTable,difUTable: pointer;
  MC,DC: int32;
  midCenter, difCenter: int32;
  i: integer;
begin
  maxCounter := frameSpec^.length-1;
  shiftCode := frameSpec^.midShift + (frameSpec^.difShift shl 8);
  centerMask := not ((1 shl frameSpec^.centerShift)-1);
  midCodePtr := @midCodes[0];
  midSignPtr := @midSigns[0];
  difCodePtr := @difCodes[0];
  difSignPtr := @difSigns[0];
  left := 0; right := 0; // make compiler happy
  MC := midCode;
  DC := difCode;
  midCenter := frameSpec^.cMid;
  difCenter := frameSpec^.cDif;
  if assigned(frameSpec^.difUTable) then difUTable := @frameSpec^.difUTable^.table.data[0] else difUTable := nil;
  if assigned(frameSpec^.midUTable) then midUTable := @frameSpec^.midUTable^.table.data[0] else midUTable := nil;

  {not yet supported
    Clipping (encoder should insure this does not happen)
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

    {process midcode add/subtract}
    mov esi, midCodePtr
    mov eax, dword ptr [esi+ecx*4]     // ebx = abs(midCode[i])
    mov esi, midSignPtr
    mov edx, dword ptr [esi+ecx*4]     // edx = signMask (0s for add, 1s for subtract)
    {this performs the following
     if mask is 1s then ebx = -ebx, if mask is 0s then ebx is unchanged}
    xor eax, edx
    sub eax, edx
    add eax, MC
    mov MC, eax                        // eax = MC + delta

    {process difcode add/subtract}
    mov esi, difCodePtr
    mov ebx, dword ptr [esi+ecx*4]     // ebx = abs(midCode[i])
    mov esi, difSignPtr
    mov edx, dword ptr [esi+ecx*4]     // edx = signMask (0s for add, 1s for subtract)
    xor ebx, edx
    sub ebx, edx
    add ebx, DC
    mov DC, ebx                        // ebx = DC + delta

    {
      eax=mid
      ebx=dif
    }

    {note: we could make the lookup table include negative numbers and make
     this a bit faster}

    {------------------------}
    {ULAW Mid}
    mov esi, MIDUTABLE
    test esi, esi
    jz @MID_DONE

    cmp eax, 0
    jl @MID_IS_NEG

  @MID_IS_POS:
    mov eax, dword ptr [esi+eax*4]
    jmp @MID_DONE

  @MID_IS_NEG:
    neg eax
    mov eax, dword ptr [esi+eax*4]
    neg eax
  @MID_DONE:

    {------------------------}
    {ULAW Dif}
    mov esi, difUTable
    test esi, esi
    jz @DIF_DONE

    cmp ebx, 0
    jl @DIF_IS_NEG

  @DIF_IS_POS:
    mov ebx, dword ptr [esi+ebx*4]
    jmp @DIF_DONE

  @DIF_IS_NEG:
    neg ebx
    mov ebx, dword ptr [esi+ebx*4]
    neg ebx
  @DIF_DONE:

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
    add eax, MIDCENTER    // eax = mid shl midShift + cDif
    add ebx, DIFCENTER    // ebx = mid shl midShift + cMid

    {update to new center}
    mov edx, eax
    and edx, CENTERMASK
    mov MIDCENTER, edx
    mov edx, ebx
    and edx, CENTERMASK
    mov DIFCENTER, edx

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

  {write back out our centering positions}
  frameSpec^.cMid := midCenter;
  frameSpec^.cDif := difCenter;

end;
