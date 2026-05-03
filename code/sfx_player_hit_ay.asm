; ==============================================================================
; SFX_PLAYER_HIT_AY - Hit del player no bloqueante via AY hardware envelope
; ==============================================================================
; Vive en slot 1 ($6000+, siempre visible) → cero coste en bank 2.
; Direct OUTs a $FFFD/$BFFD → no requiere paging ni thunk.
;
; Diseño:
;   - Canal B (center en ABC stereo, lo más estandar en emuladores 128K).
;   - Hardware envelope shape $09 (single fade out) → decay auto de vol ~300 ms.
;   - Pitch sweep per-frame (PlayerHitPeriod += 32 cada frame durante 15 frames):
;       inicial $0080 (~853 Hz, agudo) → final $0260 (~146 Hz, grave).
;   - AY_UpdatePlayerHit se llama cada frame desde MainLoop (cold path: salta
;     en RET Z si no hay sweep activo).
;
; Conflicto: bell chimes usan canales A/B/C. Si player hit ocurre durante
; bell decay, R2/R3/R9 del bell son sobrescritos. En la practica casi nunca
; coinciden (bell = midnight + countdown; hit = combate gameplay).
;
; Llamado desde:
;   - CheckPlayerEnemyCollision.pHpDmgNotZero (cada hit) — start.
;   - CheckDeathTouchPlayer (toque de la muerte) — start.
;   - MainLoop cada frame — update.
; ==============================================================================

; --- Estado (slot 1, contended pero acceso solo durante sweep activo) ---
PlayerHitFrames:  DEFB 0          ; Frames restantes del sweep (0 = inactivo)
PlayerHitPeriod:  DEFW 0          ; Period actual (16-bit, R2/R3)

PLAYER_HIT_SWEEP_FRAMES   EQU 15
PLAYER_HIT_PERIOD_INIT    EQU $0080      ; ~853 Hz (agudo)
PLAYER_HIT_PERIOD_DELTA   EQU 32         ; +32/frame → final $0260 (~146 Hz)

; ==============================================================================
; AY_PlayPlayerHit - Inicia el SFX y arma el sweep
; ==============================================================================
AY_PlayPlayerHit:
    LD A, PLAYER_HIT_SWEEP_FRAMES
    LD (PlayerHitFrames), A
    LD HL, PLAYER_HIT_PERIOD_INIT
    LD (PlayerHitPeriod), HL

    DI
    LD HL, .phRegs
    LD C, $FD
.phLoop:
    LD A, (HL)
    CP $FF
    JR Z, .phDone
    LD B, $FF
    OUT (C), A                          ; AY register select
    INC HL
    LD B, $BF
    LD A, (HL)
    OUT (C), A                          ; AY data
    INC HL
    JR .phLoop
.phDone:
    EI
    RET

.phRegs:
    DEFB  2, $80          ; R2  = period B lo (= $80, period $0080)
    DEFB  3, $00          ; R3  = period B hi
    DEFB  9, $10          ; R9  = vol B usa envelope
    DEFB 11, $00          ; R11 = env period lo
    DEFB 12, $08          ; R12 = env period hi ($0800 → ~300 ms decay)
    DEFB  7, $3D          ; R7  = mixer (tono B on, A/C off, noise off)
    DEFB 13, $09          ; R13 = envelope shape (single fade out, hold low)
                          ;       Escribir R13 RE-DISPARA el envelope → ultimo
    DEFB $FF              ; sentinel

; ==============================================================================
; AY_UpdatePlayerHit - Per-frame: sweep R2/R3 hacia grave
; ==============================================================================
; Llamar cada frame desde MainLoop. No-op si sweep inactivo (frames=0).
; Destruye: A, BC, DE, HL.
; ==============================================================================
AY_UpdatePlayerHit:
    LD A, (PlayerHitFrames)
    OR A
    RET Z
    DEC A
    LD (PlayerHitFrames), A

    LD HL, (PlayerHitPeriod)
    LD DE, PLAYER_HIT_PERIOD_DELTA
    ADD HL, DE
    LD (PlayerHitPeriod), HL

    ; Escribir R2 = L, R3 = H (period B)
    DI
    LD C, $FD
    LD A, 2
    LD B, $FF
    OUT (C), A
    LD A, L
    LD B, $BF
    OUT (C), A
    LD A, 3
    LD B, $FF
    OUT (C), A
    LD A, H
    LD B, $BF
    OUT (C), A
    EI
    RET
