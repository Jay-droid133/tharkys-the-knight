; ==============================================================================
; town_gate_exit_thunk.asm - mini-thunk slot 1 para salir de credits a Inicio
; ==============================================================================
; .tgPhCredits (bank 7) hace JP aqui cuando el player pulsa un control en los
; credits. Tres lineas: OUT $00 a $7FFD (slot 3 a bank 0 + ROM 128K editor) +
; JP Inicio. No es CALL: no se vuelve.
;
; Por que vive AQUI (post-music_irq.asm INCLUDE) y no en town_gate_cutscene.asm:
; cualquier byte añadido a slot 1 ANTES de music_irq.asm empuja BellTickIrq
; sobre la IM2 table en $7A00 (sjasmplus ORG retrogrado silencioso, ver
; project_org_retrograde_overlap). Resultado: bytes del bell se sobreescriben
; con $7B = "LD A, E", y si BellVols != 0 el body cae en una cadena infinita
; que termina en JP MusicIrqHandler ($7B7B = Im2Vector) → re-entry del handler
; recursiva → music/anim/clock corren a 2-3x.
;
; Solucion: live AFTER music_irq.asm. BellTickIrq queda intacto.
;
; Reset de vars (TownGatePhase, SplashAlreadyShown, AySfxPtr, AySilenced) lo
; hace bank 7 .tgPhCredits antes del JP — writes a slot 1/2 always-vis son
; safe desde bank 7. Mover esos resets aqui costaria slot 1 extra y empujaria
; standalone_splash_thunk.
;
; Tras OUT, slot 3 = bank 0 (ROM 128K editor, irrelevante: no executemos
; desde slot 0). Inicio hace su propio InitPaging que normaliza a $10
; (bank 0 + ROM 48K) y LD SP nuevo. SP en BankCutsceneAltStack queda
; abandonado — Inicio lo resetea a SP_ADDRESS first thing.
; ==============================================================================
TownGateExitToInicio:
    XOR A                               ; A = $00: bank 0 + ROM 128K + paging on
    LD BC, $7FFD
    OUT (C), A                          ; slot 3 = bank 0 (safe: this code in slot 1)
    JP Inicio
