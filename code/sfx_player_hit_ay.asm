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
; AY_PlayKnockSoft / AY_PlayKnockLoud - Knock percusivo en canal B
; ==============================================================================
; Dos variantes de knock que comparten cutoff mechanism (BeepDurationFrames):
;
; Soft (grupos de 3 toques): noise B solo (tone B off), envelope $0200 (~1.2s
;   decay). Knock seco, mas discreto. R7 = $2A.
;
; Loud (grupo de 6 toques): noise B + tone B mix (~217 Hz), envelope $0400
;   (~2.4s decay). Knock con "body" del tone, vol perceptual ~3 dB mayor.
;   R7 = $28.
;
; Ambos:
;   - R6 = $05 (noise period, chasquido seco/agudo).
;   - R9 = $10 (use envelope, bit 4 set).
;   - R13 = $09 (decay shape, \___, retrigger en cada call). Va ULTIMO.
;   - _uphMuteR9 restaura R7 = $38 al cutoff (cleanup tras knock).
;
; IN: B = duracion frames cutoff (recomendado 4 = ~160ms).
; Destruye: A, BC, HL.
; ==============================================================================
AY_PlayKnockSoft:
    LD HL, _knockSoftRegs
    JR _ay_play_knock_seq

AY_PlayKnockLoud:
    LD HL, _knockLoudRegs
    ; fall through

_ay_play_knock_seq:
    LD A, B
    LD (BeepDurationFrames), A          ; arma cutoff via ticker
    DI
    LD C, $FD
    JP _AY_WriteRegPairs                ; tail-call: EI + RET

_knockSoftRegs:
    DEFB  6, $05          ; R6 noise period
    DEFB  7, $2A          ; R7 mixer: noise B on, tone B off
    DEFB 11, $00          ; R11 envelope period lo
    DEFB 12, $02          ; R12 envelope period hi ($0200 ~1.2s decay)
    DEFB  9, $10          ; R9 vol B = use envelope
    DEFB 13, $09          ; R13 envelope shape \___ (retrigger)
    DEFB $FF

_knockLoudRegs:
    DEFB  2, $00          ; R2 tone B period lo
    DEFB  3, $02          ; R3 tone B period hi ($0200 ~217 Hz, body grave)
    DEFB  6, $05          ; R6 noise period
    DEFB  7, $28          ; R7 mixer: tone B + noise B both on
    DEFB 11, $00          ; R11 envelope period lo
    DEFB 12, $04          ; R12 envelope period hi ($0400 ~2.4s decay)
    DEFB  9, $10          ; R9 vol B = use envelope
    DEFB 13, $09          ; R13 envelope shape \___ (retrigger)
    DEFB $FF

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
    ; --- PendingPin tick: dispara beep diferido (lasting compass stage 2) ---
    ; Cuando AY_PlayLastingPickup arma una "PIN" tras el sweep, el ticker la
    ; dispara cuando el contador llega a 0. Escritura R2/R3/R9 inline (sin
    ; DI/EI: ya en contexto IRQ). Tras setear BeepDurationFrames el cutoff
    ; lo gestiona el path .uphCheckBeep en proximos ticks.
    LD A, (PendingPinTimer)
    OR A
    JR Z, .uphAfterPin
    DEC A
    LD (PendingPinTimer), A
    JR NZ, .uphAfterPin
    LD HL, (PendingPinPeriod)
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
    LD A, 9
    LD B, $FF
    OUT (C), A
    LD A, $0F                           ; vol max canal B
    LD B, $BF
    OUT (C), A
    LD A, (PendingPinFrames)
    LD (BeepDurationFrames), A          ; arma cutoff
    RET                                 ; skip resto del ticker este frame
.uphAfterPin:
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

; ==============================================================================
; AchievementJingle - Chime AY corto al entrar en la sala del hito actual
; ==============================================================================
; 3 notas C-G-C ascendentes (arpegio clasico de "achievement"). Canal B AY.
; No bloqueante: tickea desde MainLoop frame a frame. Patron espejo del
; MagicCompassJingle pero con tabla y estado independiente — evita refactor
; del compass jingle que ya esta en produccion. Coste: ~50 B asm + 2 B RAM.
;
; Trigger: CheckScreenTransition.doTransition cuando el player cruza a la
;          sala del hito (CurrentScreen == ObjectiveScreen).
; Ticker:  UpdateAchievementJingle, llamado cada frame desde MainLoop.
; ==============================================================================

AchievementJingleTable:
    DEFW $0080      ; nota 1: ~853 Hz (C6-ish)
    DEFB 4, 0       ; 4 frames (~160ms), 0 = no es la ultima
    DEFW $0055      ; nota 2: ~1280 Hz (G6, perfect fifth above)
    DEFB 4, 0
    DEFW $0040      ; nota 3: ~1707 Hz (C7, octave above)
    DEFB 8, 1       ; 8 frames (~320ms), 1 = ultima

; --- State (2 B) ---
AchievementJingleIdx:    DEFB $FF   ; $FF = inactivo
AchievementJingleFrames: DEFB 0

; ==============================================================================
; StartAchievementJingle - Arranca el chime (desde CheckScreenTransition)
; ==============================================================================
StartAchievementJingle:
    XOR A
    LD (AchievementJingleIdx), A     ; idx=0 (primera nota)
    INC A
    LD (AchievementJingleFrames), A  ; frames=1 -> dispara nota en proxima tick
    RET

; ==============================================================================
; UpdateAchievementJingle - Tick frame a frame; dispara nota cuando toca
; ==============================================================================
; Llamado desde MainLoop (cerca de UpdateMonstersMusic). No-op si idx=$FF.
; ==============================================================================
UpdateAchievementJingle:
    LD A, (AchievementJingleIdx)
    CP $FF
    RET Z                            ; inactivo

    LD HL, AchievementJingleFrames
    DEC (HL)
    RET NZ                           ; nota actual aun sonando

    ; Frames expiraron: leer entry de la tabla y disparar
    LD A, (AchievementJingleIdx)
    ADD A, A
    ADD A, A                         ; idx * 4 (entry size)
    LD E, A
    LD D, 0
    LD HL, AchievementJingleTable
    ADD HL, DE
    LD E, (HL) : INC HL
    LD D, (HL) : INC HL              ; DE = period
    LD A, (HL) : INC HL              ; A = frames de la nota
    LD (AchievementJingleFrames), A
    LD B, A                          ; B = duration para AY_PlayBeep cutoff
    LD A, (HL)                       ; A = isLast flag
    PUSH AF
    EX DE, HL                        ; HL = period
    CALL AY_PlayBeep
    POP AF
    OR A
    JR NZ, .ajLast
    ; No es la ultima -> avanzar idx
    LD A, (AchievementJingleIdx)
    INC A
    LD (AchievementJingleIdx), A
    RET
.ajLast:
    LD A, $FF
    LD (AchievementJingleIdx), A     ; marcar inactivo
    RET

; ==============================================================================
; CompassPickup SFX (random + lasting) - sweeps tipo PlayerHit/Death
; ==============================================================================
; Reusan _AY_PlaySweep (sweep continuo de pitch en canal B AY, no bloqueante,
; cutoff abrupto al final via _uphMuteR9). Llamados desde ApplyMagicCompassBuff
; segun MagicCompassPermanent: random -> AY_PlayCompassPickup (solo sweep),
; lasting -> AY_PlayLastingPickup (sweep + PIN sostenido tipo "WHHIII-PIN").
;
; Direccion del sweep: GRAVE -> AGUDO ("found it!" feel). Period inicial alto,
; delta NEGATIVO en two's complement ($FFE8 = -24 etc). _AY_PlaySweep usa
; ADD HL, DE asi que el wrap unsigned funciona como resta.
; ==============================================================================

; Random compass: sweep ascendente ~640 ms (16 frames)
;   $0200 (210 Hz, B3) -> $0080 (853 Hz, A5) — 2 octavas
COMPASS_SWEEP_PERIOD_INIT  EQU $0200
COMPASS_SWEEP_FRAMES       EQU 16
COMPASS_SWEEP_DELTA        EQU $FFE8         ; -24/frame

; Lasting compass: sweep ascendente ~880 ms (22 frames) + PIN sostenido
;   Sweep: $0300 (140 Hz, D3) -> $0040 (1700 Hz, ~A6) — 3+ octavas
;   PIN: $0030 (~2270 Hz) por 6 frames (240 ms), 1 frame despues del sweep
LASTING_SWEEP_PERIOD_INIT  EQU $0300
LASTING_SWEEP_FRAMES       EQU 22
LASTING_SWEEP_DELTA        EQU $FFE0         ; -32/frame
LASTING_PIN_PERIOD         EQU $0030         ; ~2270 Hz, muy brillante
LASTING_PIN_FRAMES         EQU 6             ; 240 ms
LASTING_PIN_DELAY          EQU LASTING_SWEEP_FRAMES + 1   ; fire 1 frame tras cutoff

; State del PIN diferido (tickeado por AY_UpdatePlayerHit)
PendingPinTimer:    DEFB 0       ; >0 = pendiente; 0 = nada
PendingPinPeriod:   DEFW 0       ; period AY canal B
PendingPinFrames:   DEFB 0       ; duracion del beep tras dispararse

; AY_PlayCompassPickup - magic compass random
AY_PlayCompassPickup:
    LD HL, COMPASS_SWEEP_PERIOD_INIT
    LD B, COMPASS_SWEEP_FRAMES
    LD DE, COMPASS_SWEEP_DELTA
    JP _AY_PlaySweep                  ; tail call

; AY_PlayLastingPickup - lasting compass: sweep + PIN encadenado
AY_PlayLastingPickup:
    LD HL, LASTING_SWEEP_PERIOD_INIT
    LD B, LASTING_SWEEP_FRAMES
    LD DE, LASTING_SWEEP_DELTA
    CALL _AY_PlaySweep
    ; Encolar PIN (beep agudo final) para que dispare 1 frame tras el sweep
    LD HL, LASTING_PIN_PERIOD
    LD (PendingPinPeriod), HL
    LD A, LASTING_PIN_FRAMES
    LD (PendingPinFrames), A
    LD A, LASTING_PIN_DELAY
    LD (PendingPinTimer), A
    RET
