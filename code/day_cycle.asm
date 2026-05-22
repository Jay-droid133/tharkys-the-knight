; ==============================================================================
; DAY/NIGHT CYCLE SYSTEM - Debug Mode
; ==============================================================================
; Sistema de transformacion de atributos de BG sprites segun momento del dia.
; En modo debug, la tecla T cicla entre 7 momentos.
; Sprites "house" tienen override especial para ventanas (Cyan).
; ==============================================================================

; --- Constantes ---
NUM_TIME_MOMENTS    EQU 7

; --- Variables ---
CurrentTimeOfDay:       DEFB 0      ; Crepusculo temprano
CurrentRemapTable:      DEFW RemapTable_CrepT
CurrentHouseRemapTable: DEFW RemapTable_CrepT
BgSpriteIsHouse:        DEFB 0      ; Flag temporal por sprite
BgSpriteSkipRemap:      DEFB 0      ; 1 = ApplyDayCycleRemap retorna sin remap (preserva attrs raw del sprite). Usado por random pickups (life/health/stamina) que deben mantener su brillo siempre.
DebugKeyDebounce:       DEFB 0      ; Anti-rebote tecla T

; ==============================================================================
; SetTimeOfDay - Cambia el momento del dia
; ==============================================================================
; Entrada: A = momento (0-6)
; ==============================================================================
SetTimeOfDay:
    LD (CurrentTimeOfDay), A

    ; N2 (fase 4 = medianoche 00:00): incrementar ciclo de dia
    CP 4
    JR NZ, .notNewCycle
    LD HL, DayCycleCount
    INC (HL)
    JR .skipBellsReset
.notNewCycle:
    ; Salir de phase 4 (o entrar a cualquier no-4): rearmar BellsTriggered para
    ; que la proxima medianoche (natural o por T) vuelva a disparar campanadas.
    ; Sin esto, ciclar con T pasa por N2 una sola vez por sesion.
    XOR A
    LD (BellsTriggered), A
.skipBellsReset:
    LD A, (CurrentTimeOfDay)            ; recuperar phase (XOR A clobbeo A)

    ; N2 (medianoche): campanadas primero, remap al terminar
    CP 4
    JR Z, .bellsFirst

    ; Amanecer temprano (fase 5): despawnear monsters + musica de amanecer
    CP 5
    JR NZ, .noScareMon
    CALL ScareAllMonsters
    CALL StopMonstersMusic          ; cortar el secuencer "po-po-popo-po"
    ; En el path natural el bell decay (max 30f) termino hace minutos de game
    ; time, asi que BellVol* esta a 0 con seguridad. Debug T-key 4->5 inmediato
    ; podria solapar bell decay con sunrise music por ~1s; aceptado como
    ; artefacto debug-only sin chequeo cruzado a bank 4.
    LD A, 1                         ; track 1 = Sunrise
    CALL StartMusic
    JR .noKillMon
.noScareMon:
    ; Amanecer tardio (fase 6): matar monsters supervivientes
    CP 6
    JR NZ, .noKillMon
    CALL KillAllActiveMonsters
.noKillMon:

    ; Actualizar tablas de remap y tabla de nasties
    CALL UpdateRemapTables
    CALL UpdateNastyTable

    ; Forzar remap de atributos (sin redibujar pixeles)
    LD A, 1
    LD (AttrsDirty), A
    RET

.bellsFirst:
    ; NO actualizar tablas de REMAP: mantener colores de N1 durante campanadas.
    ; SI actualizar nasty table: la tabla de tipos a spawnear depende de la
    ; fase, no del remap visual. Si capturamos los 3 monsters durante este
    ; intervalo de N2, post-captura se desbloquea spawn de nasties y queremos
    ; que sean nocturnos (Crepuscular), no diurnos.
    CALL UpdateNastyTable
    ; Idempotente: si bells ya sonaron (porque el jugador abrio la iglesia
    ; antes de medianoche natural y forzo el evento), saltamos.
    LD A, (BellsTriggered)
    OR A
    RET NZ
    LD A, 1
    LD (BellsTriggered), A
    CALL StartBellChimes
    RET

; ==============================================================================
; TriggerChurchMidnight - llamada al abrir la puerta de la iglesia 1a vez
; ==============================================================================
; Si bells aun no han sonado (estamos antes de medianoche natural):
;   - Salta reloj a 00:00.
;   - Dispara phase 4 (N2 = medianoche) -> bells, ventanas off, monsters spawn.
;   - Aplica remap de colores INMEDIATAMENTE (no espera al final de las
;     campanadas como hace el path natural). El usuario quiere que la
;     iglesia se vea en colores de noche desde el momento mismo de abrir
;     la puerta, no que conserve el color diurno hasta que terminen las 12
;     campanadas. La cadena post-bell vuelve a llamar UpdateRemapTables
;     pero ya esta en N2 -> no-op visual.
; Si bells ya sonaron (medianoche pasada de forma natural antes de abrir
; iglesia): no-op. La puerta se abre normal sin clock-jump anti-climatico.
;
; El guard via BellsTriggered hace esto idempotente: el path natural de
; medianoche en .bellsFirst tambien lo setea, asi que segundo trigger desde
; aqui no re-dispara nada.
; ==============================================================================
TriggerChurchMidnight:
    LD A, (BellsTriggered)
    OR A
    RET NZ                              ; bells ya sonaron -> no-op
    LD A, 4                             ; phase 4 = N2 (medianoche)
    CALL SetClockToPhaseHour            ; GameHours=0, Min=0, SubMinute=0
    LD A, 4
    CALL SetTimeOfDay                   ; setea phase + .bellsFirst
    ; Aplicar remap N2 ya: por defecto SetTimeOfDay(4) NO toca remap
    ; (lo hace .bellsDoneTimer al terminar campanadas para mantener colores
    ; diurnos durante chimes). En este path queremos lo contrario.
    CALL UpdateRemapTables
    LD A, 1
    LD (AttrsDirty), A
    RET

; ==============================================================================
; UpdateRemapTables - Actualiza punteros de remap segun CurrentTimeOfDay
; ==============================================================================
UpdateRemapTables:
    LD A, (CurrentTimeOfDay)
    LD HL, RemapTablePtrs
    LD E, A
    LD D, 0
    ADD HL, DE
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (CurrentRemapTable), DE

    LD A, (CurrentTimeOfDay)
    LD HL, RemapHouseTablePtrs
    LD E, A
    LD D, 0
    ADD HL, DE
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (CurrentHouseRemapTable), DE
    RET

; ==============================================================================
; CheckDebugKeys - Lee teclas T (ciclo dia), S/D (DayCycleCount), N (noclip).
; Gateada por DebugUnlocked: requiere secuencia B-U-G previa (debug_unlock.asm).
; ==============================================================================
CheckDebugKeys:
    LD A, (DebugUnlocked)
    OR A
    RET Z                   ; Debug bloqueado: ignorar T/S/D/N
    LD A, $FB
    IN A, ($FE)
    BIT 4, A                ; T key: bit 4 de semi-fila $FBFE (0=pulsada)
    JR NZ, .notPressed

    ; Tecla pulsada: comprobar debounce
    LD A, (DebugKeyDebounce)
    OR A
    RET NZ                  ; Ya estaba pulsada, ignorar

    ; Primera pulsacion: ciclar
    LD A, 1
    LD (DebugKeyDebounce), A

    LD A, (CurrentTimeOfDay)
    INC A
    CP NUM_TIME_MOMENTS
    JR C, .noWrap
    XOR A                   ; Volver a 0 (Dia)
.noWrap:
    PUSH AF
    CALL SetTimeOfDay
    POP AF
    CALL SetClockToPhaseHour
    RET

.notPressed:
    XOR A
    LD (DebugKeyDebounce), A

    ; --- Tecla S: incrementar DayCycleCount (sube velocidad nasties) ---
    LD A, $FD
    IN A, ($FE)
    LD C, A                 ; C = estado semi-fila $FDFE
    BIT 1, C                ; S key: bit 1 (0=pulsada)
    JR NZ, .sNotPressed
    LD A, (SpeedKeyDebounce)
    OR A
    RET NZ
    LD A, 1
    LD (SpeedKeyDebounce), A
    LD HL, DayCycleCount
    LD A, (HL)
    CP 10
    RET NC                  ; Ya en maximo
    INC (HL)
    RET
.sNotPressed:
    ; --- Tecla D: decrementar DayCycleCount (baja velocidad nasties) ---
    BIT 2, C                ; D key: bit 2 (0=pulsada)
    JR NZ, .dNotPressed
    LD A, (SpeedKeyDebounce)
    OR A
    RET NZ
    LD A, 1
    LD (SpeedKeyDebounce), A
    LD HL, DayCycleCount
    LD A, (HL)
    CP 1
    RET Z                   ; Ya en minimo
    DEC (HL)
    RET
.dNotPressed:
    XOR A
    LD (SpeedKeyDebounce), A

    ; --- Tecla N: togglea NoclipMode (debug) ---
    LD A, $7F
    IN A, ($FE)                 ; fila SPACE-SS-M-N-B
    BIT 3, A                    ; N = bit 3 (0 = pulsada)
    JR NZ, .nNotPressed
    LD A, (NoclipKeyDebounce)
    OR A
    RET NZ
    LD A, 1
    LD (NoclipKeyDebounce), A
    LD A, (NoclipMode)
    XOR 1
    LD (NoclipMode), A
    RET
.nNotPressed:
    XOR A
    LD (NoclipKeyDebounce), A
    RET

SpeedKeyDebounce: DEFB 0
NoclipKeyDebounce: DEFB 0

; DrawSwordModeHUD / DrawNoclipHUD: rutinas debug eliminadas (recuperables
; del historial git). Las teclas debug (N noclip, S/D speed) siguen activas.

; ==============================================================================
; ApplyDayCycleRemap - Transforma un byte de atributo segun momento del dia
; ==============================================================================
; Entrada: A = attr original
; Salida:  A = attr transformado
; Preserva: HL, DE, BC, IX
; ==============================================================================
ApplyDayCycleRemap:
    PUSH HL
    LD H, A                     ; H = attr (temp save)
    ; Skip remap si flag activa (random pickups: preservar brillo siempre).
    LD A, (BgSpriteSkipRemap)
    OR A
    JR NZ, .skipRemap
    LD A, (CurrentTimeOfDay)
    OR A
    JR NZ, .doRemap
.skipRemap:
    LD A, H                     ; Dia o flag: devolver sin cambio
    POP HL
    RET

.doRemap:
    PUSH DE
    PUSH BC

    LD A, H                     ; A = attr original
    LD C, A                     ; C = attr original

    ; Guardar flash + ink (bits 7, 2-0)
    AND $87                     ; A = F000_0III
    LD B, A                     ; B = flash | ink

    ; Extraer paper+bright como indice 0-15
    LD A, C
    AND $78                     ; A = 0BPPP000
    RRCA
    RRCA
    RRCA                        ; A = 0000BPPP = indice

    ; Elegir tabla segun tipo de sprite
    LD E, A
    LD D, 0
    LD A, (BgSpriteIsHouse)
    OR A
    JR Z, .useStdTable
    LD HL, (CurrentHouseRemapTable)
    JR .doLookup
.useStdTable:
    LD HL, (CurrentRemapTable)
.doLookup:
    ADD HL, DE
    LD A, (HL)                  ; A = nuevo paper+bright (0-15)

    ; Reconstruir atributo
    RLCA
    RLCA
    RLCA                        ; A = 0BPPP000
    OR B                        ; A = FBPPPIII

    POP BC
    POP DE
    POP HL
    RET

; ==============================================================================
; CheckIfHouseSprite - Determina si un sprite es tipo "house"
; ==============================================================================
; Entrada: A = sprite ID
; Setea BgSpriteIsHouse (0 o 1)
; Preserva: A, DE, IX
;
; Stage B.2: antes comparaba DE contra punteros en HouseSpriteList. Con
; sprites repartidos en varios banks, dos sprites en banks distintos pueden
; compartir direccion $Cxxx y dar falso positivo. Ahora comparamos por ID
; (unico globalmente) contra HouseIdList (formato DEFB id, terminador $FF).
; ==============================================================================
CheckIfHouseSprite:
    PUSH AF
    PUSH HL
    PUSH BC

    LD B, A                     ; B = id buscado

    XOR A
    LD (BgSpriteIsHouse), A     ; Default: no es house

    LD HL, HouseIdList
.checkLoop:
    LD A, (HL)
    CP $FF
    JR Z, .checkDone            ; Terminador: no encontrado
    CP B
    JR Z, .checkFound
    INC HL
    JR .checkLoop

.checkFound:
    LD A, 1
    LD (BgSpriteIsHouse), A

.checkDone:
    POP BC
    POP HL
    POP AF
    RET

; HouseIdList: auto-generada por el level editor en screen_data.asm
; (vive en bank 0 para acceso sin paginar). Lista DEFB id terminada en $FF.
; Incluye automaticamente cualquier sprite cuyo nombre contenga "house".

; DrawRoomInfo: rutina debug eliminada (HUD coords + room hex). Si vuelves a
; necesitarla, recuperala del historial git.

; Bloque debug eliminado: DrawPlayerSpeedHUD, DrawZoneCountHUD,
; DrawEnemySpeedHUD, DrawHudCharRow0, DrawTimeIndicator, DrawHudChar,
; DrawDayCycleHUD ("DAY xx" en row 1 cols 0-5).
; (Recuperables del historial git si se necesitan otra vez.)

; ==============================================================================
; DATOS
; ==============================================================================

; RoomNameTable + RoomName_* + TimeLabels eliminados (solo los usaban
; DrawRoomInfo y DrawTimeIndicator, ya borrados). Recuperables del historial.

; --- Tablas de punteros a remap tables (indexadas por momento) ---
RemapTablePtrs:
    DEFW RemapTable_Day         ; 0: Dia
    DEFW RemapTable_CrepT       ; 1: Crep. temprano
    DEFW RemapTable_CrepTd      ; 2: Crep. tardio
    DEFW RemapTable_NocheT      ; 3: Noche temprana
    DEFW RemapTable_NocheTd     ; 4: Noche tardia
    DEFW RemapTable_CrepTd      ; 5: Amanecer temprano (= CrepTd standard)
    DEFW RemapTable_CrepT       ; 6: Amanecer tardio (= CrepT)

RemapHouseTablePtrs:
    DEFW RemapTable_Day         ; 0: Dia (sin override)
    DEFW RemapTable_CrepT       ; 1: CrepT (sin override house)
    DEFW RemapHouse_CrepTd      ; 2: CrepTd house
    DEFW RemapHouse_NocheT      ; 3: NocheT house
    DEFW RemapHouse_NocheTd     ; 4: NocheTd house
    DEFW RemapHouse_AmanT       ; 5: AmanT house
    DEFW RemapTable_CrepT       ; 6: AmanTd (sin override house)

; ==============================================================================
; REMAP TABLES - Standard (sprites normales)
; ==============================================================================
; 16 entradas: indice = bright*8 + color_paper
; Valor = new_bright*8 + new_color_paper
;
; Colores: 0=B 1=Bl 2=R 3=M 4=G 5=C 6=Y 7=W
; Indice 0-7 = dim, 8-15 = bright
; ==============================================================================

RemapTable_Day:
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  2,  3,  4,  5,  6,  7,   8,   9, 10, 11, 12, 13, 14, 15

RemapTable_CrepT:   ; Crepusculo temprano / Amanecer tardio
    ; W->Y, Y->M, G->M (keep bright), R keeps bright, C+->C-
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  2,  3,  3,  5,  3,  6,   8,   9, 10, 11, 11,  5, 11, 14

RemapTable_CrepTd:  ; Crepusculo tardio / Amanecer temprano (standard)
    ; W->M, Y->Bl, G->Bl (keep bright), R+->R-, C+->C-
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  2,  3,  1,  5,  1,  3,   8,   9,  2, 11,  9,  5,  9, 11

RemapTable_NocheT:  ; Noche temprana
    ; R/M/Y/G/W -> Bl (keep bright), C+ -> C-
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  1,  1,  1,  5,  1,  1,   8,   9,  9,  9,  9,  5,  9,  9

RemapTable_NocheTd: ; Noche tardia (= NocheT, preservando bright)
    ; Igual que NocheT: Blue conserva bright original. C+ -> C-.
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  1,  1,  1,  5,  1,  1,   8,   9,  9,  9,  9,  5,  9,  9

; ==============================================================================
; REMAP TABLES - House override (ventanas = Cyan)
; ==============================================================================
; Solo difieren en indices 5 (C-) y 13 (C+) respecto a su tabla standard

RemapHouse_CrepTd:  ; Crep. tardio: ventanas ON -> Yellow dim, Y->Bl, G->Bl (keep bright)
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  2,  3,  1,  6,  1,  3,   8,   9,  2, 11,  9,  6,  9, 11

RemapHouse_NocheT:  ; Noche temprana: ventanas Y+, Y->Bl, G->Bl (keep bright)
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  1,  1,  1, 14,  1,  1,   8,   9,  1,  9,  9, 14,  9,  1

RemapHouse_NocheTd: ; Noche tardia: ventanas OFF -> Blue dim
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  1,  1,  1,  1,  1,  1,   0,   1,  1,  1,  1,  1,  1,  1

RemapHouse_AmanT:   ; Amanecer temprano: ventanas -> Magenta, Y->Bl, G->Bl (keep bright)
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  2,  3,  1,  3,  1,  3,   8,   9,  2, 11,  9, 11,  9, 11

