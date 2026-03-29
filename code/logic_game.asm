; ==============================================================================
; LOGICA DEL JUEGO - Sistema de entidades estilo Sabre Wulf
; ==============================================================================
; - Estructura de entidad de 12 bytes (universal)
; - Game loop per-entity: erase → update → draw
; - Movimiento 8-bit (sin subpixel)
; - Animacion por SpriteID (incrementar dentro de rango)
; - XOR draw/erase (una sola rutina)
; ==============================================================================

; ==============================================================================
; ReadInput - Lee teclado y genera direccion + fuego
; ==============================================================================
ReadInput:
    XOR A
    LD (InputDirection), A
    LD (InputFire), A

    ; --- Q (Arriba) ---
    LD BC, $FBFE
    IN A, (C)
    BIT 0, A
    JR NZ, .noUp
    LD A, (InputDirection)
    OR DIR_N
    LD (InputDirection), A
.noUp:
    ; --- A (Abajo) ---
    LD BC, $FDFE
    IN A, (C)
    BIT 0, A
    JR NZ, .noDown
    LD A, (InputDirection)
    OR DIR_S
    LD (InputDirection), A
.noDown:
    ; --- O (Izquierda) ---
    LD BC, $DFFE
    IN A, (C)
    BIT 1, A
    JR NZ, .noLeft
    LD A, (InputDirection)
    OR DIR_W
    LD (InputDirection), A
.noLeft:
    ; --- P (Derecha) ---
    LD BC, $DFFE
    IN A, (C)
    BIT 0, A
    JR NZ, .noRight
    LD A, (InputDirection)
    OR DIR_E
    LD (InputDirection), A
.noRight:
    ; --- SPACE (Fuego) ---
    LD BC, $7FFE
    IN A, (C)
    BIT 0, A
    JR NZ, .noFire
    LD A, 1
    LD (InputFire), A
.noFire:
    ; Cancelar opuestos
    LD A, (InputDirection)
    LD B, A
    AND DIR_N | DIR_S
    CP DIR_N | DIR_S
    JR NZ, .noVC
    LD A, B
    AND ~(DIR_N | DIR_S) & $FF
    LD B, A
.noVC:
    LD A, B
    AND DIR_E | DIR_W
    CP DIR_E | DIR_W
    JR NZ, .noHC
    LD A, B
    AND ~(DIR_E | DIR_W) & $FF
    LD B, A
.noHC:
    LD A, B
    LD (InputDirection), A
    RET

; ==============================================================================
; InitEntities - Inicializa la tabla de entidades
; ==============================================================================
; Limpia todos los slots y configura el slot 0 como player.
; ==============================================================================
InitEntities:
    ; Limpiar toda la tabla a ceros
    LD HL, EntityTable
    LD DE, EntityTable + 1
    LD BC, NUM_ENTITIES * ENT_SIZE - 1
    XOR A
    LD (HL), A
    LDIR

    ; Configurar slot 0: Player
    LD IX, EntityTable
    LD (IX+ENT_SPRITEID), SPRID_IDLE    ; Frame idle 0
    LD (IX+ENT_TYPE), TYPE_PLAYER
    LD (IX+ENT_STATE), STATE_IDLE
    LD (IX+ENT_POSX), START_PLAYER_X
    LD (IX+ENT_POSY), START_PLAYER_Y
    LD (IX+ENT_ATTR), WHITE | $40       ; Bright blanco
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_ANIMBASE), SPRID_IDLE
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_IDLE
    LD (IX+ENT_DIR), DIR_E << 4         ; lastHDir=E, dir=none
    LD (IX+ENT_FLAGS), 1 << ENTF_VISIBLE
    RET

; ==============================================================================
; ProcessEntities - Loop principal per-entity (flicker-free)
; ==============================================================================
; Orden optimizado: update → attrs → XOR erase + XOR draw (back-to-back) → attrs
; Los dos DrawSprite van seguidos para minimizar el gap visible al beam CRT.
; ==============================================================================
ProcessEntities:
    LD IX, EntityTable
    LD A, NUM_ENTITIES
    LD (.counter), A

.loop:
    LD A, (IX+ENT_TYPE)
    OR A
    JP Z, .skip                 ; Slot inactivo

    LD A, (ScreenJustRedrawn)
    OR A
    JR NZ, .freshDraw

    ; ==================================================================
    ; FRAME NORMAL: render PRIMERO (beam racing), logica DESPUES
    ; ==================================================================
    ; Usa PlayerOldX/Y/SprID persistentes del frame anterior.
    ; Asi el erase+draw ocurre INMEDIATAMENTE tras HALT,
    ; antes de que el beam CRT alcance la zona visible (linea 64).
    ; UpdatePlayer (lento, ~5200 T por collision) va DESPUES del draw.
    ; ==================================================================

    ; 1. Buscar direccion del sprite VIEJO (persistente)
    LD A, (PlayerOldSprID)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (.oldSprAddr), DE

    ; 2. Buscar direccion del sprite ACTUAL (para el draw)
    CALL GetSpriteAddr          ; SpriteAddrTemp = sprite actual

    ; ==================================================================
    ; SECCION CRITICA: XOR erase + XOR draw (lo antes posible tras HALT)
    ; ==================================================================

    ; 3. XOR erase en posicion vieja con sprite viejo
    LD A, (PlayerOldY)
    LD D, A
    LD A, (PlayerOldX)
    LD E, A
    PUSH IX
    LD IX, (.oldSprAddr)
    CALL DrawSprite
    POP IX

    ; 4. XOR draw en posicion actual con sprite actual
    LD D, (IX+ENT_POSY)
    LD E, (IX+ENT_POSX)
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX

    ; ==================================================================
    ; ATRIBUTOS: despues de los pixeles (el sprite ya esta dibujado)
    ; ==================================================================

    ; 5. Restaurar attrs en posicion vieja
    LD A, (PlayerOldY)
    LD D, A
    LD A, (PlayerOldX)
    LD E, A
    CALL RestoreEntityAttr

    ; 6. Guardar attrs en posicion nueva
    LD D, (IX+ENT_POSY)
    LD E, (IX+ENT_POSX)
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL SaveEntityAttr
    POP IX

    ; 7. Pintar atributo del sprite
    LD D, (IX+ENT_POSY)
    LD E, (IX+ENT_POSX)
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr

    ; ==================================================================
    ; LOGICA: UpdatePlayer DESPUES del render (no afecta timing visual)
    ; ==================================================================

    ; 8. Actualizar PlayerOld = posicion actual (ANTES de update)
    LD A, (IX+ENT_POSX)
    LD (PlayerOldX), A
    LD A, (IX+ENT_POSY)
    LD (PlayerOldY), A
    LD A, (IX+ENT_SPRITEID)
    LD (PlayerOldSprID), A

    ; 9. Update (cambia pos y animacion para el PROXIMO frame)
    LD A, (IX+ENT_TYPE)
    CP TYPE_PLAYER
    CALL Z, UpdatePlayer

    JR .skip

    ; ==================================================================
    ; PRIMER FRAME tras redibujar pantalla: update + draw + sync old
    ; ==================================================================
.freshDraw:
    LD A, (IX+ENT_TYPE)
    CP TYPE_PLAYER
    CALL Z, UpdatePlayer
    CALL DrawEntity

    ; Sincronizar PlayerOld con posicion actual
    LD A, (IX+ENT_POSX)
    LD (PlayerOldX), A
    LD A, (IX+ENT_POSY)
    LD (PlayerOldY), A
    LD A, (IX+ENT_SPRITEID)
    LD (PlayerOldSprID), A

.skip:
    LD DE, ENT_SIZE
    ADD IX, DE
    LD A, (.counter)
    DEC A
    LD (.counter), A
    JP NZ, .loop

    ; Limpiar flag despues de procesar TODAS las entidades
    XOR A
    LD (ScreenJustRedrawn), A
    RET

.counter:    DEFB 0
.oldSprAddr: DEFW 0

; ==============================================================================
; DrawEntity - Guarda attrs, XOR-dibuja sprite, pinta attrs de entidad
; ==============================================================================
; Solo se usa en .freshDraw (primer frame tras transicion de pantalla).
; IX = puntero a la entidad
; ==============================================================================
DrawEntity:
    ; Guardar attrs del fondo ANTES de pintar
    CALL GetSpriteAddr
    LD D, (IX+ENT_POSY)
    LD E, (IX+ENT_POSX)
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL SaveEntityAttr
    POP IX

    ; Pintar atributo ANTES del draw (evita ventana con attrs de fondo)
    LD D, (IX+ENT_POSY)
    LD E, (IX+ENT_POSX)
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr

    ; XOR draw del sprite (attrs ya correctos)
    LD D, (IX+ENT_POSY)
    LD E, (IX+ENT_POSX)
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX
    RET

; ==============================================================================
; GetSpriteAddr - Obtiene puntero al sprite actual de la entidad
; ==============================================================================
; Lee SpriteID de la entidad, busca en SpriteFrameTable.
; Resultado guardado en SpriteAddrTemp (IX se preserva).
; ==============================================================================
GetSpriteAddr:
    LD A, (IX+ENT_SPRITEID)
    LD L, A
    LD H, 0
    ADD HL, HL                  ; × 2 (cada entrada es DEFW)
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (SpriteAddrTemp), DE
    RET

SpriteAddrTemp: DEFW 0

; ==============================================================================
; UpdatePlayer - Actualiza estado, movimiento y animacion del player
; ==============================================================================
; IX = puntero a la entidad del player (slot 0)
; ==============================================================================
UpdatePlayer:
    CALL UpdatePlayerState
    CALL UpdatePlayerMovement
    CALL UpdatePlayerAnimation
    RET

; ==============================================================================
; UpdatePlayerState - Determina estado y direccion desde input
; ==============================================================================
UpdatePlayerState:
    LD A, (InputDirection)
    LD B, A
    LD A, (InputFire)
    LD C, A

    ; Sin input → idle
    LD A, B
    OR C
    JR NZ, .notIdle
    LD (IX+ENT_STATE), STATE_IDLE
    ; Dir actual = none (bits 0-3), mantener lastHDir (bits 4-7)
    LD A, (IX+ENT_DIR)
    AND $F0                     ; Limpiar dir actual, mantener lastHDir
    LD (IX+ENT_DIR), A
    RET

.notIdle:
    ; Guardar direccion actual en bits 0-3
    LD A, (IX+ENT_DIR)
    AND $F0                     ; Mantener lastHDir
    OR B                        ; Añadir dir actual
    LD (IX+ENT_DIR), A

    ; Actualizar lastHDir si hay componente E/W
    LD A, B
    AND DIR_E | DIR_W
    JR Z, .noHorizUpdate
    ; Guardar en bits 4-7
    RLCA
    RLCA
    RLCA
    RLCA                        ; Shift a bits 4-7
    LD C, A                     ; C = lastHDir en bits 4-7
    LD A, (IX+ENT_DIR)
    AND $0F                     ; Mantener dir actual
    OR C                        ; Añadir lastHDir
    LD (IX+ENT_DIR), A
.noHorizUpdate:

    ; Fighting o running?
    LD A, (InputFire)
    OR A
    JR Z, .running
    LD (IX+ENT_STATE), STATE_FIGHTING
    RET

.running:
    LD (IX+ENT_STATE), STATE_RUNNING
    RET

; ==============================================================================
; UpdatePlayerMovement - Fiel a Sabre Wulf: mueve cada N frames
; ==============================================================================
; El original usa turns_per_player_move=2: el player se mueve cada 2 frames.
; Desplazamiento por turno: SPEED_RUN_X horizontal, SPEED_RUN_Y vertical.
; ==============================================================================
UpdatePlayerMovement:
    ; Fiel a Sabre Wulf: mueve solo cada PLAYER_MOVE_TURNS frames
    LD A, (PlayerMoveTimer)
    DEC A
    LD (PlayerMoveTimer), A
    RET NZ                      ; No es el turno de moverse
    LD A, PLAYER_MOVE_TURNS
    LD (PlayerMoveTimer), A     ; Resetear timer

    LD A, (IX+ENT_DIR)
    AND $0F                     ; Dir actual (bits 0-3)
    RET Z                       ; Sin movimiento

    ; Determinar velocidad segun estado
    LD A, (IX+ENT_STATE)
    CP STATE_FIGHTING
    LD A, SPEED_RUN
    JR NZ, .gotSpeed
    LD A, SPEED_FIGHT
.gotSpeed:
    LD (.speed), A

    ; --- Movimiento horizontal (con colision) ---
    LD A, (IX+ENT_POSX)
    LD (.savedX), A             ; Guardar X antes de mover

    LD A, (IX+ENT_DIR)
    BIT 2, A                    ; DIR_E?
    JR Z, .noE
    LD A, (.speed)
    LD B, A
    LD A, (IX+ENT_POSX)
    ADD A, B
    CP SCREEN_MAX_X
    JR C, .clampE
    LD A, SCREEN_MAX_X
.clampE:
    LD (IX+ENT_POSX), A
.noE:
    LD A, (IX+ENT_DIR)
    BIT 3, A                    ; DIR_W?
    JR Z, .noW
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.speed)
    LD C, A
    LD A, B
    SUB C
    JR NC, .clampW
    XOR A                       ; Clamp a 0
.clampW:
    LD (IX+ENT_POSX), A
.noW:
    ; Check colision X
    CALL CheckEntityCollision
    JR Z, .xOk
    LD A, (.savedX)
    LD (IX+ENT_POSX), A        ; Revertir X
.xOk:

    ; --- Movimiento vertical (con colision) ---
    LD A, (IX+ENT_POSY)
    LD (.savedY), A

    LD A, (IX+ENT_DIR)
    BIT 1, A                    ; DIR_S?
    JR Z, .noS
    LD A, (.speed)
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, B
    CP SCREEN_MAX_Y
    JR C, .clampS
    LD A, SCREEN_MAX_Y
.clampS:
    LD (IX+ENT_POSY), A
.noS:
    LD A, (IX+ENT_DIR)
    BIT 0, A                    ; DIR_N?
    JR Z, .noN
    LD A, (IX+ENT_POSY)
    LD B, A
    LD A, (.speed)
    LD C, A
    LD A, B
    SUB C
    JR C, .toMinY           ; underflow → por debajo de 0
    CP SCREEN_MIN_Y
    JR NC, .clampN          ; A >= SCREEN_MIN_Y → ok
.toMinY:
    LD A, SCREEN_MIN_Y
.clampN:
    LD (IX+ENT_POSY), A
.noN:
    ; Check colision Y
    CALL CheckEntityCollision
    JR Z, .yOk
    LD A, (.savedY)
    LD (IX+ENT_POSY), A        ; Revertir Y
.yOk:
    RET

.speed:  DEFB 0
.savedX: DEFB 0
.savedY: DEFB 0

; ==============================================================================
; CheckEntityCollision - Colision de la entidad contra sprites de fondo
; ==============================================================================
; Comprueba 3 puntos del bounding box (como el original).
; IX = entidad. Salida: Z=libre, NZ=colision.
; ==============================================================================
CheckEntityCollision:
    ; Punto 1: esquina superior-izquierda (X, Y)
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    RET NZ

    ; Punto 2: esquina superior-derecha (X+15, Y)
    LD A, (IX+ENT_POSX)
    ADD A, 15
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    RET NZ

    ; Punto 3: esquina inferior-izquierda (X, Y+20)
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 20
    LD C, A
    CALL IsPointBlocked
    RET NZ

    ; Punto 4: esquina inferior-derecha (X+15, Y+20)
    LD A, (IX+ENT_POSX)
    ADD A, 15
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 20
    LD C, A
    CALL IsPointBlocked
    RET                         ; Z/NZ del ultimo check

; ==============================================================================
; UpdatePlayerAnimation - Animacion por SpriteID
; ==============================================================================
; Determina el AnimBase segun estado+dir, avanza frame si timer expira.
; ==============================================================================
UpdatePlayerAnimation:
    ; Determinar animacion segun estado y direccion
    LD A, (IX+ENT_STATE)
    CP STATE_FIGHTING
    JR Z, .animFight
    CP STATE_RUNNING
    JR Z, .animRun

    ; --- IDLE ---
    LD D, SPRID_IDLE
    LD E, ANIM_FRAMES_IDLE
    LD C, ANIM_DELAY_IDLE
    JR .applyAnim

.animFight:
    ; Pelear usa lastHDir (bits 4-7 de ENT_DIR)
    LD A, (IX+ENT_DIR)
    RRCA
    RRCA
    RRCA
    RRCA
    AND $0F                     ; lastHDir
    CP DIR_W
    JR Z, .fightW
    LD D, SPRID_FIGHT_E
    JR .fightSet
.fightW:
    LD D, SPRID_FIGHT_W
.fightSet:
    LD E, ANIM_FRAMES_FIGHT
    LD C, ANIM_DELAY_FIGHT
    JR .applyAnim

.animRun:
    LD A, (IX+ENT_DIR)
    AND $0F                     ; dir actual
    ; Prioridad: E/W sobre N/S
    BIT 2, A
    JR NZ, .runE
    BIT 3, A
    JR NZ, .runW
    BIT 0, A
    JR NZ, .runN
    LD D, SPRID_WALK_S
    JR .runSet
.runE:
    LD D, SPRID_WALK_E
    LD E, 4
    LD C, ANIM_DELAY_RUN
    JR .applyAnim
.runW:
    LD D, SPRID_WALK_W
    LD E, 4
    LD C, ANIM_DELAY_RUN
    JR .applyAnim
.runN:
    LD D, SPRID_WALK_N
.runSet:
    LD E, ANIM_FRAMES_WALK
    LD C, ANIM_DELAY_RUN

.applyAnim:
    ; D = nuevo AnimBase, E = num frames, C = delay
    ; ¿Cambio de animacion?
    LD A, (IX+ENT_ANIMBASE)
    CP D
    JR Z, .sameAnim

    ; Nueva animacion → reiniciar
    LD (IX+ENT_ANIMBASE), D
    LD (IX+ENT_SPRITEID), D     ; Reset al primer frame
    LD (IX+ENT_ANIMTIMER), C
    RET

.sameAnim:
    ; Decrementar timer
    DEC (IX+ENT_ANIMTIMER)
    RET NZ

    ; Timer expirado → avanzar frame
    LD (IX+ENT_ANIMTIMER), C    ; Reset timer

    LD A, (IX+ENT_SPRITEID)
    INC A
    ; ¿Fuera de rango?
    LD B, A                     ; B = nuevo SpriteID
    SUB D                       ; A = frame relativo (nuevo - animBase)
    CP E                        ; ¿>= num_frames?
    JR C, .frameOk
    LD B, D                     ; Reset al AnimBase
.frameOk:
    LD (IX+ENT_SPRITEID), B
    RET
