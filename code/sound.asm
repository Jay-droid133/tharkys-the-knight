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
    ; P7: sin DI. Con DI, cada SFX de mas de ~1 frame se comia IRQs: la musica
    ; (que avanza en el handler IM 2) y $5C78 perdian ticks. El handler cuesta
    ; ~250-900 T por frame: un microcorte cada 20 ms en el tono (comprobar de oido).
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

; --- Resto de SFX de beeper: migrados al AY (code/sfx_library.json: AYSFX_ATTACK,
; ENEMY_DEATH, ENEMY_SPAWN, PICKUP, BAD_PICKUP, NO_SWORD, BLOCKED_EXIT, KEY_DROP,
; DOOR_CLOSE, DOOR_OPEN, WELL_RECOVER). PlaySFX bloqueaba la CPU (y antes las
; IRQ) mientras sonaba: el espadazo, ~75.000 T por golpe. Los datos de beeper
; originales (y los que ya no usaba nadie: ScreenTransition, Thunder, Countdown*,
; BellChime) estan en el historial de git. Solo quedan los pasos: <1 ms.

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
POST_BELL_WINDOWS_DELAY   EQU 45    ; 45 frames a 25fps = 1.8s (era 90 a 50fps)
POST_WINDOWS_SPAWN_DELAY  EQU 38    ; 38 frames a 25fps = 1.5s (era 75 a 50fps)
BellsDoneTimer:       DEFB 0        ; >0 = contando hasta windows off
SpawnAfterWinTimer:   DEFB 0        ; >0 = contando hasta monster spawn

; ==============================================================================
; StartBellChimes - Inicia secuencia de 12 campanadas
; ==============================================================================
StartBellChimes:
    ; Silenciar musica activa (death o cualquier otra). Bell escribe R7 (mixer
    ; all-on), R0-R5 (period A/B/C) y R8-R10 (vols), clobbeando lo que la musica
    ; mantenga en canal B. Mejor parar limpiamente que oir glitches.
    PUSH AF
    LD A, $FF
    CALL StartMusic
    POP AF
    LD A, 12                            ; 12 campanadas (medianoche)
    LD (BellCount), A
    ; Sonar la primera inmediatamente: deadline = FRAMES actual
    LD HL, (SYS_FRAMES)
    LD (BellNextFrame), HL
    ; ScareTimer pausa+huida solo si los monsters NO estan atrapados. Post-
    ; cinematica iglesia (MonsterTrappedFlags == $07) los nasties siguen
    ; persiguiendo con normalidad — ya no hay narrativa de "huida diaria".
    LD A, (MonsterTrappedFlags)
    AND $07
    CP $07
    RET Z
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
    ; Si las campanadas las disparo el jugador abriendo la iglesia (i.e.
    ; ChurchDoorOpen=1 al terminar bells), resaltar la estatua del
    ; monstruo esperado. Si fueron campanadas naturales de medianoche,
    ; ChurchDoorOpen sigue en 0 y este call es no-op.
    LD A, (ChurchDoorOpen)
    OR A
    JR Z, .ubdSkipHighlight
    CALL StartStatueBlink
.ubdSkipHighlight:
    ; Gate post-cinematica iglesia: si los 3 monsters estan atrapados
    ; (MonsterTrappedFlags == $07) ya no spawneara nada — ni armamos
    ; SpawnAfterWinTimer ni arrancamos la musica de tension (que era el
    ; "calma antes de la tormenta" del SpawnMonsters subsiguiente).
    LD A, (MonsterTrappedFlags)
    AND $07
    CP $07
    RET Z
    ; Armar el gating: SpawnAfterWinTimer = 1 = "esperando a que Tension
    ; termine para spawnear". El check real esta en .ubdCheckSpawn (mira
    ; MusicTimer del driver tabular). Cuando Tension acaba (MusicTimer
    ; pasa a 0), dispara SpawnMonsters. Asi el primer monster aparece
    ; tras Tension + el natural ~0.8s de MONSTER_ENTRY_BASE -> "calma
    ; antes de la tormenta".
    LD A, 1
    LD (SpawnAfterWinTimer), A
    ; Musica de tension organica entre lights-off y monster spawn (track 0)
    XOR A                           ; A = 0 = MUSIC_TENSION
    CALL StartMusic
    RET
.ubdCheckSpawn:
    LD A, (SpawnAfterWinTimer)
    OR A
    RET Z                           ; no armado (boot, ya disparado, etc.)
    ; Gating dinamico: esperar a que MusicTimer del driver tabular llegue
    ; a 0. Indica que Tension (la musica activa) acaba de terminar (su
    ; ultima nota se cumplio y MusicEndOfTable.meotStop puso Timer=0).
    ; Robusto a cambios de duracion en TensionMusicTable.
    LD A, (MusicTimer)
    OR A
    RET NZ                          ; Tension aun sonando
    ; Tension acabo: rearmar y disparar spawn.
    XOR A
    LD (SpawnAfterWinTimer), A
    JP SpawnMonsters

; ==============================================================================
; MonstersMusic - Secuencer ad-hoc para una nota grave repetida
; ==============================================================================
; Ritmo "po-po-popo-po": 5 hits con gaps definidos en MonstersBeatGaps. Cada
; hit dispara AY_PlayBeep(period=$0688 ~C2, dur=4f) en canal B AY (~160ms).
; Loopable. Arrancado desde SpawnMonsters (StartMonstersMusic). Detenido al
; sunrise (StopMonstersMusic).
;
; NO usa el driver tabular ni reserva nada en slot 1 — el patron es puro
; codigo. Variables (Timer + Step) viven al final de esta rutina (bank 0).
;
; Para iterar: ajustar MonstersBeatGaps (frames entre hits) o el period en
; UpdateMonstersMusic (LD HL, $0688) para cambiar el tono.
; ==============================================================================

; --- StartMonstersMusic: arranca el secuencer ---
; Se llama desde SpawnMonsters una vez por noche. Setea Step=0 + Timer=1
; para que el primer hit suene en el frame siguiente.
StartMonstersMusic:
    XOR A
    LD (MonstersMusicStep), A       ; Step = 0 → primer hit
    INC A
    LD (MonstersMusicTimer), A      ; Timer = 1 → suena ya en proximo update
    RET

; --- StopMonstersMusic: detiene el secuencer ---
; Se llama al sunrise (day_cycle.asm fase 5). Step=$FF actua como sentinel
; "inactivo" en UpdateMonstersMusic (INC A → 0 → RET Z).
StopMonstersMusic:
    LD A, $FF
    LD (MonstersMusicStep), A
    RET

; --- UpdateMonstersMusic: tick por frame desde MainLoop ---
; Si activo, decrementa Timer; cuando llega a 0, dispara AY_PlayBeep y
; avanza Step (con wrap a 0 al pasar de 4). Si Step=$FF, no-op.
UpdateMonstersMusic:
    LD A, (MonstersMusicStep)
    INC A
    RET Z                           ; $FF + INC = 0 → inactivo
    DEC A                           ; restaurar Step real
    LD HL, MonstersMusicTimer
    DEC (HL)
    RET NZ                          ; aun esperando proximo hit
    ; Hora del proximo "po": leer gap[Step] -> Timer
    LD HL, MonstersBeatGaps
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (MonstersMusicTimer), A
    ; Avanzar Step con wrap a 0 al llegar a 5
    LD HL, MonstersMusicStep
    INC (HL)
    LD A, (HL)
    CP 5
    JR C, .ummDoBeep
    XOR A
    LD (HL), A                      ; wrap: Step=0 → vuelve al inicio del patron
.ummDoBeep:
    ; Migrado a AY_PlaySFX (sfx_library.json: AYSFX_MONSTERS_PO).
    LD A, AYSFX_MONSTERS_PO
    JP AY_PlaySFX                   ; tail-call

; --- Datos del patron "po-po-popo-po" ---
; Frames entre hits consecutivos. Total = 12+12+4+8+26 = 62 frames = ~2.48s/loop.
; Beat 1: po (gap 12 hasta beat 2)
; Beat 2: po (gap 12 hasta beat 3.0)
; Beat 3.0: po (gap 4 hasta beat 3.5 = corchea)
; Beat 3.5: po (gap 8 hasta beat 4)
; Beat 4: po (gap 26 hasta beat 1 = loop — pausa larga al final)
MonstersBeatGaps:
    DEFB 12, 12, 4, 8, 26

MonstersMusicTimer: DEFB 0
MonstersMusicStep:  DEFB $FF             ; $FF = inactivo (sentinel)
