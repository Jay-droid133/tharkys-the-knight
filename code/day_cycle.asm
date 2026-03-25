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
    CALL SetTimeOfDay
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
    CALL .drawHudChar
    POP HL

    ; Segundo caracter en columna 31
    INC HL
    LD A, (HL)
    LD E, 31
    CALL .drawHudChar

    ; Atributos del indicador (bright white on black)
    LD HL, ATTR_BASE + 23 * 32 + 30
    LD A, $47                   ; bright, paper=black, ink=white
    LD (HL), A
    INC HL
    LD (HL), A
    RET

; Dibuja un caracter de la ROM font en fila 23 del HUD
; A = codigo ASCII, E = columna (0-31)
.drawHudChar:
    ; Calcular puntero a font data: $3C00 + ASCII * 8
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    LD BC, $3C00
    ADD HL, BC                  ; HL = font data

    ; Calcular dir VRAM para fila 23: $50E0 + columna
    LD D, $50                   ; Tercio 2, scan line 0
    LD A, $E0                   ; Fila 7 dentro del tercio (23-16=7, 7*32=$E0)
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

; --- Lista de sprites tipo "house" (terminada en $0000) ---
HouseSpriteList:
    DEFW BgGfx_big_house
    DEFW $0000

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
    ; W->Y (same bright), R+->R-, C+->C-
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  2,  3,  4,  5,  6,  6,   8,   9,  2, 11, 12,  5, 14, 14

RemapTable_CrepTd:  ; Crepusculo tardio / Amanecer temprano (standard)
    ; W->M-, Y->M-, R+->R-, C+->C-
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  2,  3,  4,  5,  3,  3,   8,   9,  2, 11, 12,  5,  3,  3

RemapTable_NocheT:  ; Noche temprana
    ; R->Bl-, M->Bl(keep bright), Y->Bl-, W->Bl-, C+->C-
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  1,  1,  4,  5,  1,  1,   8,   9,  1,  9, 12,  5,  1,  1

RemapTable_NocheTd: ; Noche tardia (todo dim)
    ; Como NocheT pero forzar todo a dim
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  1,  1,  4,  5,  1,  1,   0,   1,  1,  1,  4,  5,  1,  1

; ==============================================================================
; REMAP TABLES - House override (ventanas = Cyan)
; ==============================================================================
; Solo difieren en indices 5 (C-) y 13 (C+) respecto a su tabla standard

RemapHouse_CrepTd:  ; Crep. tardio: ventanas ON -> Yellow dim
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  2,  3,  4,  6,  3,  3,   8,   9,  2, 11, 12,  6,  3,  3

RemapHouse_NocheT:  ; Noche temprana: ventanas ON brillantes -> Yellow bright
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  1,  1,  4, 14,  1,  1,   8,   9,  1,  9, 12, 14,  1,  1

RemapHouse_NocheTd: ; Noche tardia: ventanas OFF -> Blue dim
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  1,  1,  4,  1,  1,  1,   0,   1,  1,  1,  4,  1,  1,  1

RemapHouse_AmanT:   ; Amanecer temprano: ventanas -> Magenta dim
    ;       B-  Bl-  R-  M-  G-  C-  Y-  W-   B+  Bl+  R+  M+  G+  C+  Y+  W+
    DEFB    0,   1,  2,  3,  4,  3,  3,  3,   8,   9,  2, 11, 12,  3,  3,  3
