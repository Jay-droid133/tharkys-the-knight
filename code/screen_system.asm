; ==============================================================================
; SISTEMA DE PANTALLAS (estilo Sabre Wulf - flick-screen)
; ==============================================================================
; Sabre Wulf usa un mapa de 256 pantallas (16x16) con transicion instantanea.
; El jugador cambia de pantalla al tocar el borde.
; Cada pantalla es una rejilla de 32x22 tiles de 8x8 pixeles.
; ==============================================================================

; ==============================================================================
; InitScreenSystem - Inicializa el sistema de pantallas
; ==============================================================================
; Configura la pantalla inicial y marca para redibujar.
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
    CALL CalcScreenAddress      ; Calcular puntero a datos de pantalla
    RET

; ==============================================================================
; CalcScreenAddress - Calcula la direccion de datos de la pantalla actual
; ==============================================================================
; Entrada: CurrentScreenX, CurrentScreenY
; Salida: CurrentScreenAddr = puntero a los datos de la pantalla
;
; Indice = ScreenY * MAP_WIDTH + ScreenX
; Cada entrada en ScreenPointerTable es un DEFW (2 bytes)
; Direccion = ScreenPointerTable + indice * 2
; ==============================================================================
CalcScreenAddress:
    LD A, (CurrentScreenY)
    LD L, A
    LD H, 0
    ; Multiplicar por 16 (MAP_WIDTH)
    ADD HL, HL                  ; x2
    ADD HL, HL                  ; x4
    ADD HL, HL                  ; x8
    ADD HL, HL                  ; x16
    LD A, (CurrentScreenX)
    LD E, A
    LD D, 0
    ADD HL, DE                  ; HL = Y*16 + X = indice de pantalla
    ADD HL, HL                  ; HL = indice * 2 (tabla de DEFW)
    LD DE, ScreenPointerTable
    ADD HL, DE                  ; HL = direccion en tabla de punteros
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = puntero a datos de la pantalla
    LD (CurrentScreenAddr), DE
    RET

; ==============================================================================
; CheckScreenTransition - Detecta si el jugador debe cambiar de pantalla
; ==============================================================================
; Comprueba si la posicion del jugador esta en la zona de transicion
; de alguno de los 4 bordes. Si hay transicion, actualiza la pantalla
; y reposiciona al jugador en el borde opuesto.
; ==============================================================================
CheckScreenTransition:
    XOR A
    LD (ScreenTransition), A    ; Limpiar flag

    ; --- Comprobar borde OESTE (izquierdo) ---
    LD A, (PlayerXHi)
    CP TRANSITION_ZONE
    JR NC, .noWest
    ; Hay transicion hacia el Oeste?
    LD A, (CurrentScreenX)
    OR A
    JR Z, .noWest               ; Ya estamos en el borde del mapa
    DEC A
    LD (CurrentScreenX), A
    LD A, DIR_W
    LD (ScreenTransition), A
    ; Reposicionar jugador al borde derecho (sin re-triggear este)
    LD A, SCREEN_MAX_X - 8
    LD (PlayerXHi), A
    JR .doTransition

.noWest:
    ; --- Comprobar borde ESTE (derecho) ---
    LD A, (PlayerXHi)
    CP SCREEN_MAX_X
    JR C, .noEast
    LD A, (CurrentScreenX)
    CP MAP_WIDTH - 1
    JR Z, .noEast               ; Ya estamos en el borde del mapa
    INC A
    LD (CurrentScreenX), A
    LD A, DIR_E
    LD (ScreenTransition), A
    ; Reposicionar jugador al borde izquierdo
    LD A, TRANSITION_ZONE + 1
    LD (PlayerXHi), A
    JR .doTransition

.noEast:
    ; --- Comprobar borde NORTE (superior) ---
    LD A, (PlayerYHi)
    CP TRANSITION_ZONE
    JR NC, .noNorth
    LD A, (CurrentScreenY)
    OR A
    JR Z, .noNorth
    DEC A
    LD (CurrentScreenY), A
    LD A, DIR_N
    LD (ScreenTransition), A
    ; Reposicionar jugador al borde inferior (sin re-triggear sur)
    LD A, SCREEN_MAX_Y - 8
    LD (PlayerYHi), A
    JR .doTransition

.noNorth:
    ; --- Comprobar borde SUR (inferior) ---
    LD A, (PlayerYHi)
    CP SCREEN_MAX_Y
    JR C, .noSouth
    LD A, (CurrentScreenY)
    CP MAP_HEIGHT - 1
    JR Z, .noSouth
    INC A
    LD (CurrentScreenY), A
    LD A, DIR_S
    LD (ScreenTransition), A
    ; Reposicionar jugador al borde superior
    LD A, TRANSITION_ZONE + 1
    LD (PlayerYHi), A

.doTransition:
    ; Limpiar subpixel para evitar glitches de posicion
    XOR A
    LD (PlayerXLo), A
    LD (PlayerYLo), A
    ; Sincronizar posicion "old" del sprite para que no borre basura
    LD A, (PlayerXHi)
    LD (PlayerOldXHi), A
    LD A, (PlayerYHi)
    LD (PlayerOldYHi), A
    ; Recalcular puntero y marcar redibujado
    CALL CalcScreenAddress
    LD A, 1
    LD (ScreenDirty), A
.noSouth:
    RET

; ==============================================================================
; DrawScreen - Dibuja la pantalla actual
; ==============================================================================
; Dos fases:
;   1. Si ScreenDirty: limpiar pixeles (solo en transiciones de pantalla)
;   2. Siempre: repintar atributos de tiles (para que el jugador no los borre)
;
; Formato de pantalla: SCR_TILES_TOTAL bytes (32x22), cada byte = tile ID.
; ==============================================================================
DrawScreen:
    LD A, (ScreenDirty)
    OR A
    RET Z                       ; Nada que hacer si no hay cambio de pantalla

    ; --- Limpiar pixeles ---
    LD HL, SCREEN_BASE
    LD DE, SCREEN_BASE + 1
    LD BC, 6143                 ; 6144 bytes de pixeles - 1
    XOR A
    LD (HL), A
    LDIR

    ; --- Pintar atributos de todos los tiles ---
    LD HL, (CurrentScreenAddr)  ; HL = puntero a datos de la pantalla
    LD DE, ATTR_BASE            ; DE = inicio de atributos

    LD B, SCR_TILE_H            ; 22 filas
.rowLoop:
    PUSH BC
    LD B, SCR_TILE_W            ; 32 columnas
.colLoop:
    LD A, (HL)                  ; A = tile ID
    INC HL
    CALL GetTileAttr            ; A = atributo de color para este tile
    LD (DE), A
    INC DE
    DJNZ .colLoop

    POP BC
    DJNZ .rowLoop

    ; --- Limpiar zona de HUD (2 filas de atributos inferiores) ---
    ; DE ya apunta a ATTR_BASE + 22*32 = fila 22
    LD B, 64                    ; 2 filas * 32 columnas
    XOR A
.hudClear:
    LD (DE), A
    INC DE
    DJNZ .hudClear

    ; Marcar como limpio
    XOR A
    LD (ScreenDirty), A
    RET

; ==============================================================================
; GetTileAttr - Devuelve el atributo de color para un tipo de tile
; ==============================================================================
; Entrada: A = tile ID
; Salida: A = atributo ZX Spectrum (FBPPPIII)
; ==============================================================================
GetTileAttr:
    ; Usar tabla de lookup para convertir tile ID -> atributo
    PUSH HL
    PUSH DE
    LD L, A
    LD H, 0
    LD DE, TileAttrTable
    ADD HL, DE
    LD A, (HL)
    POP DE
    POP HL
    RET

; ==============================================================================
; Tabla de atributos por tile ID
; ==============================================================================
; Cada byte: bit7=flash, bit6=bright, bits5-3=paper, bits2-0=ink
; ==============================================================================
; Con pixeles a 0 solo se ve PAPER (bits 5-3). INK se ve donde pixel=1.
; Para tiles sin graficos de pixel, usamos PAPER = color deseado.
TileAttrTable:
    DEFB $00                    ; 0 = TILE_EMPTY  -> Paper negro (fondo negro)
    DEFB $49                    ; 1 = TILE_WALL   -> Paper azul bright (bloque azul solido)
    DEFB $20                    ; 2 = TILE_BUSH_TL-> Paper verde
    DEFB $20                    ; 3 = TILE_BUSH_TR-> Paper verde
    DEFB $20                    ; 4 = TILE_BUSH_BL-> Paper verde
    DEFB $20                    ; 5 = TILE_BUSH_BR-> Paper verde
    DEFB $60                    ; 6 = TILE_PLANT_1-> Paper verde bright
    DEFB $60                    ; 7 = TILE_PLANT_2-> Paper verde bright
    DEFB $00                    ; 8 = TILE_PATH_H -> Paper negro (camino = suelo)
    DEFB $00                    ; 9 = TILE_PATH_V -> Paper negro (camino = suelo)
    DEFB $70                    ; 10= TILE_DOOR   -> Paper amarillo bright (pasaje visible)
    ; Resto hasta 255 = negro
    DEFS 245, $00
