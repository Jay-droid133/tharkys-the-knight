; ==============================================================================
; STANDALONE SPLASH thunks - Slot 1
; ==============================================================================
; Solo se ensambla con --define STANDALONE. Vive en slot 1 (siempre visible).
;
; Refactor B: el body movido a bank 4 (standalone_main_b4.asm). Solo el blob
; ZX0 + descompresor stays en bank 1. Por eso F1Setup ahora pagina bank 4
; (no bank 1) y descomprime via trampoline cross-bank.
; ==============================================================================

; ==============================================================================
; StandaloneF1Setup - Entry boot: pagina bank 4 + CALL F1Body
; ==============================================================================
; F1Body (en bank 4) carga font + cards 0/1 + CALL DecompressSplashTrampoline
; (que pagina bank 1, descomprime, repagina bank 4).
; ==============================================================================
StandaloneF1Setup:
    LD (.sf1SavedSP), SP
    LD SP, PagingAltStackTop
    ; Page bank 4 en slot 3
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    CALL StandaloneF1Body
    ; Repagina bank 0 antes de restore SP
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD SP, (.sf1SavedSP)
    RET

.sf1SavedSP: DEFW 0

; ==============================================================================
; DecompressSplashTrampoline - cross-bank decompress helper
; ==============================================================================
; Llamado por F1Body (en bank 4) cuando toca descomprimir bg-185 (Card 2).
; Pagina bank 1 (donde vive blob + dzx0_standard), descomprime a $4000,
; repagina bank 4 (caller).
;
; SP ya apunta al alt_stack (set por F1Setup), asi que push/pop de
; dzx0_standard van al alt_stack en slot 1 (siempre visible) sin riesgo.
; Destruye: AF, BC, DE, HL.
; ==============================================================================
DecompressSplashTrampoline:
    LD A, (CurrentPaging)
    AND $F8
    OR 1
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD HL, bg_splash_zx0_data
    LD DE, $4000
    CALL dzx0_standard
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET
