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
; ebx: varies
; ecx: pixel count [0]
; edx: varies 

GLOBAL _ColLine_MMX
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
; COLOR FILL
; -------------------------------------------------

; ebx = fillColor

; special case for direct blit.
ColLine_MMX:
  mov  eax, ebx
  push ecx
  shr  ecx, 2
  test ecx, ecx
  jz .final
  
  movd mm1, eax
  punpckldq mm1, mm1
.xloop:
  movq [edi], mm1
  movq [edi+8], mm1
  add  edi, 16
  dec  ecx
  jnz .xloop
.final:
  pop  ecx
  and  ecx, 3  
  rep  stosd
  ret

ColLine_Blend_MMX:
  ; replicate alpha
  mov        eax, ebx
  shr        eax, 24
  movd       mm7, eax
  punpcklwd  mm7, mm7
  punpckldq  mm7, mm7        ; MM7 <- 0 A 0 A | 0 A 0 A
  ; replicated 255-alpha
  movq       mm4, b25
  psubw      mm4, mm7        ; MM4 <- 0 `A 0 `A | 0 `A 0 `A}
  ; premultiply source color
  movd       src, ebx        ; MM1 <-  0  0  0  0|  0 Rs Gs Bs
  punpcklbw  src, zer        ; MM1 <-  0  0  0 Rs|  0 Gs  0 Bs
  pmullw     src, mm7        ; MM1 <-  0  A*Rs A*Gs A*bs
.xloop:
  mov        edx, [edi]
  movd       mm6, edx         ; MM6 <-  0  0  0  0|  0 Rd Gd Bd
  punpcklbw  mm6, zer         ; MM6 <-  0  0  0 Rd|  0 Gd  0 Bd
  pmullw     mm6, mm4         ; MM6 <-  0  (255-A)*Rd (255-A)*Gd (255-A)*bd
  paddw      mm6, src         ; MM6 <- A*Rs+(255-A)*Rd ...
  paddw      mm6, b25
  psrlw      mm6, 8           ; MM6 <- (A*Rs+(255-A)*Rd) / 256
  packuswb   mm6, mm6         ; MM6 = 0 0 0 0 | 0 R G B
  movd       eax, mm6
  mov        [edi], eax
  add        edi, 4
  dec        ecx
  jnz       .xloop
  ret

col_jump_table:
  dd ColLine_MMX
  dd ColLine_Blend_MMX

_ColLine_MMX:
  and eax, $1
  mov eax, [col_jump_table + eax * 4]
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
