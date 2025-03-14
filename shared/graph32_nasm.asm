section .text
[BITS 32]

; -------------------------------
; Register Conventions
; -------------------------------
; esi: srcPtr [moved to end of line]
; edi: dstPtr [moved to end of line]
; mm0: 0
; mm1: [used for current color]
; mm2: tint
; mm3: bias (255 as 4x uint16)
; eax: [destroyed]
; ebx: [preserved]
; ecx: pixel count [0]


GLOBAL _drawLine_MMX
GLOBAL _drawLine_Tint_Blend_MMX
GLOBAL _drawLine_Tint_MMX
GLOBAL _drawLine_Blend_MMX

GLOBAL _stretchLine_Tint_Blend_Nearest_MMX
GLOBAL _stretchLine_Blend_Nearest_MMX:
GLOBAL _stretchLine_Tint_Nearest_MMX:
GLOBAL _stretchLine_Nearest_MMX:


; common registers
%define zer mm0
%define src mm1
%define tnt mm2
%define b25 mm3

%macro DRAW_SAMPLE 0
    movd      src, [esi]
    add       esi, 4
    punpcklbw src, zer
%endmacro

%macro DRAW_TINT 0
    pmullw    src, tnt
    paddw     src, b25
    psrlw     src, 8
%endmacro

%macro DRAW_BLEND 0
    movq      mm7, src
    psrlq     mm7, 48
    movd      eax, mm7
    cmp       al, 0
    je        .skip
    cmp       al, 255
    je        .blit
    
    movd      mm6, [edi]
    punpcklbw mm6, zer

    movd      mm4, eax
    punpcklwd mm4, mm4
    punpckldq mm4, mm4

    movq      mm5, b25
    psubw     mm5, mm4

    pmullw    src, mm4
    pmullw    mm6, mm5
    paddw     src, mm6
    paddw     src, b25
    psrlw     src, 8
%endmacro

%macro DRAW_BLIT 0
    packuswb  src, src
    movd      [edi], src
%endmacro

%macro DRAW_END 0
    add edi, 4    
    dec ecx
    jnz .xloop
%endmacro

; -------------------------------------------------
; DRAWING
; -------------------------------------------------

_drawLine_Tint_Blend_MMX:
.xloop:  
  DRAW_SAMPLE
  DRAW_TINT
  DRAW_BLEND
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_END
  ret

_drawLine_Tint_MMX:
.xloop:    
  DRAW_SAMPLE
  DRAW_TINT 
.blit:      
  DRAW_BLIT  
.skip:    
  DRAW_END  
  ret

_drawLine_Blend_MMX:
.xloop:    
  DRAW_SAMPLE
  DRAW_BLEND
.blit:      
  DRAW_BLIT    
.skip:    
  DRAW_END  
  ret

; special case for direct blit.
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

; -------------------------------------------------
; SCALING
; -------------------------------------------------

; stretchLine_MMX NASM implementation
; ebx: tx * 65536
; edx: tdx * 65536

%macro STRETCH_SAMPLE 0
  mov       eax, ebx
  shr       eax, 16
  movd      src, [esi+eax*4]
  punpcklbw src, zer
  add       ebx, edx
%endmacro

_stretchLine_Tint_Blend_Nearest_MMX:
 .xloop:
  STRETCH_SAMPLE
  DRAW_TINT
  DRAW_BLEND
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_END

_stretchLine_Tint_Nearest_MMX:
 .xloop:
  STRETCH_SAMPLE
  DRAW_TINT
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_END  

_stretchLine_Blend_Nearest_MMX:
 .xloop:
  STRETCH_SAMPLE
  DRAW_BLEND  
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_END  

_stretchLine_Nearest_MMX:
 .xloop:
  STRETCH_SAMPLE
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_END  
