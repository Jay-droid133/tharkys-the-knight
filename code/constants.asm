; ==============================================================================
; CONSTANTES DEL SISTEMA Y JUEGO
; ==============================================================================

; --- Direcciones de Memoria ---
ORIGIN_ADDRESS  EQU 32768           ; $8000 - Inicio de nuestro juego en RAM
SP_ADDRESS      EQU 65368           ; $FF58 - Tope seguro para la pila (Stack)

; --- Mapa de Video ---
SCREEN_BASE     EQU 16384           ; $4000 - Inicio de los píxeles
ATTR_BASE       EQU 22528           ; $5800 - Inicio de los atributos (colores)
ATTR_SIZE       EQU 768             ; Tamaño de la zona de atributos

; --- Colores Básicos (Tinta) ---
BLACK           EQU 0
BLUE            EQU 1
RED             EQU 2
MAGENTA         EQU 3
GREEN           EQU 4
CYAN            EQU 5
YELLOW          EQU 6
WHITE           EQU 7

; --- Rutinas de la ROM ---
ROM_CLS         EQU $0DAF           ; Limpiar pantalla
ROM_CHAN_OPEN   EQU $1601           ; Abrir canal (pantalla principal)
ROM_PRINT       EQU $203C           ; Imprimir carácter

; --- Movimiento estilo Sabre Wulf (velocidades 16-bit) ---
; Byte alto = pixeles, Byte bajo = subpixel (fraccion)
; Sabre Wulf usa $02A0 en X y $0230 en Y para correr
; Y velocidades menores para pelear: $0230 X, $01C0 Y
SPEED_RUN_X     EQU $02A0           ; Velocidad X corriendo (~2.625 px/frame)
SPEED_RUN_Y     EQU $0230           ; Velocidad Y corriendo (~2.1875 px/frame)
SPEED_FIGHT_X   EQU $0230           ; Velocidad X peleando
SPEED_FIGHT_Y   EQU $01C0           ; Velocidad Y peleando

; --- Limites de pantalla (en pixeles, considerando sprite 16x16) ---
SCREEN_MIN_X    EQU 0               ; Limite izquierdo
SCREEN_MAX_X    EQU 240             ; Limite derecho (256 - 16 sprite width)
SCREEN_MIN_Y    EQU 0               ; Limite superior
SCREEN_MAX_Y    EQU 160             ; Limite inferior (176 area juego - 16 sprite height)

; --- Animacion (delays en frames de pantalla) ---
ANIM_DELAY_RUN  EQU 4               ; Frames entre cambios de anim corriendo (12.5fps)
ANIM_DELAY_IDLE EQU 8               ; Frames entre cambios de anim idle (6.25fps)

; --- Numero de frames de animacion por estado ---
; Sabre Wulf real: Walk E/W=4, Walk N/S=4, Fight=6, Idle=2
ANIM_FRAMES_WALK    EQU 3           ; Frames caminando (simplificado de 4)
ANIM_FRAMES_FIGHT   EQU 2           ; Frames peleando (simplificado de 6)
ANIM_FRAMES_IDLE    EQU 2           ; Frames idle

; --- Direcciones del jugador ---
DIR_NONE        EQU 0
DIR_N           EQU 1
DIR_S           EQU 2
DIR_E           EQU 4
DIR_W           EQU 8
DIR_NE          EQU 5               ; DIR_N | DIR_E
DIR_NW          EQU 9               ; DIR_N | DIR_W
DIR_SE          EQU 6               ; DIR_S | DIR_E
DIR_SW          EQU 10              ; DIR_S | DIR_W

; --- Estados del jugador ---
STATE_IDLE      EQU 0
STATE_RUNNING   EQU 1
STATE_FIGHTING  EQU 2

; --- Puertos de teclado (semi-filas del ZX Spectrum) ---
KEY_ROW_QAOP_P  EQU $DFFE           ; Fila P,O,I,U,Y  (bit0=P)
KEY_ROW_QAOP_O  EQU $DFFE           ; Fila P,O,I,U,Y  (bit1=O)
KEY_ROW_QAOP_Q  EQU $FBFE           ; Fila Q,W,E,R,T  (bit0=Q)
KEY_ROW_QAOP_A  EQU $FDFE           ; Fila A,S,D,F,G  (bit0=A)
KEY_ROW_SPACE   EQU $7FFE           ; Fila SPACE,SS,M,N,B (bit0=SPACE)

; ==============================================================================
; SISTEMA DE PANTALLAS (estilo Sabre Wulf)
; ==============================================================================
; Sabre Wulf: mapa de 256 pantallas en grid 16x16.
; Cada pantalla es una vista fija (flick-screen).
; Al tocar el borde, se transiciona a la pantalla adyacente.
;
; Cada pantalla se define como una rejilla de tiles de 8x8 pixeles.
; Area de juego: 256x176 pixeles = 32x22 caracteres.
; (Las 2 filas inferiores = HUD/panel de estado)
; ==============================================================================

; --- Dimensiones del mapa ---
MAP_WIDTH       EQU 16              ; Ancho del mapa en pantallas
MAP_HEIGHT      EQU 16              ; Alto del mapa en pantallas
MAP_TOTAL       EQU 256             ; Total de pantallas (16x16)

; --- Dimensiones de cada pantalla (en tiles de 8x8) ---
SCR_TILE_W      EQU 32              ; Tiles de ancho por pantalla
SCR_TILE_H      EQU 22              ; Tiles de alto (22 filas = 176px area de juego)
SCR_TILES_TOTAL EQU 704             ; 32 * 22 = tiles por pantalla

; --- Dimensiones del area de juego (en pixeles) ---
PLAY_AREA_W     EQU 256             ; Ancho en pixeles
PLAY_AREA_H     EQU 176             ; Alto en pixeles (22 filas de 8px)
HUD_Y_START     EQU 176             ; Pixel Y donde empieza el HUD (filas 22-23)

; --- Tipos de tile ---
; Cada tile tiene un ID de 0-255 que referencia su grafico
TILE_EMPTY      EQU 0               ; Suelo transitable (vacio)
TILE_WALL       EQU 1               ; Muro solido (no transitable)
TILE_BUSH_TL    EQU 2               ; Arbusto esquina sup-izq
TILE_BUSH_TR    EQU 3               ; Arbusto esquina sup-der
TILE_BUSH_BL    EQU 4               ; Arbusto esquina inf-izq
TILE_BUSH_BR    EQU 5               ; Arbusto esquina inf-der
TILE_PLANT_1    EQU 6               ; Planta decorativa 1
TILE_PLANT_2    EQU 7               ; Planta decorativa 2
TILE_PATH_H     EQU 8               ; Camino horizontal
TILE_PATH_V     EQU 9               ; Camino vertical
TILE_DOOR       EQU 10              ; Puerta/pasaje entre pantallas
; Tiles 11-255 reservados para mas vegetacion, objetos, etc.

; --- Flags de tile (propiedades en la tabla de colision) ---
TFLAG_WALK      EQU 0               ; Se puede caminar (bit 0)
TFLAG_SOLID     EQU 1               ; Solido/bloqueante (bit 1)
TFLAG_DAMAGE    EQU 2               ; Hace danyo al contacto (bit 2)
TFLAG_COLLECT   EQU 4               ; Coleccionable (bit 3)

; --- Posicion inicial del jugador en el mapa ---
START_SCREEN_X  EQU 8               ; Pantalla inicial X (centro del mapa)
START_SCREEN_Y  EQU 8               ; Pantalla inicial Y
START_PLAYER_X  EQU 120             ; Pixel X inicial dentro de la pantalla
START_PLAYER_Y  EQU 88              ; Pixel Y inicial dentro de la pantalla

; --- Zona de transicion (pixeles desde el borde que activan cambio) ---
TRANSITION_ZONE EQU 4               ; Pixeles de margen para activar transicion
