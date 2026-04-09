; ==============================================================================
; SOUND ENGINE - Beeper SFX para ZX Spectrum 48K
; ==============================================================================
; Motor de efectos de sonido usando el beeper (puerto $FE, bit 4).
; Soporta tonos con sweep de pitch, ruido percusivo y silencios.
;
; Formato de datos de efecto (4 bytes por paso, terminado con duration=0):
;   DEFB duration      ; iteraciones del bucle externo (0 = fin)
;   DEFB pitch         ; semi-periodo del bucle interno (menor = mas agudo)
;   DEFB pitchDelta    ; sumado al pitch cada iteracion (signed, para sweeps)
;   DEFB flags         ; bit 0 = modo ruido (pitch XOR R para periodos random)
; ==============================================================================

; ==============================================================================
; PlaySFX - Reproduce un efecto de sonido
; ==============================================================================
; Entrada: HL = puntero a datos del efecto
; Modifica: AF, BC, DE, HL
; ==============================================================================
PlaySFX:
    DI                          ; Sin interrupciones para audio limpio
    LD A, (CurrentBorderColor)
    AND $07                     ; Solo bits de color del borde
    LD E, A                     ; E = color del borde (preservado durante output)

.nextStep:
    LD A, (HL)                  ; Leer duration
    OR A
    JR Z, .done                 ; duration=0 → fin del efecto

    LD B, A                     ; B = duration (bucle externo)
    INC HL
    LD C, (HL)                  ; C = pitch (semi-periodo)
    INC HL
    LD D, (HL)                  ; D = pitchDelta (signed)
    INC HL
    LD A, (HL)                  ; A = flags
    INC HL
    PUSH HL                     ; Guardar puntero al siguiente paso
    BIT 0, A
    JR NZ, .noiseLoop           ; bit 0 set → modo ruido

; --- Bucle de tono normal ---
.toneLoop:
    ; Semi-periodo HIGH
    LD A, E
    OR $10                      ; bit 4 = speaker ON
    OUT ($FE), A
    LD A, C                     ; A = pitch actual
.toneDelayHi:
    DEC A
    JR NZ, .toneDelayHi     ; delay proporcional al pitch

    ; Semi-periodo LOW
    LD A, E                     ; speaker OFF (solo borde)
    OUT ($FE), A
    LD A, C
.toneDelayLo:
    DEC A
    JR NZ, .toneDelayLo

    ; Aplicar pitch sweep
    LD A, C
    ADD A, D                    ; pitch += pitchDelta
    JR Z, .toneClamp           ; evitar pitch=0 (bucle infinito)
    JP M, .toneClamp            ; evitar pitch negativo
    LD C, A
.toneAfterClamp:
    DJNZ .toneLoop
    JR .stepDone

.toneClamp:
    LD C, 1                     ; pitch minimo = 1
    JR .toneAfterClamp

; --- Bucle de ruido (periodos pseudo-aleatorios) ---
.noiseLoop:
    ; Semi-periodo HIGH con ruido
    LD A, E
    OR $10
    OUT ($FE), A
    LD A, R                     ; R register como PRNG
    XOR C                       ; mezclar con pitch base
    AND $1F                     ; limitar rango (0-31)
    OR $01                      ; minimo 1
.noiseDelayHi:
    DEC A
    JR NZ, .noiseDelayHi

    ; Semi-periodo LOW
    LD A, E
    OUT ($FE), A
    LD A, R
    XOR C
    AND $1F
    OR $01
.noiseDelayLo:
    DEC A
    JR NZ, .noiseDelayLo

    ; Aplicar pitch sweep (afecta base del ruido)
    LD A, C
    ADD A, D
    JR Z, .noiseClamp
    JP M, .noiseClamp
    LD C, A
.noiseAfterClamp:
    DJNZ .noiseLoop
    JR .stepDone

.noiseClamp:
    LD C, 1
    JR .noiseAfterClamp

.stepDone:
    POP HL                      ; Recuperar puntero al siguiente paso
    JR .nextStep

.done:
    LD A, E                     ; Asegurar speaker OFF al terminar
    OUT ($FE), A
    EI
    RET

; ==============================================================================
; DATOS DE EFECTOS DE SONIDO
; ==============================================================================

; --- SFX_FootstepTic / Tac: "tic-tac" breve al andar ---
; Dos variantes alternas: agudo ("tic") y grave ("tac"), muy cortos
SFX_FootstepTic:
    DEFB 3, 18, 0, 0            ; click agudo brevísimo
    DEFB 0                      ; fin

SFX_FootstepTac:
    DEFB 3, 30, 0, 0            ; click grave brevísimo
    DEFB 0                      ; fin

; --- SFX_Attack: "swish" rapido descendente (~60ms) ---
; Dos pasos: sweep rapido de agudo a grave
SFX_Attack:
    DEFB 40, 8, 1, 0           ; sweep descendente rapido (agudo → medio)
    DEFB 25, 20, 2, 0          ; continua bajando (medio → grave)
    DEFB 0                      ; fin

; --- SFX_EnemyDeath: "explosion" con ruido (~100ms) ---
; Ruido percusivo seguido de tono descendente
SFX_EnemyDeath:
    DEFB 50, 10, 0, 1          ; rafaga de ruido (percusion)
    DEFB 30, 15, 2, 0          ; tono descendente (explosion)
    DEFB 20, 8, 0, 1           ; cola de ruido
    DEFB 0                      ; fin

; --- SFX_PlayerHit: "ouch" ascendente + snap (~80ms) ---
; Tono ascendente rapido seguido de ruido seco
SFX_PlayerHit:
    DEFB 35, 40, -2, 0         ; tono ascendente (grave → agudo)
    DEFB 20, 6, 0, 1           ; snap de ruido corto
    DEFB 15, 12, 1, 0          ; cola tonal descendente
    DEFB 0                      ; fin

; --- SFX_ScreenTransition: "chime" ascendente (~120ms) ---
; Tres tonos escalonados ascendentes
SFX_ScreenTransition:
    DEFB 30, 30, 0, 0          ; tono grave
    DEFB 30, 20, 0, 0          ; tono medio
    DEFB 30, 12, 0, 0          ; tono agudo
    DEFB 20, 8, -1, 0          ; cola con sweep ascendente
    DEFB 0                      ; fin

; --- SFX_EnemySpawn: "pop" ascendente + crackle (~70ms) ---
; Tono rapido ascendente y crujido
SFX_EnemySpawn:
    DEFB 25, 35, -2, 0         ; tono ascendente rapido
    DEFB 20, 5, 0, 0           ; tono agudo breve
    DEFB 15, 12, 0, 1          ; crackle de ruido
    DEFB 0                      ; fin

; --- SFX_WellRecover: tono ascendente "power-up" (~100ms) ---
; Tres escalones ascendentes, tipo recarga
SFX_WellRecover:
    DEFB 50, 60, 0, 0          ; grave profundo
    DEFB 50, 45, 0, 0          ; medio-grave
    DEFB 50, 35, 0, 0          ; medio
    DEFB 50, 25, 0, 0          ; medio-agudo
    DEFB 50, 18, 0, 0          ; agudo
    DEFB 60, 12, -1, 0         ; sweep ascendente
    DEFB 40, 8, 0, 0           ; agudo brillante sostenido
    DEFB 0                      ; fin

; --- SFX_Pickup: "ding" ascendente corto al recoger objeto (~50ms) ---
SFX_Pickup:
    DEFB 40, 50, 0, 0          ; tono grave largo
    DEFB 40, 35, 0, 0          ; tono medio
    DEFB 40, 25, 0, 0          ; tono medio-agudo
    DEFB 40, 18, 0, 0          ; tono agudo
    DEFB 50, 12, -1, 0         ; sweep ascendente final
    DEFB 0                      ; fin

; --- SFX_BellChime: campanada grave de medianoche (~200ms) ---
; Tono grave resonante con decay lento, como campana de iglesia
; --- SFX_BellChime: una campanada grave (~corta, para repetir) ---
SFX_BellChime:
    DEFB 250, 220, 0, 0        ; golpe grave
    DEFB 80, 240, 1, 0         ; decay
    DEFB 0                      ; fin

; --- Sistema de campanadas con pausa entre ellas ---
; Usa la variable de sistema FRAMES ($5C78, 16 bits low) que avanza con cada
; interrupcion de raster — sigue contando aunque PlaySFX bloquee la CPU.
; Asi el ritmo de campanadas se mantiene aunque haya SFX beeper de por medio.
BellCount:      DEFB 0          ; campanadas restantes (0 = inactivo)
BellNextFrame:  DEFW 0          ; valor de FRAMES en el que toca la siguiente
BELL_PAUSE      EQU 75          ; frames de pausa entre campanadas (~1.5s a 50fps)
SYS_FRAMES      EQU $5C78       ; ROM system var, contador 16-bit avanza con interrupts

; --- Cadena de eventos tras la ultima campanada ---
; last chime → (delay) → windows off → (delay) → monster spawn
POST_BELL_WINDOWS_DELAY   EQU 90    ; frames tras ultima campanada hasta apagar ventanas (~1.8s)
POST_WINDOWS_SPAWN_DELAY  EQU 75    ; frames tras apagar ventanas hasta spawnear monsters (~1.5s)
BellsDoneTimer:       DEFB 0        ; >0 = contando hasta windows off
SpawnAfterWinTimer:   DEFB 0        ; >0 = contando hasta monster spawn

; ==============================================================================
; StartBellChimes - Inicia secuencia de 12 campanadas
; ==============================================================================
StartBellChimes:
    LD A, 12
    LD (BellCount), A
    ; Sonar la primera inmediatamente: deadline = FRAMES actual
    LD HL, (SYS_FRAMES)
    LD (BellNextFrame), HL
    LD A, SCARE_TIMER_BELLS
    LD (ScareTimer), A
    RET

; ==============================================================================
; UpdateBellChimes - Llamar cada frame desde el main loop
; ==============================================================================
UpdateBellChimes:
    LD A, (BellCount)
    OR A
    RET Z                       ; sin campanadas pendientes

    ; Comparar FRAMES actual con BellNextFrame
    LD HL, (SYS_FRAMES)
    LD DE, (BellNextFrame)
    OR A
    SBC HL, DE                  ; HL = FRAMES - BellNextFrame
    RET C                       ; FRAMES < deadline → aun no toca

    ; Sonar campanada (AY, no bloquea CPU)
    PUSH BC
    PUSH DE
    CALL AY_PlayBellChime
    POP DE
    POP BC

    ; Resincronizar: deadline siguiente = FRAMES actual + BELL_PAUSE
    ; Esto evita acumular drift cuando los SFX bloquean interrupts
    LD HL, (SYS_FRAMES)
    LD DE, BELL_PAUSE
    ADD HL, DE
    LD (BellNextFrame), HL

    LD HL, BellCount
    DEC (HL)
    RET NZ
    JR .bellsDone

.bellsDone:
    ; Ultima campanada:
    ;   1) matar todos los nasties vivos (puff)
    ;   2) arrancar cadena diferida: windows off → monster spawn
    CALL KillAllActiveNasties
    LD A, POST_BELL_WINDOWS_DELAY
    LD (BellsDoneTimer), A
    RET

; ==============================================================================
; UpdateBellsDoneTimer - Llamar cada frame tras UpdateBellChimes
; ==============================================================================
; Maneja la cadena diferida tras la ultima campanada:
;   1) BellsDoneTimer cuenta hasta 0 → apagar ventanas (UpdateRemapTables)
;      y arranca SpawnAfterWinTimer
;   2) SpawnAfterWinTimer cuenta hasta 0 → SpawnMonsters
; ==============================================================================
UpdateBellsDoneTimer:
    LD A, (BellsDoneTimer)
    OR A
    JR Z, .ubdCheckSpawn
    DEC A
    LD (BellsDoneTimer), A
    JR NZ, .ubdCheckSpawn
    ; Llego a 0: apagar ventanas
    CALL UpdateRemapTables
    LD A, 1
    LD (AttrsDirty), A
    LD A, POST_WINDOWS_SPAWN_DELAY
    LD (SpawnAfterWinTimer), A
    RET
.ubdCheckSpawn:
    LD A, (SpawnAfterWinTimer)
    OR A
    RET Z
    DEC A
    LD (SpawnAfterWinTimer), A
    RET NZ
    ; Llego a 0: spawnear monsters
    JP SpawnMonsters
