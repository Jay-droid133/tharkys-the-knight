; ==============================================================================
; STANDALONE SPLASH body - Bank 1
; ==============================================================================
; Solo se ensambla con --define STANDALONE. Vive en bank 1 (slot 3) junto al
; blob ZX0 y al descompresor.
;
; Layout en bank 1:
;   DecompressSplashBody:   wrapper de ~15 B (CALL dzx0 + repaging)
;   dzx0_standard:          descompresor (68 B)
;   bg_splash_zx0_data:     blob comprimido (~4 KB) via INCBIN
;
; Entry: DecompressSplash (slot 1) ya pagino bank 1 en slot 3 y cambio SP a
; alt_stack. Aqui solo descomprimimos y repaginamos bank 0 antes del RET.
; ==============================================================================

DecompressSplashBody:
    LD HL, bg_splash_zx0_data       ; src en bank 1 (slot 3)
    LD DE, $4000                    ; dst = VRAM (slot 1, siempre visible)
    CALL dzx0_standard
    ; Repaging bank 0 ANTES del RET para que el stack normal vuelva a ser
    ; accesible. El SP sigue apuntando al alt_stack (slot 1, visible), por
    ; lo que el RET hace pop del alt_stack y vuelve al thunk en slot 1.
    LD A, (CurrentPaging)
    AND $F8                         ; bank 0
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

    INCLUDE "dzx0_standard.asm"

bg_splash_zx0_data:
    INCBIN "bg_splash.zx0"
bg_splash_zx0_end:
