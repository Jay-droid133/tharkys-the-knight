; ==============================================================================
; CONSTANTES DEL SISTEMA Y JUEGO
; ==============================================================================

; --- Direcciones de Memoria ---
ORIGIN_ADDRESS  EQU 32768           ; $8000 - Inicio de nuestro juego en RAM
SP_ADDRESS      EQU 65368           ; $FF58 - Tope seguro para la pila (Stack)

; --- Plaza del reloj (referencia para sonido espacial de campanadas) ---
; NO confundir con START_SCREEN_X/Y (spawn del player, exportado por el editor).
; Vive aqui (no en screen_data.asm) porque ese archivo lo regenera el editor
; y se llevaria por delante estas EQUs.
PLAZA_SCREEN_X  EQU 8
PLAZA_SCREEN_Y  EQU 9

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
ANIM_DELAY_PUFF EQU 1               ; 1 frame a 25fps = 40ms (puff 24x24, 6f → 240ms total)
ANIM_DELAY_SPAWN EQU 1              ; 1 frame a 25fps = 40ms (spawn 24x24, 6f → 240ms total)

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
SLOT_NASTY0     EQU 7               ; Slots 7-9: nasties activos (slot 10 reservado, sin usar)
NUM_NASTIES     EQU 3
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

; --- DEBUG: deshabilita el spawn de TODOS los enemigos (nasties, monsters,
; muerte, monsters post-bells). Util para testing puro de mecanicas.
; Poner a 0 cuando termine el debug.
DEBUG_NO_ENEMIES    EQU 0

; DEBUG: forzar siempre compass al rolear random pickup. Pone a 0 para volver
; a la distribución normal. Usado para test rápido del power-up.
DEBUG_FORCE_COMPASS EQU 0

; DEBUG: forzar siempre mushroom al rolear random pickup. Pone a 0 para
; volver a la distribución normal. Util para probar el debuff (block fire
; + SFX de error). Si DEBUG_FORCE_COMPASS y DEBUG_FORCE_MUSHROOM estan
; ambos a 1, gana COMPASS (chequeado primero).
DEBUG_FORCE_MUSHROOM EQU 0

; DEBUG: forzar siempre roulette al rolear random pickup. Pone a 0 para
; volver a distribución normal. Util para probar el ciclado de RouletteOrder.
DEBUG_FORCE_ROULETTE EQU 0

; DEBUG: forzar roll a uno de los buffs/debuffs que cambian color (RAYO,
; CARACOL, MUSHROOM) al 33% cada uno. Util para probar el color cycler:
; recoges 1, vuelves a la sala, sale otro, y los ves cyclar a la vez.
; Pone a 0 para volver a distribución normal.
DEBUG_FORCE_COLOR_CHANGER EQU 0

; DEBUG: forzar roll a los nuevos buffs ESPADA / ESCUDO / ESCUDO_RAYO al
; 33% cada uno. Util para probar fase 3 (sin estar todavia en RouletteOrder
; ni en PROB_*_END). Pone a 0 para volver a distribución normal.
DEBUG_FORCE_NEW_BUFFS EQU 0

; DEBUG: forzar siempre REVERSE debuff. Util para probar fase 4.
; Pone a 0 para volver a distribución normal.
DEBUG_FORCE_REVERSE EQU 0

; --- Step-up / sidestep del player ---
; Rango de nudges (px) probados perpendicularmente al toparse con un obstaculo.
; Iterativo MIN..MAX. Por cada nivel se prueban ambas direcciones (UP/DOWN o
; LEFT/RIGHT) antes de avanzar al siguiente.
;   MIN=8: descarta lifts sub-char (1-7 px) que serian espurios al rozar
;     bordes de char en transiciones entre sprites adyacentes. Solo lifts
;     "reales" de >=1 char.
;   MAX=12: cubre alineamientos Y%8=4 que requieren 9-12 px para clarear
;     un obstaculo de 1 char.
MIN_STEP_LIFT       EQU 8
MAX_STEP_LIFT       EQU 12

; --- Stamina / Salud ---
STAMINA_MAX         EQU 16          ; Nivel maximo (= 16 scanlines del HUD)
HEALTH_MAX          EQU 16
STAMINA_DRAIN_RATE  EQU 13          ; 13 frames a 25fps ~0.5s (era 25 a 50fps)
STAMINA_REGEN_RATE  EQU 50          ; 50 frames a 25fps = 2s
HEALTH_REGEN_RATE   EQU 100         ; 100 frames a 25fps = 4s
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
DEATH_SPAWN_FRAMES   EQU 250         ; 10s a 25fps. Pausa con TimeFrozen=1.
DEATH_SPEED          EQU 1           ; 1 px por update; acumulador 1/2 -> mueve cada 2 frames
DEATH_STUCK_THRESHOLD EQU 6          ; Frames sin movimiento -> activar BFS rescue
DEATH_BFS_MAX_DEPTH  EQU 3           ; Profundidad max del mini-BFS (diamond ~25 cells)
DEATH_GHOST_FRAMES   EQU 96          ; 3.84s a 25fps. Sincronizado: cae justo al final del silencio post-8a nota de DeathMusicTable (8 beats x 12 frames). Ghost mode persistente hasta despawn.

; --- Pausa cinematografica tras 3a captura en iglesia ---
POST_TRAP_NASTY_DELAY  EQU 100       ; 4s @ 25fps. Total de la pausa post-cutscene.
POST_TRAP_KEY_DELAY    EQU 75        ; Frame del timer al que aparece la llave (1s desde el cutscene -> 3s antes de nasties).
POST_TRAP_LASTING_DELAY EQU 60       ; Frame del timer al que aparece compass_lasting (~0.6s tras el cheque).
DEATH_GHOST_SPEED    EQU SPEED_RUN   ; Velocidad ghost = SPEED_RUN del player (4 px/frame)
DEATH_MIN_SPAWN_DIST EQU 8           ; Min distancia BFS al player en cells. Evita instakill en cul-de-sac.

; --- Well cooldown tras curar (modo prueba; ajustar al gusto) ---
; --- Player lives ---
PLAYER_LIVES_INIT       EQU 3            ; Vidas iniciales
PLAYER_LIVES_MAX        EQU 5            ; Cap (futuro Life pickup incrementa hasta este max)

; --- Death border flash ---
DEATH_BORDER_YELLOW_FRAMES EQU 50        ; 2s a 25fps
DEATH_BORDER_RED_FRAMES    EQU 50        ; 2s a 25fps

; --- Player death animation (durante fase yellow del border flash) ---
PLAYER_DEATH_ANIM_DELAY  EQU 13          ; ~0.5s a 25fps por frame (3 frames ≈ 1.5s; resto del yellow queda en frame final)
PLAYER_DEATH_ANIM_FRAMES EQU 3           ; Frames de la anim de muerte del player

; --- Respawn blink ---
; Phase 1: countdown "3, 2, 1!" - 3 beats con flash + bip; ultimo bip largo bloqueante.
; Beats van back-to-back: tras cada SFX (500ms o 1000ms) hay un flash off de 4 frames
; antes del siguiente beat -> fase 1 ~= 2 * (500ms + 160ms) + 1000ms = ~2.3s.
RESPAWN_FLASH_FRAMES       EQU 6         ; ~240ms silencio entre beats
; Phase 2: gracia ~1s con control + blink rapido. Activada tambien tras cada
; hit de monster/nasty (CheckPlayerEnemyCollision.pHpDmgNotZero) — invulnerable
; durante 1s con feedback visual de blink. Compartida via EnterGracePhase.
RESPAWN_GRACE_FRAMES       EQU 25        ; ~1s a 25fps
RESPAWN_GRACE_BLINK_PERIOD EQU 2         ; ~80ms entre toggles (bit 1 frame counter)

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

; ==============================================================================
; RANDOM PICKUPS — slot marker + tunables
; ==============================================================================
; Sistema: cada plantilla puede llevar hasta 4 placements con id RANDOM_SLOT_MARKER.
; Al entrar en una sala, el engine elige UN slot al azar y rolea su contenido
; segun probabilidades acumulativas sobre un byte RNG (0-255). Tipos:
;   life / health / stamina / rayo (boost) / caracol (slow) / nada.
; Sin proteccion anti-farm: rerollea cada room-enter.
RANDOM_SLOT_MARKER      EQU 210         ; sprite id reservado en bg_sprites.json ("random pickup")
RANDOM_SLOT_MAX         EQU 4           ; max slots por sala (= max placements id=210 por plantilla)

; --- Pickup amounts (lo que da cada uno al recogerlo) ---
PICKUP_HEALTH_AMT       EQU 8           ; +health, clamp a HEALTH_MAX
PICKUP_STAMINA_AMT      EQU 8           ; +stamina, clamp a STAMINA_MAX
; +1 vida, clamp a PLAYER_LIVES_MAX (constante existente)

; --- Speed buffs (rayo / caracol) ---
SPEED_BUFF_RAYO_FRAMES    EQU 250       ; 10s @ 25fps. Tunable.
SPEED_BUFF_CARACOL_FRAMES EQU 125       ;  5s @ 25fps. Tunable.

; --- Mushroom debuff: bloquea ataque durante MUSHROOM_LOCK_FRAMES ---
MUSHROOM_LOCK_FRAMES     EQU 125        ;  5s @ 25fps. Tunable.
MUSHROOM_LOCK_ATTR       EQU MAGENTA | $40   ; $43 magenta bright

; --- Magic compass: power-up que muestra ruta exacta sala-a-sala ---
; Timer 16-bit en frames de juego (25fps tras catchup): 25s = 625 frames.
; Warning de los ultimos 5s: 125 frames -> blink/tick aceleran.
MAGIC_COMPASS_FRAMES        EQU 625     ; 25s @ 25fps
MAGIC_COMPASS_WARNING_FRAMES EQU 125    ; ultimos 5s -> blink x2 + tick x2
; Blink: alterna paper amarillo ON/OFF cada N frames de juego (25fps).
;   normal:  4 frames/fase -> 8 frames/ciclo -> ~3.1 Hz
;   warning: 2 frames/fase -> 4 frames/ciclo -> ~6.2 Hz
MAGIC_COMPASS_BLINK_NORMAL  EQU 4
MAGIC_COMPASS_BLINK_WARNING EQU 2
; Char activo (mientras suena el tick): override fijo del attr al char que
; toca, ignorando el color base del editor. Da contraste fuerte de "white
; bright" sobre el color base de los demás chars.
;   $47 = ink white + paper black + bright (mismo "white bright" que la X
;   normal cuando estás en sala destino).
;
; OJO: si los chars del sprite están diseñados con paper distinto a black
; (e.g. paper white), los pixels se "invierten" al aplicar este override
; porque cambia la polaridad paper/ink. Para que se vea natural, diseña los
; 4 chars de los sprites ID 36 / ID 37 con PAPER BLACK + INK del color que prefieras —
; al activar el char el bright lo destaca sin invertir nada.
MAGIC_COMPASS_ACTIVE_ATTR   EQU WHITE | $40          ; $47
; Tick heartbeat AY: cada N game frames suena beep corto.
;   normal:  25 frames -> 1.0 s
;   warning: 12 frames -> ~0.5 s
MAGIC_COMPASS_TICK_NORMAL   EQU 25
MAGIC_COMPASS_TICK_WARNING  EQU 12
; Period AY del tick (canal B). Mas alto = mas grave.
MAGIC_COMPASS_TICK_PERIOD   EQU $00C0    ; ~570 Hz tick suave
MAGIC_COMPASS_TICK_DURATION EQU 2        ; frames del beep (cutoff abrupto)
; Iteraciones máx del BFS sala-a-sala por frame. El BFS se amortiza en chunks
; pequeños para no gastar el presupuesto del frame post-transición de golpe
; (eso causaba parpadeo del reloj HUD). 8 iter/frame = ~3-4 frames totales
; para un BFS típico (path 13 saltos, ~30 iter en total).
MAGIC_COMPASS_BFS_ITERS_PER_FRAME EQU 32      ; 4x mas rapido. Cada chunk dura ~1.8 ms bajo DI; periodo IRQ 20 ms → sin riesgo.
SPEED_BUFF_RAYO_RUN     EQU 6           ; 1.5x SPEED_RUN
SPEED_BUFF_RAYO_FIGHT   EQU 3           ; 1.5x SPEED_FIGHT
SPEED_BUFF_CARACOL_RUN  EQU 2           ; 0.5x SPEED_RUN
SPEED_BUFF_CARACOL_FIGHT EQU 1          ; 0.5x SPEED_FIGHT
; Player attr aplicado durante buff (paper black + ink bright):
SPEED_BUFF_RAYO_ATTR    EQU CYAN  | $40 ; $45 cyan bright
SPEED_BUFF_CARACOL_ATTR EQU GREEN | $40 ; $44 green bright
; SpeedBuffType encoding (RAM):
SPEED_BUFF_NONE         EQU 0
SPEED_BUFF_TYPE_RAYO    EQU 1
SPEED_BUFF_TYPE_CARACOL EQU 2

; --- ESPADA buff (no consume stamina + ataca a 0 + cancela cooldown azul) ---
ESPADA_BUFF_FRAMES      EQU 12 * 25                     ; 12s a 25 fps = 300 frames
ESPADA_BUFF_ATTR        EQU RED   | $40                 ; $42 red bright

; --- ESCUDO buff (invulnerabilidad contra nasti/monster contact, knockback persiste) ---
ESCUDO_BUFF_FRAMES      EQU 15 * 25                     ; 15s a 25 fps = 375 frames
ESCUDO_BUFF_ATTR        EQU YELLOW | $40                ; $46 yellow bright

; --- REVERSE debuff (controles Q<->A, O<->P invertidos) ---
REVERSE_BUFF_FRAMES     EQU 7 * 25                      ; 7s a 25 fps = 175 frames
REVERSE_BUFF_ATTR       EQU BLUE  | $40                 ; $41 blue bright

; --- Player color cycler ---
; Cada COLOR_CYCLER_PERIOD frames, el cycler avanza al siguiente color de
; entre los buffs/debuffs activos. 12 frames = ~480ms por color a 25 fps.
; Con N buffs activos, ciclo completo dura N * 480ms.
COLOR_CYCLER_PERIOD     EQU 12

; --- Probabilidades del roll (TUNE) ---
; Umbrales acumulativos sobre RNG byte (0-255). Definidos como suma encadenada
; (cada uno = el anterior + su peso) → cambiar el peso de un tipo no rompe los
; siguientes; el slack va a "nada".
; Ratio actual: life:health:stamina:rayo:caracol:roulette:mushroom:compass:nada
;             = 0.5:1:1:1:1:1:1:0.5:18
;   life     = 0.5X = 8    (3.1%)
;   health   = 1X   = 16   (6.3%)
;   stamina  = 1X   = 16   (6.3%)
;   rayo     = 1X   = 16   (6.3%)
;   caracol  = 1X   = 16   (6.3%)
;   roulette = 1X   = 16   (6.3%)
;   mushroom = 1X   = 16   (6.3%)
;   compass  = 0.5X = 8    (3.1%)  -> mismo peso que life (drop "raro")
;   nada     = resto = 144 (56.3%)
PICKUP_X                EQU 16
PROB_LIFE_END           EQU PICKUP_X / 2                                        ; 8
PROB_HEALTH_END         EQU PROB_LIFE_END + PICKUP_X                            ; 24
PROB_STAMINA_END        EQU PROB_HEALTH_END + PICKUP_X                         ; 40
PROB_RAYO_END           EQU PROB_STAMINA_END + PICKUP_X                         ; 56
PROB_CARACOL_END        EQU PROB_RAYO_END + PICKUP_X                            ; 72
PROB_ROULETTE_END       EQU PROB_CARACOL_END + PICKUP_X                         ; 88
PROB_MUSHROOM_END       EQU PROB_ROULETTE_END + PICKUP_X                        ; 104
PROB_COMPASS_END        EQU PROB_MUSHROOM_END + PICKUP_X / 2                    ; 112
; resto [112..256) -> nada (56.3%)

; --- Roulette: cicla entre los tipos definidos en RouletteOrder ---
; Cada ROULETTE_CYCLE_FRAMES, el sprite/efecto del synth pickup avanza un
; paso en RouletteOrder. Al recoger, se aplica el efecto del tipo activo.
ROULETTE_CYCLE_FRAMES   EQU 12                          ; ~480ms @ 25fps por tipo. Tunable.
; Type ids usados por RouletteOrder + lookup en RouletteTypePtrs:
ROUL_LIFE               EQU 1
ROUL_HEALTH             EQU 2
ROUL_STAMINA            EQU 3
ROUL_RAYO               EQU 4
ROUL_CARACOL            EQU 5
ROUL_MUSHROOM           EQU 6
ROUL_COMPASS            EQU 7

; --- Random pickup memory cache: encoding del campo "rolled" ---
; Identifica el resultado del roll guardado en el cache (cur/prev). 0 = NONE
; cubre dos casos: roll original cayo en "nada", o el pickup ya fue consumido
; (CheckRandomSyntheticPickup zappea cur.rolled=0 al hit). Restaurar NONE
; equivale a "no spawnea pickup en esta sala" -> evita farmeo por respawn.
ROLLED_NONE             EQU 0
ROLLED_LIFE             EQU 1
ROLLED_HEALTH           EQU 2
ROLLED_STAMINA          EQU 3
ROLLED_RAYO             EQU 4
ROLLED_CARACOL          EQU 5
ROLLED_ROULETTE         EQU 6
ROLLED_MUSHROOM         EQU 7
ROLLED_COMPASS          EQU 8
ROLLED_ESPADA           EQU 9
ROLLED_ESCUDO           EQU 10
ROLLED_ESCUDO_RAYO      EQU 11
ROLLED_REVERSE          EQU 12
