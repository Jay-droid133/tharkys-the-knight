; ==============================================================================
; STANDALONE SPLASH thunk - Slot 1
; ==============================================================================
; Solo se ensambla con --define STANDALONE.
;
; Entry point para descomprimir bg_splash.zx0 a $4000. Pagina bank 1 + SP swap
; a alt_stack (slot 1) y salta a DecompressSplashBody (vive en bank 1, junto
; al blob comprimido y al descompresor ZX0).
;
; Patron identico a bank_cutscene_thunks: stack normal en slot 3 queda oculto
; mientras bank 1 esta paginado, asi que SP va al alt_stack en slot 1. El RET
; del body se hace tras repaginar bank 0 -> stack normal accesible otra vez.
; ==============================================================================

DecompressSplash:
    LD (.dspSavedSP), SP            ; salva SP normal
    LD SP, PagingAltStackTop        ; SP -> alt_stack en slot 1
    ; Page bank 1 en slot 3 (inline)
    LD A, (CurrentPaging)
    AND $F8
    OR 1
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    ; Salto al body en bank 1. El body hace CALL dzx0_standard + repaging.
    CALL DecompressSplashBody       ; en bank 1, $Cxxx
    ; Body ha repaginado bank 0 antes de RET, asi que aqui slot 3 = bank 0
    ; (stack normal accesible). Solo nos queda restaurar SP normal.
    LD SP, (.dspSavedSP)
    RET

.dspSavedSP: DEFW 0
