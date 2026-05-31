; ==============================================================================
; debug_unlock_thunk.asm - thunk slot 1 (bank 5) para DebugFramePollBody (bank 4)
; ==============================================================================
; DebugFramePollBody vive en bank 4 (slot 3). Este thunk lo invoca 1x/frame desde
; MainLoop paginando bank 4, con SP en la alt-stack (slot 1, always-visible) para
; NO enmascarar los IRQs durante el page switch (tick musica 25 Hz exacto). Mismo
; patron que AY_UpdateBell (ay_sound_thunks.asm), que corre cada frame ya.
;
; SIN DI interno: el cuerpo no escribe AY directamente — su unico AY toca via
; PauseAy/ResumeAy (slot 1), que abren/cierran su propia ventana DI/EI. Dejar los
; IRQs activos es seguro: el handler (MusicIrqHandler) es slot-3-agnostic y empuja
; sobre la alt-stack. El tail-call DebugFramePollBody -> CheckPauseKey -> PauseAy/
; ResumeAy (slot 1) desenrolla con RET hasta este thunk (PauseAy/ResumeAy no tocan
; slot 3, asi corren bien con bank 4 paginado).
;
; Restore hardcoded a bank 0: invariante MainLoop "slot 3 = bank 0 al inicio del
; frame".
; ==============================================================================
DebugFramePoll:
    LD (.dfpSavedSP), SP
    LD SP, PagingAltStackTop
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 4 (sin DI; SP alterno)
    CALL DebugFramePollBody
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 0 (sin DI; SP alterno)
    LD SP, (.dfpSavedSP)
    RET
.dfpSavedSP: DEFW 0
