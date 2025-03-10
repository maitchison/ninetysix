procedure blitCol_ASM(pixels: pRGBA;count: int32;col: RGBA);
asm
  push edi
  push ecx
  push eax

  mov edi, PIXELS
  mov ecx, COUNT
  mov eax, COL
  rep stosd

  pop eax
  pop ecx
  pop edi
end;

procedure blitImage_ASM(dstPage, srcPage: tPage; dstX, dstY, srcX, srcY, width, height: int32);
var
  srcPtr, dstPtr: pointer;
  srcStride, dstStride: dword;
begin
  srcPtr := srcPage.getAddress(srcX, srcY);
  dstPtr := dstPage.getAddress(dstX, dstY);
  srcStride := (srcPage.width - width) * 4;
  dstStride := (dstPage.width - width) * 4;

  asm
    pushad

    mov esi, SRCPTR
    mov edi, DSTPTR

    mov ebx, HEIGHT
  @YLOOP:
    mov ecx, WIDTH
    rep movsd
    add esi, SRCSTRIDE
    add edi, DSTSTRIDE
    dec ebx
    jnz @YLOOP
    popad
  end;

end;
