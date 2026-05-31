; ==============================================================================
; beeper_ticks_thunks.asm - thunks slot 1 (bank 5) para beeper_ticks.asm (bank 4)
; ==============================================================================
; El cuerpo (beeper_ticks.asm) se movio a bank 4 para liberar slot 1 (sitio para
; minimap.asm). Aqui viven los 2 entry points que se llaman desde codigo NO en
; bank 4:
;   - UpdateBeeperTicks: 1x/frame desde MainLoop (normal stack en slot 3).
;   - FireBuffNormalTick: desde el loop de ShowMinimapTimed (minimap_timed.asm).
;
; Ningun simbolo interno de beeper_ticks se llama desde fuera del modulo (los
; JP .ubt*/Fire*/BeeperTick son intra-bank-4), asi que solo hacen falta estos 2.
; ==============================================================================

; --- UpdateBeeperTicks: 1x/frame desde MainLoop --------------------------------
; Alt-stack bank-4 (mismo patron que AY_UpdateBell, que ya corre cada frame). SIN
; DI: BeeperTick toca el beeper ($FE) con IRQs activos a proposito; el handler es
; slot-3-agnostic y empuja sobre la alt-stack. Restore a bank 0 (invariante
; MainLoop "slot 3 = bank 0 al inicio del frame").
UpdateBeeperTicks:
    LD (.ubtSavedSP), SP
    LD SP, PagingAltStackTop
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 4 (sin DI; SP alterno)
    CALL UpdateBeeperTicksBody
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 0 (sin DI; SP alterno)
    LD SP, (.ubtSavedSP)
    RET
.ubtSavedSP: DEFW 0

; --- FireBuffNormalTick: tic beeper aislado para ShowMinimapTimed --------------
; El caller (minimap_timed.asm) YA corre con SP en la alt-stack (ShowMinimapTimed
; hizo LD SP, PagingAltStackTop) y slot 3 = bank 0. Por eso NO tocamos SP aqui:
; resetearlo a PagingAltStackTop descartaria el frame del caller. Solo page-call-
; page; los IRQs durante el beep empujan sobre la alt-stack vigente (always-vis).
FireBuffNormalTick:
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 4
    CALL FireBuffNormal
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 0 (restore invariante minimap)
    RET
