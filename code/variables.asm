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

; --- Movimiento del player (fiel a Sabre Wulf turns_per_player_move) ---
PlayerMoveTimer:    DEFB 1      ; Countdown: mueve cuando llega a 0, reset a PLAYER_MOVE_TURNS

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
; terminador. 256 bytes permite ~50 entries, muy por encima de lo tipico.
; ==============================================================================
CurrentScreenBuffer: DEFS 256

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
CurrentBorderColor: DEFB BLUE       ; Color actual del borde (preservado durante SFX)
PlayerPrevState:    DEFB 0          ; Estado previo del player (detectar transicion a fighting)
FootstepToggle:     DEFB 0          ; Alterna 0/1 cada frame de animacion: suena solo en 1
PlayerCurrentSpeed: DEFB 2          ; Velocidad actual del player (debug HUD)
SpeedFracAccum:     DEFB 0          ; Acumulador fraccionario de velocidad (0-255)
