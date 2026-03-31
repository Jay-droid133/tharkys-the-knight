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
    ; Reset spawn timer para nueva pantalla (1 = spawnear inmediato)
    LD A, 1
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

    ; DE = puntero a BgGfx sprite data
    PUSH DE
    POP IX                      ; IX = sprite data
    CALL DrawBgGfxSprite

    POP HL
    JR .sprLoop

.drawDone:
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
    RET

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
    RET Z                       ; Terminador $0000 → fin

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
