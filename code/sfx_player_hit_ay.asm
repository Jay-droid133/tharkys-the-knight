; ==============================================================================
; SFX_PLAYER_HIT_AY - Hit del player no bloqueante, ESTILO BEEPER 48K via AY
; ==============================================================================
; Vive en slot 1 ($6000+, siempre visible) → cero coste en bank 2.
; Direct OUTs a $FFFD/$BFFD → no requiere paging ni thunk.
;
; Diseño beeper-style:
;   - Canal B (center en ABC stereo, lo más estandar en emuladores 128K).
;   - Vol FIJA al maximo ($0F, bit 4 = 0 → SIN hardware envelope) — emula
;     la naturaleza on/off del beeper 1-bit del 48K.
;   - Cutoff ABRUPTO al acabar el sweep (mute R9 = 0 en el ultimo frame).
;     Sin fade. Asi suena "snappy" como un BEEP del 48K, no "ay-decay".
;   - Pitch sweep per-frame (PlayerHitPeriod += delta cada frame durante N
;     frames): inicial agudo → final grave (mismo perfil que SFX beeper de
;     hits clasicos en 48K).
;   - AY_UpdatePlayerHit se llama cada 2 IRQs (= 25 Hz) desde el handler IM 2
;     en music_irq.asm (cold path: salta en RET Z si no hay sweep activo).
;     Tickear desde IRQ inmuniza la duracion del beep frente a la latencia
;     de MainLoop (transiciones lentas estiraban el beep antes).
;
; Diferencias con beeper real: el AY produce onda cuadrada perfecta al 50%
; duty, mientras que el beeper 1-bit tiene timing imperfecto que da timbre
; "sucio". Los bordes abruptos (sin envelope, cutoff instantaneo) son lo que
; mas vende la estetica beeper sin recurrir a CPU-bit-bang del puerto $FE.
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

; --- Hit (golpe no fatal): sweep snappy, vol max constante, cutoff abrupto ---
PLAYER_HIT_SWEEP_FRAMES   EQU 4          ; 4 frames @ 25 fps = 160 ms
PLAYER_HIT_PERIOD_INIT    EQU $0080      ; ~853 Hz (agudo)
PLAYER_HIT_PERIOD_DELTA   EQU 112        ; +112/frame → final $0240 (~150 Hz)

; --- Death (golpe fatal): mas grave que el hit, ~1s ---
PLAYER_DEATH_SWEEP_FRAMES EQU 25         ; 25 frames @ 25 fps = 1.0 s
PLAYER_DEATH_PERIOD_INIT  EQU $0080      ; mismo punto de salida agudo
PLAYER_DEATH_PERIOD_DELTA EQU 80         ; +80/frame → final $0850 (~52 Hz)

; ==============================================================================
; AY_PlayPlayerHit / AY_PlayPlayerDeath - wrappers sobre _AY_PlaySweep
; ==============================================================================
; Ambos arman el mismo sweep "agudo→grave" beeper-style. Diferencias: frames
; totales y delta por frame. R2/R3 iniciales son comunes ($0080 ~853 Hz) → la
; tabla los hardcodea.
; ==============================================================================
AY_PlayPlayerHit:
    LD HL, PLAYER_HIT_PERIOD_INIT
    LD B, PLAYER_HIT_SWEEP_FRAMES
    LD DE, PLAYER_HIT_PERIOD_DELTA
    JR _AY_PlaySweep

AY_PlayPlayerDeath:
    LD HL, PLAYER_DEATH_PERIOD_INIT
    LD B, PLAYER_DEATH_SWEEP_FRAMES
    LD DE, PLAYER_DEATH_PERIOD_DELTA
    ; fall through

; IN: HL=period inicial, B=frames, DE=delta.
_AY_PlaySweep:
    LD (PlayerHitPeriod), HL
    LD (PlayerHitDelta), DE
    LD A, B
    LD (PlayerHitFrames), A
    DI
    LD C, $FD
    LD HL, .phRegs
    JP _AY_WriteRegPairs                ; tail call: hace EI + RET

.phRegs:
    DEFB  2, $80          ; R2  = period B lo (= $80, period $0080)
    DEFB  3, $00          ; R3  = period B hi
    DEFB  9, $0F          ; R9  = vol B max FIJA (bit 4 = 0 → SIN envelope)
                          ; (R7 mixer permanece en $38 desde AY_Init — no tocar
                          ; aqui para no cortar las voces A/C de la musica poly2)
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
    ; R9 = $0F (vol max fija, SIN envelope). R7 mixer ya esta en $38 (set por
    ; AY_Init) — no tocar para no apagar las voces A/C de la musica poly2.
    LD HL, .beepRegs
    JP _AY_WriteRegPairs                ; tail call: EI + RET

.beepRegs:
    DEFB  9, $0F          ; vol B = max fija (bit 4 = 0 → sin envelope)
                          ; (R7 mixer permanece en $38 desde AY_Init — no tocar
                          ; aqui para no cortar las voces A/C de la musica poly2)
    DEFB $FF              ; sentinel

; ==============================================================================
; AY_PlayKnockNoise - Click de noise PERCUSIVO en canal B (con envelope HW)
; ==============================================================================
; Usa el generador de noise del AY (R6) MAS el envelope HW (R11/R12 period,
; R13 shape \$09 = decay one-shot que se queda en 0). Esto da ataque inmediato
; a vol max y decay rapido — suena percusivo en lugar de buzz constante.
;
; Cambia R7 mixer para enable noise B + disable tone B (A/C intactos para no
; cortar la musica). R9 = \$10 (bit 4 = use envelope; bits 0-3 ignorados).
;
; CRITICO: R13 retrigger debe escribirse ULTIMO — cualquier write a R13
; dispara el envelope desde el principio, asi que tiene que ir despues de
; configurar R11/R12 (period) y R9 (vol mode = envelope).
;
; CRITICO: _uphMuteR9 fue extendido para restaurar R7=\$38 al final del cutoff.
; Sin eso, tras el knock tone B quedaria desabilitado y siguientes beeps/hits
; no sonarian.
;
; Tuning del decay: R11/R12 = envelope period 16-bit. Con master clock 1.77MHz,
; un step del envelope = period × (256/clock) ≈ period/6928 seg. El envelope
; baja 16 steps (15→0). Ejemplos:
;   period \$0020 (32) → 32*16/6928 ≈ 74 ms (snappy, recomendado)
;   period \$0040 (64) → ~148 ms (mas mate)
;   period \$0010 (16) → ~37 ms (super seco)
;
; IN: B = duracion en frames del cutoff hard (a 25fps: 2 ≈ 80ms). Con envelope
; activo, el sonido decae solo antes del cutoff — el cutoff solo asegura que
; el mute de R9 + restore de R7 ocurra al final. B=2 frames OK.
; Destruye: A, BC, HL.
; ==============================================================================
AY_PlayKnockNoise:
    LD A, B
    LD (BeepDurationFrames), A          ; arma cutoff via ticker
    DI
    LD C, $FD
    LD HL, .knockRegs
    JP _AY_WriteRegPairs                ; tail-call: EI + RET

.knockRegs:
    DEFB  2, $00          ; R2 tone B period lo
    DEFB  3, $02          ; R3 tone B period hi (period $0200 ~217 Hz: tono
                          ; grave que da "body" al knock — la nota la enmascara
                          ; el noise pero su energia se suma al volumen percibido)
    DEFB  6, $05          ; R6 noise period: small (~5) = chasquido seco/agudo
    DEFB  7, $28          ; R7 mixer: $28 = 0010 1000
                          ;   bit 0 (tone A en) = 0 ✓ musica A sigue
                          ;   bit 1 (tone B en) = 0 ON ← tone B activo (boost vol)
                          ;   bit 2 (tone C en) = 0 ✓ musica C sigue
                          ;   bit 3 (noise A) = 1 (off)
                          ;   bit 4 (noise B) = 0 ON ← noise B activo
                          ;   bit 5 (noise C) = 1 (off)
                          ; Tone+noise en mismo canal B se MEZCLAN a la salida
                          ; → potencia perceptual mayor que noise solo.
    DEFB 11, $00          ; R11 envelope period lo
    DEFB 12, $04          ; R12 envelope period hi (period $0400 = ~2.4s decay
                          ; → durante 160ms cutoff, envelope decae solo de 15
                          ; a ~14, practicamente constante max. El "percusivo"
                          ; lo da el cutoff abrupto al final.)
    DEFB  9, $10          ; R9 vol B = use envelope (bit 4 = 1, bits 0-3 ign)
    DEFB 13, $09          ; R13 envelope shape: \___ (decay one-shot, hold 0)
                          ; → ataque inmediato + decay lento = max vol durante
                          ; toda la ventana. Tiene que ir ULTIMO: writing R13
                          ; retriggers envelope desde el principio.
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
; AY_UpdatePlayerHit - Per-frame: sweep R2/R3 hacia grave + cutoff beep
; ==============================================================================
; LLAMADO DESDE EL IRQ HANDLER (music_irq.asm) cada 2 IRQs (= 25 Hz). El
; handler ya tiene interrupts deshabilitados al entrar — esta rutina NO hace
; DI/EI internos. Si se llamara desde MainLoop, una IRQ podria caer mid-OUT
; corrompiendo el AY register pointer; pero como solo se llama desde IRQ
; (con IFF=0), no hay race.
;
; Tickea: PlayerHitFrames (sweep hit/death) Y BeepDurationFrames (beep
; BASIC-style). No-op si ambos inactivos (RET Z).
; Destruye: A, BC, DE, HL.
; ==============================================================================
AY_UpdatePlayerHit:
    LD A, (PlayerHitFrames)
    OR A
    JR Z, .uphCheckBeep
    DEC A
    LD (PlayerHitFrames), A
    JR Z, _uphMuteR9                    ; ultimo frame: cutoff abrupto beeper-style

    LD HL, (PlayerHitPeriod)
    LD DE, (PlayerHitDelta)             ; delta variable (hit=32, death=40)
    ADD HL, DE
    LD (PlayerHitPeriod), HL

    ; Escribir R2 = L, R3 = H (period B). Sin DI/EI: ya en contexto IRQ.
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
    RET

; --- Tick del beep BASIC-style: decrementa contador, mute al llegar a 0 ---
.uphCheckBeep:
    LD A, (BeepDurationFrames)
    OR A
    RET Z
    DEC A
    LD (BeepDurationFrames), A
    RET NZ
    ; fall-through al cutoff compartido

; --- Cutoff abrupto compartido: mute R9 (canal B vol = 0). Sin DI/EI. ---
; Llamado al final del sweep (PlayerHit/Death), beep o knock.
; Tras mute, restaura R7 mixer a $38 (default de AY_Init: tones A/B/C on,
; noise A/B/C off). Solo importa para el knock (que cambio R7 a $2A);
; para hit/beep es redundante pero idempotente. Coste fijo ~10 T extra.
_uphMuteR9:
    LD BC, $FFFD
    LD A, 9
    OUT (C), A
    LD BC, $BFFD
    XOR A
    OUT (C), A
    ; Restaurar R7 mixer al default ($38 = tone ABC on, noise ABC off)
    LD BC, $FFFD
    LD A, 7
    OUT (C), A
    LD BC, $BFFD
    LD A, $38
    OUT (C), A
    RET
