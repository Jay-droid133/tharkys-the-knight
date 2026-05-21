; ==============================================================================
; MINIMAP - Overlay de mapa 16x16 (tecla M)
; Bank 0
; ==============================================================================
; Pinta cada sala como un sprite topologico 8x8 px pre-renderizado. Los sprites
; reflejan paredes externas, exits (closed/open/dual) y tabiques internos del
; layout concreto de cada sala — disenados manualmente en
; tools/minimap_sprite_editor.html y agrupados/deduplicados en
; code/minimap_sprites.asm (generado por tools/build_minimap_sprites.py).
;
;   Sala valida:  pixels copiados del sprite asignado a esa (rx, ry).
;                   attr: $05 (paper=0 ink=5 no-bright) — cian dim.
;   Jugador:      mismo sprite, attr $47 (white ink bright) — sin icono.
;   Objetivo:     mismo sprite, attr $46 (yellow ink bright) — sin icono.
;   Vacio:        negro (attr $00, pixeles a 0).
;
; Tecla M: abrir. Tecla M otra vez: cerrar.
; ScreenDirty=1 al cerrar -> repintado completo en el siguiente frame.
;
; INC H avanza scanlines dentro de un char (siempre en el mismo third:
; $40xx/$48xx/$50xx). Las dir. de fila 0 vienen de mmRowTable (16 DEFW).
; ==============================================================================

MINIMAP_ATTR_BASE   EQU $5888   ; char(8,4): $5800 + 4*32 + 8

MM_EMPTY    EQU $00
MM_ROOM     EQU $05     ; cian dim (paper=0 ink=5 no-bright)
MM_PLAYER   EQU $47     ; blanco bright (paper=0 ink=7 bright)
MM_GOAL     EQU $46     ; amarillo bright (paper=0 ink=6 bright)

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
    POP BC
    POP AF
    ; caer a ShowMinimap. NO esperar la liberación aqui: lo haremos DENTRO de
    ; ShowMinimap tras cambiar SP a la alt-stack. De lo contrario los IRQs
    ; durante el HALT-loop hacen PUSH a $FFxx, corrompiendo
    ; MinimapSpriteData/Index (que viven ahi en bank 0).

; ------------------------------------------------------------------------------
; ShowMinimap - puede llamarse directamente
; ------------------------------------------------------------------------------
ShowMinimap:
    ; DI ANTES de cambiar SP: cierra la ventana en la que un IRQ M2 podria
    ; entrar con SP apuntando a la alt-stack pero IFF=1 y rebosarla.
    ; Cambio el stack a una zona alterna porque SP_ADDRESS=$FF58 cae DENTRO
    ; de MinimapSpriteIndex ($FEBA-$FFB9): las pushes corromperian las
    ; tablas que estoy leyendo. Uso PagingAltStack (slot 1, 64 B, siempre
    ; visible).
    DI
    LD (smSavedSP), SP
    LD SP, PagingAltStackTop
    ; Garantizar bank 0 en slot 3 — minimap_sprites.asm vive ahi.
    CALL _PageBank0

    ; Esperar liberacion de M con SP en alt-stack (los IRQ aqui no corrompen
    ; MinimapSpriteData/Index). EI necesario para que HALT despierte.
    EI
.smPreWaitRel:
    HALT
    LD BC, $7FFE
    IN A, (C)
    BIT 2, A
    JR Z, .smPreWaitRel
    DI

    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF

    ; Silenciar AY (música + SFX + bell) durante el minimap. State del driver
    ; preservado; al ResumeAy continúa donde quedó. Los tics del beeper no
    ; suenan porque MainLoop está bloqueado en el HALT-loop de abajo.
    CALL PauseAy
    DI                          ; PauseAy termina con EI; re-cerramos IRQ

    ; Cachear posicion del jugador y del objetivo
    LD A, (CurrentScreenX)
    LD (mmPlayerX), A
    LD A, (CurrentScreenY)
    LD (mmPlayerY), A
    LD A, (ObjectiveScreenX)
    LD (mmObjX), A
    LD A, (ObjectiveScreenY)
    LD (mmObjY), A

    ; Limpiar toda la capa de pixels a 0 ($4000-$57FF = 6144 B). Sin esto,
    ; los pixels del juego anterior se ven como ink amarillo (attr $06) en
    ; las celdas vacias del minimap -> "huecos" en el cuadrado exterior y
    ; basura visible en celdas sin room. ~6 ms aceptable: solo al abrir.
    LD HL, $4000
    LD (HL), 0
    LD DE, $4001
    LD BC, $1800 - 1
    LDIR

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

    ; Dibujar sprite topologico de la sala (pixels solo).
    CALL smDrawRoomSprite

    ; Decidir attr: player > goal > room.
    LD A, (mmPlayerY)
    CP C
    JR NZ, .smTryGoalAttr
    LD A, (mmPlayerX)
    CP B
    JR NZ, .smTryGoalAttr
    CALL smDrawDot              ; punto OR-eado sobre el sprite del room
    LD A, MM_PLAYER
    JR .smStoreAttr

.smTryGoalAttr:
    LD A, (mmObjY)
    CP $FF
    JR Z, .smRoomAttr
    CP C
    JR NZ, .smRoomAttr
    LD A, (mmObjX)
    CP B
    JR NZ, .smRoomAttr
    CALL smDrawDot              ; mismo punto en attr MM_GOAL (yellow bright)
    LD A, MM_GOAL
    JR .smStoreAttr

.smRoomAttr:
    LD A, MM_ROOM
.smStoreAttr:
    LD (DE), A

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

    ; Dibujar cuadrado exterior 128x128 px alrededor del minimap (4 lineas
    ; en pixel rows/cols 32, 159 / 64, 191).
    CALL smDrawOuterFrame

    ; Render completo. Reactivar IRQ para que HALT pueda despertar (HALT con
    ; IFF=0 cuelga). El SP sigue siendo el alt-stack — el IRQ handler que
    ; se dispare ahora usara la alt-stack (64 B, suficiente para el music
    ; tick que pica ~22 B).
    EI

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

    ; Restaurar stack normal. IRQ ya esta enabled (EI antes del HALT-loop).
    DI                          ; cerramos para hacer LD SP atomico
    LD SP, (smSavedSP)
    EI
    RET

smSavedSP:  DEFW 0

; ------------------------------------------------------------------------------
; smDrawRoomSprite - copia el sprite 8x8 de la sala (B, C) a VRAM.
; Input: B=col (0..15), C=row (0..15).
; Lookup: idx = MinimapSpriteIndex[C*16 + B]; src = MinimapSpriteData + idx*8.
; Destino VRAM: mmPixBase + B (low byte). 8 bytes copiados con INC del high
; del puntero (avanza scanline dentro del char).
; Destruye A. PUSH/POP BC, DE, HL.
; ------------------------------------------------------------------------------
smDrawRoomSprite:
    PUSH HL
    PUSH BC
    PUSH DE

    ; HL = MinimapSpriteIndex + C*16 + B  -> A = idx
    LD H, 0
    LD L, C
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL              ; HL = C * 16
    LD A, B
    ADD A, L
    LD L, A                 ; HL = C*16 + B
    LD DE, MinimapSpriteIndex
    ADD HL, DE
    LD A, (HL)              ; A = sprite idx (0..N-1)

    ; HL = MinimapSpriteData + idx*8
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL              ; HL = idx * 8
    LD DE, MinimapSpriteData
    ADD HL, DE              ; HL = src ptr (8 bytes)

    ; DE = VRAM dest: mmPixBase + B
    LD A, (mmPixBase)
    ADD A, B
    LD E, A
    LD A, (mmPixBase+1)
    LD D, A                 ; DE = scanline 0 del char (col B en fila actual)

    ; Copia 8 bytes (scanlines del char) con INC D para avanzar dentro del third.
    LD B, 8
.lp:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC D                   ; siguiente scanline (mismo char third)
    DJNZ .lp

    POP DE
    POP BC
    POP HL
    RET

; ------------------------------------------------------------------------------
; smDrawDot - OR del icono punto (mmDotIcon) al char actual.
; Input: B=col (0..15), (mmPixBase)=base VRAM de la fila actual.
; Usado por player y goal: marca visualmente la sala encima del sprite
; topologico. El color final lo da el attr de la celda (MM_PLAYER white
; bright para player, MM_GOAL yellow bright para goal).
; Destruye A. PUSH/POP BC, DE, HL.
; ------------------------------------------------------------------------------
smDrawDot:
    PUSH HL
    PUSH BC
    PUSH DE
    LD HL, (mmPixBase)
    LD A, L
    ADD A, B
    LD L, A                     ; HL = destino VRAM (primer scanline del char)
    LD DE, mmDotIcon            ; DE = source data (8 bytes)
    LD B, 8
.loop:
    LD A, (DE)
    OR (HL)                     ; OR con pixels existentes (paredes)
    LD (HL), A
    INC DE
    INC H                       ; next scanline (mismo char)
    DJNZ .loop
    POP DE
    POP BC
    POP HL
    RET

; Punto 2x2 centrado en char 8x8. OR-eado al sprite topologico de la sala
; marca la posicion del player (attr white bright) o del objetivo (attr
; yellow bright) sobre el resto del minimap (cian dim).
mmDotIcon:
    DEFB $00, $00, $00, $18, $18, $00, $00, $00

; ------------------------------------------------------------------------------
; smDrawOuterFrame - cuadrado 128x128 px alrededor del minimap
; Top:    pixel row  32 ($4088..$4097, 16 bytes $FF)
; Bottom: pixel row 159 ($5768..$5777, 16 bytes $FF)
; Left:   pixel col  64 (bit 7 set en 16 char rows x 8 scans = 128 pixels)
; Right:  pixel col 191 (bit 0 set en col 23, mismo loop)
; Destruye AF, BC, DE, HL, IX.
; ------------------------------------------------------------------------------
; ------------------------------------------------------------------------------
; smDrawOuterFrame - marco decorativo ALREDEDOR del minimap.
; Vive en un anillo de chars EXTERIOR al minimap (rows 3+20, cols 7+24)
; para no compartir attr con las salas perimetrales (que tienen MM_ROOM /
; MM_PLAYER / MM_GOAL).
;
; 8 sprites (NW, N, NE, W, E, SW, S, SE) editables en
; tools/minimap_sprite_editor.html y emitidos en MinimapFrameSprites
; (offsets 0,8,16,24,32,40,48,56). Attr $05 cyan dim en los 68 chars.
;
; Destruye AF, BC, DE, HL.
; ------------------------------------------------------------------------------
smDrawOuterFrame:
    DI                              ; el IRQ handler no preserva IX/IY

    ; --- Attrs $05 (paper=0 ink=cyan dim) en los 68 chars del anillo ---
    LD A, $05

    ; Top edge: row 3 cols 7..24 (18 chars)
    LD HL, $5867
    LD B, 18
.frAttrTop:
    LD (HL), A
    INC HL
    DJNZ .frAttrTop

    ; Bottom edge: row 20 cols 7..24 (18 chars)
    LD HL, $5A87
    LD B, 18
.frAttrBot:
    LD (HL), A
    INC HL
    DJNZ .frAttrBot

    ; Left edge: col 7 rows 4..19 (16 chars, step 32)
    LD HL, $5887
    LD DE, 32
    LD B, 16
.frAttrLeft:
    LD (HL), A
    ADD HL, DE
    DJNZ .frAttrLeft

    ; Right edge: col 24 rows 4..19 (16 chars, step 32)
    LD HL, $5898
    LD B, 16
.frAttrRight:
    LD (HL), A
    ADD HL, DE
    DJNZ .frAttrRight

    ; --- Pixels: copiar los 8 sprites del marco a VRAM ---

    ; NW: char (row 3, col 7)
    LD HL, MinimapFrameSprites          ; +0 NW
    LD DE, $4067
    CALL smCopyFramePiece

    ; N: 16 chars en (row 3, cols 8..23)
    LD DE, $4068
    LD B, 16
.frNLoop:
    PUSH BC
    LD HL, MinimapFrameSprites + 8      ; N
    CALL smCopyFramePiece
    INC E
    POP BC
    DJNZ .frNLoop

    ; NE: char (row 3, col 24)
    LD HL, MinimapFrameSprites + 16     ; NE
    LD DE, $4078
    CALL smCopyFramePiece

    ; W + E: iterar mmRowTable (rows 4..19) para los lados verticales
    LD HL, mmRowTable
    LD (frPtr), HL
    LD B, 16
.frWELoop:
    PUSH BC
    LD HL, (frPtr)
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD (frPtr), HL                      ; ptr avanzado (DE = col 8 base)

    PUSH DE
    DEC DE                              ; col 7 = col 8 - 1
    LD HL, MinimapFrameSprites + 24     ; W
    CALL smCopyFramePiece
    POP DE

    LD A, E
    ADD A, 16                           ; col 24 = col 8 + 16
    LD E, A
    LD HL, MinimapFrameSprites + 32     ; E
    CALL smCopyFramePiece

    POP BC
    DJNZ .frWELoop

    ; SW: char (row 20, col 7)
    LD HL, MinimapFrameSprites + 40     ; SW
    LD DE, $5087
    CALL smCopyFramePiece

    ; S: 16 chars en (row 20, cols 8..23)
    LD DE, $5088
    LD B, 16
.frSLoop:
    PUSH BC
    LD HL, MinimapFrameSprites + 48     ; S
    CALL smCopyFramePiece
    INC E
    POP BC
    DJNZ .frSLoop

    ; SE: char (row 20, col 24)
    LD HL, MinimapFrameSprites + 56     ; SE
    LD DE, $5098
    CALL smCopyFramePiece

    EI
    RET

; ------------------------------------------------------------------------------
; smCopyFramePiece - copia un sprite de 8 bytes a un char en VRAM.
; IN:  HL = src (8 bytes), DE = dest scanline 0 del char (mismo screen third)
; OUT: HL y DE preservados (avanzados internamente, restaurados).
; Destruye: AF, B.
; ------------------------------------------------------------------------------
smCopyFramePiece:
    PUSH HL
    PUSH DE
    LD B, 8
.lp:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC D                       ; next scanline (mismo third)
    DJNZ .lp
    POP DE
    POP HL
    RET

frPtr: DEFW 0

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

    ; minimap_sprites.asm ahora se INCLUDEa desde main.asm en el bloque slot 1
    ; (bank 5) para evitar que la stack en $FFxx corrompa MinimapSpriteIndex.
