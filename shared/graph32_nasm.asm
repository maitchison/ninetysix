; blendImage_MMX NASM implementation
; srcPtr in esi
; dstPtr in edi
; srcStride, dstStride, srcHeight, srcWidth, tint passed via stack or registers as you prefer

%macro DRAW_SAMPLE 0
.xloop:  
    movd      mm2, [esi]
    punpcklbw mm2, mm0
%endmacro

%macro DRAW_TINT 0
    pmullw    mm2, mm1
    paddw     mm2, mm3
    psrlw     mm2, 8
%endmacro

%macro DRAW_BLEND 0
    movq      mm7, mm2
    psrlq     mm7, 48
    movd      eax, mm7
    cmp       al, 0
    je        .skip
    cmp       al, 255
    je        .blit
.blend:
    movd      mm6, [edi]
    punpcklbw mm6, mm0

    movd      mm4, eax
    punpcklwd mm4, mm4
    punpckldq mm4, mm4

    movq      mm5, mm3
    psubw     mm5, mm4

    pmullw    mm2, mm4
    pmullw    mm6, mm5
    paddw     mm2, mm6
    paddw     mm2, mm3
    psrlw     mm2, 8
%endmacro

%macro DRAW_BLIT 0
.blit:  
    packuswb  mm2, mm2
    movd      [edi], mm2
%endmacro

%macro DRAW_EOL 0
.skip:  
    add edi, 4
    add esi, 4
    dec ecx
    jnz .xloop
%endmacro

; Main Procedure
drawLine_Tint_Blend_MMX:
  DRAW_SAMPLE
  DRAW_TINT
  DRAW_BLEND
  DRAW_BLIT
  DRAW_EOL

drawLine_Tint_MMX:
  DRAW_SAMPLE
  DRAW_TINT 
  DRAW_BLIT  
  DRAW_EOL  

drawLine_Blend_MMX:
  DRAW_SAMPLE
  DRAW_BLEND
  DRAW_BLIT    
  DRAW_EOL  

drawLine_MMX:
  push ecx
  shr ecx, 2
  test ecx, ecx
  jz .final
.xloop:
  movq mm0, [esi]
  movq mm1, [esi+8]
  movq [edi], mm0
  movq [edi+8], mm1
  add esi, 16
  add edi, 16
  dec ecx
  jnz .xloop
.final:
  pop ecx
  and ecx, 3  
  rep movsd