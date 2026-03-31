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

; --- SFX_Footstep: click suave de paso (~15ms) ---
; Golpe bajo muy corto, apenas perceptible pero da ritmo al movimiento
SFX_Footstep:
    DEFB 8, 40, 3, 0            ; tono bajo breve con ligero ascenso
    DEFB 5, 20, 0, 1            ; mini-click de ruido
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

; --- SFX_BellChime: campanada grave de medianoche (~200ms) ---
; Tono grave resonante con decay lento, como campana de iglesia
; --- SFX_BellChime: una campanada grave (~corta, para repetir) ---
SFX_BellChime:
    DEFB 250, 220, 0, 0        ; golpe grave
    DEFB 80, 240, 1, 0         ; decay
    DEFB 0                      ; fin

; --- Sistema de campanadas con pausa entre ellas ---
BellCount:      DEFB 0          ; campanadas restantes (0 = inactivo)
BellTimer:      DEFB 0          ; frames hasta la siguiente campanada
BELL_PAUSE      EQU 40          ; frames de pausa entre campanadas (~0.8s a 50fps)

; ==============================================================================
; StartBellChimes - Inicia secuencia de 12 campanadas
; ==============================================================================
StartBellChimes:
    LD A, 12
    LD (BellCount), A
    LD A, 1                     ; sonar la primera inmediatamente
    LD (BellTimer), A
    RET

; ==============================================================================
; UpdateBellChimes - Llamar cada frame desde el main loop
; ==============================================================================
UpdateBellChimes:
    LD A, (BellCount)
    OR A
    RET Z                       ; sin campanadas pendientes

    LD HL, BellTimer
    DEC (HL)
    RET NZ                      ; aun no toca

    ; Sonar una campanada
    PUSH BC
    PUSH DE
    LD HL, SFX_BellChime
    CALL PlaySFX
    POP DE
    POP BC

    ; Preparar siguiente
    LD HL, BellCount
    DEC (HL)
    JR Z, .bellsDone
    LD A, BELL_PAUSE
    LD (BellTimer), A
    RET

.bellsDone:
    ; Ultima campanada: ahora aplicar remap de attrs (apagar ventanas)
    LD A, 1
    LD (AttrsDirty), A
    RET
