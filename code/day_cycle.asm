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
; CheckDebugKeys - Lee tecla T para ciclar momento del dia
; ==============================================================================
CheckDebugKeys:
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

; --- DrawSwordModeHUD: pinta letra B/C/A en fila 23, col 0 ---
DrawSwordModeHUD:
    LD A, (SwordMode)
    LD HL, .modeChars
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                          ; A = ASCII del modo
    ; Calcular direccion en VRAM: fila 0, col 0 = $4000 (scan 0)
    LD HL, $4000
    ; Buscar glyph en ROM charset ($3C00 + char*8)
    LD E, A
    LD D, 0
    LD B, D                             ; B = 0
    SLA E : RL D                        ; *2
    SLA E : RL D                        ; *4
    SLA E : RL D                        ; *8
    PUSH HL
    LD HL, $3C00
    ADD HL, DE                          ; HL = direccion del glyph
    EX DE, HL                           ; DE = glyph
    POP HL                              ; HL = VRAM
    LD B, 8
.drawChar:
    LD A, (DE)
    LD (HL), A
    INC DE
    INC H                               ; siguiente scan line
    DJNZ .drawChar
    ; Attr: fila 0, col 0 = $5800
    LD A, $47                           ; blanco bright
    LD ($5800), A
    RET

.modeChars: DEFB "CFS"                 ; modo 0=C cooldown, 1=F fijo, 2=S stamina

; --- DrawNoclipHUD: "NC" en fila 1 cols 30-31 cuando NoclipMode activo ---
DrawNoclipHUD:
    LD A, (NoclipMode)
    OR A
    JR NZ, .ncOn
    LD A, 32                    ; espacio (limpia cuando off)
    LD E, 30
    CALL DrawHudChar
    LD A, 32
    LD E, 31
    JP DrawHudChar
.ncOn:
    LD A, 'N'
    LD E, 30
    CALL DrawHudChar
    LD A, 'C'
    LD E, 31
    JP DrawHudChar

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

; ==============================================================================
; DrawRoomInfo - Muestra coordenadas, indice y nombre del room en HUD fila 23
; ==============================================================================
; Formato: XX,YY:NN nombre_room     DY
;          cols 0-7  cols 9-29       cols 30-31 (DrawTimeIndicator)
; ==============================================================================
DrawRoomInfo:
    ; --- Limpiar cols 0-12 con espacios (13-18 = reloj HUD, 19-29 = vacío) ---
    LD E, 0
    LD B, 13
.clearLoop:
    PUSH BC
    PUSH DE
    LD A, ' '
    CALL DrawHudChar
    POP DE
    POP BC
    INC E
    DJNZ .clearLoop

    ; --- CurrentScreenX como 2 digitos decimales en cols 0-1 ---
    LD A, (CurrentScreenX)
    LD E, 0
    CALL .drawDec2

    ; --- ',' en col 2 ---
    LD A, ','
    LD E, 2
    CALL DrawHudChar

    ; --- CurrentScreenY como 2 digitos decimales en cols 3-4 ---
    LD A, (CurrentScreenY)
    LD E, 3
    CALL .drawDec2

    ; --- ':' en col 5 ---
    LD A, ':'
    LD E, 5
    CALL DrawHudChar

    ; --- Obtener room index de MapTable[Y*16+X] ---
    LD A, (CurrentScreenY)
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = Y * 16
    LD A, (CurrentScreenX)
    LD E, A
    LD D, 0
    ADD HL, DE                  ; HL = Y*16 + X
    LD DE, MapTable
    ADD HL, DE
    LD A, (HL)                  ; A = room index (0-47)
    PUSH AF                     ; guardar room index

    ; --- Room index como 2 hex en cols 6-7 ---
    PUSH AF
    RRCA
    RRCA
    RRCA
    RRCA
    AND $0F
    CALL .hexToAscii
    LD E, 6
    CALL DrawHudChar
    POP AF
    AND $0F
    CALL .hexToAscii
    LD E, 7
    CALL DrawHudChar

    ; --- Espacio en col 8 ---
    LD A, ' '
    LD E, 8
    CALL DrawHudChar

    ; --- Nombre del room: comentado (cols 9-29 libres para HUD) ---
    POP AF                      ; A = room index (descartar)

    ; --- Atributos fila 1 cols 0-12 (13-18 = reloj HUD gestiona los suyos) ---
    LD HL, ATTR_BASE + 1 * 32
    LD A, $47                   ; bright white on black
    LD B, 13
.attrLoop:
    LD (HL), A
    INC HL
    DJNZ .attrLoop
    RET

; --- Helpers ---
; Dibuja valor de A (0-99) como 2 digitos decimales en cols E, E+1
.drawDec2:
    LD C, E                     ; guardar columna inicial
    LD B, 0                     ; decenas
.divLoop:
    CP 10
    JR C, .divDone
    SUB 10
    INC B
    JR .divLoop
.divDone:
    ; B = decenas, A = unidades
    PUSH AF                     ; guardar unidades
    LD A, B
    ADD A, '0'
    LD E, C
    PUSH BC                     ; guardar C (columna) - DrawHudChar destruye BC
    CALL DrawHudChar
    POP BC                      ; restaurar C
    POP AF
    ADD A, '0'
    LD E, C
    INC E
    JP DrawHudChar              ; tail call

.hexToAscii:
    CP 10
    JR C, .isDigit
    ADD A, 'A' - 10
    RET
.isDigit:
    ADD A, '0'
    RET

; ==============================================================================
; DrawDayCycleHUD - Muestra "DAY 01" en HUD (fila 0, col 4-9)
; Usa font custom (DayHudFont) en vez de ROM font
; ==============================================================================
DrawDayCycleHUD:
    ; --- Dibujar "DAY " (chars fijos: indices 0,1,2 + espacio) ---
    LD HL, DayHudFont + 0 * 8          ; 'D'
    LD DE, $4004                        ; Fila 0, col 4
    CALL .drawChar
    LD HL, DayHudFont + 1 * 8          ; 'A'
    LD DE, $4005                        ; Fila 0, col 5
    CALL .drawChar
    LD HL, DayHudFont + 2 * 8          ; 'Y'
    LD DE, $4006                        ; Fila 0, col 6
    CALL .drawChar
    ; Col 7 = espacio (limpiar)
    LD DE, $4007
    CALL .clearChar

    ; --- Digito decenas (col 8) ---
    LD A, (DayCycleCount)
    CP 10
    JR C, .singleDigit
    ; Dos digitos: dividir A / 10
    LD B, 0
.divLoop:
    SUB 10
    INC B
    CP 10
    JR NC, .divLoop
    ; B = decenas, A = unidades
    PUSH AF                             ; Guardar unidades
    LD A, B
    CALL .getDigitFont
    LD DE, $4008                        ; Col 8
    CALL .drawChar
    POP AF                              ; Recuperar unidades
    CALL .getDigitFont
    LD DE, $4009                        ; Col 9
    CALL .drawChar
    JR .setAttrs

.singleDigit:
    ; Una cifra: decena = 0, unidad = A
    PUSH AF
    LD HL, DayHudFont + 3 * 8          ; '0'
    LD DE, $4008                        ; Col 8
    CALL .drawChar
    POP AF
    CALL .getDigitFont
    LD DE, $4009                        ; Col 9
    CALL .drawChar

.setAttrs:
    ; Atributos: bright white en cols 4-9
    LD A, $47
    LD HL, ATTR_BASE + 4
    LD B, 6
.attrLoop:
    LD (HL), A
    INC HL
    DJNZ .attrLoop
    RET

; Devuelve HL = puntero a font data del digito en A (0-9)
; A se destruye
.getDigitFont:
    ADD A, 3                            ; Digitos empiezan en indice 3 de la font
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; HL = indice * 8
    LD BC, DayHudFont
    ADD HL, BC
    RET

; Dibuja 8 bytes de font desde (HL) en VRAM (DE)
; DE = direccion VRAM base (fila 0), se incrementa D por scan line
.drawChar:
    LD B, 8
.charLoop:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC D
    DJNZ .charLoop
    RET

; Limpia 8 scan lines en VRAM (DE)
.clearChar:
    LD B, 8
    XOR A
.clearLoop:
    LD (DE), A
    INC D
    DJNZ .clearLoop
    RET

; ==============================================================================
; DrawPlayerSpeedHUD - Muestra velocidad player en HUD (fila 0, col 2)
; ==============================================================================
DrawPlayerSpeedHUD:
    LD A, (PlayerCurrentSpeed)
    ADD A, '0'
    LD E, 2
    CALL DrawHudCharRow0
    ; Atributo (bright white)
    LD A, $47
    LD (ATTR_BASE + 2), A
    RET

; ==============================================================================
; DrawZoneCountHUD - DEBUG: muestra ZoneCellCount en HUD col 11-12 (hex)
; ==============================================================================
DrawZoneCountHUD:
    LD A, (ZoneCellCount)
    ; Hi nibble
    LD B, A
    SRL A
    SRL A
    SRL A
    SRL A
    CP 10
    JR C, .dzcHiDigit
    ADD A, 'A' - 10
    JR .dzcHiOut
.dzcHiDigit:
    ADD A, '0'
.dzcHiOut:
    LD E, 11
    CALL DrawHudCharRow0
    ; Lo nibble
    LD A, B
    AND $0F
    CP 10
    JR C, .dzcLoDigit
    ADD A, 'A' - 10
    JR .dzcLoOut
.dzcLoDigit:
    ADD A, '0'
.dzcLoOut:
    LD E, 12
    CALL DrawHudCharRow0
    LD A, $47
    LD (ATTR_BASE + 11), A
    LD (ATTR_BASE + 12), A
    RET

; ==============================================================================
; DrawEnemySpeedHUD - Muestra velocidad nasties en HUD (fila 0, col 30-31)
; ==============================================================================
DrawEnemySpeedHUD:
    ; "V" en columna 30
    LD A, 'V'
    LD E, 30
    CALL DrawHudCharRow0
    ; Numero de velocidad en columna 31
    LD A, (CurrentEnemySpeed)
    ADD A, '0'
    LD E, 31
    CALL DrawHudCharRow0
    ; Atributos (bright white)
    LD A, $47
    LD (ATTR_BASE + 30), A
    LD (ATTR_BASE + 31), A
    RET

; Dibuja un caracter de la ROM font en fila 0 del HUD
; A = codigo ASCII, E = columna (0-31)
DrawHudCharRow0:
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    LD BC, $3C00
    ADD HL, BC                  ; HL = font data
    LD D, $40                   ; Tercio 0, scan line 0
    LD A, E                     ; Columna directa (fila 0 offset = 0)
    LD E, A                     ; DE = dir VRAM
    LD B, 8
.row0Char:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC D                       ; siguiente scan line
    DJNZ .row0Char
    RET

; ==============================================================================
; DrawTimeIndicator - Muestra momento del dia en HUD (fila 1, col 30-31)
; ==============================================================================
DrawTimeIndicator:
    ; Calcular puntero al label de 2 chars
    LD A, (CurrentTimeOfDay)
    ADD A, A                    ; A = momento * 2
    LD E, A
    LD D, 0
    LD HL, TimeLabels
    ADD HL, DE                  ; HL = &TimeLabels[momento*2]

    ; Primer caracter en columna 30
    LD A, (HL)
    PUSH HL
    LD E, 30
    CALL DrawHudChar
    POP HL

    ; Segundo caracter en columna 31
    INC HL
    LD A, (HL)
    LD E, 31
    CALL DrawHudChar

    ; Atributos del indicador (bright white on black)
    LD HL, ATTR_BASE + 1 * 32 + 30
    LD A, $47                   ; bright, paper=black, ink=white
    LD (HL), A
    INC HL
    LD (HL), A
    RET

; Dibuja un caracter de la ROM font en fila 1 del HUD
; A = codigo ASCII, E = columna (0-31)
DrawHudChar:
    ; Calcular puntero a font data: $3C00 + ASCII * 8
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    LD BC, $3C00
    ADD HL, BC                  ; HL = font data

    ; Calcular dir VRAM para fila 1: $40xx + $20 + columna
    LD D, $40                   ; Tercio 0, scan line 0
    LD A, $20                   ; Fila 1 dentro del tercio (1*32=$20)
    ADD A, E
    LD E, A                     ; DE = dir VRAM

    LD B, 8
.hudCharLoop:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC D                       ; Siguiente scan line
    DJNZ .hudCharLoop
    RET

; ==============================================================================
; DATOS
; ==============================================================================

; --- Nombres de rooms (debug HUD) ---
; En day_cycle.asm para no ser sobreescrito por el level editor
RoomNameTable:
    DEFW RoomName_00    ; 0 - Vacia
    DEFW RoomName_01    ; 1 - plaza inicio
    DEFW RoomName_02    ; 2 - plaza verde
    DEFW RoomName_03    ; 3
    DEFW RoomName_04    ; 4
    DEFW RoomName_05    ; 5
    DEFW RoomName_06    ; 6
    DEFW RoomName_07    ; 7
    DEFW RoomName_08    ; 8
    DEFW RoomName_09    ; 9
    DEFW RoomName_10    ; 10
    DEFW RoomName_11    ; 11
    DUP 36
    DEFW RoomName_00
    EDUP

RoomName_00: DEFB "---", 0
RoomName_01: DEFB "plaza inicio", 0
RoomName_02: DEFB "plaza verde", 0
RoomName_03: DEFB "room 3", 0
RoomName_04: DEFB "plaza E", 0
RoomName_05: DEFB "plaza NE", 0
RoomName_06: DEFB "calle S", 0
RoomName_07: DEFB "esquina SE", 0
RoomName_08: DEFB "calle N", 0
RoomName_09: DEFB "calle SW", 0
RoomName_10: DEFB "plaza NW", 0
RoomName_11: DEFB "calle NE", 0

; --- Labels para el indicador HUD ---
TimeLabels:
    DEFB "DY"                   ; 0: Dia
    DEFB "C1"                   ; 1: Crepusculo temprano
    DEFB "C2"                   ; 2: Crepusculo tardio
    DEFB "N1"                   ; 3: Noche temprana
    DEFB "N2"                   ; 4: Noche tardia
    DEFB "A1"                   ; 5: Amanecer temprano
    DEFB "A2"                   ; 6: Amanecer tardio

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

; ==============================================================================
; DayHudFont - Font custom para indicador "DAY xx" (chars01-456x480-104x8.aseprite)
; Orden: D, A, Y, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9  (13 chars x 8 bytes = 104 bytes)
; ==============================================================================
DayHudFont:
    ; 'D'
    DEFB $00, $F0, $6C, $62, $62, $64, $F8, $00
    ; 'A'
    DEFB $00, $0C, $38, $64, $FC, $C6, $C3, $00
    ; 'Y'
    DEFB $00, $C2, $C2, $EC, $78, $38, $0E, $00
    ; '0'
    DEFB $00, $3C, $62, $C2, $C2, $E2, $7C, $00
    ; '1'
    DEFB $00, $18, $38, $68, $08, $18, $7E, $00
    ; '2'
    DEFB $00, $7C, $C6, $8E, $38, $62, $FE, $00
    ; '3'
    DEFB $00, $7C, $C6, $1C, $06, $E6, $7C, $00
    ; '4'
    DEFB $00, $33, $63, $C6, $FC, $18, $30, $00
    ; '5'
    DEFB $00, $3E, $60, $7C, $06, $C6, $7C, $00
    ; '6'
    DEFB $00, $1E, $60, $FC, $C2, $C2, $7C, $00
    ; '7'
    DEFB $00, $FE, $C6, $0C, $38, $70, $E0, $00
    ; '8'
    DEFB $00, $3C, $62, $7C, $C6, $C2, $7C, $00
    ; '9'
    DEFB $00, $7C, $C2, $E2, $3E, $0C, $F0, $00
