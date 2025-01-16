procedure process_ASM(sfxSamplePtr: pAudioSample16S; midCode, difCode: int32; midCodes,difCodes,midSigns,difSigns: tDwords; frameSpec: pFrameSpec);
var
  maxCounter: dword;
  shiftCode: word;
  left, right: word;
  midCodePtr, midSignPtr: pointer;
  difCodePtr, difSignPtr: pointer;
  MC,DC: int32;
  i: integer;
begin
  maxCounter := frameSpec^.length-1;
  {todo: this might be around the wrong way}
  shiftCode := frameSpec^.midShift + (frameSpec^.difShift shl 8);
  midCodePtr := @midCodes[0];
  midSignPtr := @midSigns[0];
  difCodePtr := @difCodes[0];
  difSignPtr := @difSigns[0];
  MC := midCode;
  DC := difCode;

  {not yet supported
    ULAW
    Centering
    EMA
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
      eax = masked code
      ebx = code
      edx = sign mask
    }

    {process midcode add/subtract}
    mov esi, midCodePtr
    mov ebx, dword ptr [esi+ecx*4]     // ebx = abs(midCode[i])
    mov esi, midSignPtr
    mov edx, dword ptr [esi+ecx*4]     // edx = signMask (0s for add, 1s for subtract)
    {this performs the following
     if mask is 1s then ebx = -ebx, if mask is 0s then ebx is unchanged}
    xor ebx, edx
    sub ebx, edx
    add MC,  ebx

    {process difcode add/subtract}
    mov esi, difCodePtr
    mov ebx, dword ptr [esi+ecx*4]     // ebx = abs(midCode[i])
    mov esi, difSignPtr
    mov edx, dword ptr [esi+ecx*4]     // edx = signMask (0s for add, 1s for subtract)
    xor ebx, edx
    sub ebx, edx
    add DC,  ebx


    {convert mid+dif into sample}
    {
      cx = shiftCode
      eax = tmp
      ebx = tmp
      edx = tmp
    }

    push cx

    mov cx, shiftCode

    mov eax, MC
    shl eax, cl
    mov ebx, DC
    xchg cl, ch
    shl ebx, cl

    mov edx, eax
    add edx, ebx
    sar edx, 1
    mov LEFT, dx

    mov edx, eax
    sub edx, ebx
    sar edx, 1
    mov RIGHT, dx

    pop cx

    {write out sample}

    {
      eax = tmp
      edi = samplePtr
    }

    {todo: these might be swapped}
    mov ax, LEFT
    shl eax, 16
    mov ax, RIGHT
    mov dword ptr [edi+ecx*4], eax

    inc ecx
    cmp ecx, maxCounter
    jl @SAMPLE_LOOP

    popad
  end;
end;
