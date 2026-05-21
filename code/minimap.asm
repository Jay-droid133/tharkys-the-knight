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
;                   attr: $06 (paper=0 ink=6 no-bright) — amarillo dim.
;   Jugador:      su sprite del room + icono player (8x8) OR-ed por encima.
;   Objetivo:     su sprite del room + icono X (8x8) OR-ed por encima.
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

    ; Toda sala existente recibe attr MM_ROOM + su sprite topologico.
    LD A, MM_ROOM
    LD (DE), A
    CALL smDrawRoomSprite

    ; Si la sala es la del jugador, OR-ear el icon player encima.
    LD A, (mmPlayerY)
    CP C
    JR NZ, .smTryGoal
    LD A, (mmPlayerX)
    CP B
    JR NZ, .smTryGoal
    PUSH HL
    LD HL, mmIconPlayer
    LD (mmCurIcon), HL
    CALL smDrawIcon
    POP HL
    JR .smAdvance

.smTryGoal:
    LD A, (mmObjY)
    CP $FF
    JR Z, .smAdvance
    CP C
    JR NZ, .smAdvance
    LD A, (mmObjX)
    CP B
    JR NZ, .smAdvance
    PUSH HL
    LD HL, mmIconGoal
    LD (mmCurIcon), HL
    CALL smDrawIcon
    POP HL

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

; ------------------------------------------------------------------------------
; smDrawOuterFrame - cuadrado 128x128 px alrededor del minimap
; Top:    pixel row  32 ($4088..$4097, 16 bytes $FF)
; Bottom: pixel row 159 ($5768..$5777, 16 bytes $FF)
; Left:   pixel col  64 (bit 7 set en 16 char rows x 8 scans = 128 pixels)
; Right:  pixel col 191 (bit 0 set en col 23, mismo loop)
; Destruye AF, BC, DE, HL, IX.
; ------------------------------------------------------------------------------
smDrawOuterFrame:
    DI                              ; el IRQ handler no preserva IX/IY
    ; --- Attrs $06 (amarillo dim) en los 64 chars del borde del minimap.
    ; Sin esto, los chars del borde que coinciden con celdas vacias
    ; (MapTable=0) tienen attr=$00 default -> pixels del frame invisibles.
    LD A, $06                       ; MM_ROOM (yellow dim)
    LD HL, $5888                    ; row 4 col 8
    LD B, 16
.frAttrTop:
    LD (HL), A
    INC HL
    DJNZ .frAttrTop
    LD HL, $5A68                    ; row 19 col 8
    LD B, 16
.frAttrBot:
    LD (HL), A
    INC HL
    DJNZ .frAttrBot
    LD HL, $5888                    ; col 8 from row 4 step 32
    LD DE, 32
    LD B, 16
.frAttrLeft:
    LD (HL), A
    ADD HL, DE
    DJNZ .frAttrLeft
    LD HL, $5897                    ; col 23 from row 4 step 32
    LD B, 16
.frAttrRight:
    LD (HL), A
    ADD HL, DE
    DJNZ .frAttrRight
    ; --- Top: $4088..$4097 ---
    LD HL, $4088
    LD A, $FF
    LD B, 16
.frTop:
    LD (HL), A
    INC L
    DJNZ .frTop

    ; --- Bottom: $5768..$5777 ---
    LD HL, $5768
    LD B, 16
.frBot:
    LD (HL), A
    INC L
    DJNZ .frBot

    ; --- Left + Right: iterar mmRowTable via ptr en RAM (sin IX) ---
    LD HL, mmRowTable
    LD (frPtr), HL
    LD B, 16
.frRowLoop:
    PUSH BC
    LD HL, (frPtr)
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD (frPtr), HL              ; ptr avanzado
    EX DE, HL                   ; HL = mmRowTable entry actual
    LD B, 8
.frScanLoop:
    SET 7, (HL)                 ; left edge (col 8, bit 7 = pixel x=64)
    LD A, L
    ADD A, 15
    LD E, A
    LD D, H
    LD A, (DE)
    OR $01                      ; right edge (col 23, bit 0 = pixel x=191)
    LD (DE), A
    INC H                       ; next scanline (mismo char row)
    DJNZ .frScanLoop
    POP BC
    DJNZ .frRowLoop
    EI
    RET

frPtr: DEFW 0

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

    ; minimap_sprites.asm ahora se INCLUDEa desde main.asm en el bloque slot 1
    ; (bank 5) para evitar que la stack en $FFxx corrompa MinimapSpriteIndex.
