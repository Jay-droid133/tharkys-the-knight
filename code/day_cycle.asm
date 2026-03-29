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
CurrentTimeOfDay:       DEFB 0      ; Momento actual (0-6)
CurrentRemapTable:      DEFW RemapTable_Day
CurrentHouseRemapTable: DEFW RemapTable_Day
BgSpriteIsHouse:        DEFB 0      ; Flag temporal por sprite
DebugKeyDebounce:       DEFB 0      ; Anti-rebote tecla T

; ==============================================================================
; SetTimeOfDay - Cambia el momento del dia
; ==============================================================================
; Entrada: A = momento (0-6)
; ==============================================================================
SetTimeOfDay:
    LD (CurrentTimeOfDay), A

    ; Buscar puntero tabla standard
    LD HL, RemapTablePtrs
    LD E, A
    LD D, 0
    ADD HL, DE
    ADD HL, DE              ; HL = RemapTablePtrs + momento*2
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (CurrentRemapTable), DE

    ; Buscar puntero tabla house
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

    ; Forzar redibujado de pantalla
    LD A, 1
    LD (ScreenDirty), A
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
    RET

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
    LD A, (CurrentTimeOfDay)
    OR A
    JR NZ, .doRemap
    LD A, H                     ; Dia: devolver sin cambio
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
; Entrada: DE = direccion datos del sprite
; Setea BgSpriteIsHouse (0 o 1)
; Preserva: DE, IX
; ==============================================================================
CheckIfHouseSprite:
    PUSH HL
    PUSH BC

    XOR A
    LD (BgSpriteIsHouse), A     ; Default: no es house

    LD HL, HouseSpriteList
.checkLoop:
    LD C, (HL)
    INC HL
    LD B, (HL)
    INC HL                      ; BC = direccion sprite house
    LD A, B
    OR C
    JR Z, .checkDone            ; Terminador: no encontrado

    LD A, B
    CP D
    JR NZ, .checkLoop
    LD A, C
    CP E
    JR NZ, .checkLoop

    ; Encontrado: es house
    LD A, 1
    LD (BgSpriteIsHouse), A

.checkDone:
    POP BC
    POP HL
    RET

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
; DrawTimeIndicator - Muestra momento del dia en HUD (fila 23, col 30-31)
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

; HouseSpriteList is now auto-generated in bg_gfx.asm

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
    ; R->Bl-, M->Bl, Y->Bl, G->Bl (keep bright), W->Bl-, C+->C-
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  1,  1,  1,  5,  1,  1,   8,   9,  1,  9,  9,  5,  9,  1

RemapTable_NocheTd: ; Noche tardia (todo dim)
    ; Como NocheT pero forzar todo a dim
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  1,  1,  1,  5,  1,  1,   0,   1,  1,  1,  1,  5,  1,  1

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
