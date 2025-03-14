; drawLine_MMX NASM implementation
; esi: srcPtr -> moved to end of line
; edi: dstPtr -> moved to end of line
; mm1: tintColor
; mm3: bias (255 as 4x uint16)
; eax -> destroyed
; ebx: [preserved]
; ecx: pixel count -> destroyed

section .text
[BITS 32]


GLOBAL _drawLine_MMX
GLOBAL _drawLine_Tint_Blend_MMX
GLOBAL _drawLine_Tint_MMX
GLOBAL _drawLine_Blend_MMX

%macro DRAW_SAMPLE 0
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
    packuswb  mm2, mm2
    movd      [edi], mm2
%endmacro

%macro DRAW_EOL 0
    add edi, 4
    add esi, 4
    dec ecx
    jnz .xloop
%endmacro

; Main Procedure
_drawLine_Tint_Blend_MMX:
.xloop:  
  DRAW_SAMPLE
  DRAW_TINT
  DRAW_BLEND
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_EOL
  ret

_drawLine_Tint_MMX:
.xloop:    
  DRAW_SAMPLE
  DRAW_TINT 
.blit:      
  DRAW_BLIT  
.skip:    
  DRAW_EOL  
  ret

_drawLine_Blend_MMX:
.xloop:    
  DRAW_SAMPLE
  DRAW_BLEND
.blit:      
  DRAW_BLIT    
.skip:    
  DRAW_EOL  
  ret

_drawLine_MMX:
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
  ret