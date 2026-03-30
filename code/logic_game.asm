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

    ; Limpiar tabla de atributos salvados
    LD HL, SavedAttrTable
    LD DE, SavedAttrTable + 1
    LD BC, NUM_ENTITIES * 18 - 1
    XOR A
    LD (HL), A
    LDIR

    ; Configurar slot 0: Player
    LD IX, EntityTable
    LD (IX+ENT_SPRITEID), SPRID_IDLE
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
    LD (IX+ENT_OLDX), START_PLAYER_X
    LD (IX+ENT_OLDY), START_PLAYER_Y
    LD (IX+ENT_OLDSPRID), SPRID_IDLE
    LD (IX+ENT_DRAWX), START_PLAYER_X

    ; Resetear spawn timer
    LD A, SPAWN_INTERVAL
    LD (SpawnTimer), A
    RET

; ==============================================================================
; ProcessEntities - Player directo + loop de enemigos (slots 1-9)
; ==============================================================================
; Optimizado: player se procesa sin dispatch. Enemigos solo iteran el rango
; activo (immortals + nasties), sin recorrer slots vacios (10-16).
; ==============================================================================
ProcessEntities:
    ; === PLAYER (slot 0, siempre activo) ===
    LD IX, EntityTable
    XOR A
    CALL SetAttrSlot            ; Slot 0

    LD A, (ScreenJustRedrawn)
    OR A
    JP NZ, .plFresh
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    JP NZ, .plFresh

    ; --- Frame normal player ---
    LD A, (IX+ENT_OLDSPRID)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (.oldSprAddr), DE

    CALL GetSpriteAddr

    ; XOR erase viejo
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    PUSH IX
    LD IX, (.oldSprAddr)
    CALL DrawSprite
    POP IX

    ; XOR draw nuevo
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX

    ; Restaurar attrs vieja pos
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    CALL RestoreEntityAttr

    ; Guardar attrs nueva pos
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL SaveEntityAttr
    POP IX

    ; Pintar attr
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr

    ; Guardar old = actual
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A

    ; Update + flush
    CALL UpdatePlayer
    CALL CalcDrawX
    CALL FlushAttrSlot
    JP .enemiesStart

    ; --- Primer frame player (transicion) ---
.plFresh:
    RES ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    CALL UpdatePlayer
    CALL CalcDrawX
    CALL DrawEntity

    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A

    CALL GetSpriteAddr
    CALL CalcDrawX
    CALL FlushAttrSlot

    ; === ENEMIES (slots 1 a SLOT_NASTY0+NUM_NASTIES-1) ===
.enemiesStart:
    LD IX, EntityTable + (SLOT_IMMORTAL0 * ENT_SIZE)
    LD A, NUM_IMMORTALS + NUM_NASTIES
    LD (.counter), A

.enLoop:
    LD A, (IX+ENT_TYPE)
    OR A
    JP Z, .enSkip               ; Slot inactivo

    ; ¿Recien spawneado o pantalla recien dibujada?
    LD A, (ScreenJustRedrawn)
    OR A
    JP NZ, .enFresh
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    JP NZ, .enFresh

    ; --- Frame normal enemigo ---
    LD A, (IX+ENT_OLDSPRID)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (.oldSprAddr), DE

    CALL GetSpriteAddr

    ; XOR erase viejo
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    PUSH IX
    LD IX, (.oldSprAddr)
    CALL DrawSprite
    POP IX

    ; XOR draw nuevo
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX

    ; Pintar attr (sin save/restore)
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr

    ; Guardar old = actual
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A

    ; Update AI
    CALL UpdateEnemy
    CALL CalcDrawX
    JP .enSkip

    ; --- Primer frame enemigo (spawn o transicion) ---
.enFresh:
    RES ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    CALL UpdateEnemy
    CALL CalcDrawX
    CALL GetSpriteAddr

    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX

    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr

    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX

    ; Sync old = actual
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A

.enSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    LD A, (.counter)
    DEC A
    LD (.counter), A
    JP NZ, .enLoop

    ; Limpiar flag despues de procesar TODAS las entidades
    XOR A
    LD (ScreenJustRedrawn), A

    ; Spawn system: intentar crear nasties
    CALL TrySpawnNasty
    RET

.counter:    DEFB 0
.oldSprAddr: DEFW 0

; ==============================================================================
; CalcDrawX - Calcula ENT_DRAWX (POSX ajustado para sprites de ataque)
; ==============================================================================
CalcDrawX:
    LD A, (IX+ENT_ANIMBASE)
    CP SPRID_ATTACK_WEST
    LD A, (IX+ENT_POSX)
    JR NZ, .noOffset
    SUB 8
.noOffset:
    LD (IX+ENT_DRAWX), A
    RET

; ==============================================================================
; DrawEntity - Guarda attrs, XOR-dibuja sprite, pinta attrs de entidad
; ==============================================================================
; Solo se usa en .freshDraw (primer frame tras transicion de pantalla).
; IX = puntero a la entidad
; ==============================================================================
DrawEntity:
    CALL GetSpriteAddr

    ; Guardar attrs del fondo ANTES de pintar
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL SaveEntityAttr
    POP IX

    ; Pintar atributo ANTES del draw
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr

    ; XOR draw del sprite
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
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
    ; Offsets segun animacion (sprites 24px de ataque)
    ; collL: offset izquierdo (0 normal, -8 attack west = espada a la izq)
    ; collW: offset derecho  (15 normal, 23 attack east/west = sprite mas ancho)
    LD A, (IX+ENT_ANIMBASE)
    CP SPRID_ATTACK_WEST
    JR Z, .collAttackW
    CP SPRID_ATTACK_EAST
    JR Z, .collAttackE
    LD A, 0
    LD (.collL), A
    LD A, 15
    JR .collSetW
.collAttackW:
    LD A, 8                     ; izquierda desplazada 8 (espada)
    LD (.collL), A
    LD A, 15                    ; derecha igual que walk (cuerpo en X..X+15)
    JR .collSetW
.collAttackE:
    LD A, 0
    LD (.collL), A
    LD A, 23                    ; derecha extendida (espada a la derecha)
.collSetW:
    LD (.collW), A

    ; Punto 1: esquina superior-izquierda (X-collL, Y)
    LD A, (.collL)
    LD B, A
    LD A, (IX+ENT_POSX)
    SUB B
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    RET NZ

    ; Punto 2: esquina superior-derecha (X+collW, Y)
    LD A, (.collW)
    LD B, A
    LD A, (IX+ENT_POSX)
    ADD A, B
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    RET NZ

    ; Punto 3: esquina inferior-izquierda (X-collL, Y+20)
    LD A, (.collL)
    LD B, A
    LD A, (IX+ENT_POSX)
    SUB B
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 20
    LD C, A
    CALL IsPointBlocked
    RET NZ

    ; Punto 4: esquina inferior-derecha (X+collW, Y+20)
    LD A, (.collW)
    LD B, A
    LD A, (IX+ENT_POSX)
    ADD A, B
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 20
    LD C, A
    CALL IsPointBlocked
    RET                         ; Z/NZ del ultimo check

.collL: DEFB 0
.collW: DEFB 15

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
    LD D, SPRID_ATTACK_EAST
    JR .fightSet
.fightW:
    LD D, SPRID_ATTACK_WEST
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
    ; Push-back al entrar en animaciones de ataque con sprite 24px
    LD A, D
    CP SPRID_ATTACK_EAST
    JR Z, .pushBackEast
    CP SPRID_ATTACK_WEST
    JR NZ, .noPushBack

    ; Attack west: comprobar X-8 en fila superior e inferior → mover +8
    PUSH DE
    PUSH BC
    LD A, (IX+ENT_POSX)
    SUB 8
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JR NZ, .doPushBackWest
    LD A, (IX+ENT_POSX)
    SUB 8
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 20
    LD C, A
    CALL IsPointBlocked
    JR Z, .noPushBackPop
.doPushBackWest:
    LD A, (IX+ENT_POSX)
    ADD A, 8
    LD (IX+ENT_POSX), A
    JR .noPushBackPop

    ; Attack east: comprobar X+23 en fila superior E inferior → mover -8
.pushBackEast:
    PUSH DE
    PUSH BC
    LD A, (IX+ENT_POSX)
    ADD A, 23
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JR NZ, .doPushBackEast
    LD A, (IX+ENT_POSX)
    ADD A, 23
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 20
    LD C, A
    CALL IsPointBlocked
    JR Z, .noPushBackPop
.doPushBackEast:
    LD A, (IX+ENT_POSX)
    SUB 8
    LD (IX+ENT_POSX), A
.noPushBackPop:
    POP BC
    POP DE
.noPushBack:
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

; ==============================================================================
; SISTEMA DE ENEMIGOS
; ==============================================================================

; ==============================================================================
; UpdateEnemy - AI patrol + bounce (estilo Sabre Wulf)
; ==============================================================================
; Cada frame: posicion += delta. Si choca con borde o fondo, invierte delta.
; Animacion: cicla SpriteID dentro del rango del tipo.
; IX = puntero a la entidad enemiga.
; ==============================================================================
UpdateEnemy:
    ; --- Movimiento horizontal ---
    LD A, (IX+ENT_POSX)
    LD (.savedEX), A
    LD B, A
    LD A, (IX+ENT_DELTAX)
    LD C, A
    ; Test signo para ADD signed
    BIT 7, C
    JR NZ, .eDeltaXNeg
    ; Positivo: mover derecha
    LD A, B
    ADD A, C
    CP SCREEN_MAX_X
    JR C, .eClampXOk
    LD A, SCREEN_MAX_X - 1
    JR .eReverseX
.eDeltaXNeg:
    ; Negativo: mover izquierda
    LD A, B
    ADD A, C                    ; ADD signed (C es negativo)
    JR C, .eClampXOk            ; No underflow → ok
    XOR A                       ; Clamp a 0
    JR .eReverseX
.eClampXOk:
    LD (IX+ENT_POSX), A
    ; Check colision fondo en X
    CALL CheckEnemyCollision
    JR Z, .eXDone
    ; Colision → revertir X e invertir delta
    LD A, (.savedEX)
    LD (IX+ENT_POSX), A
.eReverseX:
    LD A, (IX+ENT_DELTAX)
    NEG
    LD (IX+ENT_DELTAX), A
.eXDone:

    ; --- Movimiento vertical ---
    LD A, (IX+ENT_POSY)
    LD (.savedEY), A
    LD B, A
    LD A, (IX+ENT_DELTAY)
    LD C, A
    BIT 7, C
    JR NZ, .eDeltaYNeg
    LD A, B
    ADD A, C
    CP SCREEN_MAX_Y
    JR C, .eClampYOk
    LD A, SCREEN_MAX_Y - 1
    JR .eReverseY
.eDeltaYNeg:
    LD A, B
    ADD A, C
    JR C, .eCheckMinY
    LD A, SCREEN_MIN_Y
    JR .eReverseY
.eCheckMinY:
    CP SCREEN_MIN_Y
    JR NC, .eClampYOk
    LD A, SCREEN_MIN_Y
    JR .eReverseY
.eClampYOk:
    LD (IX+ENT_POSY), A
    CALL CheckEnemyCollision
    JR Z, .eYDone
    LD A, (.savedEY)
    LD (IX+ENT_POSY), A
.eReverseY:
    LD A, (IX+ENT_DELTAY)
    NEG
    LD (IX+ENT_DELTAY), A
.eYDone:

    ; --- Animacion ---
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .eAnimDone
    LD A, ENEMY_ANIM_DELAY
    LD (IX+ENT_ANIMTIMER), A
    ; Avanzar frame
    LD A, (IX+ENT_SPRITEID)
    INC A
    LD B, A
    SUB (IX+ENT_ANIMBASE)
    CP 2                        ; 2 frames por enemigo
    JR C, .eFrameOk
    LD B, (IX+ENT_ANIMBASE)     ; Reset
.eFrameOk:
    LD (IX+ENT_SPRITEID), B
.eAnimDone:
    RET

.savedEX: DEFB 0
.savedEY: DEFB 0

; ==============================================================================
; CheckEnemyCollision - Colision enemigo contra fondo (2 puntos, simplificado)
; ==============================================================================
; IX = entidad. Salida: Z=libre, NZ=colision.
; ==============================================================================
CheckEnemyCollision:
    ; Punto 1: esquina sup-izq (X, Y)
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    RET NZ
    ; Punto 2: esquina inf-der (X+13, Y+13)
    LD A, (IX+ENT_POSX)
    ADD A, 13
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 13
    LD C, A
    CALL IsPointBlocked
    RET

; ==============================================================================
; TrySpawnNasty - Intenta crear un nasty en un slot vacio
; ==============================================================================
; Llamado cada frame. Solo spawnea cuando el timer llega a 0.
; ==============================================================================
TrySpawnNasty:
    LD A, (SpawnTimer)
    DEC A
    LD (SpawnTimer), A
    RET NZ

    ; Reset timer
    LD A, SPAWN_INTERVAL
    LD (SpawnTimer), A

    ; Buscar slot vacio en nasties (slots 7-12)
    LD IX, EntityTable + (SLOT_NASTY0 * ENT_SIZE)
    LD B, NUM_NASTIES
.spawnSearch:
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .foundSlot
    LD DE, ENT_SIZE
    ADD IX, DE
    DJNZ .spawnSearch
    RET                         ; No hay slots vacios

.foundSlot:
    ; Elegir tipo de nasty (pseudo-random usando R register)
    LD A, R
    AND $03                     ; 0-3 → 4 tipos de enemigo
    LD L, A
    LD H, 0
    LD DE, NastyTypeTable
    ADD HL, DE
    ; Leer SpriteID base del tipo
    LD A, (HL)

    ; Configurar entidad
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMBASE), A
    LD (IX+ENT_TYPE), TYPE_NASTY
    LD (IX+ENT_STATE), STATE_RUNNING
    LD (IX+ENT_ANIMTIMER), ENEMY_ANIM_DELAY
    LD (IX+ENT_FLAGS), (1 << ENTF_VISIBLE) | (1 << ENTF_DESTRUCT) | (1 << ENTF_NEWSPAWN)

    ; Color segun tipo
    LD A, R
    AND $03
    ADD A, 2                    ; Colores 2-5 (rojo, magenta, verde, cyan)
    OR $40                      ; Bright
    LD (IX+ENT_ATTR), A

    ; Posicion: aleatoria dentro del area de juego (con reintentos)
    LD A, 3
    LD (.spawnTries), A

.spawnRetry:
    ; X aleatorio: 16 .. SCREEN_MAX_X-16 (evitar bordes pegados a muros)
    LD A, R
    AND $F8                     ; Multiplos de 8 (alineado a char)
    ADD A, 16
    CP SCREEN_MAX_X - 16
    JR C, .sXOk
    LD A, 120                   ; Centro si overflow
.sXOk:
    LD (IX+ENT_POSX), A

    ; Y aleatorio: SCREEN_MIN_Y+16 .. SCREEN_MAX_Y-16
    LD A, R
    AND $78                     ; Multiplos de 8, rango 0-120
    ADD A, SCREEN_MIN_Y + 16
    CP SCREEN_MAX_Y - 16
    JR C, .sYOk
    LD A, 88                    ; Centro si overflow
.sYOk:
    LD (IX+ENT_POSY), A

    ; Comprobar colision: 4 esquinas del bounding box (16x14)
    ; Esquina sup-izq (X, Y)
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JR NZ, .spawnBlocked
    ; Esquina sup-der (X+15, Y)
    LD A, (IX+ENT_POSX)
    ADD A, 15
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JR NZ, .spawnBlocked
    ; Esquina inf-izq (X, Y+13)
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 13
    LD C, A
    CALL IsPointBlocked
    JR NZ, .spawnBlocked
    ; Esquina inf-der (X+15, Y+13)
    LD A, (IX+ENT_POSX)
    ADD A, 15
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 13
    LD C, A
    CALL IsPointBlocked
    JR Z, .spawnPosOk
.spawnBlocked:

    ; Reintento
    LD A, (.spawnTries)
    DEC A
    LD (.spawnTries), A
    JR NZ, .spawnRetry

    ; Todos los intentos fallaron → cancelar spawn
    LD (IX+ENT_TYPE), TYPE_NONE
    RET

.spawnTries: DEFB 0

.spawnPosOk:
    ; Velocidades aleatorias (1 o -1 en cada eje)
    LD A, R
    BIT 2, A
    JR Z, .dxPos
    LD A, -ENEMY_SPEED
    JR .setDX
.dxPos:
    LD A, ENEMY_SPEED
.setDX:
    LD (IX+ENT_DELTAX), A
    LD A, R
    BIT 3, A
    JR Z, .dyPos
    LD A, -ENEMY_SPEED
    JR .setDY
.dyPos:
    LD A, ENEMY_SPEED
.setDY:
    LD (IX+ENT_DELTAY), A

    ; Inicializar old pos = pos actual (evitar XOR basura)
    LD A, (IX+ENT_POSX)
    LD (IX+ENT_OLDX), A
    LD (IX+ENT_DRAWX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A

    ; Dir: asignar segun deltas
    LD A, (IX+ENT_DELTAX)
    BIT 7, A
    JR Z, .dirE
    LD A, DIR_W
    JR .dirSet
.dirE:
    LD A, DIR_E
.dirSet:
    LD (IX+ENT_DIR), A
    RET

; --- Tabla de tipos de nasty (SpriteID base) ---
NastyTypeTable:
    DEFB SPRID_ENEMY_0          ; Spider
    DEFB SPRID_ENEMY_1          ; Scorpion
    DEFB SPRID_ENEMY_2          ; Bat
    DEFB SPRID_ENEMY_3          ; Snake

; ==============================================================================
; CheckPlayerEnemyCollision - Colision jugador contra todos los enemigos
; ==============================================================================
; Llamado desde el main loop despues de ProcessEntities.
; Comprueba bounding box overlap entre player y cada enemigo activo.
; ==============================================================================
CheckPlayerEnemyCollision:
    ; NO usar IY — el handler IM 1 del ROM necesita IY=$5C3A.
    ; Leer coords del player desde memoria directa.
    LD IX, EntityTable + (SLOT_IMMORTAL0 * ENT_SIZE)  ; Empezar en slot 1
    LD B, NUM_IMMORTALS + NUM_NASTIES       ; Slots 1-12

.checkLoop:
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .nextEnemy

    ; Comprobar overlap X: |playerX - enemyX| < 14
    LD A, (EntityTable + ENT_POSX)          ; player X
    SUB (IX+ENT_POSX)
    JR NC, .posX
    NEG
.posX:
    CP 14
    JR NC, .nextEnemy

    ; Comprobar overlap Y: |playerY - enemyY| < 14
    LD A, (EntityTable + ENT_POSY)          ; player Y
    SUB (IX+ENT_POSY)
    JR NC, .posY
    NEG
.posY:
    CP 14
    JR NC, .nextEnemy

    ; Colision detectada!
    ; Si player esta atacando y enemigo es destructible → matar enemigo
    LD A, (EntityTable + ENT_STATE)         ; player state
    CP STATE_FIGHTING
    JR NZ, .playerHit

    ; Player atacando → destruir enemigo
    BIT ENTF_DESTRUCT, (IX+ENT_FLAGS)
    JR Z, .playerHit               ; No destructible (immortal)

    ; Matar nasty: limpiar slot
    LD (IX+ENT_TYPE), TYPE_NONE
    JR .nextEnemy

.playerHit:
    ; Enemigo toca al player → flash atributo (feedback visual basico)
    LD A, RED | $40
    LD (EntityTable + ENT_ATTR), A
    JR .nextEnemy

.nextEnemy:
    LD DE, ENT_SIZE
    ADD IX, DE
    DJNZ .checkLoop

    ; Restaurar color del player si no colisiona (vuelve a blanco)
    LD A, (EntityTable + ENT_ATTR)
    CP RED | $40
    RET NZ
    ; Solo restaurar si ya no toca nada (el flash dura 1 frame)
    LD A, WHITE | $40
    LD (EntityTable + ENT_ATTR), A
    RET
