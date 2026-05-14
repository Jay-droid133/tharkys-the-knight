; ==============================================================================
; MINIMAP - Overlay de mapa 16x16 (tecla I)
; Bank 0
; ==============================================================================
; Dibuja un sprite 8x8 por sala en la capa de pixeles + attrs:
;   Sala valida: borde azul oscuro, relleno negro
;                  pixel pattern: $FF,$81x6,$FF  attr: $01 (paper=0 ink=1)
;   Jugador:     bloque solido amarillo brillante
;                  pixel pattern: $FFx8           attr: $76 (bright paper=6 ink=6)
;   Objetivo:    bloque solido cyan brillante
;                  pixel pattern: $FFx8           attr: $6D (bright paper=5 ink=5)
;   Vacio:       negro (attrs ya $00, pixeles no importan con paper=ink=0)
;
; Tecla I: abrir. Tecla I otra vez: cerrar.
; ScreenDirty=1 al cerrar -> BG repintado en el siguiente frame.
;
; ATENCION: INC H avanza el scanline dentro de un mismo char (pattern
; $40xx,$41xx..$47xx para el tercer 0, etc.) sin cruzar thirds.
; Los address de fila inicial vienen de mmRowTable (16 DEFW precalculados).
; ==============================================================================

; Attr base: char(8,4) en pantalla 32x24 -> $5800 + 4*32 + 8 = $5888
MINIMAP_ATTR_BASE   EQU $5888

MM_EMPTY    EQU $00     ; negro (vacio, attr ya limpio por LDIR)
MM_ROOM     EQU $01     ; azul oscuro (paper=0 ink=1 no-bright)
MM_PLAYER   EQU $76     ; amarillo brillante (paper=6 ink=6 bright)
MM_GOAL     EQU $6D     ; cyan brillante    (paper=5 ink=5 bright)

; Pixeles del sprite de sala (borde azul oscuro, interior negro)
MM_PIX_TOP  EQU $FF     ; fila 0 y 7: borde completo
MM_PIX_MID  EQU $81     ; filas 1-6:  solo bits 7 y 0 (bordes izq/der)
MM_PIX_SOLID EQU $FF    ; filas 0-7 solido (jugador / objetivo)

; ------------------------------------------------------------------------------
; CheckMinimapKey - llamar desde MainLoop cada frame
; Preserva todos los registros del caller.
; ------------------------------------------------------------------------------
CheckMinimapKey:
    PUSH AF
    PUSH BC
    LD BC, $DFFE            ; fila P-O-I-U-Y
    IN A, (C)
    BIT 2, A                ; I = bit 2 (active low)
    JR Z, .pressed
    POP BC
    POP AF
    RET
.pressed:
.waitRel:
    HALT
    IN A, (C)
    BIT 2, A
    JR Z, .waitRel          ; esperar liberacion (debounce)
    POP BC
    POP AF
    ; caer a ShowMinimap

; ------------------------------------------------------------------------------
; ShowMinimap - puede llamarse directamente
; ------------------------------------------------------------------------------
ShowMinimap:
    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF

    ; Cachear posicion del jugador y del objetivo
    LD A, (CurrentScreenX)
    LD (mmPlayerX), A
    LD A, (CurrentScreenY)
    LD (mmPlayerY), A
    LD A, (ObjectiveScreenX)
    LD (mmObjX), A
    LD A, (ObjectiveScreenY)
    LD (mmObjY), A

    ; Limpiar toda la capa de atributos a negro ($00)
    LD HL, $5800
    LD (HL), 0
    LD DE, $5801
    LD BC, 767
    LDIR

    ; Inicializar puntero a tabla de filas de pixeles
    LD HL, mmRowTable
    LD (mmRowTablePtr), HL

    ; Bucle principal: HL = MapTable, DE = attr dest, C = fila, B = columna
    LD HL, MapTable
    LD DE, MINIMAP_ATTR_BASE
    LD C, 0                     ; fila minimap (0..15)

.smRow:
    ; Leer pixel base de la tabla de filas
    PUSH HL
    LD HL, (mmRowTablePtr)
    LD A, (HL)
    LD (mmPixBase), A
    INC HL
    LD A, (HL)
    LD (mmPixBase+1), A
    INC HL
    LD (mmRowTablePtr), HL
    POP HL

    LD B, 0                     ; columna minimap (0..15)

.smCol:
    LD A, (HL)
    OR A
    JR Z, .smAdvance            ; vacio: no attr, no pixeles

    ; Jugador?
    LD A, (mmPlayerY)
    CP C
    JR NZ, .smTryGoal
    LD A, (mmPlayerX)
    CP B
    JR NZ, .smTryGoal
    LD A, MM_PLAYER
    LD (DE), A
    CALL smDrawSolid
    JR .smAdvance

.smTryGoal:
    LD A, (mmObjY)
    CP $FF
    JR Z, .smIsRoom             ; objetivo no resuelto
    CP C
    JR NZ, .smIsRoom
    LD A, (mmObjX)
    CP B
    JR NZ, .smIsRoom
    LD A, MM_GOAL
    LD (DE), A
    CALL smDrawSolid
    JR .smAdvance

.smIsRoom:
    LD A, MM_ROOM
    LD (DE), A
    CALL smDrawBorder

.smAdvance:
    INC HL
    INC DE
    INC B
    LD A, B
    CP 16
    JR NZ, .smCol

    ; Saltar 16 bytes en attrs para ir al inicio de la siguiente fila
    LD A, E
    ADD A, 16
    LD E, A
    JR NC, .smNoCarry
    INC D
.smNoCarry:
    INC C
    LD A, C
    CP 16
    JR NZ, .smRow

    ; Esperar pulsacion de I para cerrar
    LD BC, $DFFE
.smWaitPress:
    HALT
    IN A, (C)
    BIT 2, A
    JR NZ, .smWaitPress
.smWaitRelease:
    IN A, (C)
    BIT 2, A
    JR Z, .smWaitRelease

    ; Forzar repintado completo en el siguiente frame
    LD A, 1
    LD (ScreenDirty), A

    POP AF
    POP BC
    POP DE
    POP HL
    RET

; ------------------------------------------------------------------------------
; smDrawBorder - sprite 8x8 borde azul oscuro, interior negro
; mmPixBase + B = direccion del primer scanline del char
; Destruye A. PUSH/POP BC.
; ------------------------------------------------------------------------------
smDrawBorder:
    PUSH HL
    PUSH BC
    LD HL, (mmPixBase)
    LD A, L
    ADD A, B
    LD L, A                     ; HL -> scanline r=0 del char
    LD A, MM_PIX_TOP
    LD (HL), A                  ; r=0: borde superior
    INC H
    LD A, MM_PIX_MID
    LD B, 6
.sdb_mid:
    LD (HL), A                  ; r=1..6: bordes izq/der
    INC H
    DJNZ .sdb_mid
    LD A, MM_PIX_TOP
    LD (HL), A                  ; r=7: borde inferior
    POP BC
    POP HL
    RET

; ------------------------------------------------------------------------------
; smDrawSolid - sprite 8x8 solido (jugador / objetivo)
; mmPixBase + B = direccion del primer scanline del char
; Destruye A. PUSH/POP BC.
; ------------------------------------------------------------------------------
smDrawSolid:
    PUSH HL
    PUSH BC
    LD HL, (mmPixBase)
    LD A, L
    ADD A, B
    LD L, A                     ; HL -> scanline r=0 del char
    LD A, MM_PIX_SOLID
    LD B, 8
.sds_loop:
    LD (HL), A
    INC H
    DJNZ .sds_loop
    POP BC
    POP HL
    RET

; ------------------------------------------------------------------------------
; mmRowTable: direccion del scanline r=0 para la columna 8 de cada fila minimap
; Fila minimap 0..15 = char fila 4..19 de pantalla
; Formula: $4000 + ((y & $C0)<<5) + ((y & $38)<<2) + ((y & $07)<<8) + 8
;   donde y = char_row * 8 (r=0)
; ------------------------------------------------------------------------------
mmRowTable:
    DEFW $4088  ; cy=4  (y=32)
    DEFW $40A8  ; cy=5  (y=40)
    DEFW $40C8  ; cy=6  (y=48)
    DEFW $40E8  ; cy=7  (y=56)
    DEFW $4808  ; cy=8  (y=64)
    DEFW $4828  ; cy=9  (y=72)
    DEFW $4848  ; cy=10 (y=80)
    DEFW $4868  ; cy=11 (y=88)
    DEFW $4888  ; cy=12 (y=96)
    DEFW $48A8  ; cy=13 (y=104)
    DEFW $48C8  ; cy=14 (y=112)
    DEFW $48E8  ; cy=15 (y=120)
    DEFW $5008  ; cy=16 (y=128)
    DEFW $5028  ; cy=17 (y=136)
    DEFW $5048  ; cy=18 (y=144)
    DEFW $5068  ; cy=19 (y=152)

; Variables temporales
mmRowTablePtr:  DEFW 0
mmPixBase:      DEFW 0
mmPlayerX:      DEFB 0
mmPlayerY:      DEFB 0
mmObjX:         DEFB 0
mmObjY:         DEFB 0
