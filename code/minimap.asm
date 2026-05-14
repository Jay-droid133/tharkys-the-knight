; ==============================================================================
; MINIMAP - Overlay de mapa 16x16 (tecla I)
; Bank 0
; ==============================================================================
; Dibuja un sprite 8x8 por sala en la capa de pixeles + attrs.
; Las conexiones reales (gaps walkables) se leen de MinimapConnTable (bank 0,
; generada por tools/build_screen_gaps.py).
;
;   Sala valida:  borde azul oscuro, lados abiertos segun conexiones reales
;                   attr: $01 (paper=0 ink=1 no-bright)
;   Jugador:      bloque solido amarillo brillante
;                   attr: $76 (bright paper=6 ink=6)
;   Objetivo:     bloque solido cyan brillante
;                   attr: $6D (bright paper=5 ink=5)
;   Vacio:        negro (attr ya $00, pixeles irrelevantes con paper=ink=0)
;
; Patron de sala (bit 3=N bit 2=S bit 1=W bit 0=E en flags, 1=abierto):
;   fila 0: $FF si N cerrado, $00 si N abierto
;   filas 1-6: bit7=1 si W cerrado, bit0=1 si E cerrado
;   fila 7: $FF si S cerrado, $00 si S abierto
;
; Tecla I: abrir. Tecla I otra vez: cerrar.
; ScreenDirty=1 al cerrar -> repintado completo en el siguiente frame.
;
; INC H avanza scanlines dentro de un char (siempre en el mismo third:
; $40xx/$48xx/$50xx). Las dir. de fila 0 vienen de mmRowTable (16 DEFW).
; ==============================================================================

MINIMAP_ATTR_BASE   EQU $5888   ; char(8,4): $5800 + 4*32 + 8

MM_EMPTY    EQU $00
MM_ROOM     EQU $01     ; azul oscuro (paper=0 ink=1 no-bright)
MM_PLAYER   EQU $76     ; amarillo brillante (paper=6 ink=6 bright)
MM_GOAL     EQU $6D     ; cyan brillante    (paper=5 ink=5 bright)

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

    ; Bucle principal: HL=MapTable, DE=attr dest, C=fila, B=columna
    LD HL, MapTable
    LD DE, MINIMAP_ATTR_BASE
    LD C, 0                     ; fila minimap (0..15)

.smRow:
    ; Leer pixel base de esta fila desde la tabla
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
    JR Z, .smAdvance            ; vacio: sin attr, sin pixeles

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
    JR Z, .smIsRoom
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
    CALL smDrawConnectedBorder

.smAdvance:
    INC HL
    INC DE
    INC B
    LD A, B
    CP 16
    JR NZ, .smCol

    ; Saltar 16 bytes en attrs para la siguiente fila de pantalla
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

    LD A, 1
    LD (ScreenDirty), A

    POP AF
    POP BC
    POP DE
    POP HL
    RET

; ------------------------------------------------------------------------------
; smDrawConnectedBorder - sprite 8x8 borde azul oscuro con lados abiertos
; Input: B=col (0..15), C=row (0..15)
; Flags de conexion desde MinimapConnTable[C*16+B]:
;   bit3=N  bit2=S  bit1=W  bit0=E  (1=abierto)
; Destruye A, D, E. PUSH/POP BC, DE, HL.
; ------------------------------------------------------------------------------
smDrawConnectedBorder:
    PUSH HL
    PUSH BC
    PUSH DE

    ; Leer flags: MinimapConnTable[C*16 + B]
    LD H, 0
    LD L, C
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL              ; HL = C * 16
    LD A, B
    ADD A, L
    LD L, A                 ; HL = C*16 + B  (no desborda: max 240+15=255)
    LD DE, MinimapConnTable
    ADD HL, DE
    LD A, (HL)              ; A = flags
    LD E, A                 ; guardar flags en E

    ; Apuntar a pixeles del char actual: mmPixBase + B
    LD HL, (mmPixBase)
    LD A, L
    ADD A, B
    LD L, A

    ; --- fila 0: $FF si N cerrado, $00 si N abierto ---
    LD A, E
    AND $08                 ; bit 3 = N
    LD A, $FF
    JR Z, .topWrite         ; N cerrado (bit=0, Z=1) -> $FF
    LD A, $00               ; N abierto -> $00
.topWrite:
    LD (HL), A
    INC H

    ; --- filas 1-6: bit7=(W cerrado), bit0=(E cerrado) ---
    LD A, E
    LD D, $00               ; mid pixel
    BIT 1, A                ; bit 1 = W
    JR NZ, .wOpen           ; W abierto: dejar bit7=0
    SET 7, D                ; W cerrado: pared izquierda
.wOpen:
    BIT 0, A                ; bit 0 = E
    JR NZ, .eOpen           ; E abierto: dejar bit0=0
    SET 0, D                ; E cerrado: pared derecha
.eOpen:
    LD A, D
    LD B, 6
.midLoop:
    LD (HL), A
    INC H
    DJNZ .midLoop

    ; --- fila 7: $FF si S cerrado, $00 si S abierto ---
    LD A, E
    AND $04                 ; bit 2 = S
    LD A, $FF
    JR Z, .botWrite         ; S cerrado -> $FF
    LD A, $00               ; S abierto -> $00
.botWrite:
    LD (HL), A

    POP DE
    POP BC
    POP HL
    RET

; ------------------------------------------------------------------------------
; smDrawSolid - sprite 8x8 solido (jugador / objetivo)
; Destruye A. PUSH/POP BC, HL.
; ------------------------------------------------------------------------------
smDrawSolid:
    PUSH HL
    PUSH BC
    LD HL, (mmPixBase)
    LD A, L
    ADD A, B
    LD L, A
    LD A, $FF
    LD B, 8
.loop:
    LD (HL), A
    INC H
    DJNZ .loop
    POP BC
    POP HL
    RET

; ------------------------------------------------------------------------------
; Tabla de dir. del primer scanline (r=0) para columna 8, filas minimap 0..15
; Formula: $4000 + ((y & $C0)<<5) + ((y & $38)<<2) + ((y & $07)<<8) + 8
;   donde y = char_row * 8
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

    INCLUDE "minimap_conn.asm"
