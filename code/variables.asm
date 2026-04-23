; ==============================================================================
; VARIABLES EN RAM MANTENIDAS POR EL JUEGO
; ==============================================================================

GameFrameCounter:   DEFB 0      ; Contador que incrementa cada frame (0-255)
GameState:          DEFB 0      ; Estado: 0=Menu, 1=InGame, 2=GameOver

; ==============================================================================
; TABLA DE ENTIDADES (estilo Sabre Wulf)
; ==============================================================================
; 17 slots × 12 bytes = 204 bytes.
; Slot 0: Player. Slots 1-6: Inmortales. Slots 7-12: Nasties. 13-16: Objetos.
; Cada entidad: SpriteID, Type, State, PosX, PosY, Attr, DeltaX, DeltaY,
;               AnimBase, AnimTimer, Dir, Flags
; ==============================================================================
EntityTable:        DEFS NUM_ENTITIES * ENT_SIZE

; --- Input crudo ---
InputDirection:     DEFB 0      ; Direccion leida del teclado este frame
InputFire:          DEFB 0      ; Fuego leido del teclado este frame

; --- Debug: noclip (tecla N togglea) ---
NoclipMode:         DEFB 0      ; 0 = colision normal, 1 = sin colision (atraviesa todo)

; --- Sistema de llaves/candados (4 sets sucesivos) ---
; 0=ninguna, 1=Forest, 2=Ruins, 3=Cemetery, 4=TownGate.
; Solo una llave a la vez: se consume al abrir el candado correspondiente.
CurrentKey:         DEFB 0
; Stash temporal: behavior del pickup tocado (0=normal, 1-4=key id, 5-8=lock id+4)
PickupCurBehavior:  DEFB 0

; --- Movimiento del player (fiel a Sabre Wulf turns_per_player_move) ---
PlayerMoveTimer:    DEFB 1      ; Countdown: mueve cuando llega a 0, reset a PLAYER_MOVE_TURNS

; --- Render Y del player: POSY + offset si hay celda ocupada justo encima ---
PlayerDrawY:        DEFB 0
EnemyDrawY:         DEFB 0       ; Y renderizado por ProcessOneEnemy (monster +1 si techo pegado, resto = POSY)

; --- Spawn system ---
SpawnTimer:         DEFB SPAWN_INTERVAL  ; Countdown para intentar spawn de nasty

; --- Round-robin de enemigos (estilo Sabre Wulf) ---
EnemyStepIdx:       DEFB 0      ; Posicion actual en el round-robin (0 a NUM_MONSTERS+NUM_NASTIES-1)

; --- Render/Logic split: buffer de enemigos procesados este frame ---
FrameEnemyCount:    DEFB 0      ; Cuantos enemigos se renderizaron este frame
FrameEnemySlots:    DEFS MAX_ENEMIES_PER_FRAME * 2  ; Punteros IX (DEFW) de cada enemigo

; --- Pending erase: entidades cuya puff termino y necesitan erase final ---
PendingEraseCount:  DEFB 0      ; Cuantas entidades necesitan erase final
PendingEraseSlots:  DEFS 3 * 5  ; Hasta 3 entidades: 2b IX + 1b OLDSPRID + 1b OLDX + 1b OLDY

; ==============================================================================
; SISTEMA DE PANTALLAS
; ==============================================================================

; --- Posicion actual en el mapa de pantallas (grid 16x16) ---
CurrentScreenX:     DEFB START_SCREEN_X  ; Columna actual (0-15)
CurrentScreenY:     DEFB START_SCREEN_Y  ; Fila actual (0-15)

; --- Puntero a los datos de la pantalla actual ---
CurrentScreenAddr:  DEFW 0      ; Direccion en memoria de los datos de la pantalla actual

; --- Flag de transicion ---
ScreenTransition:   DEFB 0      ; 0=sin transicion, 1=N, 2=S, 4=E, 8=W
LastScreenTransition: DEFB 0    ; Ultima transicion real (persiste entre frames)
LastEntryPosX:      DEFB 120    ; Posicion X del player al entrar en la room
LastEntryPosY:      DEFB 90     ; Posicion Y del player al entrar en la room

; --- Flags de redibujado ---
ScreenDirty:        DEFB 1      ; 1=hay que redibujar la pantalla completa
AttrsDirty:         DEFB 0      ; 1=solo remap attrs (cambio de fase, sin cambio de room)

; --- Flag de transicion reciente (skip restore en primer frame) ---
ScreenJustRedrawn:  DEFB 0      ; 1=pantalla recien dibujada, no restaurar attrs

; ==============================================================================
; MAPA DE COLISION (pre-computado al cargar pantalla)
; ==============================================================================
; 32 columnas × 22 filas = 704 bytes. 0=libre, 1=bloqueado.
; Coordenadas en char-space del room (sin BG_Y_OFFSET).
; Se construye en BuildCollisionMap al cargar cada pantalla.
; ==============================================================================
CollisionMap:       DEFS 32 * 22

; ==============================================================================
; CURRENT SCREEN BUFFER (copia de Room_Txx desde bank 1)
; ==============================================================================
; Los datos de rooms viven en bank 1 ($C000-$FFFF paginable). Al cargar una
; pantalla, LoadRoomToBuffer pagina bank 1, copia los bytes del room actual
; hasta el terminador $0000, y repagina bank 0. El engine siempre lee desde
; este buffer (RAM fija), asi no hace falta tocar paginacion en el hot path.
; Tamaño: suficiente para el room mas grande. Entries = 5 B (ptr+x+y+v) + 2 B
; terminador. 1024 bytes permite ~200 entries (widow fills can be numerous).
; ==============================================================================
CurrentScreenBuffer: DEFS 1024

; ==============================================================================
; BG SPRITE BUFFER (copia del sprite BG activo desde bank 3)
; ==============================================================================
; Los graficos de BG sprites viven en bank 3 ($C000-$FFFF paginable). Cada
; vez que hay que dibujar (o leer el header) de un BG sprite, LoadBgSpriteToBuffer
; pagina bank 3, copia BG_SPRITE_BUFFER_SIZE bytes al buffer, y repagina bank 0.
; El draw routine opera sobre el buffer.
;
; Tamaño: 1024 B. El sprite mas grande es tall_house (88x8 = 704 B pixel data
; + 2 header + 1 tint + 2 attr header + 88 attrs ≈ 800 B). 1024 da margen.
; ==============================================================================
BG_SPRITE_BUFFER_SIZE EQU 1024
BgSpriteBuffer:     DEFS BG_SPRITE_BUFFER_SIZE

; Pixel data del reloj de plaza (16 scan lines x 2 bytes = 32 B).
; Copiado desde bank 3 una vez por pantalla via LoadPlazaClockPixels.
; DrawPlazaClock (cada frame) lo lee desde aqui sin paginar.
PlazaClockPixels:   DEFS 32

; ==============================================================================
; BUFFER DE ATRIBUTOS LIMPIOS (copia del fondo sin sprites)
; ==============================================================================
; 768 bytes. Se rellena tras DrawScreen + RemapScreenAttrs.
; Usado para restaurar atributos tras borrar sprites con color.
; ==============================================================================
CleanAttrMap:       DEFS ATTR_SIZE

; ==============================================================================
; SISTEMA DE POZOS (recuperacion)
; ==============================================================================
CurrentEnemySpeed:  DEFB 1      ; Velocidad base nasties (escala por ciclo: 1,1,2,2)
CurrentEnemyAnimDelay: DEFB 8   ; Delay animacion nasties (escala por ciclo, base ENEMY_ANIM_DELAY)

WellActive:         DEFB 0      ; 1=hay pozo en esta pantalla, 0=no
WellPosX:           DEFB 0      ; X pixel del pozo
WellPosY:           DEFB 0      ; Y pixel del pozo
WellFlashTimer:     DEFB 0      ; Countdown flash HUD tras recuperar (0=inactivo)

PlazaClockActive:   DEFB 0      ; 1=hay reloj de plaza en esta pantalla
PlazaClockCharX:    DEFB 0      ; charX del reloj (con BG_Y_OFFSET ya aplicado en Y)
PlazaClockCharY:    DEFB 0      ; charY del reloj (con BG_Y_OFFSET)
PlazaScanAddrs:     DEFS 32     ; 16 words: dir VRAM por scan line de la esfera

; --- Paginacion 128K ---
; Port $7FFD es write-only, guardamos el valor actual en esta variable sombra
; Bits 0-2: RAM bank en slot 3 ($C000-$FFFF)
; Bit 3: pantalla (0=normal bank 5, 1=shadow bank 7)
; Bit 4: ROM (0=128 editor, 1=48 BASIC)
; Bit 5: disable paging (NO tocar)
CurrentPaging:      DEFB $10    ; default: bank 0 en slot 3, pantalla normal, ROM 48


; ==============================================================================
; SISTEMA DE SONIDO
; ==============================================================================
CurrentBorderColor: DEFB BLACK      ; Color actual del borde (preservado durante SFX)
PlayerPrevState:    DEFB 0          ; Estado previo del player (detectar transicion a fighting)
FootstepToggle:     DEFB 0          ; Alterna 0/1 cada frame de animacion: suena solo en 1
PlayerCurrentSpeed: DEFB 2          ; Velocidad actual del player (debug HUD)

; ==============================================================================
; MONSTER AI v2 — estado por monster + RoomHistory (fase 2)
; ==============================================================================
; 3 monsters activos. Slots parallelos — indice = 0,1,2 relativo a SLOT_MONSTER0.
; Total: 3*4 + 3 = 15 bytes.
; ==============================================================================

; Screen donde el monster "vive" actualmente (screen_id = Y*16+X, 0..255).
; Si == CurrentScreenId => monster esta en la room del player.
MonsterRoomId:       DEFB 0, 0, 0

; Cuenta atras en frames. 0 = sin accion pendiente. Si > 0 => cuenta hasta
; migrar (linger normal) o volver por el borde (pushed). El flag MAI_FLAG_PUSHED
; decide cual.
MonsterLingerTimer:  DEFB 0, 0, 0

; Ultimo borde de entrada/salida (MAI_SIDE_N/S/W/E). Usado para reaparecer
; por el borde correcto cuando expira el timer, o para guardar el gap de
; salida al amanecer (Regla 7 / STATE_LEAVING).
MonsterEntryBorder:  DEFB 0, 0, 0

; Coord char (0-31) del gap de salida al amanecer (Regla 7). Parejado con
; MonsterEntryBorder[slot] cuando MAI_FLAG_LEAVING esta set.
MonsterExitCoord:    DEFB 0, 0, 0

; Flags combinados (bits 0-2 definidos en constants.asm).
MonsterAiFlags:      DEFB 0, 0, 0

; Buffer circular de las 3 ultimas rooms distintas visitadas por el player.
; [0] = actual, [1] = anterior, [2] = la anterior. Un monster cuya room no
; este en este buffer => mas de 2 rooms atras => teleport a la room actual.
RoomHistory:         DEFB 0, 0, 0

; Ultima room donde el monster estuvo TYPE_MONSTER visible + su POSX/POSY.
; Usado para restaurar monsters "en transito" (TYPE_NONE post-transicion, aun
; no activados por TryRespawn) cuando el player vuelve rapidamente al room
; anterior. Inicial $FF = nunca visto.
MonsterLastSeenRoom: DEFB $FF, $FF, $FF
MonsterLastSeenX:    DEFB 0, 0, 0
MonsterLastSeenY:    DEFB 0, 0, 0

; Posicion original del monster al entrar en STATE_SCARED (pausa del amanecer).
; Guardada la primera vez por slot, usada como ancla del shake aleatorio.
; MAI_FLAG_SHAKE_SAVED indica si el slot ya tiene orig guardado.
MonsterShakeOrigX:   DEFB 0, 0, 0
MonsterShakeOrigY:   DEFB 0, 0, 0
