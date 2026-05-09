; ==============================================================================
; AY SOUND - Driver del chip AY-3-8912 (Spectrum 128K)
; ==============================================================================
; Puertos:
;   $FFFD: write = seleccionar registro AY (0-13)
;   $BFFD: write = escribir valor al registro seleccionado
;
; Registros AY:
;   R0/R1: tono canal A (12 bits, period = 1750000 / (16 * frequency))
;   R2/R3: tono canal B
;   R4/R5: tono canal C
;   R6:    period del ruido (5 bits)
;   R7:    mixer (bit 0-2: tonos A/B/C off, bit 3-5: ruido A/B/C off, bit 6-7: I/O)
;          bit a 0 = canal activo, bit a 1 = silenciado
;   R8:    volumen A (bits 0-3) o envelope (bit 4=1)
;   R9:    volumen B
;   R10:   volumen C
;   R11/R12: period del envelope
;   R13:   forma del envelope (0-15)
; ==============================================================================

; ==============================================================================
; AY_WriteReg - Escribe un valor en un registro AY
; ==============================================================================
; Entrada: A = registro (0-13), E = valor
; Destruye: BC, A
; ==============================================================================
AY_WriteReg:
    LD BC, $FFFD
    OUT (C), A                  ; seleccionar registro
    LD BC, $BFFD
    OUT (C), E                  ; escribir valor
    RET

; ==============================================================================
; AY_Stop - Silencia inmediatamente cualquier sonido en curso
; ==============================================================================
; Mismo efecto que AY_Init pero pensado para silenciar antes de un SFX beeper
; ==============================================================================
AY_StopImpl:
    LD A, 8
    LD E, 0
    CALL AY_WriteReg
    LD A, 9
    LD E, 0
    CALL AY_WriteReg
    LD A, 10
    LD E, 0
    CALL AY_WriteReg
    RET


; ==============================================================================
; AY_Init - Silencia todos los canales (volumen 0). Mixer = $38 (todos los
; tonos enable, ruidos off). El silencio se gestiona via volumen por canal:
; bell, music poly y SFX comparten el chip sin clobbear el mixer entre ellos.
; ==============================================================================
AY_InitImpl:
    LD A, 7                     ; mixer
    LD E, $38                   ; tonos ABC on, ruidos off; muting via vol
    CALL AY_WriteReg
    LD A, 8                     ; volumen A
    LD E, 0
    CALL AY_WriteReg
    LD A, 9                     ; volumen B
    LD E, 0
    CALL AY_WriteReg
    LD A, 10                    ; volumen C
    LD E, 0
    CALL AY_WriteReg
    RET

; ==============================================================================
; AY_PlayBellChime - Toca una campanada de iglesia en el canal A
; ==============================================================================
; Tono grave + envelope decay. La CPU queda libre inmediatamente —
; el AY toca solo durante el decay.
; ==============================================================================
; Period para canal A: tono grave ~110Hz → period = 1750000/(16*110) ≈ 994 = $3E2
; ==============================================================================
; ==============================================================================
; Variables del decay manual de la campana (con pan estereo)
; ==============================================================================
; BellVolL/C/R: volumen actual de cada canal (0-15)
; BellMaxL/C/R: volumen inicial de cada canal (set en AY_PlayBellChime)
; Cuando los 3 son 0, la campana esta silenciada.
BellVolL:       DEFB 0          ; volumen actual canal A (izquierdo)
BellVolC:       DEFB 0          ; volumen actual canal B (centro)
BellVolR:       DEFB 0          ; volumen actual canal C (derecho)
BellDecayTimer: DEFB 0          ; frames hasta el siguiente decremento

BELL_DECAY_RATE EQU 2           ; 2 frames a 25fps (era 4 a 50fps)

; ==============================================================================
; AY_PlayBellChime - Inicia una campanada con volumen + pan estereo
; ==============================================================================
; Volumen total proporcional a la distancia Manhattan a la plaza.
; Pan: dx>0 plaza al este (mas C), dx<0 plaza al oeste (mas A), dx=0 centro (B).
; ==============================================================================
AY_PlayBellChimeImpl:
    ; --- Calcular dx (signed) y |dx|, |dy| respecto a la PLAZA del reloj ---
    ; (No usar START_SCREEN_X/Y, que es el spawn del player y cambia con el
    ; editor — el sonido espacial debe centrarse en la plaza real).
    LD A, (CurrentScreenX)
    SUB PLAZA_SCREEN_X          ; A = dx (signed: + player al este, - player al oeste)
    LD D, A                     ; D = dx signed (player - plaza)
    JR NC, .absDxOk
    NEG
.absDxOk:
    LD B, A                     ; B = |dx|

    LD A, (CurrentScreenY)
    SUB PLAZA_SCREEN_Y
    JR NC, .absDyOk
    NEG
.absDyOk:
    ADD A, B                    ; A = |dx| + |dy| = distancia Manhattan

    ; --- Volumenes por tramo: dom(inante) y far (canal opuesto al dom) ---
    ;   dist 0..2  -> dom=15, far=12  (cerca: bell envolvente, dom +9dB)
    ;   dist 3..5  -> dom=12, far= 8  (medio: mas direccional, dom +12dB)
    ;   dist 6+    -> dom= 9, far= 5  (lejos: muy direccional, dom +12dB)
    ; Centro (canal B en stereo) = dom/2. En panCenter (dx=0) solo suena B.
    LD B, 9                     ; default tramo lejano: dom
    LD C, 5                     ;                       far
    CP 6
    JR NC, .volTotalSet
    LD B, 12                    ; tramo medio
    LD C, 8
    CP 3
    JR NC, .volTotalSet
    LD B, 15                    ; tramo cercano
    LD C, 12
.volTotalSet:                   ; B = dom_vol, C = far_vol

    ; --- Reparto del volumen entre canales segun dx (D = player-plaza) ---
    ; D > 0  → player al ESTE de plaza → plaza al oeste (canal A dominante)
    ; D < 0  → player al OESTE de plaza → plaza al este (canal C dominante)
    ; D == 0 → alineado X → solo canal B (centro)
    LD A, D
    OR A
    JR Z, .panCenter
    JP P, .panLeft              ; D > 0 (positivo): plaza al oeste
    ; D < 0: plaza al este → canal C dominante
.panRight:
    LD A, C
    LD (BellVolL), A            ; canal A = far (lejano de plaza)
    LD A, B
    LD (BellVolR), A            ; canal C = dom
    SRL A
    LD (BellVolC), A            ; canal B = dom/2
    JR .panDone

.panLeft:
    ; D > 0: plaza al oeste → canal A dominante
    LD A, B
    LD (BellVolL), A            ; canal A = dom
    SRL A
    LD (BellVolC), A            ; canal B = dom/2
    LD A, C
    LD (BellVolR), A            ; canal C = far
    JR .panDone

.panCenter:
    ; Alineado: solo canal B
    LD A, B
    LD (BellVolC), A
    XOR A
    LD (BellVolL), A
    LD (BellVolR), A

.panDone:
    LD A, BELL_DECAY_RATE
    LD (BellDecayTimer), A

    ; --- Configurar tono en los 3 canales (period 600 = $0258 → ~180Hz) ---
    LD A, 0                     ; R0: tone A LSB
    LD E, $58
    CALL AY_WriteReg
    LD A, 1                     ; R1: tone A MSB
    LD E, $02
    CALL AY_WriteReg
    LD A, 2                     ; R2: tone B LSB
    LD E, $58
    CALL AY_WriteReg
    LD A, 3                     ; R3: tone B MSB
    LD E, $02
    CALL AY_WriteReg
    LD A, 4                     ; R4: tone C LSB
    LD E, $58
    CALL AY_WriteReg
    LD A, 5                     ; R5: tone C MSB
    LD E, $02
    CALL AY_WriteReg

    ; --- Mixer: tonos A, B, C activos ---
    LD A, 7
    LD E, $38                   ; 00111000: ruidos off, tonos ABC on
    CALL AY_WriteReg

    ; --- Volúmenes iniciales ---
    LD A, 8
    LD HL, BellVolL
    LD E, (HL)
    CALL AY_WriteReg
    LD A, 9
    LD HL, BellVolC
    LD E, (HL)
    CALL AY_WriteReg
    LD A, 10
    LD HL, BellVolR
    LD E, (HL)
    CALL AY_WriteReg

    RET

; ==============================================================================
; AY_UpdateBell - Decay manual del volumen de los 3 canales
; ==============================================================================
; Llamar cada frame desde el main loop.
; ==============================================================================
; AY_UpdateBellImpl: catchup wall-clock — avanza N game frames de decay donde
; N = FramesElapsed (calculado en MainLoop top). Identico a tickear N veces
; per-frame (preserva la fase del BellDecayTimer modulo BELL_DECAY_RATE).
AY_UpdateBellImpl:
    LD A, (FramesElapsed)
    OR A
    RET Z
    LD B, A
.aubLoop:
    PUSH BC
    CALL .aubTickOnce
    POP BC
    DJNZ .aubLoop
    RET

.aubTickOnce:
    ; ¿alguno de los 3 canales aún suena?
    LD A, (BellVolL)
    LD B, A
    LD A, (BellVolC)
    OR B
    LD B, A
    LD A, (BellVolR)
    OR B
    RET Z                       ; los 3 a 0 → silenciado

    LD HL, BellDecayTimer
    DEC (HL)
    RET NZ                      ; aun no toca decrementar

    LD A, BELL_DECAY_RATE
    LD (BellDecayTimer), A

    ; Decrementar canal A (si > 0)
    LD A, (BellVolL)
    OR A
    JR Z, .skipA
    DEC A
    LD (BellVolL), A
    LD E, A
    LD A, 8
    CALL AY_WriteReg
.skipA:

    ; Decrementar canal B (si > 0)
    LD A, (BellVolC)
    OR A
    JR Z, .skipB
    DEC A
    LD (BellVolC), A
    LD E, A
    LD A, 9
    CALL AY_WriteReg
.skipB:

    ; Decrementar canal C (si > 0)
    LD A, (BellVolR)
    OR A
    RET Z
    DEC A
    LD (BellVolR), A
    LD E, A
    LD A, 10
    JP AY_WriteReg              ; tail call

; ==============================================================================
; MUSIC DRIVER - Dispatcher entre tracks (canal B AY)
; ==============================================================================
; State + tablas + tick (UpdateMusicTick / UpdateMusicImpl / MusicAdvanceNote)
; viven AHORA en code/music_irq.asm (slot 1, $6000-$7FFF, siempre visible).
; El IRQ handler debe poder leer ese codigo/datos sin paginar slot 3 — paginar
; dentro del IRQ rompe los PUSH/POP del propio handler (ver
; project_ay_thunk_stack_bug.md).
;
; Aqui solo queda StartMusicImpl (dispatcher one-shot al cambiar de track):
; corre en bank 4 (paged en slot 3 por su thunk) y referencia simbolos de
; slot 1 (TensionMusicTable, MusicLoop, etc.) que estan siempre visibles.
; Tail-jumpea a MusicAdvanceNote (slot 1) tras setear mixer/vol.
;
; Tracks (mismo formato; ver music_irq.asm para tablas):
;   0=Tension, 1=Sunrise, 2=EndGame (LOOP), 3=GameOver, 4=Death (LOOP)
;   $FF=STOP, $FE=restart, $FD=stop-if-loopable
; ==============================================================================

; (state vars + tablas movidas a music_irq.asm — ver bloque
; "MUSIC DRIVER STATE + TABLES + TICK" alli.)

; --- StartMusicImpl: dispatcher entre tracks. Lee track_id de MusicTrackArg ---
; Entrada: (MusicTrackArg) = 0..4 (track) o $FF (sentinel STOP). Track ids
; desconocidos no listados resultan en no-op (RET sin armar nada). Setup AY
; (mixer + vol) compartido. NO usar A como entrada: el thunk en bank 2 clobbea
; A al leer CurrentPaging antes del CALL (ver project_ay_thunk_stack_bug.md).
StartMusicImpl:
    LD A, (MusicTrackArg)
    CP $FF
    JR Z, .smStop                   ; sentinel: parar musica activa
    CP $FE
    JR Z, .smRestart                ; sentinel: re-armar track actual desde
                                    ; primera nota, PRESERVANDO MusicLoop y
                                    ; MusicSpeedShift (utiles para enfasis
                                    ; ej. "muerte se lanza" -> sigue loop +
                                    ; aplica nuevo tempo desde nota 0).
    CP $FD
    JR Z, .smStopIfLoopable         ; sentinel: parar solo si el track activo
                                    ; es loopable. Usado por screen_system
                                    ; al cambiar sala — corta DeathMusic (loopable,
                                    ; ligada a Death entity) pero deja sonar
                                    ; tension/sunrise (one-shot, music continua).
    ; Default: track no-loopable + tempo normal (se sobrescriben abajo segun track)
    PUSH AF
    XOR A
    LD (MusicLoop), A
    LD (MusicSpeedShift), A         ; nuevo arranque siempre a tempo normal
    POP AF
    ; --- Resolver tabla + modo polifonico segun track id ---
    ; Tracks in-game (0/1/4) = poly2 (canal A+C, B reservado SFX).
    ; Tracks game-end (2/3) = poly3 (A+B+C, sin SFX en escena).
    LD HL, TensionMusicTable
    OR A
    JR Z, .smArmPoly2
    LD HL, SunriseMusicTable
    DEC A
    JR Z, .smArmPoly2
    LD HL, EndGameMusicTable
    DEC A
    JR Z, .smArmPoly3Loop            ; track 2 = LOOPABLE
    LD HL, GameOverMusicTable
    DEC A
    JR Z, .smArmPoly3
    LD HL, DeathMusicTable
    DEC A
    JR Z, .smArmPoly2Loop            ; track 4 = LOOPABLE
    RET                              ; track_id desconocido: no-op

.smArmPoly2Loop:
    LD A, 1
    LD (MusicLoop), A
    ; fall-through
.smArmPoly2:
    LD A, 2
    LD (MusicMode), A
    JR .smArmCommon

.smArmPoly3Loop:
    LD A, 1
    LD (MusicLoop), A
    ; fall-through
.smArmPoly3:
    LD A, 3
    LD (MusicMode), A
    ; fall-through
.smArmCommon:
    LD (MusicTableStart), HL        ; guardar inicio de tabla para reentry en loop
    LD (MusicPtr), HL
    ; Mixer R7 vive en $38 (set por AY_Init) — los 3 tonos enable + ruidos off.
    ; El silencio de un canal se gestiona via vol=0 (en MusicAdvanceNote y en
    ; los SFX). No re-escribimos R7 aqui para no clobbear bell residual.
    JP MusicAdvanceNote             ; tail-call: arma vol+period del primer nota

.smStopIfLoopable:
    ; Sentinel $FD: solo para si el track activo es loopable. Tracks one-shot
    ; (tension/sunrise/endgame) pasan de largo y siguen sonando.
    LD A, (MusicLoop)
    OR A
    RET Z
    ; fall-through al stop normal
.smStop:
    ; Sentinel $FF: silencio inmediato + clear flags. Reusable como cualquier
    ; otro StartMusic call: `LD A, $FF : CALL StartMusic`.
    XOR A
    LD (MusicTimer), A
    LD (MusicLoop), A
    LD (MusicSpeedShift), A         ; reset tempo
    LD H, A
    LD L, A
    LD (MusicPeriodA), HL           ; clear periods → re-arm no escribe AY
    LD (MusicPeriodB), HL
    LD (MusicPeriodC), HL
    ; Mute los 3 canales (poly2 usa A+C; poly3 usa A+B+C; vale para ambos).
    LD A, 8
    LD E, 0
    CALL AY_WriteReg                ; R8 = 0 (vol A)
    LD A, 9
    LD E, 0
    CALL AY_WriteReg                ; R9 = 0 (vol B — solo era usado en poly3)
    LD A, 10
    LD E, 0
    JP AY_WriteReg                  ; tail-call: R10 = 0 (vol C)

.smRestart:
    ; Sentinel $FE: re-armar track actual desde MusicTableStart sin tocar
    ; mixer/vol (ya estan seteados desde StartMusic previo) ni resetear
    ; MusicLoop / MusicSpeedShift. La primera nota suena este mismo frame
    ; (MusicAdvanceNote la carga). Util para sincronizar cambios de tempo
    ; con eventos del juego sin esperar al fin de la nota actual.
    LD HL, (MusicTableStart)
    LD (MusicPtr), HL
    JP MusicAdvanceNote

; (UpdateMusicTick / UpdateMusicImpl / MusicAdvanceNote movidos a music_irq.asm
; — slot 1, siempre visible, llamado desde el IRQ handler sin paginar.)

