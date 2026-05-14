; ==============================================================================
; MINIMAP - Overlay de mapa 16x16 (tecla I)
; Bank 0
; ==============================================================================
; MapTable es un grid 16x16 (256 bytes): indice 0=vacio, nonzero=sala valida.
; La minimap se dibuja SOLO en la capa de atributos (paper=ink => bloque solido).
; Los pixeles del BG no se modifican; ScreenDirty=1 al cerrar fuerza repintado.
;
; Tecla I: abrir. Tecla I de nuevo: cerrar.
;
; Colores:
;   Vacio          -> negro   ($00)
;   Sala valida    -> blanco brillante ($7F  bright,paper=7,ink=7)
;   Jugador        -> amarillo brillante ($76 bright,paper=6,ink=6)
;   Objetivo activo-> cyan brillante    ($6D bright,paper=5,ink=5)
; ==============================================================================

; Attr del char (8, 4): $5800 + 4*32 + 8 = $5888
MINIMAP_ATTR_BASE   EQU $5888

MM_EMPTY    EQU $00
MM_ROOM     EQU $09
MM_PLAYER   EQU $76
MM_GOAL     EQU $6D

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
; ShowMinimap - puede llamarse directamente (no requiere pasar por Check)
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

    ; Limpiar toda la capa de atributos a negro
    LD HL, $5800
    LD (HL), 0
    LD DE, $5801
    LD BC, 767
    LDIR

    ; Dibujar grid 16x16 en attrs char(8,4)..(23,19)
    LD HL, MapTable
    LD DE, MINIMAP_ATTR_BASE
    LD C, 0                 ; C = fila minimap (0..15)

.smRow:
    LD B, 0                 ; B = columna minimap (0..15)
.smCol:
    LD A, (HL)
    OR A
    JR Z, .smEmpty

    ; Jugador?
    LD A, (mmPlayerY)
    CP C
    JR NZ, .smTryGoal
    LD A, (mmPlayerX)
    CP B
    JR NZ, .smTryGoal
    LD A, MM_PLAYER
    JR .smWrite

.smTryGoal:
    ; Objetivo? ($FF = no resuelto: saltar)
    LD A, (mmObjY)
    CP $FF
    JR Z, .smPlain
    CP C
    JR NZ, .smPlain
    LD A, (mmObjX)
    CP B
    JR NZ, .smPlain
    LD A, MM_GOAL
    JR .smWrite

.smPlain:
    LD A, MM_ROOM
    JR .smWrite

.smEmpty:
    XOR A                   ; MM_EMPTY = 0

.smWrite:
    LD (DE), A
    INC HL
    INC DE
    INC B
    LD A, B
    CP 16
    JR NZ, .smCol

    ; Saltar al inicio de la siguiente fila del attr screen (+16 bytes)
    LD A, E
    ADD A, 16
    LD E, A
    JR NC, .smNext
    INC D
.smNext:
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

    ; Forzar repintado del BG en el siguiente frame
    LD A, 1
    LD (ScreenDirty), A

    POP AF
    POP BC
    POP DE
    POP HL
    RET

; Variables temporales
mmPlayerX:  DEFB 0
mmPlayerY:  DEFB 0
mmObjX:     DEFB 0
mmObjY:     DEFB 0
