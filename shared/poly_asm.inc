procedure polyLine_ASM(screenPtr, texturePtr: pointer; texX, texY, texDeltaX, texDeltaY: int32;textureWidth, textureSize, cnt: dword);
asm
  pushad

  {todo: MMX version, four pixels at a time :) }

  {
    EAX   temp
    EBX   texX      X.X
    ECX   counter
    EDX   texY      Y.Y

    EDI   screen
    ESI   texture
  }

  mov edi, SCREENPTR
  mov esi, TEXTUREPTR

  xor eax, eax
  mov ebx, TEXX
  mov ecx, CNT
  mov edx, TEXY

@LOOP:

  {get our texel}
  {this would be much faster if texture width was 256}
  push edx
  xor eax, eax
  ror edx, 16
  mov ax, dx
  ror edx, 16
  mul dword ptr TEXTUREWIDTH    // eax = y * srcWidth
  ror ebx, 16
  add ax, bx                    // eax = y * srcWidth + x
  ror ebx, 16
  cmp eax, TEXTURESIZE
  jae @Skip
  mov eax, [esi+eax*4]
@Blit:
  mov dword ptr [edi], eax
@Skip:
  pop edx
  add edi, 4
  add ebx, TEXDELTAX
  add edx, TEXDELTAY

  dec ecx
  jnz @LOOP

  popad
end;

{
optimized version of polyLine when dims are 256x256
notes:
 - uses 8.8 instead of 16.16
 - always uses wrap method for out of bounds.
 - blit only (no alpha check)
}
procedure polyLine256_ASM(screenPtr, texturePtr: pointer; texX, texY, texDeltaX, texDeltaY: int32;textureWidth, textureSize, cnt: dword);
begin
  assertEqual(textureWidth, 256);
  assertEqual(textureSize, 65536);
asm
  pushad

  {
    EAX   temp
    EBX   texX      0|0|X.X
    ECX   counter
    EDX   texY      0|0|Y.Y

    EDI   screen
    ESI   texture
  }

  mov edi, SCREENPTR
  mov esi, TEXTUREPTR

  xor eax, eax
  mov ebx, TEXX
  sar ebx, 8
  mov ecx, CNT
  mov edx, TEXY
  sar edx, 8

  // convert from 16.16 to 8.8
  mov eax, texDeltaX
  sar eax, 8
  mov texDeltaX, eax
  mov eax, texDeltaY
  sar eax, 8
  mov texDeltaY, eax
  xor eax, eax
@PIXELLOOP:
  {get our texel}
  movzx eax, bh
  mov ah, dh
  mov eax, [esi+eax*4]
@ALPHATEST:
  rol eax,8
  cmp al, 0
  je @Skip
  cmp al, 255
  je @Blit
@Mix:

  {perform mixing (slow without MMX!)}
  push ebx
  push ecx
  push edx

  mov cl,  al
  mov ch,  255
  sub ch,  al

  // setup:

  ror eax, 8
  mov ebx, dword ptr [edi]

  // eax = sA|sR|sG|sB
  // ebx = dA|dR|dG|sB
  // ecx = ? | ? | 255 - alpha | alpha
  // edx = (used to store mixed result)

  {blue}
  mul cl                    // (al*cl->ax) -> ax = sR*alpha
  mov dl,  ah               // store results
  mov al,  bl
  mul ch
  add dl,  ah               // we now have src + dst
  ror eax, 8
  ror ebx, 8
  ror edx, 8
  {green}
  mul cl                    // (al*cl->ax) -> ax = sR*alpha
  mov dl,  ah               // store results
  mov al,  bl
  mul ch
  add dl,  ah               // we now have src + dst
  ror eax, 8
  ror ebx, 8
  ror edx, 8
  {red}
  mul cl                    // (al*cl->ax) -> ax = sR*alpha
  mov dl,  ah               // store results
  mov al,  bl
  mul ch
  add dl,  ah               // we now have src + dst
  ror eax, 8
  ror ebx, 8
  ror edx, 8

  // edx = r|g|b|-
  // last ror8 will be done by blit
  mov dl, 255
  mov eax, edx

  pop edx
  pop ecx
  pop ebx

@Blit:
  ror eax,8
  mov dword ptr [edi], eax
@Skip:
  add edi, 4
  add ebx, TEXDELTAX
  add edx, TEXDELTAY

  dec ecx
  jnz @PIXELLOOP

  popad
end;
end;