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
PlayerHitFrames:    DEFB 0        ; Frames restantes del sweep (0 = inactivo)
PlayerHitPeriod:    DEFW 0        ; Period actual (16-bit, R2/R3)
PlayerHitDelta:     DEFW 0        ; Delta por frame (parametriza speed/depth)
BeepDurationFrames: DEFB 0        ; Frames restantes del beep BASIC-BEEP-style
                                  ; (0 = inactivo o ya muteado)

; --- Hit (golpe no fatal): sweep corto y decay rapido (~600ms) ---
PLAYER_HIT_SWEEP_FRAMES   EQU 15
PLAYER_HIT_PERIOD_INIT    EQU $0080      ; ~853 Hz (agudo)
PLAYER_HIT_PERIOD_DELTA   EQU 32         ; +32/frame → final $0260 (~146 Hz)
PLAYER_HIT_ENV_HI         EQU $08        ; R12 → ~300 ms decay envelope

; --- Death (golpe fatal): mas largo, mas grave, decay lento ---
PLAYER_DEATH_SWEEP_FRAMES EQU 50         ; 2.0 s @ 25fps
PLAYER_DEATH_PERIOD_INIT  EQU $0080      ; mismo punto de salida agudo
PLAYER_DEATH_PERIOD_DELTA EQU 40         ; +40/frame → final $0850 (~52 Hz)
PLAYER_DEATH_ENV_HI       EQU $40        ; R12 → ~2.36 s decay (fade lento)

; ==============================================================================
; AY_PlayPlayerHit / AY_PlayPlayerDeath - wrappers sobre _AY_PlaySweep
; ==============================================================================
; Ambos arman el mismo sweep "agudo→grave" con hardware envelope. Diferencias:
; frames totales, delta por frame, periodo del envelope. R2/R3 iniciales son
; comunes ($0080 ~853 Hz) → la tabla los hardcodea.
; ==============================================================================
AY_PlayPlayerHit:
    LD HL, PLAYER_HIT_PERIOD_INIT
    LD B, PLAYER_HIT_SWEEP_FRAMES
    LD DE, PLAYER_HIT_PERIOD_DELTA
    LD A, PLAYER_HIT_ENV_HI
    JR _AY_PlaySweep

AY_PlayPlayerDeath:
    LD HL, PLAYER_DEATH_PERIOD_INIT
    LD B, PLAYER_DEATH_SWEEP_FRAMES
    LD DE, PLAYER_DEATH_PERIOD_DELTA
    LD A, PLAYER_DEATH_ENV_HI
    ; fall through

; IN: HL=period inicial, B=frames, DE=delta, A=R12 env period hi.
_AY_PlaySweep:
    LD (PlayerHitPeriod), HL
    LD (PlayerHitDelta), DE
    LD (.envPatch), A                   ; SMC: parchea R12 en la tabla
    LD A, B
    LD (PlayerHitFrames), A
    DI
    LD C, $FD
    LD HL, .phRegs
    JP _AY_WriteRegPairs                ; tail call: hace EI + RET

.phRegs:
    DEFB  2, $80          ; R2  = period B lo (= $80, period $0080)
    DEFB  3, $00          ; R3  = period B hi
    DEFB  9, $10          ; R9  = vol B usa envelope
    DEFB 11, $00          ; R11 = env period lo
    DEFB 12               ; R12 = env period hi (siguiente byte parcheado)
.envPatch:
    DEFB $08              ; ← parcheado por _AY_PlaySweep ($08 hit / $40 death)
    DEFB  7, $3D          ; R7  = mixer (tono B on, A/C off, noise off)
    DEFB 13, $09          ; R13 = envelope shape (single fade out, hold low)
                          ;       Escribir R13 RE-DISPARA el envelope → ultimo
    DEFB $FF              ; sentinel

; ==============================================================================
; AY_PlayBeep - Pitido BASIC-BEEP-style (vol fija + cutoff abrupto tras N frames)
; ==============================================================================
; Equivalente al BEEP duration, pitch del 48K. Vol max constante durante N
; frames, despues mute abrupto via AY_UpdatePlayerHit (que tickea cada frame).
; Canal B (center stereo ABC). No bloqueante.
;
; IN: HL = period AY canal B (mayor = mas grave).
;     B  = duracion en frames (a 25 fps: 4 ≈ 160ms, 11 ≈ 440ms).
;
; Sugerencias:
;   HL=$0080 B=4  → ~853 Hz, ~160ms (beep "tick" del countdown).
;   HL=$0040 B=11 → ~1707 Hz, ~440ms (beep "GO!" final, mas largo).
; Destruye: A, BC, HL.
; ==============================================================================
AY_PlayBeep:
    LD A, B
    LD (BeepDurationFrames), A          ; activa el contador de cutoff
    DI
    LD C, $FD
    ; R2 = L (period B lo)
    LD A, 2
    LD B, $FF
    OUT (C), A
    LD A, L
    LD B, $BF
    OUT (C), A
    ; R3 = H (period B hi)
    LD A, 3
    LD B, $FF
    OUT (C), A
    LD A, H
    LD B, $BF
    OUT (C), A
    ; R9 = $0F (vol max fija, SIN envelope), R7 = mixer (B tono only)
    LD HL, .beepRegs
    JP _AY_WriteRegPairs                ; tail call: EI + RET

.beepRegs:
    DEFB  9, $0F          ; vol B = max fija (bit 4 = 0 → sin envelope)
    DEFB  7, $3D          ; mixer (B tono on, A/C off, noise off)
    DEFB $FF              ; sentinel

; ==============================================================================
; _AY_WriteRegPairs - Helper compartido (PlayerHit + Beep)
; ==============================================================================
; Escribe pares (reg, val) leidos de HL hasta sentinel $FF. Caller debe haber
; hecho DI y `LD C, $FD`. Hace EI + RET al final.
; ==============================================================================
_AY_WriteRegPairs:
    LD A, (HL)
    CP $FF
    JR Z, .awrpDone
    LD B, $FF
    OUT (C), A                          ; AY register select ($FFFD)
    INC HL
    LD B, $BF
    LD A, (HL)
    OUT (C), A                          ; AY data ($BFFD)
    INC HL
    JR _AY_WriteRegPairs
.awrpDone:
    EI
    RET

; ==============================================================================
; AY_UpdatePlayerHit - Per-frame: sweep R2/R3 hacia grave
; ==============================================================================
; Llamar cada frame desde MainLoop. No-op si sweep inactivo (frames=0).
; Destruye: A, BC, DE, HL.
; ==============================================================================
AY_UpdatePlayerHit:
    LD A, (PlayerHitFrames)
    OR A
    JR Z, .uphCheckBeep
    DEC A
    LD (PlayerHitFrames), A

    LD HL, (PlayerHitPeriod)
    LD DE, (PlayerHitDelta)             ; delta variable (hit=32, death=40)
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

; --- Tick del beep BASIC-style: decrementa contador, mute al llegar a 0 ---
.uphCheckBeep:
    LD A, (BeepDurationFrames)
    OR A
    RET Z
    DEC A
    LD (BeepDurationFrames), A
    RET NZ
    ; Cutoff: mute R9 (canal B vol = 0). R7 mixer queda igual (= no-op).
    DI
    LD BC, $FFFD
    LD A, 9
    OUT (C), A
    LD BC, $BFFD
    XOR A
    OUT (C), A
    EI
    RET
