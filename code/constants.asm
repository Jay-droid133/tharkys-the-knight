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

; --- Movimiento estilo Sabre Wulf (8-bit, sin subpixel) ---
; --- Movimiento estilo Sabre Wulf ---
; Fiel al original: 4px cada 2 frames (turns_per_player_move=2).
; PlayerMoveTimer controla cuándo se aplica el movimiento.
SPEED_RUN           EQU 2           ; 2 px por movimiento (cada frame = 2px/frame, fiel al original)
SPEED_FIGHT         EQU 1           ; 1 px por movimiento peleando (mas lento)
PLAYER_MOVE_TURNS   EQU 1           ; Mover cada frame (granularidad fina para colision char-based)

; --- Limites de pantalla (en pixeles) ---
; Los limites maximos asumen sprite 16px ancho, ~16px alto.
; Para sprites mas grandes, el clamp real se ajusta en runtime.
; HUD en filas 0-1 (16px superiores); area de juego en filas 2-23.
SCREEN_MIN_X    EQU 0               ; Limite izquierdo
SCREEN_MAX_X    EQU 232             ; Limite derecho (con margen para shift: 256 - 16 - 8)
SCREEN_MIN_Y    EQU 16              ; Limite superior (debajo del HUD: 2 filas x 8px)
SCREEN_MAX_Y    EQU 171             ; Limite inferior (16 + 176 - 21)
BG_Y_OFFSET     EQU 2              ; Offset (char-rows) aplicado al dibujar/colisionar sprites BG

; --- Animacion (delays en frames de pantalla) ---
ANIM_DELAY_RUN  EQU 4               ; Frames entre cambios de anim corriendo
ANIM_DELAY_IDLE EQU 20               ; Frames entre cambios de anim idle
ANIM_DELAY_FIGHT EQU 3              ; Frames entre cambios de anim peleando
ANIM_DELAY_PUFF EQU 3               ; Frames entre cambios de anim puff (muerte)
ANIM_DELAY_SPAWN EQU 3              ; Frames entre cambios de anim spawn (aparicion)

; --- Numero de frames de animacion por estado ---
ANIM_FRAMES_WALK    EQU 3           ; Frames caminando por direccion
ANIM_FRAMES_FIGHT   EQU 5           ; Frames peleando por direccion
ANIM_FRAMES_IDLE    EQU 2           ; Frames idle
ANIM_FRAMES_PUFF    EQU 6           ; Frames de la animacion puff (muerte)
ANIM_FRAMES_SPAWN   EQU 6           ; Frames de la animacion spawn (aparicion)

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

; --- Estados del jugador/entidad ---
STATE_IDLE      EQU 0
STATE_RUNNING   EQU 1
STATE_FIGHTING  EQU 2
STATE_DYING     EQU 3               ; Animacion de muerte (puff)
STATE_SPAWNING  EQU 4               ; Animacion de aparicion (spawn)

; ==============================================================================
; SISTEMA DE ENTIDADES (estilo Sabre Wulf)
; ==============================================================================
; Estructura de 12 bytes por entidad, universal para player/enemigos/objetos.
; Acceso via IX + ENT_* offset.
; ==============================================================================

; --- Offsets en la estructura de entidad (16 bytes) ---
ENT_SPRITEID    EQU 0               ; Frame actual (indice en SpriteFrameTable)
ENT_TYPE        EQU 1               ; Tipo de entidad
ENT_STATE       EQU 2               ; Estado (idle/run/fight/dead)
ENT_POSX        EQU 3               ; Pixel X en pantalla (8-bit)
ENT_POSY        EQU 4               ; Pixel Y en pantalla (8-bit)
ENT_ATTR        EQU 5               ; Color/atributo ZX Spectrum
ENT_DELTAX      EQU 6               ; Velocidad X (signed byte)
ENT_DELTAY      EQU 7               ; Velocidad Y (signed byte)
ENT_ANIMBASE    EQU 8               ; SpriteID del primer frame de la anim
ENT_ANIMTIMER   EQU 9               ; Countdown para cambiar frame
ENT_DIR         EQU 10              ; bits 0-3: dir actual, bits 4-7: lastHDir
ENT_FLAGS       EQU 11              ; bit0: visible, bit1: solid, bit2: destructible
ENT_OLDX        EQU 12              ; X del frame anterior (para XOR erase)
ENT_OLDY        EQU 13              ; Y del frame anterior (para XOR erase)
ENT_OLDSPRID    EQU 14              ; SpriteID del frame anterior
ENT_DRAWX       EQU 15              ; X de dibujo (ajustado para attack offset)

ENT_SIZE        EQU 16              ; Bytes por entidad
NUM_ENTITIES    EQU 17              ; Total de slots

; --- Tipos de entidad ---
TYPE_NONE       EQU 0               ; Slot inactivo
TYPE_PLAYER     EQU 1               ; Jugador (Sabreman)
TYPE_IMMORTAL   EQU 2               ; Enemigo permanente (rhino, wolf, etc.)
TYPE_NASTY      EQU 3               ; Enemigo destruible (spawn aleatorio)
TYPE_OBJECT     EQU 4               ; Objeto coleccionable

; --- Flags de entidad (ENT_FLAGS) ---
ENTF_VISIBLE    EQU 0               ; bit 0: entidad visible
ENTF_SOLID      EQU 1               ; bit 1: entidad solida (colisiona)
ENTF_DESTRUCT   EQU 2               ; bit 2: destruible
ENTF_NEWSPAWN   EQU 3               ; bit 3: recien creada (usar freshDraw, no erase)

; --- Rangos de slots ---
SLOT_PLAYER     EQU 0               ; Slot 0: player
SLOT_IMMORTAL0  EQU 1               ; Slots 1-6: inmortales
NUM_IMMORTALS   EQU 6
SLOT_NASTY0     EQU 7               ; Slots 7-9: nasties (spawn)
NUM_NASTIES     EQU 3
SLOT_OBJECT0    EQU 13              ; Slots 13-16: objetos
NUM_OBJECTS     EQU 4

; --- Velocidades de enemigos ---
ENEMY_SPEED     EQU 2               ; Pixels por update (compensar round-robin)
ENEMY_ANIM_DELAY EQU 8              ; Frames entre cambio de frame

; --- Spawn system ---
SPAWN_INTERVAL  EQU 100             ; Frames entre intentos de spawn

; --- Round-robin (estilo Sabre Wulf) ---
MAX_ENEMIES_PER_FRAME EQU 2         ; Enemigos procesados por frame (erase+logic+draw combinados)

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
; (Las 2 filas superiores = HUD/panel de estado; area de juego filas 2-23)
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
HUD_Y_START     EQU 0               ; Pixel Y donde empieza el HUD (filas 0-1, superior)

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
; Tiles 10-255 reservados para mas vegetacion, objetos, etc.

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
