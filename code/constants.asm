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
;
; FRAMERATE FIJO 25FPS
; --------------------
; El MainLoop usa doble HALT (2 × 20ms = 40ms/frame = 25fps).
; Esto garantiza velocidad y animacion constantes independientemente
; de la carga de CPU (numero de enemigos en pantalla).
; Todas las constantes de timing estan calibradas para 25fps.
;
SPEED_RUN           EQU 4           ; 4 px por frame a 25fps = 100px/s
SPEED_FIGHT         EQU 2           ; 2 px por frame a 25fps = 50px/s
PLAYER_MOVE_TURNS   EQU 1           ; Mover cada frame (granularidad fina para colision char-based)

; --- Limites de pantalla (en pixeles) ---
; Los limites maximos asumen sprite 16px ancho, ~16px alto.
; Para sprites mas grandes, el clamp real se ajusta en runtime.
; HUD en filas 0-1 (16px superiores); area de juego en filas 2-23.
SCREEN_MIN_X    EQU 0               ; Limite izquierdo
SCREEN_MAX_X    EQU 232             ; Limite derecho (con margen para shift: 256 - 16 - 8)
SCREEN_MIN_Y    EQU 16              ; Limite superior (debajo del HUD: 2 filas x 8px)
SCREEN_MAX_Y    EQU 168             ; Limite inferior alineado a múltiplo de 8 (antes: 171)
BG_Y_OFFSET     EQU 2              ; Offset (char-rows) aplicado al dibujar/colisionar sprites BG

; --- Animacion (delays en frames de pantalla) ---
ANIM_DELAY_RUN  EQU 2               ; 2 frames a 25fps = 80ms (era 4 a 50fps)
ANIM_DELAY_IDLE EQU 10              ; 10 frames a 25fps = 400ms (era 20 a 50fps)
ANIM_DELAY_FIGHT EQU 1              ; 1 frame a 25fps = 40ms (era 2 a 50fps)
ANIM_DELAY_PUFF EQU 2               ; 2 frames a 25fps ~80ms (era 3 a 50fps ~60ms)
ANIM_DELAY_SPAWN EQU 2              ; 2 frames a 25fps ~80ms (era 3 a 50fps ~60ms)

; --- Numero de frames de animacion por estado ---
ANIM_FRAMES_WALK    EQU 3           ; Frames caminando por direccion
ANIM_FRAMES_FIGHT   EQU 5           ; Frames peleando por direccion
ANIM_FRAMES_IDLE    EQU 2           ; Frames idle
ANIM_FRAMES_PUFF    EQU 6           ; Frames de la animacion puff (muerte)
ANIM_FRAMES_SPAWN   EQU 6           ; Frames de la animacion spawn (aparicion)
ANIM_FRAMES_MONSTER EQU 3           ; Frames unicos de animacion de monstruo
MONSTER_BOUNCE_LEN  EQU 4           ; Slots bounce (0,1,2,1)

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
STATE_SCARED    EQU 5               ; Huida hacia borde (campanadas)
STATE_ATTACKING EQU 6               ; Nasty depredador lanzandose hacia el player

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
TYPE_MONSTER   EQU 2               ; Monstruo permanente (rhino, wolf, etc.)
TYPE_NASTY      EQU 3               ; Enemigo destruible (spawn aleatorio)
TYPE_OBJECT     EQU 4               ; Objeto coleccionable
TYPE_DEATH      EQU 5               ; La muerte: persigue al player tras 10s en sala

; --- Flags de entidad (ENT_FLAGS) ---
ENTF_VISIBLE    EQU 0               ; bit 0: entidad visible
ENTF_SOLID      EQU 1               ; bit 1: entidad solida (colisiona)
ENTF_DESTRUCT   EQU 2               ; bit 2: destruible
ENTF_NEWSPAWN   EQU 3               ; bit 3: recien creada (usar freshDraw, no erase)
ENTF_KB_DIRECT  EQU 4               ; bit 4: knockback directo del player (no billar)
                                    ;   Set al golpear con espada; clear al heredar
                                    ;   kb por colision billar. CheckChurchTrap solo
                                    ;   dispara la trampa si este bit esta set.

; --- Rangos de slots ---
SLOT_PLAYER     EQU 0               ; Slot 0: player
SLOT_MONSTER0  EQU 1               ; Slots 1-6: monstruos
NUM_MONSTERS   EQU 6
SLOT_NASTY0     EQU 7               ; Slots 7-10: nasties (spawn)
NUM_NASTIES     EQU 4
SLOT_DEATH      EQU 11              ; Slot 11: la muerte (entidad unica TYPE_DEATH)
SLOT_OBJECT0    EQU 13              ; Slots 13-16: objetos
NUM_OBJECTS     EQU 4

; --- Velocidades de enemigos ---
ENEMY_SPEED     EQU 2               ; Pixels por update (compensar round-robin)
MONSTER_SPEED    EQU 2               ; Pixels por update (efectivo ~1 px/frame con round-robin)
MONSTER_MAX_HITS EQU 5              ; Golpes directos para matar un monster
MONSTER_KB_SPEED EQU 4              ; Pixels por update durante knockback
MONSTER_RESPAWN_DELAY EQU 75        ; 75 frames a 25fps = 3s (era 150 a 50fps)
MONSTER_STUN_TOTAL EQU 12           ; 12 frames a 25fps ~0.5s (era 24 a 50fps)
MONSTER_STUN_PAUSE EQU 6            ; 6 frames a 25fps (era 12 a 50fps)
ENEMY_ANIM_DELAY EQU 4              ; 4 frames a 25fps = 160ms (era 8 a 50fps)
; PREDATOR_SPEED: se lee de PredatorSpeedTable segun DayCycleCount
; Tipos de depredador (bits 0-1 de PredatorTable)
PRED_NONE       EQU 0               ; No depredador (movimiento random)
PRED_FROM_ABOVE EQU 1               ; Se lanza desde arriba (Eagle, Bat)
PRED_FROM_BELOW EQU 2               ; Se lanza desde abajo (Snake, Scorpion)
PRED_HORIZONTAL EQU 3               ; Se lanza horizontalmente (Goat, RabidCat)
PRED_ALIGN_DIST EQU 12              ; Distancia de alineacion para activar ataque
PREDATOR_COOLDOWN EQU 25            ; 25 frames a 25fps = 1s (era 50 a 50fps)

; --- Stamina / Salud ---
STAMINA_MAX         EQU 16          ; Nivel maximo (= 16 scanlines del HUD)
HEALTH_MAX          EQU 16
STAMINA_DRAIN_RATE  EQU 13          ; 13 frames a 25fps ~0.5s (era 25 a 50fps)
STAMINA_REGEN_RATE  EQU 25          ; 25 frames a 25fps = 1s (era 50 a 50fps)
HEALTH_REGEN_RATE   EQU 50          ; 50 frames a 25fps = 2s (era 100 a 50fps)
STAMINA_THRESHOLD_HIGH EQU 12       ; >= libre (continuo)
STAMINA_THRESHOLD_MID  EQU 7        ; >= fixed swing
STAMINA_THRESHOLD_LOW  EQU 3        ; >= cooldown corto
; < LOW = cooldown largo + 1 punto recuperado tras cada cooldown
ATTACK_COOLDOWN_FRAMES EQU 10       ; 10 frames a 25fps = 0.4s (era 20 a 50fps)
ATTACK_SWING_FRAMES EQU ANIM_FRAMES_FIGHT * ANIM_DELAY_FIGHT ; Opcion C: = 1 ciclo de animacion
SCARE_FLEE_THRESHOLD EQU 50          ; 50 a 25fps (era 100 a 50fps)
SCARE_TIMER_BELLS EQU 125           ; 125 a 25fps = ~5s (era 250 a 50fps)
SCARE_TIMER_DAWN  EQU 125           ; 125 a 25fps = ~5s (era 250 a 50fps)
FLEE_PLAYER_AVOID EQU 12            ; Pixeles de proximidad para evitar al player al huir
NEAR_ENTRY_DIST EQU 30              ; Distancia minima monster-entrada al restaurar room

; --- Spawn system ---
SPAWN_INTERVAL  EQU 12              ; ~0.5s a 25fps (era 25 = 1s) — primer nasty post-transition
                                    ; (Gap entre spawns consecutivos = R AND 7 frames, 0-0.28s)

; --- La muerte (TYPE_DEATH, slot 11) ---
DEATH_SPAWN_FRAMES   EQU 125         ; DEBUG: 5s a 25fps (final: 250 = 10s). Pausa con TimeFrozen=1.
DEATH_SPEED          EQU 1           ; 1 px por update; acumulador 1/2 -> mueve cada 2 frames
DEATH_STUCK_THRESHOLD EQU 6          ; Frames sin movimiento -> activar BFS rescue
DEATH_BFS_MAX_DEPTH  EQU 3           ; Profundidad max del mini-BFS (diamond ~25 cells)

; --- Well cooldown tras curar (modo prueba; ajustar al gusto) ---
WELL_COOLDOWN_FRAMES  EQU 125        ; 5 s @ 25 fps
WELL_COOLDOWN_ATTR_L  EQU $78        ; Celda inferior-izq: BRIGHT + PAPER WHITE
WELL_COOLDOWN_ATTR_R  EQU $38        ; Celda inferior-der: PAPER WHITE (sin bright)

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

; --- Posicion inicial del jugador: definida en screen_data.asm (level editor) ---

; --- Zona de transicion (pixeles desde el borde que activan cambio) ---
TRANSITION_ZONE EQU 4               ; Pixeles de margen para activar transicion

; ==============================================================================
; MONSTER AI v2 (fase 2 — estructuras en RAM + bank 6)
; ==============================================================================
; Timings tuneables. Unidad: frames a 25fps.
MAI_LINGER_NORMAL   EQU 18          ; ~0.7s — migrar tras abandono sin push
MAI_LINGER_PUSHED   EQU 25          ; ~1s — vuelta tras knockback de espada
MAI_ENTRY_OFFSET    EQU 0           ; Spawn inicial: al borde mismo (Regla 1)
MAI_REENTRY_OFFSET  EQU 16          ; Reaparicion tras push: 2 chars dentro (Regla 4)
MAI_WAIT_OFFSET     EQU 40          ; Offset del migrado "esperando" desde entry gap (evita solape con player)

; Lados de un screen (coincide con ScreenGaps_*.asm y el campo EntryBorder)
MAI_SIDE_N          EQU 0
MAI_SIDE_S          EQU 1
MAI_SIDE_W          EQU 2
MAI_SIDE_E          EQU 3

; Flags por monster (campo MonsterAiFlags[slot], 1 byte)
MAI_FLAG_PUSHED     EQU %00000001   ; bit 0: empujado por espada (usar LINGER_PUSHED)
MAI_FLAG_LEAVING    EQU %00000010   ; bit 1: buscando hueco y saliendo (amanecer/muerte)
MAI_FLAG_REMOTE     EQU %00000100   ; bit 2: asentado en una room distinta al player
MAI_FLAG_SHAKE_SAVED EQU %00001000  ; bit 3: orig POSX/POSY guardados para shake del amanecer

; ScreenGaps: DEFB count, {side, coord} × count
MAI_GAP_REC_SIZE    EQU 2           ; bytes por entrada de gap

; RoomHistory: ventana de las ultimas 3 rooms distintas visitadas.
MAI_HISTORY_LEN     EQU 3

; Flow field: direcciones resueltas + intervalo de recomputacion
MAI_DIR_NONE        EQU $FF
MAI_DIR_N           EQU 0
MAI_DIR_S           EQU 1
MAI_DIR_W           EQU 2
MAI_DIR_E           EQU 3
MAI_FLOW_INTERVAL   EQU 10          ; frames entre recomputaciones de BFS
