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
    LD A, 1
    LD (ScreenDirty), A
    LD (ScreenJustRedrawn), A
.noSouth:
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
    XOR A
    LD (ScreenDirty), A
    LD A, 1
    LD (ScreenJustRedrawn), A
    CALL DrawClockSprite        ; restaurar decoración del reloj tras borrado de pantalla
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
; IsPointBlocked - Comprueba si un punto pixel esta bloqueado por un sprite solido
; ==============================================================================
; Estilo Sabre Wulf (rutina B873): itera la lista de sprites del room,
; comprueba si el punto cae dentro del bounding box de algun sprite solido.
;
; Entrada: B = X pixel, C = Y pixel
; Salida: Z = libre, NZ = bloqueado
; Preserva: BC (punto), DE (para el caller)
; ==============================================================================
IsPointBlocked:
    PUSH DE
    ; Pre-computar coordenadas char del punto UNA SOLA VEZ (no dentro del bucle)
    LD A, B
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (.ptCharX), A
    LD A, C
    RRCA
    RRCA
    RRCA
    AND $1F
    SUB BG_Y_OFFSET             ; ajustar por offset HUD (sprites BG dibujados 2 filas abajo)
    LD (.ptCharY), A

    LD HL, (CurrentScreenAddr)
.loop:
    ; Leer DEFW sprite_ptr
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    ; Terminador?
    LD A, D
    OR E
    JR Z, .free
    ; Leer sprX en B, sprY en C directamente desde la lista
    LD B, (HL)
    INC HL
    LD C, (HL)
    INC HL
    PUSH HL                     ; Guardar puntero a siguiente entrada
    ; Leer definicion del sprite: nuevo formato BG (height_px, width_bytes)
    EX DE, HL
    LD A, (HL)                  ; A = height_px
    OR A
    JR Z, .nullSpr              ; sprite nulo (sin datos), saltar
    RRCA
    RRCA
    RRCA
    AND $1F                     ; A = height_px / 8 = height_chars
    LD E, A                     ; E = height_chars
    INC HL
    LD D, (HL)                  ; D = width_bytes (= width_chars)
    POP HL                      ; restaurar puntero room

    ; Todos los BG sprites son solidos (no hay flags en nuevo formato)

    ; === Comprobar X: ptCharX en [B, B+D) ===
    LD A, (.ptCharX)
    SUB B                       ; A = ptCharX - sprX
    JR C, .loop                 ; fuera por la izquierda
    CP D                        ; comparar offset con width
    JR NC, .loop                ; fuera por la derecha (offset >= width)

    ; === Comprobar Y: ptCharY en [C, C+E) ===
    LD A, (.ptCharY)
    SUB C                       ; A = ptCharY - sprY
    JR C, .loop                 ; fuera por arriba
    CP E                        ; comparar offset con height
    JR NC, .loop                ; fuera por abajo

    ; Punto dentro de sprite solido!
    LD A, 1
    OR A                        ; NZ = bloqueado
    POP DE
    RET

.nullSpr:
    POP HL                      ; restaurar puntero room para sprites nulos
    JR .loop

.free:
    XOR A                       ; Z = libre
    POP DE
    RET

; Variables temporales para IsPointBlocked
.ptCharX: DEFB 0
.ptCharY: DEFB 0
