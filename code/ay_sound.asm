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
; AY_Init - Silencia todos los canales (volumen 0, mixer todo off)
; ==============================================================================
AY_InitImpl:
    LD A, 7                     ; mixer
    LD E, $3F                   ; todos los tonos y ruidos en off
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
    ; --- Calcular dx (signed) y |dx|, |dy| ---
    LD A, (CurrentScreenX)
    SUB START_SCREEN_X          ; A = dx (signed: + plaza al oeste, - plaza al este)
    LD D, A                     ; D = dx signed (player - plaza)
    JR NC, .absDxOk
    NEG
.absDxOk:
    LD B, A                     ; B = |dx|

    LD A, (CurrentScreenY)
    SUB START_SCREEN_Y
    JR NC, .absDyOk
    NEG
.absDyOk:
    ADD A, B                    ; A = |dx| + |dy| = distancia Manhattan
    LD C, A                     ; C = distancia

    ; --- Volumen total = max(15 - dist*2, 1) ---
    ADD A, A                    ; A = dist * 2
    LD B, A
    LD A, 15
    SUB B                       ; A = 15 - dist*2
    JR NC, .volTotalOk
    LD A, 1
.volTotalOk:
    OR A
    JR NZ, .volTotalSet
    LD A, 1
.volTotalSet:
    LD B, A                     ; B = volumen total (1-15)

    ; --- Reparto del volumen entre canales segun dx (D = player-plaza) ---
    ; D > 0  → player está al ESTE de plaza → plaza al oeste (canal A más fuerte)
    ; D < 0  → player está al OESTE de plaza → plaza al este (canal C más fuerte)
    ; D == 0 → alineado X → canal B
    LD A, D
    OR A
    JR Z, .panCenter
    JP P, .panLeft              ; D > 0 (positivo): plaza al oeste
    ; D < 0: plaza al este → canal C dominante
    LD A, B                     ; A = vol total
    LD (BellVolR), A            ; canal C = full
    SRL B
    LD A, B
    LD (BellVolC), A            ; canal B = mitad
    SRL B
    LD A, B
    LD (BellVolL), A            ; canal A = cuarto
    JR .panDone

.panLeft:
    ; D > 0: plaza al oeste → canal A dominante
    LD A, B
    LD (BellVolL), A
    SRL B
    LD A, B
    LD (BellVolC), A
    SRL B
    LD A, B
    LD (BellVolR), A
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
; MUSIC DRIVER - Reproductor tabular generico no-bloqueante (canal A)
; ==============================================================================
; El driver es content-agnostic: solo recorre MusicPtr y avanza notas hasta
; duration=0. Cualquier tabla en el formato (period_lo, period_hi, duration)
; suena con este motor. El dispatch entre tracks vive en StartMusicImpl.
;
; Tracks actuales:
;   0 = Tension     (TensionMusicTable)  lights-off -> monster spawn
;   1 = Sunrise     (SunriseMusicTable)  fase 5 del dia
;   2 = EndGame     (EndGameMusicTable)  pantalla de creditos
;   3 = GameOver    (GameOverMusicTable) jingle de muerte final
;
; CPU-free durante la reproduccion: solo escribe registros AY al cambiar de nota.
; No interfiere con BellVolL/C/R cuando el bell ya completo decay; ver gotcha
; en project_ay_music_driver.md para tracks que se solapan con bell activo.
; ==============================================================================
MusicPtr:    DEFW 0          ; Ptr a la nota actual en la tabla activa
MusicTimer:  DEFB 0          ; Frames restantes en la nota actual (0 = inactivo)

; Period AY = 1750000 / (16 * frequency). Duraciones en frames a 25fps (1f=40ms).
; Tablas pueden tener cualquier longitud — el driver no asume nada salvo el
; terminator (period=0, duration=0).

; --- Track 0: TensionMusic ---
; 4 notas en registro grave de organo (A2 - C3 - A2 - D3, ~1.5s total).
TensionMusicTable:
    DEFW $03E2                      ; A2  ~110 Hz
    DEFB 9                          ; ~360ms
    DEFW $0344                      ; C3  ~131 Hz
    DEFB 9
    DEFW $03E2                      ; A2
    DEFB 9
    DEFW $02E9                      ; D3  ~147 Hz (climax mas alto)
    DEFB 11                         ; ~440ms sostenido
    DEFW 0
    DEFB 0                          ; fin

; --- Track 1: SunriseMusic ---
; Arpegio ascendente C major + resolucion, ~5s. Borrador inicial — iterar.
SunriseMusicTable:
    DEFW $0344                      ; C3  ~131 Hz
    DEFB 6
    DEFW $0297                      ; E3  ~165 Hz
    DEFB 6
    DEFW $022E                      ; G3  ~196 Hz
    DEFB 6
    DEFW $01A2                      ; C4  ~262 Hz
    DEFB 6
    DEFW $014C                      ; E4  ~330 Hz
    DEFB 12                         ; sostenido
    DEFW $01A2                      ; C4
    DEFB 6
    DEFW $022E                      ; G3
    DEFB 6
    DEFW $01A2                      ; C4
    DEFB 6
    DEFW $014C                      ; E4
    DEFB 6
    DEFW $0117                      ; G4  ~392 Hz climax
    DEFB 30                         ; ~1.2s final brillante
    DEFW 0
    DEFB 0

; --- Track 2: EndGameMusic ---
; Fanfarria de victoria, mayor, ~6s. Borrador inicial — iterar.
EndGameMusicTable:
    DEFW $022E                      ; G3
    DEFB 4                          ; corchea
    DEFW $022E                      ; G3
    DEFB 4
    DEFW $022E                      ; G3
    DEFB 4
    DEFW $01A2                      ; C4
    DEFB 12                         ; negra punteada
    DEFW $014C                      ; E4
    DEFB 8
    DEFW $01A2                      ; C4
    DEFB 4
    DEFW $014C                      ; E4
    DEFB 16                         ; blanca
    DEFW $0117                      ; G4
    DEFB 4
    DEFW $014C                      ; E4
    DEFB 4
    DEFW $01A2                      ; C4
    DEFB 4
    DEFW $0117                      ; G4
    DEFB 30                         ; final largo brillante
    DEFW 0
    DEFB 0

; --- Track 3: GameOverMusic ---
; Descenso menor, somber, ~2.5s. Borrador inicial — iterar.
GameOverMusicTable:
    DEFW $01F1                      ; A3  ~220 Hz
    DEFB 10
    DEFW $022E                      ; G3
    DEFB 10
    DEFW $0272                      ; F3
    DEFB 10
    DEFW $0297                      ; E3
    DEFB 10
    DEFW $02E9                      ; D3
    DEFB 12
    DEFW $0344                      ; C3 (resolucion grave)
    DEFB 24                         ; final sostenido ~960ms
    DEFW 0
    DEFB 0

; --- StartMusicImpl: dispatcher entre tracks. Lee track_id de MusicTrackArg ---
; Entrada: (MusicTrackArg) = 0..3 (Tension, Sunrise, EndGame, GameOver). Track ids
; desconocidos resultan en no-op (RET sin armar nada). Setup AY (mixer + vol)
; compartido. NO usar A como entrada: el thunk en bank 2 clobbea A al leer
; CurrentPaging antes del CALL (ver project_ay_thunk_stack_bug.md).
StartMusicImpl:
    ; Resolver puntero a tabla segun track_id
    LD A, (MusicTrackArg)
    LD HL, TensionMusicTable
    OR A
    JR Z, .smArm
    LD HL, SunriseMusicTable
    DEC A
    JR Z, .smArm
    LD HL, EndGameMusicTable
    DEC A
    JR Z, .smArm
    LD HL, GameOverMusicTable
    DEC A
    JR Z, .smArm
    RET                             ; track_id desconocido: no-op
.smArm:
    PUSH HL                         ; preservar tabla a traves de AY_WriteReg (clobbea BC/A)
    ; Mixer: solo tono B activo (A/C off, ruidos off). Canal B = centro (ambos
    ; altavoces) en cableado ACB del Spectrum 128. Canal A es izquierdo y C es
    ; derecho — reservados para campanadas con paneo segun distancia a plaza.
    LD A, 7
    LD E, $3D                       ; %00111101 (bit 1=0 -> B tono on; bits 0,2=1 -> A,C off)
    CALL AY_WriteReg
    ; Volumen canal B (R9)
    LD A, 9
    LD E, 12                        ; vol medio-alto
    CALL AY_WriteReg
    POP HL
    LD (MusicPtr), HL
    JP MusicAdvanceNote

; --- UpdateMusicImpl: catchup wall-clock — avanza N game frames donde
; N = FramesElapsed (calculado en MainLoop top). Bajo carga normal N=1.
; Tras una transicion lenta puede ser N=3..10 → consume varias notas en una
; llamada para preservar el ritmo en wall-clock.
UpdateMusicImpl:
    LD A, (FramesElapsed)
    OR A
    RET Z
    LD B, A
.upmiLoop:
    PUSH BC
    CALL .upmiTickOnce
    POP BC
    DJNZ .upmiLoop
    RET

.upmiTickOnce:
    LD A, (MusicTimer)
    OR A
    RET Z                           ; inactivo
    DEC A
    LD (MusicTimer), A
    RET NZ                          ; aun en la nota actual
    ; Hora de la siguiente nota (fall-through a MusicAdvanceNote)

; --- MusicAdvanceNote: lee 3 bytes de la tabla y aplica al AY ---
; Formato de entry (3 bytes):
;   period=$XXXX, duration=$NN  -> nota normal a ese pitch durante NN frames
;   period=$0000, duration=$NN  -> rest (mute R8) durante NN frames (NN!=0)
;   period=$0000, duration=$00  -> terminador (silencia canal y para)
;
; OJO: AY_WriteReg clobbea B y C (LD BC, $FFFD/$BFFD). Hay que stashear los
; bytes de period en D y E (que SI se preservan a traves del call).
MusicAdvanceNote:
    LD HL, (MusicPtr)
    LD E, (HL)                      ; E = pitch_lo
    INC HL
    LD D, (HL)                      ; D = pitch_hi
    INC HL
    LD A, (HL)                      ; duration
    INC HL
    OR A
    JR Z, .manEnd                   ; duration = 0 -> fin de tabla
    LD (MusicPtr), HL
    LD (MusicTimer), A
    ; ¿es rest? (period == 0 y duration != 0)
    LD A, E
    OR D
    JR Z, .manRest
    ; Nota normal: re-armar vol R9 (por si venimos de un rest que la mute) +
    ; escribir period en R2/R3 (canal B). Re-armar siempre cuesta 1 AY_WriteReg
    ; extra por nota; mas barato que llevar un flag de estado.
    PUSH DE
    LD A, 9
    LD E, 12
    CALL AY_WriteReg                ; R9 = vol B medio-alto
    POP DE
    LD A, 2                         ; R2 = period B low
    CALL AY_WriteReg                ; escribe E (pitch_lo); D preservado
    LD A, 3                         ; R3 = period B high
    LD E, D                         ; recargar E con pitch_hi
    JP AY_WriteReg                  ; tail-call
.manRest:
    ; Silencio durante MusicTimer frames; UpdateMusicImpl seguira tickeando.
    LD A, 9
    LD E, 0
    JP AY_WriteReg                  ; tail-call (mute R9)
.manEnd:
    ; Silenciar canal B
    XOR A
    LD (MusicTimer), A              ; flag inactivo
    LD A, 9
    LD E, 0
    JP AY_WriteReg                  ; tail-call
