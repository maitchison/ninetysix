{$link graph32_nasm.obj}
var
  textureStride: dword external name '_textureStride';
  yFactor: qword external name '_yFactor';

procedure drawLine_MMX(); cdecl; external name 'DrawLine_MMX';
procedure colLine_MMX(); cdecl; external name 'ColLine_MMX';
procedure stretchLineNearest_MMX(); cdecl; external name 'StretchLineNearest_MMX';
procedure stretchLineLinear_MMX(); cdecl; external name 'StretchLineLinear_MMX';

function getCallCode(blendMode: tBlendMode; tint: RGBA): int32;
begin
  result := 0;
  case blendMode of
    bmNone: exit(-1);
    bmBlend: result += 1;
  end;
  if int32(tint) <> -1 then result += 2;
end;

procedure drawRect_MMX(dstPage: tPage; aRect: tRect; col: RGBA; blendMode: tBlendMode);
var
  dstPtr: pointer;
  dstStride: dword;
  callCode: int32;
begin

  callCode := getCallCode(blendMode, RGBA.White);
  if callCode < 0 then exit;

  dstPtr := dstPage.getAddress(aRect.pos.x, aRect.pos.y);
  dstStride := (dstPage.width - aRect.width) * 4;

  asm
    cli
    pushad
    mov       edi, DSTPTR
    mov       ebx, ARECT.HEIGHT
    pxor      mm0, mm0
    mov       eax, $00ff00ff
    movd      mm3, eax
    punpckldq mm3, mm3
  @YLOOP:
    mov       ecx, ARECT.WIDTH
    push      ebx
    mov       eax, CALLCODE
    mov       ebx, COL
    call      colLine_MMX
    pop       ebx
    add       edi, DSTSTRIDE
    dec       ebx
    jnz      @YLOOP
    popad
    emms
    sti
  end;
end;


procedure drawImage_MMX(dstPage, srcPage: tPage; dstX, dstY: int32; srcRect: tRect; tint: RGBA; blendMode: tBlendMode);
var
  srcPtr, dstPtr: pointer;
  srcStride, dstStride: dword;
  callCode: int32;
begin

  {we don't support mul yet}
  if blendMode = bmMul then begin
    drawImage_REF(dstPage, srcPage, dstX, dstY, srcRect, tint, blendMode);
    exit;
  end;

  callCode := getCallCode(blendMode, tint);
  if callCode < 0 then exit;

  srcPtr := srcPage.getAddress(srcRect.x, srcRect.y);
  dstPtr := dstPage.getAddress(dstX, dstY);
  srcStride := (srcPage.width - srcRect.width) * 4;
  dstStride := (dstPage.width - srcRect.width) * 4;

  asm
    cli
    pushad
    mov esi, SRCPTR
    mov edi, DSTPTR
    mov ebx, SRCRECT.HEIGHT

    {MM0 <- 0}
    pxor      MM0, MM0
    {MM2 <- tintColor as int16}
    movd      MM2, TINT
    punpcklbw MM2, MM0
    {MM3 <- bias}
    mov       eax, $00ff00ff
    movd      MM3, eax
    punpckldq MM3, MM3

  @YLOOP:
    mov       ecx, SRCRECT.WIDTH
    push      ebx
    mov       eax, CALLCODE
    call      drawLine_MMX
    pop       ebx

    add       esi, SRCSTRIDE
    add       edi, DSTSTRIDE
    dec       ebx
    jnz       @YLOOP
    popad
    emms
    sti
  end;
end;

{draw image stretched}
procedure stretchImage_MMX(dstPage, srcPage: tPage; dstRect: tRect; srcX, srcY, srcDx, srcDy: single; tint: RGBA; filter: tTextureFilter; blendMode: tBlendMode);
var
  i,j: integer;
  dstPtr: pRGBA;
  src: RGBA;
  tx,ty: int32;
  tdx,tdy: int32;
  linePtr: pointer;
  callCode: integer;
  callProc: procedure cdecl;
  yCode: integer;
  yCodes: array[0..3] of word;
  stride: word;
  ctx,cty: integer;
  maxY: integer;
begin

  callCode := getCallCode(blendMode, tint);
  if callCode < 0 then exit;

  maxY := srcPage.height;

  case filter of
    tfNearest: begin
      callProc := stretchLineNearest_MMX;
      {this seems to make things look better}
      srcX += 0.25;
      srcY += 0.25;
    end;
    tfLinear: begin
      callProc := stretchLineLinear_MMX;
      {adjust center offset for linear. Effectively moving from trunc to round}
      srcX -= 0.5;
      srcY -= 0.5;
      dec(maxY); {due to filtering we can't sample the last line}
    end;
  end;

  tdx := trunc(srcDx*65536);
  tdy := trunc(srcDy*65536);
  tx := trunc(srcX*65536);
  ty := trunc(srcY*65536);
  ctx := clamp(tx, 0, 65536*(srcPage.width-1)-1);

  for j := 0 to dstRect.height-1 do begin
    dstPtr := dstPage.getAddress(dstRect.x, dstRect.y+j);
    cty := clamp(ty, 0, (65536*maxY)-1);
    linePtr := srcPage.getAddress(0, cty div 65536);

    {for linear filtering}
    yCode := (cty div 256) and $ff;
    yCodes[0] := yCode;
    yCodes[1] := yCode;
    yCodes[2] := 255-yCode;
    yCodes[3] := 255-yCode;

    {setup global parameters}
    move(yCodes, yFactor, 8);
    textureStride := srcPage.width;

    {todo: setup once and don't call emms every line}
    asm
      cli
      pushad
      mov       esi, LINEPTR
      mov       edi, DSTPTR
      mov       ecx, DSTRECT.WIDTH
      mov       ebx, CTX
      mov       edx, TDX
      pxor      mm0, mm0
      movd      mm2, TINT
      punpcklbw mm2, mm0
      mov       eax, 255
      movd      mm3, eax
      punpcklwd mm3, mm3
      punpckldq mm3, mm3

      mov       eax, CALLCODE
      call      callProc
      popad
      emms
      sti
    end;

    ty += tdy;
  end;
end;
