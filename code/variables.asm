; ==============================================================================
; VARIABLES EN RAM MANTENIDAS POR EL JUEGO
; ==============================================================================
; Aquí definimos todos los datos mutables del juego.
; Usamos DEFB (Byte, 8 bits), DEFW (Word, 16 bits), DEFS (Espacio de bytes).

GameFrameCounter:   DEFB 0      ; Contador que incrementa cada frame (0-255)
GameState:          DEFB 0      ; Estado: 0=Menu, 1=InGame, 2=GameOver

; --- Posicion del jugador en 16-bit (estilo Sabre Wulf) ---
; Byte alto = posicion en pixeles, Byte bajo = fraccion subpixel
; Esto permite velocidades no enteras y movimiento suave
PlayerXLo:          DEFB 0      ; Subpixel X (fraccion)
PlayerXHi:          DEFB 120    ; Pixel X (posicion visible)
PlayerYLo:          DEFB 0      ; Subpixel Y (fraccion)
PlayerYHi:          DEFB 88     ; Pixel Y (posicion visible)

; --- Estado de movimiento ---
PlayerDir:          DEFB DIR_NONE   ; Direccion actual (bits: N=1,S=2,E=4,W=8)
PlayerLastHDir:     DEFB DIR_E      ; Ultima direccion horizontal (para ataque retenido)
PlayerState:        DEFB STATE_IDLE ; Estado: 0=idle, 1=running, 2=fighting
PlayerFire:         DEFB 0          ; Boton de fuego presionado (0=no, 1=si)

; --- Animacion ---
PlayerAnimFrame:    DEFB 0      ; Frame actual de animacion (0..N-1)
PlayerAnimDelay:    DEFB ANIM_DELAY_IDLE  ; Contador de delay (decrementa cada frame)
PlayerAnimNumFrames: DEFB 2     ; Numero de frames en anim actual
PlayerAnimBase:     DEFW ANIM_IDX_IDLE  ; Offset base en SpriteFrameTable

; --- Input crudo ---
InputDirection:     DEFB 0      ; Direccion leida del teclado este frame
InputFire:          DEFB 0      ; Fuego leido del teclado este frame

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
