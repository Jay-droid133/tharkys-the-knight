; ==============================================================================
; STANDALONE SPLASH thunk - Slot 1
; ==============================================================================
; Solo se ensambla con --define STANDALONE. Vive en slot 1 (siempre visible).
;
; F1: thunk unico StandaloneF1Setup que combina LoadFont (bank 4) + Decompress
; bg-185 (bank 1) + Print test text. Es un one-shot al boot; el slot 1 esta
; apretado (88 B free post-music_irq) y tres thunks separados desbordarian.
; En F2+ (state machine real) refactorizare a entry points independientes
; cuando reorganice slot 1 con presupuesto holgado (e.g. moviendo algo a bank 7).
;
; Patron: alt_stack en slot 1 durante TODOS los page switches para que las IRQs
; no corrompan el stack normal (que vive en slot 3 bank 0, oculto cuando
; otro bank esta paginado en slot 3).
; ==============================================================================

StandaloneF1Setup:
    LD (.sf1SavedSP), SP
    LD SP, PagingAltStackTop
    ; --- Paso 1: cargar font Reward desde bank 4 a BgSpriteBuffer ---
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD HL, CreditsFontData
    LD DE, BgSpriteBuffer
    LD BC, CREDITS_FONT_SIZE
    LDIR
    ; --- Paso 2: paginar bank 1 + body (decompress + print + repagina bank 0) ---
    LD A, (CurrentPaging)
    AND $F8
    OR 1
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    CALL StandaloneF1Body           ; body repagina bank 0 antes de RET
    LD SP, (.sf1SavedSP)
    RET

.sf1SavedSP: DEFW 0
