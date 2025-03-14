section .text
[BITS 32]

; drawCodes
; 0 blendMode
; 1 needsTint
; 2 filter

; -------------------------------
; Register Conventions
; -------------------------------
; esi: srcPtr [moved to end of line]
; edi: dstPtr [moved to end of line]
; mm0: 0
; mm1: [used for current color]
; mm2: tint
; mm3: bias (255 as 4x uint16)
; eax: draw code [destroyed]
; ebx: [preserved]
; ecx: pixel count [0]

GLOBAL _DrawLine_MMX
GLOBAL _StretchLineNearest_MMX:

; common registers
%define zer mm0
%define src mm1
%define tnt mm2
%define b25 mm3

; -------------------------------------------------
; DRAWING
; -------------------------------------------------

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

; special case for direct blit.
DrawLine_MMX:
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

DrawLine_Tint_MMX:
.xloop:    
  DRAW_SAMPLE
  DRAW_TINT 
.blit:      
  DRAW_BLIT  
.skip:    
  DRAW_END  
  ret

DrawLine_Blend_MMX:
.xloop:    
  DRAW_SAMPLE
  DRAW_BLEND
.blit:      
  DRAW_BLIT    
.skip:    
  DRAW_END  
  ret

DrawLine_Tint_Blend_MMX:
.xloop:  
  DRAW_SAMPLE
  DRAW_TINT
  DRAW_BLEND
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_END
  ret

draw_jump_table:
  dd DrawLine_MMX
  dd DrawLine_Blend_MMX
  dd DrawLine_Tint_MMX
  dd DrawLine_Tint_Blend_MMX

_DrawLine_MMX:
  and eax, $3  
  mov eax, [draw_jump_table + eax * 4]
  call eax
  ret

; -------------------------------------------------
; SCALING
; -------------------------------------------------

; stretchLineNearest_MMX NASM implementation
; ebx: tx * 65536
; edx: tdx * 65536

%macro STRETCH_SAMPLE 0
  mov       eax, ebx
  shr       eax, 16
  movd      src, [esi+eax*4]
  punpcklbw src, zer
  add       ebx, edx
%endmacro

StretchLineNearest_MMX:
.xloop:
  STRETCH_SAMPLE
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_END  
  ret

StretchLineNearest_Blend_MMX:
.xloop:
  STRETCH_SAMPLE
  DRAW_BLEND  
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_END  
  ret

StretchLineNearest_Tint_MMX:
.xloop:
  STRETCH_SAMPLE
  DRAW_TINT
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_END  
  ret

StretchLineNearest_Tint_Blend_MMX:
.xloop:
  STRETCH_SAMPLE
  DRAW_TINT
  DRAW_BLEND
.blit:        
  DRAW_BLIT
.skip:    
  DRAW_END
  ret

stretch_jump_table:
  dd StretchLineNearest_MMX
  dd StretchLineNearest_Blend_MMX
  dd StretchLineNearest_Tint_MMX
  dd StretchLineNearest_Tint_Blend_MMX

_StretchLineNearest_MMX:
  and eax, $3  
  mov eax, [stretch_jump_table + eax * 4]
  call eax
  ret
