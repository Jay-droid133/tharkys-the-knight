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

; --- Render state: posicion/sprite del frame anterior (para erase antes de logica) ---
PlayerOldX:         DEFB START_PLAYER_X
PlayerOldY:         DEFB START_PLAYER_Y
PlayerOldSprID:     DEFB 0

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

; --- Flag de redibujado ---
ScreenDirty:        DEFB 1      ; 1=hay que redibujar la pantalla completa

; --- Flag de transicion reciente (skip restore en primer frame) ---
ScreenJustRedrawn:  DEFB 0      ; 1=pantalla recien dibujada, no restaurar attrs
