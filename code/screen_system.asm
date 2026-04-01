; ==============================================================================
; SISTEMA DE PANTALLAS (estilo Sabre Wulf - flick-screen)
; ==============================================================================
; Mapa de 256 pantallas (16x16). Cada pantalla es un "room" definido como
; lista de sprites de fondo (BgSprites). La colision se hace iterando la
; lista de sprites del room actual (como la rutina B873 de Sabre Wulf).
; ==============================================================================

; ==============================================================================
; InitScreenSystem - Inicializa el sistema de pantallas
; ==============================================================================
InitScreenSystem:
    LD A, START_SCREEN_X
    LD (CurrentScreenX), A
    LD A, START_SCREEN_Y
    LD (CurrentScreenY), A
    LD A, 1
    LD (ScreenDirty), A         ; Forzar dibujado inicial
    XOR A
    LD (ScreenTransition), A
    CALL CalcScreenAddress
    RET

; ==============================================================================
; CalcScreenAddress - Lee MapTable y RoomTable para obtener puntero al room
; ==============================================================================
; MapTable[Y*16+X] = indice de room -> RoomTable[indice] = puntero a room data
; ==============================================================================
CalcScreenAddress:
    LD A, (CurrentScreenY)
    LD L, A
    LD H, 0
    ADD HL, HL                  ; x2
    ADD HL, HL                  ; x4
    ADD HL, HL                  ; x8
    ADD HL, HL                  ; x16
    LD A, (CurrentScreenX)
    LD E, A
    LD D, 0
    ADD HL, DE                  ; HL = Y*16 + X
    LD DE, MapTable
    ADD HL, DE                  ; HL = &MapTable[index]
    LD A, (HL)                  ; A = room index (0-47)
    ; Lookup en RoomTable (tabla de DEFWs)
    LD L, A
    LD H, 0
    ADD HL, HL                  ; index * 2
    LD DE, RoomTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = puntero a room data
    LD (CurrentScreenAddr), DE
    RET

; ==============================================================================
; CheckScreenTransition - Detecta si el jugador debe cambiar de pantalla
; ==============================================================================
CheckScreenTransition:
    XOR A
    LD (ScreenTransition), A

    ; --- Comprobar borde OESTE (izquierdo) ---
    LD A, (EntityTable + ENT_POSX)
    CP TRANSITION_ZONE
    JR NC, .noWest
    LD A, (CurrentScreenX)
    OR A
    JR Z, .noWest
    DEC A
    LD (CurrentScreenX), A
    LD A, DIR_W
    LD (ScreenTransition), A
    LD A, SCREEN_MAX_X - 8
    LD (EntityTable + ENT_POSX), A
    JR .doTransition

.noWest:
    ; --- Comprobar borde ESTE (derecho) ---
    LD A, (EntityTable + ENT_POSX)
    CP SCREEN_MAX_X
    JR C, .noEast
    LD A, (CurrentScreenX)
    CP MAP_WIDTH - 1
    JR Z, .noEast
    INC A
    LD (CurrentScreenX), A
    LD A, DIR_E
    LD (ScreenTransition), A
    LD A, TRANSITION_ZONE + 1
    LD (EntityTable + ENT_POSX), A
    JR .doTransition

.noEast:
    ; --- Comprobar borde NORTE (superior) ---
    LD A, (EntityTable + ENT_POSY)
    CP SCREEN_MIN_Y + TRANSITION_ZONE
    JR NC, .noNorth
    LD A, (CurrentScreenY)
    OR A
    JR Z, .noNorth
    DEC A
    LD (CurrentScreenY), A
    LD A, DIR_N
    LD (ScreenTransition), A
    LD A, SCREEN_MAX_Y - 8
    LD (EntityTable + ENT_POSY), A
    JR .doTransition

.noNorth:
    ; --- Comprobar borde SUR (inferior) ---
    LD A, (EntityTable + ENT_POSY)
    CP SCREEN_MAX_Y
    JR C, .noSouth
    LD A, (CurrentScreenY)
    CP MAP_HEIGHT - 1
    JR Z, .noSouth
    INC A
    LD (CurrentScreenY), A
    LD A, DIR_S
    LD (ScreenTransition), A
    LD A, SCREEN_MIN_Y + TRANSITION_ZONE + 1
    LD (EntityTable + ENT_POSY), A

.doTransition:
    CALL CalcScreenAddress
    CALL ClearNasties           ; Limpiar enemigos al cambiar de pantalla
    CALL RepositionMonstersAtEntry ; Monsters siguen al player desde la pantalla anterior
    ; SFX de transicion de pantalla
    LD HL, SFX_ScreenTransition
    CALL PlaySFX
    XOR A
    LD (PendingEraseCount), A   ; Cancelar erases pendientes (pantalla se borra)
    LD A, 1
    LD (ScreenDirty), A
    LD (ScreenJustRedrawn), A
.noSouth:
    RET

; ==============================================================================
; ClearNasties - Limpia todos los slots de nasties (enemigos destruibles)
; ==============================================================================
; Los nasties no persisten entre pantallas (como en Sabre Wulf).
; ==============================================================================
ClearNasties:
    LD HL, EntityTable + (SLOT_NASTY0 * ENT_SIZE)
    LD B, NUM_NASTIES
.clearLoop:
    PUSH BC
    PUSH HL
    LD (HL), 0                  ; ENT_SPRITEID = 0
    INC HL
    LD (HL), 0                  ; ENT_TYPE = 0 (inactivo)
    POP HL
    LD DE, ENT_SIZE
    ADD HL, DE
    POP BC
    DJNZ .clearLoop
    ; Reset spawn timer para nueva pantalla (delay antes de nasties)
    LD A, SPAWN_INTERVAL
    LD (SpawnTimer), A
    RET

; ==============================================================================
; DrawScreen - Dibuja la pantalla actual iterando BG sprites
; ==============================================================================
; Formato room: DEFW BgGfx_ptr : DEFB x_char, y_char ... DEFW $0000
; Formato BgGfx: DEFB height_px, width_bytes, pixel_data(CPL),
;                DEFB attr_h, attr_w, attr_data
; Solo se ejecuta cuando ScreenDirty=1 (cambio de pantalla).
; ==============================================================================
DrawScreen:
    LD A, (ScreenDirty)
    OR A
    RET Z

    ; --- Reset well detection ---
    XOR A
    LD (WellActive), A

    ; --- Limpiar pixeles ---
    LD HL, SCREEN_BASE
    LD DE, SCREEN_BASE + 1
    LD BC, 6143
    XOR A
    LD (HL), A
    LDIR

    ; --- Limpiar atributos: ink=WHITE, paper=BLACK ---
    LD HL, ATTR_BASE
    LD DE, ATTR_BASE + 1
    LD BC, ATTR_SIZE - 1
    LD A, $07
    LD (HL), A
    LDIR

    ; --- Iterar sprites del room ---
    LD HL, (CurrentScreenAddr)
.sprLoop:
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD A, D
    OR E
    JR Z, .drawDone

    LD B, (HL)                  ; B = x_char
    INC HL
    LD C, (HL)                  ; C = y_char
    INC HL
    PUSH HL                     ; Guardar puntero room data

    ; Comprobar si es sprite tipo "house" (para day cycle)
    CALL CheckIfHouseSprite

    ; Comprobar si es pozo: guardar posicion para recuperacion
    PUSH HL                     ; Preservar room data ptr (ya en stack via PUSH HL arriba)
    PUSH BC                     ; Preservar x_char, y_char
    LD HL, BgGfx_well_pozo
    OR A
    SBC HL, DE                  ; HL = 0 si coincide
    POP BC
    POP HL
    JR NZ, .notWell
    ; Es pozo: guardar posicion en pixeles
    LD A, B                     ; x_char
    ADD A, A                    ; *2
    ADD A, A                    ; *4
    ADD A, A                    ; *8
    LD (WellPosX), A
    LD A, C                     ; y_char
    ADD A, BG_Y_OFFSET          ; + offset HUD
    ADD A, A                    ; *2
    ADD A, A                    ; *4
    ADD A, A                    ; *8
    LD (WellPosY), A
    LD A, 1
    LD (WellActive), A
.notWell:

    ; DE = puntero a BgGfx sprite data
    PUSH DE
    POP IX                      ; IX = sprite data
    CALL DrawBgGfxSprite

    POP HL
    JR .sprLoop

.drawDone:
    ; --- Dibujar objetos per-cell desde ObjectTable ---
    LD HL, ObjectTable
.objDrawLoop:
    LD A, (HL)
    CP $FF
    JR Z, .objDrawDone
    LD B, A                     ; B = mapX
    INC HL
    LD C, (HL)                  ; C = mapY
    INC HL
    ; Comparar con pantalla actual
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .objDrawSkip
    LD A, (CurrentScreenY)
    CP C
    JR NZ, .objDrawSkip
    ; Coincide: leer sprite pointer y posicion
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx pointer
    INC HL
    LD B, (HL)                  ; B = charX
    INC HL
    LD C, (HL)                  ; C = charY
    INC HL
    PUSH HL
    ; Comprobar si es pozo
    PUSH DE
    PUSH BC
    LD HL, BgGfx_well_pozo
    OR A
    SBC HL, DE
    POP BC
    POP DE
    JR NZ, .objNotWell
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    LD (WellPosX), A
    LD A, C
    ADD A, BG_Y_OFFSET
    ADD A, A
    ADD A, A
    ADD A, A
    LD (WellPosY), A
    LD A, 1
    LD (WellActive), A
.objNotWell:
    ; No es house sprite (sin remap de color)
    XOR A
    LD (BgSpriteIsHouse), A
    PUSH DE
    POP IX
    CALL DrawBgGfxSprite
    POP HL
    JR .objDrawLoop
.objDrawSkip:
    INC HL                      ; skip DEFW ptr (2) + DEFB x (1) + DEFB y (1)
    INC HL
    INC HL
    INC HL
    JR .objDrawLoop
.objDrawDone:

    ; --- Dibujar pickups desde PickupTable (sin colision) ---
    LD HL, PickupTable
.pkDrawLoop:
    LD A, (HL)
    CP $FF
    JR Z, .pkDrawDone
    LD B, A                     ; B = mapX
    INC HL
    LD C, (HL)                  ; C = mapY
    INC HL
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .pkDrawSkip
    LD A, (CurrentScreenY)
    CP C
    JR NZ, .pkDrawSkip
    ; Coincide: leer sprite pointer y posicion
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx pointer
    INC HL
    LD B, (HL)                  ; B = charX
    INC HL
    LD C, (HL)                  ; C = charY
    INC HL
    PUSH HL
    XOR A
    LD (BgSpriteIsHouse), A
    PUSH DE
    POP IX
    CALL DrawBgGfxSprite
    POP HL
    JR .pkDrawLoop
.pkDrawSkip:
    INC HL
    INC HL
    INC HL
    INC HL
    JR .pkDrawLoop
.pkDrawDone:

    CALL BuildCollisionMap      ; Pre-computar mapa de colision para la nueva pantalla
    XOR A
    LD (ScreenDirty), A
    LD A, 1
    LD (ScreenJustRedrawn), A

    ; Marcar TODOS los enemigos como NEWSPAWN para que no hagan erase
    ; (round-robin: no todos se renderizan este frame)
    LD IX, EntityTable + SLOT_MONSTER0 * ENT_SIZE
    LD B, NUM_MONSTERS + NUM_NASTIES
.markFresh:
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .markSkip
    SET ENTF_NEWSPAWN, (IX+ENT_FLAGS)
.markSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    DJNZ .markFresh

    CALL DrawClockSprite        ; restaurar decoración del reloj tras borrado de pantalla
    CALL DrawTimeIndicator      ; HUD: momento del dia (col 30-31)
    CALL DrawRoomInfo           ; HUD: coordenadas y nombre de room (fila 23)
    ; Snapshot de atributos limpios (fondo sin sprites)
    JP SaveCleanAttrs           ; tail call

; ==============================================================================
; DrawBgGfxSprite - Dibuja un BG sprite con pixeles y atributos
; ==============================================================================
; Entrada: IX = datos del sprite, B = x_char, C = y_char
; Formato: DEFB height_px, width_bytes, pixel_data(CPL),
;          DEFB attr_h, attr_w, attr_data
; ==============================================================================
DrawBgGfxSprite:
    LD A, (IX+0)                ; height_px
    OR A
    RET Z                       ; sprite nulo (sin datos)
    LD (.heightCnt), A
    LD A, (IX+1)                ; width_bytes
    LD (.widthVal), A

    ; Aplicar offset HUD: desplazar sprites BG 2 filas hacia abajo
    LD A, C
    ADD A, BG_Y_OFFSET
    LD C, A

    ; Guardar posicion para la fase de atributos
    LD A, B
    LD (.xChar), A
    LD A, C
    LD (.yChar), A

    INC IX
    INC IX                      ; IX -> pixel data

    ; Calcular dir VRAM inicio: x_pixel = x_char*8, y_pixel = y_char*8
    LD A, C
    RLCA
    RLCA
    RLCA
    LD D, A                     ; D = y_pixel
    LD A, B
    RLCA
    RLCA
    RLCA
    LD E, A                     ; E = x_pixel
    CALL CalcPixelAddr          ; HL = dir VRAM

    ; --- Copiar pixel data (CPL para des-invertir) ---
.pixRow:
    LD A, (.widthVal)
    LD B, A
    PUSH HL                     ; guardar inicio de fila VRAM

.pixCol:
    LD A, (IX+0)
    CPL                         ; des-invertir (dato almacenado CPL'd)
    LD (HL), A
    INC IX
    INC HL
    DJNZ .pixCol

    POP HL                      ; restaurar inicio fila
    LD A, (.heightCnt)
    DEC A
    LD (.heightCnt), A
    JR Z, .pixDone
    CALL NextPixelLine          ; HL = siguiente linea pixel
    JR .pixRow

.pixDone:
    ; --- Pintar atributos ---
    LD A, (IX+0)                ; attr_h
    OR A
    RET Z
    LD E, A                     ; E = filas de atributos
    LD A, (IX+1)                ; attr_w
    LD D, A                     ; D = columnas de atributos
    INC IX
    INC IX                      ; IX -> attr data

    ; Calcular dir atributos: ATTR_BASE + y_char*32 + x_char
    LD A, (.yChar)
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = y_char * 32
    LD A, (.xChar)
    ADD A, L
    LD L, A
    JR NC, .noCarryA
    INC H
.noCarryA:
    LD BC, ATTR_BASE
    ADD HL, BC                  ; HL = dir atributo VRAM

.attrRow:
    LD B, D                     ; B = attr_w
    PUSH HL

.attrCol:
    LD A, (IX+0)
    CALL ApplyDayCycleRemap     ; Transformar attr segun momento del dia
    LD (HL), A
    INC IX
    INC HL
    DJNZ .attrCol

    POP HL
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC E
    JR NZ, .attrRow
    RET

; Variables locales DrawBgGfxSprite
.heightCnt: DEFB 0
.widthVal:  DEFB 0
.xChar:     DEFB 0
.yChar:     DEFB 0

; ==============================================================================
; RemapScreenAttrs - Remap rapido de atributos (sin redibujar pixeles)
; ==============================================================================
; Solo se ejecuta cuando AttrsDirty=1 (cambio de fase day/night).
; Itera BG sprites saltando pixel data, solo repinta attrs con nuevo remap.
; ==============================================================================
RemapScreenAttrs:
    LD A, (AttrsDirty)
    OR A
    RET Z

    XOR A
    LD (AttrsDirty), A

    ; --- Iterar sprites del room (solo attrs) ---
    LD HL, (CurrentScreenAddr)
.rsLoop:
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD A, D
    OR E
    JR Z, .rsDone

    LD B, (HL)                  ; B = x_char
    INC HL
    LD C, (HL)                  ; C = y_char
    INC HL
    PUSH HL

    CALL CheckIfHouseSprite

    PUSH DE
    POP IX                      ; IX = sprite data
    CALL RemapBgAttrsOnly

    POP HL
    JR .rsLoop

.rsDone:
    CALL DrawClockSprite
    CALL DrawTimeIndicator
    ; Snapshot de atributos limpios tras remap
    JP SaveCleanAttrs           ; tail call

; ==============================================================================
; SaveCleanAttrs - Copia ATTR_BASE → CleanAttrMap (768 bytes)
; ==============================================================================
; Llamado tras DrawScreen y RemapScreenAttrs.
; ==============================================================================
SaveCleanAttrs:
    LD HL, ATTR_BASE
    LD DE, CleanAttrMap
    LD BC, ATTR_SIZE
    LDIR
    RET

; ==============================================================================
; RestoreOldAttr - Restaura atributos del fondo en posicion vieja del sprite
; ==============================================================================
; D = pixelY viejo, E = pixelX viejo. Restaura 3x3 celdas desde CleanAttrMap.
; ==============================================================================
RestoreOldAttr:
    ; Calcular offset en attr map: (Y/8)*32 + (X/8)
    LD A, D
    RRCA
    RRCA
    RRCA
    AND $1F                             ; charY
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; HL = charY * 32
    LD A, E
    RRCA
    RRCA
    RRCA
    AND $1F                             ; charX
    LD E, A
    LD D, 0
    ADD HL, DE                          ; HL = offset en attr map
    ; DE = destino en ATTR_BASE, BC fuente en CleanAttrMap
    PUSH HL
    LD DE, ATTR_BASE
    ADD HL, DE
    EX DE, HL                           ; DE = ATTR_BASE + offset (destino)
    POP HL
    LD BC, CleanAttrMap
    ADD HL, BC                          ; HL = CleanAttrMap + offset (fuente)
    ; Copiar 3 celdas × 3 filas
    LD B, 3
.roaRow:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    LD A, (HL)
    LD (DE), A
    ; Siguiente fila: avanzar 30 posiciones (32 - 2 ya avanzadas)
    PUSH BC
    LD BC, 30
    ADD HL, BC
    EX DE, HL
    ADD HL, BC
    EX DE, HL
    POP BC
    DJNZ .roaRow
    RET

; ==============================================================================
; RemapBgAttrsOnly - Salta pixel data de un BG sprite, solo repinta attrs
; ==============================================================================
; Entrada: IX = datos del sprite, B = x_char, C = y_char
; ==============================================================================
RemapBgAttrsOnly:
    LD A, (IX+0)                ; height_px
    OR A
    RET Z
    LD D, A                     ; D = height_px
    LD A, (IX+1)                ; width_bytes
    LD E, A                     ; E = width_bytes

    ; Aplicar offset HUD
    LD A, C
    ADD A, BG_Y_OFFSET
    LD C, A

    ; Saltar cabecera + pixel data: 2 + height_px * width_bytes
    ; Calcular offset = D * E
    PUSH BC
    LD A, D                     ; height_px
    LD B, E                     ; width_bytes
    LD HL, 0
.mulLoop:
    LD D, 0
    LD E, A                     ; DE = height_px
    ADD HL, DE
    DJNZ .mulLoop
    ; HL = height_px * width_bytes
    PUSH IX
    POP DE                      ; DE = sprite base
    ADD HL, DE
    INC HL
    INC HL                      ; saltar cabecera (2 bytes)
    PUSH HL
    POP IX                      ; IX = inicio de attr data
    POP BC                      ; B = x_char, C = y_char

    ; Leer attr_h, attr_w
    LD A, (IX+0)                ; attr_h
    OR A
    RET Z
    LD E, A                     ; E = attr_h (filas)
    LD A, (IX+1)                ; attr_w
    LD D, A                     ; D = attr_w (cols)
    INC IX
    INC IX                      ; IX -> attr data

    ; Calcular dir atributos: ATTR_BASE + y_char*32 + x_char
    LD A, C
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = y_char * 32
    LD A, B
    ADD A, L
    LD L, A
    JR NC, .noCarry
    INC H
.noCarry:
    LD BC, ATTR_BASE
    ADD HL, BC                  ; HL = dir atributo VRAM

.raRow:
    LD B, D                     ; B = attr_w
    PUSH HL

.raCol:
    LD A, (IX+0)
    CALL ApplyDayCycleRemap
    LD (HL), A
    INC IX
    INC HL
    DJNZ .raCol

    POP HL
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC E
    JR NZ, .raRow
    RET

; ==============================================================================
; BuildCollisionMap - Construye mapa de colision desde los sprites del room
; ==============================================================================
; Llamado una vez al cargar cada pantalla (desde DrawScreen).
; Itera la lista de BG sprites y marca su footprint en CollisionMap.
; Todos los BG sprites se tratan como solidos.
; ==============================================================================
BuildCollisionMap:
    ; Limpiar mapa a 0 (todo libre)
    LD HL, CollisionMap
    LD DE, CollisionMap + 1
    LD BC, 32 * 22 - 1
    XOR A
    LD (HL), A
    LDIR

    ; Iterar sprites del room
    LD HL, (CurrentScreenAddr)
.bcmLoop:
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD A, D
    OR E
    JR Z, .bcmRoomDone          ; Terminador $0000 → pasar a ObjectTable

    LD B, (HL)                  ; B = x_char
    INC HL
    LD C, (HL)                  ; C = y_char
    INC HL
    PUSH HL                     ; Guardar puntero room data

    ; Leer dimensiones del sprite
    EX DE, HL
    LD A, (HL)                  ; height_px
    OR A
    JR Z, .bcmNullSpr
    RRCA
    RRCA
    RRCA
    AND $1F                     ; A = height_chars
    LD D, A                     ; D = height_chars
    INC HL
    LD E, (HL)                  ; E = width_chars (= width_bytes)

    ; Marcar rectangulo en CollisionMap
    ; B=x_char, C=y_char, D=height, E=width
    CALL .markRect

.bcmNullSpr:
    POP HL
    JR .bcmLoop

    ; --- Marcar objetos per-cell desde ObjectTable ---
.bcmRoomDone:
    LD HL, ObjectTable
.objColLoop:
    LD A, (HL)
    CP $FF
    RET Z
    LD B, A                     ; B = mapX
    INC HL
    LD C, (HL)                  ; C = mapY
    INC HL
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .objColSkip
    LD A, (CurrentScreenY)
    CP C
    JR NZ, .objColSkip
    ; Coincide: leer sprite y marcar colision
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx pointer
    INC HL
    LD B, (HL)                  ; B = charX
    INC HL
    LD C, (HL)                  ; C = charY
    INC HL
    PUSH HL
    EX DE, HL                   ; HL = BgGfx pointer
    LD A, (HL)                  ; height_px
    RRCA
    RRCA
    RRCA
    AND $1F
    LD D, A                     ; D = height_chars
    INC HL
    LD E, (HL)                  ; E = width_chars
    CALL .markRect
    POP HL
    JR .objColLoop
.objColSkip:
    INC HL
    INC HL
    INC HL
    INC HL
    JR .objColLoop

; --- Marca un rectangulo en el CollisionMap ---
; B=x_char, C=y_char, D=height (filas), E=width (cols)
.markRect:
    ; Calcular HL = CollisionMap + C*32 + B
    LD A, C
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = y_char * 32
    LD A, B
    ADD A, L
    LD L, A
    JR NC, .mrNoCarry
    INC H
.mrNoCarry:
    LD BC, CollisionMap
    ADD HL, BC                  ; HL = &CollisionMap[y*32 + x]

.mrRowLoop:
    PUSH HL
    LD B, E                     ; B = width
.mrColLoop:
    LD (HL), 1
    INC HL
    DJNZ .mrColLoop
    POP HL
    ; Siguiente fila: HL += 32
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC D
    JR NZ, .mrRowLoop
    RET

; ==============================================================================
; IsPointBlocked - Lookup rapido en CollisionMap (O(1))
; ==============================================================================
; Entrada: B = X pixel, C = Y pixel
; Salida: Z = libre, NZ = bloqueado
; Preserva: BC, DE
; ==============================================================================
IsPointBlocked:
    PUSH DE
    ; charX = X_pixel / 8
    LD A, B
    RRCA
    RRCA
    RRCA
    AND $1F
    LD E, A                     ; E = charX
    ; charY = Y_pixel / 8 - BG_Y_OFFSET
    LD A, C
    RRCA
    RRCA
    RRCA
    AND $1F
    SUB BG_Y_OFFSET
    ; Bounds check (charY debe estar en 0..21)
    CP 22
    JR NC, .ipFree
    ; HL = CollisionMap + charY*32 + charX
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = charY * 32
    LD D, 0
    ADD HL, DE                  ; + charX
    LD DE, CollisionMap
    ADD HL, DE
    LD A, (HL)
    OR A                        ; Z=libre, NZ=bloqueado
    POP DE
    RET
.ipFree:
    XOR A                       ; Z = libre
    POP DE
    RET

; ==============================================================================
; CheckPickupCollect - Comprobar si el jugador recoge un pickup
; ==============================================================================
; Recorre PickupTable. Si el jugador solapa con un pickup en la pantalla actual,
; borra el sprite (XOR redraw) y desactiva la entrada (mapX = $FE).
; Los pickups reaparecen al volver a la pantalla (DrawScreen los redibuja).
; ==============================================================================
CheckPickupCollect:
    LD HL, PickupTable
.cpLoop:
    LD A, (HL)
    CP $FF
    RET Z                       ; fin de tabla
    CP $FE
    JP Z, .cpSkipInactive       ; entrada desactivada (ya recogida)
    LD B, A                     ; B = mapX
    INC HL
    LD C, (HL)                  ; C = mapY
    INC HL
    ; Comprobar pantalla actual
    LD A, (CurrentScreenX)
    CP B
    JP NZ, .cpSkipEntry
    LD A, (CurrentScreenY)
    CP C
    JP NZ, .cpSkipEntry
    ; Pantalla correcta: leer sprite data
    ; HL apunta a DEFW BgGfx_ptr
    PUSH HL                     ; guardar puntero a entrada
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx ptr
    INC HL
    LD B, (HL)                  ; B = charX
    INC HL
    LD C, (HL)                  ; C = charY
    ; Calcular rect del pickup en pixeles
    ; px_left = charX * 8, px_top = (charY + BG_Y_OFFSET) * 8
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A                    ; A = px_left
    LD (.cpPkLeft+1), A        ; self-modify: store pickup left
    ; width from sprite data
    PUSH BC
    PUSH DE
    EX DE, HL                  ; HL = BgGfx ptr
    LD A, (HL)                 ; height_px
    LD (.cpPkH+1), A
    INC HL
    LD A, (HL)                 ; width_bytes
    ADD A, A
    ADD A, A
    ADD A, A                   ; width_px = width_bytes * 8
    LD (.cpPkW+1), A
    POP DE
    POP BC
    LD A, C
    ADD A, BG_Y_OFFSET
    ADD A, A
    ADD A, A
    ADD A, A                   ; A = px_top
    LD (.cpPkTop+1), A
    ; Player rect: 16x16 sprite at EntityTable pos
    LD A, (EntityTable + ENT_POSX)
    LD (.cpPlX+1), A
    LD A, (EntityTable + ENT_POSY)
    LD (.cpPlY+1), A
    ; AABB overlap test:
    ; player_right > pk_left AND player_left < pk_right
    ; player_bottom > pk_top AND player_top < pk_bottom
.cpPlX:
    LD A, 0                     ; player_left (self-mod)
    ADD A, 16                   ; player_right = left + 16
.cpPkLeft:
    LD B, 0                     ; pickup_left (self-mod)
    CP B
    JR C, .cpNoHit              ; player_right <= pk_left
    JR Z, .cpNoHit
    ; player_left < pk_right?
.cpPkW:
    LD A, 0                     ; pk_width (self-mod)
    ADD A, B                    ; A = pk_right = pk_left + pk_width
    LD B, A                     ; B = pk_right
.cpPlX2:
    LD A, (.cpPlX+1)            ; player_left (re-read)
    CP B
    JR NC, .cpNoHit             ; player_left >= pk_right
    ; vertical check
.cpPlY:
    LD A, 0                     ; player_top (self-mod)
    ADD A, 16                   ; player_bottom
.cpPkTop:
    LD B, 0                     ; pickup_top (self-mod)
    CP B
    JR C, .cpNoHit
    JR Z, .cpNoHit
.cpPkH:
    LD A, 0                     ; pk_height (self-mod)
    ADD A, B                    ; pk_bottom = pk_top + pk_height
    LD B, A
    LD A, (.cpPlY+1)            ; player_top
    CP B
    JR NC, .cpNoHit
    ; --- HIT: player overlaps pickup ---
    POP HL                      ; recover entry pointer (DEFW BgGfx_ptr)
    PUSH HL
    ; Guardar datos para borrado diferido (siguiente frame)
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx ptr
    INC HL
    LD A, (HL)                  ; charX
    LD (PendingPickupCX), A
    INC HL
    LD A, (HL)                  ; charY
    LD (PendingPickupCY), A
    ; Leer dimensiones del sprite
    EX DE, HL
    LD A, (HL)                  ; height_px
    RRCA : RRCA : RRCA
    AND $1F
    LD (PendingPickupH), A
    INC HL
    LD A, (HL)
    LD (PendingPickupW), A
    LD A, 1
    LD (PendingPickupErase), A  ; marcar borrado pendiente
    ; Desactivar entrada
    POP HL                      ; entry pointer (DEFW pos)
    DEC HL
    DEC HL                      ; apuntar a mapX
    LD (HL), $FE                ; desactivar
    ; Avanzar al siguiente entry: +6 desde mapX
    LD DE, 6
    ADD HL, DE
    JP .cpLoop
.cpNoHit:
    POP HL                      ; recover entry pointer
    ; Avanzar 4 bytes (ptr+x+y) para llegar al siguiente entry
    INC HL
    INC HL
    INC HL
    INC HL
    JP .cpLoop
.cpSkipEntry:
    ; Ya leimos mapX,mapY (2 bytes), skip 4 mas (ptr+x+y)
    INC HL
    INC HL
    INC HL
    INC HL
    JP .cpLoop
.cpSkipInactive:
    ; Entrada desactivada: skip 5 bytes (mapY + ptr + x + y)
    LD DE, 5
    ADD HL, DE
    JP .cpLoop

; ==============================================================================
; ErasePickupArea - Borra un rectangulo de pixeles y atributos
; ==============================================================================
; Entrada: B=charX, C=charY, D=height_chars, E=width_chars
; Borra los pixeles a 0 y los atributos a $07 (ink white, paper black)
; ==============================================================================
; ==============================================================================
; DoPendingPickupErase - Ejecuta borrado diferido de pickup
; ==============================================================================
; Llamar DESPUES de que el player haya sido borrado (XOR erase) y ANTES de
; que se dibuje de nuevo en su nueva posicion.
; ==============================================================================
DoPendingPickupErase:
    LD A, (PendingPickupErase)
    OR A
    RET Z                       ; nada pendiente
    XOR A
    LD (PendingPickupErase), A  ; limpiar flag
    LD A, (PendingPickupCX)
    LD B, A
    LD A, (PendingPickupCY)
    LD C, A
    LD A, (PendingPickupH)
    LD D, A
    LD A, (PendingPickupW)
    LD E, A
    ; fall through a ErasePickupArea

ErasePickupArea:
    ; Entrada: B=charX, C=charY, D=height_chars, E=width_chars
    ; Borra pixeles a 0 (fondo negro)
    PUSH BC                     ; guardar charX, charY originales
    PUSH DE                     ; guardar dims
    ; Aplicar offset HUD
    LD A, C
    ADD A, BG_Y_OFFSET
    LD C, A
    ; --- Borrar pixeles ---
    LD A, C
    RLCA : RLCA : RLCA
    LD D, A
    LD A, B
    RLCA : RLCA : RLCA
    LD E, A
    CALL CalcPixelAddr          ; HL = dir VRAM
    POP DE                      ; D=height_chars, E=width_chars
    PUSH DE                     ; re-guardar dims para atributos
    LD A, D
    RLCA : RLCA : RLCA          ; D = total pixel lines
    LD D, A
.epaPixRow:
    PUSH HL
    LD B, E
.epaPixCol:
    LD (HL), 0
    INC HL
    DJNZ .epaPixCol
    POP HL
    CALL NextPixelLine
    DEC D
    JR NZ, .epaPixRow
    ; --- Borrar atributos ---
    POP DE                      ; D=height_chars, E=width_chars
    POP BC                      ; B=charX, C=charY originales
    LD A, C
    ADD A, BG_Y_OFFSET
    LD L, A
    LD H, 0
    ADD HL, HL : ADD HL, HL : ADD HL, HL : ADD HL, HL : ADD HL, HL  ; HL = (charY+offset)*32
    LD A, B
    ADD A, L
    LD L, A
    JR NC, .epaNoCarry
    INC H
.epaNoCarry:
    LD BC, ATTR_BASE
    ADD HL, BC                  ; HL = dir atributo
.epaAttrRow:
    PUSH HL
    LD B, E
.epaAttrCol:
    LD (HL), 0                  ; negro total
    INC HL
    DJNZ .epaAttrCol
    POP HL
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC D
    JR NZ, .epaAttrRow
    RET
