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
; Tecla M: abrir. Tecla M otra vez: cerrar.
; ScreenDirty=1 al cerrar -> repintado completo en el siguiente frame.
;
; INC H avanza scanlines dentro de un char (siempre en el mismo third:
; $40xx/$48xx/$50xx). Las dir. de fila 0 vienen de mmRowTable (16 DEFW).
; ==============================================================================

MINIMAP_ATTR_BASE   EQU $5888   ; char(8,4): $5800 + 4*32 + 8

MM_EMPTY    EQU $00
MM_ROOM     EQU $06     ; amarillo dim (paper=0 ink=6 no-bright)
; Player/Goal usan los mismos attrs que las salas (MM_ROOM). Los iconos
; (sprites BG 87 y 180) se pintan OR con los pixels existentes -> se ven
; tanto la pared del room como el icon encima en el mismo color.
MM_PLAYER   EQU MM_ROOM
MM_GOAL     EQU MM_ROOM

; ------------------------------------------------------------------------------
; CheckMinimapKey - llamar desde MainLoop cada frame
; Preserva todos los registros del caller.
; ------------------------------------------------------------------------------
CheckMinimapKey:
    PUSH AF
    PUSH BC
    LD BC, $7FFE            ; fila SPACE-SS-M-N-B
    IN A, (C)
    BIT 2, A                ; M = bit 2 (active low)
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

    ; Silenciar AY (música + SFX + bell) durante el minimap. State del driver
    ; preservado; al ResumeAy continúa donde quedó. Los tics del beeper no
    ; suenan porque MainLoop está bloqueado en el HALT-loop de abajo.
    CALL PauseAy

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
    CALL smDrawConnectedBorder  ; pintar pared del room (base sobre la que se AND-ea)
    LD HL, mmIconPlayer
    LD (mmCurIcon), HL
    CALL smDrawIcon
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
    CALL smDrawConnectedBorder  ; pintar pared del room (base sobre la que se AND-ea)
    LD HL, mmIconGoal
    LD (mmCurIcon), HL
    CALL smDrawIcon
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

    ; Esperar pulsacion de M para cerrar
    LD BC, $7FFE
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

    ; Reanudar AY: el driver continúa donde estaba y re-arma vols en la
    ; siguiente nota; los SFX activos siguen su sweep desde donde se pausaron.
    CALL ResumeAy

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

    ; --- Forzar paredes en bordes externos del mapa (16x16): aunque la tabla
    ;     diga "gap" en un lado del borde (porque el template del room tiene
    ;     walkable cells ahi pero no hay vecina al otro lado), se debe dibujar
    ;     pared. Limpia el bit correspondiente. ---
    LD A, C
    OR A
    JR NZ, .smcbNotTop
    RES 3, E                ; C=0  -> N cerrado (pared superior)
.smcbNotTop:
    CP 15
    JR NZ, .smcbNotBot
    RES 2, E                ; C=15 -> S cerrado (pared inferior)
.smcbNotBot:
    LD A, B
    OR A
    JR NZ, .smcbNotLeft
    RES 1, E                ; B=0  -> W cerrado (pared izquierda)
.smcbNotLeft:
    CP 15
    JR NZ, .smcbNotRight
    RES 0, E                ; B=15 -> E cerrado (pared derecha)
.smcbNotRight:

    ; --- Deduplicar paredes compartidas: si hay vecina existente al E o al S,
    ;     marcar ese lado como "abierto" para que solo la vecina dibuje la pared.
    ;     Resultado: paredes compartidas son lineas de 1 px (no 2).
    ;     Solo se desactiva en lados con vecina valida; bordes externos y vecinas
    ;     vacias siguen dibujando normal.
    LD A, B
    CP 15
    JR Z, .skipDedupE       ; ultima columna -> dibujar E si cerrado
    PUSH HL
    PUSH DE
    LD H, 0
    LD L, C
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL              ; HL = C*16
    LD A, B
    INC A
    ADD A, L
    LD L, A                 ; HL = C*16 + (B+1)
    LD DE, MapTable
    ADD HL, DE
    LD A, (HL)
    POP DE
    POP HL
    OR A
    JR Z, .skipDedupE       ; vecina vacia -> dibujar E
    SET 0, E                ; vecina existe -> ella dibuja su W
.skipDedupE:
    LD A, C
    CP 15
    JR Z, .skipDedupS       ; ultima fila -> dibujar S
    PUSH HL
    PUSH DE
    LD A, C
    INC A
    LD H, 0
    LD L, A
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL              ; HL = (C+1)*16
    LD A, B
    ADD A, L
    LD L, A                 ; HL = (C+1)*16 + B
    LD DE, MapTable
    ADD HL, DE
    LD A, (HL)
    POP DE
    POP HL
    OR A
    JR Z, .skipDedupS       ; vecina vacia -> dibujar S
    SET 2, E                ; vecina existe -> ella dibuja su N
.skipDedupS:

    ; Apuntar a pixeles del char actual: mmPixBase + B
    LD HL, (mmPixBase)
    LD A, L
    ADD A, B
    LD L, A

    ; --- Calcular D (paredes laterales W/E) primero, para OR-earlo
    ;     tambien en filas 0 y 7 y eliminar huecos verticales en esquinas
    LD A, E
    LD D, $00
    BIT 1, A                ; bit 1 = W
    JR NZ, .wOpen           ; W abierto: dejar bit7=0
    SET 7, D                ; W cerrado: pared izquierda
.wOpen:
    BIT 0, A                ; bit 0 = E
    JR NZ, .eOpen           ; E abierto: dejar bit0=0
    SET 0, D                ; E cerrado: pared derecha
.eOpen:

    ; --- fila 0: (N cerrado ? $FF : $00) OR D ---
    LD A, E
    AND $08
    JR NZ, .topOpen         ; N abierto -> base $00
    LD A, $FF
    JR .topMerge
.topOpen:
    XOR A
.topMerge:
    OR D
    LD (HL), A
    INC H

    ; --- filas 1-6: D ---
    LD A, D
    LD B, 6
.midLoop:
    LD (HL), A
    INC H
    DJNZ .midLoop

    ; --- fila 7: (S cerrado ? $FF : $00) OR D ---
    LD A, E
    AND $04
    JR NZ, .botOpen
    LD A, $FF
    JR .botMerge
.botOpen:
    XOR A
.botMerge:
    OR D
    LD (HL), A

    POP DE
    POP BC
    POP HL
    RET

; ------------------------------------------------------------------------------
; smDrawIcon - aplica OR con los 8 bytes desde (mmCurIcon) al char actual.
; Pre: mmCurIcon = ptr a tabla de 8 bytes (los pixels del icon).
; Donde el icon es 1, enciende el pixel (icon visible). Donde es 0, mantiene
; el pixel existente (pared visible). Asi el icon se superpone a la pared
; sin borrarla.
; Destruye A. PUSH/POP BC, DE, HL.
; ------------------------------------------------------------------------------
smDrawIcon:
    PUSH HL
    PUSH BC
    PUSH DE
    LD HL, (mmPixBase)
    LD A, L
    ADD A, B
    LD L, A                     ; HL = destino VRAM (primer scanline del char)
    LD DE, (mmCurIcon)          ; DE = source data (8 bytes)
    LD B, 8
.loop:
    LD A, (DE)
    OR (HL)                     ; OR con pixels existentes (pared)
    LD (HL), A
    INC DE
    INC H                       ; next scanline (mismo char)
    DJNZ .loop
    POP DE
    POP BC
    POP HL
    RET

; --- Iconos del minimap (8x8 pixels c/u) -------------------------------------
; pixelBytes extraidos de bg_sprites.json id 87 (player) e id 180 (x).
; Mantenidos aqui en lugar de en bg_gfx*.asm porque son exclusivos del minimap
; y caben en 16 B + 2 B ptr - mucho mas barato que la pipeline de sprites BG.
mmIconPlayer:
    DEFB $00, $00, $3C, $24, $3C, $18, $00, $00    ; sprite 87 'player icon'
mmIconGoal:
    DEFB $00, $42, $24, $18, $18, $24, $42, $00    ; sprite 180 'x icon'

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
mmCurIcon:      DEFW 0          ; ptr al icon activo (player o goal) para smDrawIcon
mmPlayerX:      DEFB 0
mmPlayerY:      DEFB 0
mmObjX:         DEFB 0
mmObjY:         DEFB 0

    INCLUDE "minimap_conn.asm"
