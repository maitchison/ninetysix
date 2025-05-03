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

procedure blitImage_ASM(dstPage, srcPage: tPage; dstX, dstY: int32; srcRect: tRect);
var
  srcPtr, dstPtr: pointer;
  srcStride, dstStride: dword;
begin
  srcPtr := srcPage.getAddr(srcRect.x, srcRect.y);
  dstPtr := dstPage.getAddr(dstX, dstY);
  srcStride := (srcPage.width - srcRect.width) * 4;
  dstStride := (dstPage.width - srcRect.width) * 4;

  asm
    pushad

    mov esi, SRCPTR
    mov edi, DSTPTR

    mov ebx, SRCRECT.HEIGHT
  @YLOOP:
    mov ecx, SRCRECT.WIDTH
    rep movsd
    add esi, SRCSTRIDE
    add edi, DSTSTRIDE
    dec ebx
    jnz @YLOOP
    popad
  end;
end;
