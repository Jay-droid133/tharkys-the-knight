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

    ; Resetear spawn timer (1 = spawnear en el primer frame), round-robin y pending erase
    LD A, 1
    LD (SpawnTimer), A
    XOR A
    LD (EnemyStepIdx), A
    LD (PendingEraseCount), A
    RET

; ==============================================================================
; ProcessPlayer - Procesa player completo: erase + logic + draw (cada frame)
; ==============================================================================
; Fiel a Sabre Wulf: no se separa render de logica. Todo junto tras HALT.
; ==============================================================================
ProcessPlayer:
    LD IX, EntityTable

    ; --- Fresh check ---
    LD A, (ScreenJustRedrawn)
    OR A
    JP NZ, .plFresh
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    JP NZ, .plFresh

    ; --- Logica PRIMERO: actualizar estado, movimiento, animacion ---
    CALL UpdatePlayer
    CALL CalcDrawX

    ; --- Skip si nada cambio (compara DESPUES de logica) ---
    LD A, (IX+ENT_DRAWX)
    CP (IX+ENT_OLDX)
    JR NZ, .plDoErase
    LD A, (IX+ENT_POSY)
    CP (IX+ENT_OLDY)
    JR NZ, .plDoErase
    LD A, (IX+ENT_SPRITEID)
    CP (IX+ENT_OLDSPRID)
    RET Z                               ; Nada cambio → skip todo

.plDoErase:
    ; --- Erase viejo ---
    LD A, (IX+ENT_OLDSPRID)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (OldSprAddr), DE
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    PUSH IX
    LD IX, (OldSprAddr)
    CALL DrawSprite
    POP IX

    ; --- Draw nuevo ---
    CALL GetSpriteAddr
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX

    ; Pintar attr
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
.plSaveOld:
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    RET

    ; --- Primer frame (pantalla recien dibujada): logica + draw, sin erase ---
.plFresh:
    RES ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    CALL UpdatePlayer
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
    JR .plSaveOld

; ==============================================================================
; ProcessEnemies - Round-robin: erase + logic + draw por entidad
; ==============================================================================
; Fiel a Sabre Wulf: cada entidad hace todo junto (erase viejo, AI, draw nuevo).
; Procesa hasta MAX_ENEMIES_PER_FRAME enemigos activos, continuando desde donde
; se quedo el frame anterior. Los no procesados no se mueven ni redibujan.
; ==============================================================================
ProcessEnemies:
    LD A, 0
    LD (.peCount), A
    LD B, NUM_IMMORTALS + NUM_NASTIES

.peLoop:
    PUSH BC

    ; Calcular IX desde EnemyStepIdx
    LD A, (EnemyStepIdx)
    ADD A, SLOT_IMMORTAL0
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; × ENT_SIZE (16)
    LD DE, EntityTable
    ADD HL, DE
    PUSH HL
    POP IX

    ; Avanzar indice round-robin
    LD A, (EnemyStepIdx)
    INC A
    CP NUM_IMMORTALS + NUM_NASTIES
    JR C, .peNoWrap
    XOR A
.peNoWrap:
    LD (EnemyStepIdx), A

    ; Slot activo?
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .peSkip

    ; Checkear NEWSPAWN antes de procesar (se limpia dentro)
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    PUSH AF                             ; Guardar flags (Z=no fresh)

    ; Procesar esta entidad completa (erase + logic + draw)
    CALL ProcessOneEnemy

    ; NEWSPAWN no cuenta contra el budget (solo draw, sin erase = barato)
    POP AF
    JR NZ, .peSkip                      ; Era fresh → no contar

    ; Budget check
    LD A, (.peCount)
    INC A
    LD (.peCount), A
    CP MAX_ENEMIES_PER_FRAME
    JR NC, .peDone

.peSkip:
    POP BC
    DEC B
    JP NZ, .peLoop
    RET

.peDone:
    POP BC
    RET

.peCount: DEFB 0

; ==============================================================================
; ProcessOneEnemy - Procesa un enemigo completo: erase + logic + draw
; ==============================================================================
; IX = entidad activa. Fiel al original: todo junto, sin separar fases.
; ==============================================================================
ProcessOneEnemy:
    ; --- Dispatch segun estado ---
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    JP Z, .peDying
    CP STATE_SPAWNING
    JP Z, .peSpawning

    ; === STATE_RUNNING: logic + skip check + erase + draw ===
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    JP NZ, .peFresh

    ; --- Logica PRIMERO: AI + movimiento + animacion ---
    CALL UpdateEnemy
    CALL CalcDrawX

    ; --- Skip si nada cambio (compara DESPUES de logica) ---
    LD A, (IX+ENT_DRAWX)
    CP (IX+ENT_OLDX)
    JR NZ, .peDoErase
    LD A, (IX+ENT_POSY)
    CP (IX+ENT_OLDY)
    JR NZ, .peDoErase
    LD A, (IX+ENT_SPRITEID)
    CP (IX+ENT_OLDSPRID)
    RET Z                               ; Nada cambio → skip todo

.peDoErase:
    ; --- Erase viejo ---
    LD A, (IX+ENT_OLDSPRID)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (OldSprAddr), DE
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    PUSH IX
    LD IX, (OldSprAddr)
    CALL DrawSprite
    POP IX

    ; --- Draw nuevo ---
    CALL GetSpriteAddr
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX

    ; Pintar attr
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
.peSaveOld:
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    RET

    ; --- Primer frame (recien spawneado): logic + draw, sin erase ---
.peFresh:
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
    JR .peSaveOld

    ; --- DYING: erase + update anim + draw (puff) ---
.peDying:
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    JP NZ, .peDyingFresh

    ; Erase viejo
    LD A, (IX+ENT_OLDSPRID)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (OldSprAddr), DE
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    PUSH IX
    LD IX, (OldSprAddr)
    CALL DrawSprite
    POP IX

    ; Update dying anim
    CALL UpdateDying

    ; Si UpdateDying lo desactivo (TYPE_NONE), no dibujar
    LD A, (IX+ENT_TYPE)
    OR A
    RET Z

    ; Draw nuevo frame puff
    CALL GetSpriteAddr
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX
    JP .peSaveOld

.peDyingFresh:
    RES ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    CALL UpdateDying
    LD A, (IX+ENT_TYPE)
    OR A
    RET Z
    CALL GetSpriteAddr
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX
    JP .peSaveOld

    ; --- SPAWNING: erase + update anim + draw ---
.peSpawning:
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    JP NZ, .peSpawnFresh

    LD A, (IX+ENT_OLDSPRID)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD (OldSprAddr), DE
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    PUSH IX
    LD IX, (OldSprAddr)
    CALL DrawSprite
    POP IX

    CALL UpdateSpawning

    CALL GetSpriteAddr
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX
    JP .peSaveOld

.peSpawnFresh:
    RES ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    CALL UpdateSpawning
    CALL GetSpriteAddr
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX
    JP .peSaveOld

; Variable compartida entre ProcessPlayer y ProcessOneEnemy
OldSprAddr: DEFW 0

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
; GetSpriteDims - Lee dimensiones del sprite desde su cabecera
; ==============================================================================
; Entrada: A = SpriteID
; Salida:  B = ancho en pixels (width_bytes * 8), C = alto en pixels
; Destruye: A, DE, HL
; ==============================================================================
GetSpriteDims:
    LD L, A
    LD H, 0
    ADD HL, HL                  ; × 2 (DEFW entries)
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = puntero a datos del sprite
    LD A, (DE)                  ; width_bytes
    ADD A, A
    ADD A, A
    ADD A, A                    ; × 8 = width_px
    LD B, A
    INC DE
    LD A, (DE)                  ; height_px
    LD C, A
    RET

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

    ; --- Animacion: seleccionar par de frames segun direccion horizontal ---
    ; DELTAX >= 0 → base+0,base+1 (derecha). DELTAX < 0 → base+2,base+3 (izquierda).
    LD A, (IX+ENT_DELTAX)
    LD C, ENEMY_FRAMES_RIGHT    ; C = offset de direccion (0 = derecha)
    BIT 7, A
    JR Z, .eAnimDir
    LD C, ENEMY_FRAMES_LEFT     ; C = 2 (izquierda)
.eAnimDir:
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .eAnimDone
    LD A, ENEMY_ANIM_DELAY
    LD (IX+ENT_ANIMTIMER), A
    ; Avanzar frame dentro del par (2 frames por direccion)
    LD A, (IX+ENT_SPRITEID)
    LD B, A
    SUB (IX+ENT_ANIMBASE)       ; offset absoluto dentro del tipo
    ; Determinar frame dentro del par: si offset AND 1 → reset, sino avanzar
    AND 1
    JR NZ, .eFrameReset
    ; Frame 0 del par → avanzar a frame 1
    INC B
    JR .eFrameSet
.eFrameReset:
    ; Frame 1 del par → volver a frame 0
    DEC B
.eFrameSet:
    LD (IX+ENT_SPRITEID), B
.eAnimDone:
    ; Ajustar sprite al par correcto segun direccion
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)       ; offset actual
    AND 1                       ; preservar frame (0 o 1) dentro del par
    ADD A, (IX+ENT_ANIMBASE)
    ADD A, C                    ; sumar offset de direccion (0 o 2)
    LD (IX+ENT_SPRITEID), A
    RET

.savedEX: DEFB 0
.savedEY: DEFB 0

; ==============================================================================
; UpdateDying - Avanza animacion puff (6 frames), luego programa erase pendiente
; ==============================================================================
; IX = entidad en STATE_DYING. ANIMBASE = SPRID_PUFF.
; Cuando el ultimo frame expira → programa erase pendiente + TYPE_NONE.
; El erase final se ejecutara en EraseDeadSprites del siguiente frame.
; ==============================================================================
UpdateDying:
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .dyAnimDone
    ; Timer expirado → avanzar frame
    LD A, ANIM_DELAY_PUFF
    LD (IX+ENT_ANIMTIMER), A
    LD A, (IX+ENT_SPRITEID)
    INC A
    LD B, A
    SUB (IX+ENT_ANIMBASE)           ; offset dentro de puff
    CP ANIM_FRAMES_PUFF             ; >= 6 → animacion terminada
    JR C, .dyFrameOk
    ; Animacion puff terminada: desactivar entidad
    ; (el erase del ultimo frame ya se hizo en ProcessOneEnemy.peDying)
    LD (IX+ENT_TYPE), TYPE_NONE
    LD (IX+ENT_STATE), STATE_IDLE
    RET
.dyFrameOk:
    LD (IX+ENT_SPRITEID), B
.dyAnimDone:
    RET

; ==============================================================================
; SchedulePendingErase - Agenda un erase pendiente para el siguiente frame
; ==============================================================================
; IX = entidad que necesita erase final. Guarda datos en PendingEraseSlots.
; ==============================================================================
SchedulePendingErase:
    LD A, (PendingEraseCount)
    CP 3
    RET NC                              ; Buffer lleno (no deberia pasar)
    ; Calcular posicion en buffer: count × 5
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; count × 8 (simplificado)
    ; Corregir: count × 5 = count × 4 + count
    LD L, A
    LD H, 0
    LD D, H
    LD E, L
    ADD HL, HL
    ADD HL, HL                          ; count × 4
    ADD HL, DE                          ; count × 5
    LD DE, PendingEraseSlots
    ADD HL, DE
    ; Guardar OLDSPRID, OLDX, OLDY + sprite addr
    LD A, (IX+ENT_OLDSPRID)
    LD (HL), A
    INC HL
    LD A, (IX+ENT_OLDX)
    LD (HL), A
    INC HL
    LD A, (IX+ENT_OLDY)
    LD (HL), A
    INC HL
    ; Resolver sprite addr y guardarla
    LD A, (IX+ENT_OLDSPRID)
    PUSH HL
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                          ; DE = sprite data addr
    POP HL
    LD (HL), E
    INC HL
    LD (HL), D
    ; Incrementar counter
    LD A, (PendingEraseCount)
    INC A
    LD (PendingEraseCount), A
    RET

; ==============================================================================
; EraseDeadSprites - Erase final de entidades cuya puff termino el frame anterior
; ==============================================================================
; Se ejecuta al inicio de la fase render, antes de RenderPlayer.
; Borra los sprites pendientes via XOR y limpia el buffer.
; ==============================================================================
EraseDeadSprites:
    LD A, (PendingEraseCount)
    OR A
    RET Z                               ; Nada pendiente (caso comun)

    LD B, A
    LD HL, PendingEraseSlots

.edLoop:
    PUSH BC
    PUSH HL
    ; Leer datos: OLDSPRID(1), OLDX(1), OLDY(1), SprAddr(2)
    INC HL                              ; skip OLDSPRID (ya resuelto)
    LD E, (HL)                          ; OLDX
    INC HL
    LD D, (HL)                          ; OLDY
    INC HL
    LD A, (HL)
    INC HL
    LD H, (HL)
    LD L, A                             ; HL = sprite data addr
    ; D=Y, E=X para DrawSprite
    PUSH IX
    PUSH HL
    POP IX                              ; IX = sprite data
    CALL DrawSprite
    POP IX

    POP HL
    LD DE, 5
    ADD HL, DE                          ; Siguiente entrada
    POP BC
    DJNZ .edLoop

    ; Limpiar buffer
    XOR A
    LD (PendingEraseCount), A
    RET

; ==============================================================================
; UpdateSpawning - Avanza animacion spawn (6 frames), luego → STATE_RUNNING
; ==============================================================================
; IX = entidad en STATE_SPAWNING. ANIMBASE = SPRID_SPAWN.
; ENT_DIR contiene el ANIMBASE real del enemigo.
; Cuando el ultimo frame expira → restaura sprite real y activa movimiento.
; ==============================================================================
UpdateSpawning:
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .spAnimDone
    ; Timer expirado → avanzar frame
    LD A, ANIM_DELAY_SPAWN
    LD (IX+ENT_ANIMTIMER), A
    LD A, (IX+ENT_SPRITEID)
    INC A
    LD B, A
    SUB (IX+ENT_ANIMBASE)           ; offset dentro de spawn
    CP ANIM_FRAMES_SPAWN            ; >= 6 → animacion terminada
    JR C, .spFrameOk
    ; Spawn terminado: transicionar a STATE_RUNNING
    LD (IX+ENT_STATE), STATE_RUNNING
    LD A, (IX+ENT_DIR)              ; Recuperar ANIMBASE real del enemigo
    LD (IX+ENT_ANIMBASE), A
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMTIMER), ENEMY_ANIM_DELAY
    RET
.spFrameOk:
    LD (IX+ENT_SPRITEID), B
.spAnimDone:
    RET

; ==============================================================================
; CheckEnemyCollision - Colision enemigo contra fondo (2 puntos, simplificado)
; ==============================================================================
; IX = entidad. Salida: Z=libre, NZ=colision.
; ==============================================================================
CheckEnemyCollision:
    ; Obtener dims reales del sprite actual
    LD A, (IX+ENT_SPRITEID)
    CALL GetSpriteDims          ; B=width_px, C=height_px
    LD A, B
    DEC A
    LD (.ecW1), A               ; width_px - 1
    LD A, C
    DEC A
    LD (.ecH1), A               ; height_px - 1

    ; Esquina sup-izq (X, Y)
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    RET NZ
    ; Esquina sup-der (X+W-1, Y)
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.ecW1)
    ADD A, B
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    RET NZ
    ; Esquina inf-izq (X, Y+H-1)
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    LD A, (.ecH1)
    ADD A, C
    LD C, A
    CALL IsPointBlocked
    RET NZ
    ; Esquina inf-der (X+W-1, Y+H-1)
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.ecW1)
    ADD A, B
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    LD A, (.ecH1)
    ADD A, C
    LD C, A
    CALL IsPointBlocked
    RET

.ecW1: DEFB 0
.ecH1: DEFB 0

; ==============================================================================
; TrySpawnNasty - Intenta crear un nasty en un slot vacio
; ==============================================================================
; Llamado cada frame. Solo spawnea cuando el timer llega a 0.
; ==============================================================================
TrySpawnNasty:
    ; Rellenar slots vacios cada frame (respawn inmediato)
    LD IX, EntityTable + (SLOT_NASTY0 * ENT_SIZE)
    LD B, NUM_NASTIES
.spawnLoop:
    PUSH BC
    LD A, (IX+ENT_TYPE)
    OR A
    CALL Z, SpawnOneNasty
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    DJNZ .spawnLoop
    RET

; ==============================================================================
; SpawnOneNasty - Inicializa un nasty en el slot IX
; ==============================================================================
SpawnOneNasty:
    ; Elegir tipo de nasty (pseudo-random usando R register)
    LD A, R
    AND $03                     ; 0-3 → 4 tipos de enemigo
    LD L, A
    LD H, 0
    LD DE, NastyTypeTable
    ADD HL, DE
    LD A, (HL)

    ; Configurar entidad base
    LD (IX+ENT_DIR), A              ; Guardar ANIMBASE real en DIR (temporal)
    LD (IX+ENT_TYPE), TYPE_NASTY
    LD (IX+ENT_STATE), STATE_SPAWNING
    LD (IX+ENT_SPRITEID), SPRID_SPAWN
    LD (IX+ENT_ANIMBASE), SPRID_SPAWN
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_SPAWN
    LD (IX+ENT_FLAGS), (1 << ENTF_VISIBLE) | (1 << ENTF_DESTRUCT) | (1 << ENTF_NEWSPAWN)

    ; Color segun tipo
    LD A, R
    AND $03
    ADD A, 2                    ; Colores 2-5 (rojo, magenta, verde, cyan)
    OR $40                      ; Bright
    LD (IX+ENT_ATTR), A

    ; Obtener dims del sprite real del enemigo (para colision de spawn)
    LD A, (IX+ENT_DIR)          ; ANIMBASE real
    CALL GetSpriteDims          ; B=width_px, C=height_px
    LD A, B
    DEC A
    LD (.spawnW1), A
    LD A, C
    DEC A
    LD (.spawnH1), A

    ; Posicion aleatoria (con reintentos)
    LD A, 3
    LD (.spawnTries), A

.spawnRetry:
    ; Mezclar R con semilla rotante para dispersar posiciones entre spawns
    LD A, (.spawnSeed)
    ADD A, 73                   ; Avanzar semilla (primo, buena dispersion)
    LD (.spawnSeed), A
    LD B, A
    LD A, R
    XOR B                       ; Mezclar semilla con R
    AND $F8                     ; Multiplos de 8
    ADD A, 16
    CP SCREEN_MAX_X - 16
    JR C, .sXOk
    LD A, 120
.sXOk:
    LD (IX+ENT_POSX), A

    LD A, (.spawnSeed)
    ADD A, 47                   ; Segundo avance (otro primo)
    LD (.spawnSeed), A
    LD B, A
    LD A, R
    XOR B
    AND $78
    ADD A, SCREEN_MIN_Y + 16
    CP SCREEN_MAX_Y - 16
    JR C, .sYOk
    LD A, 88
.sYOk:
    LD (IX+ENT_POSY), A

    ; Comprobar colision: 4 esquinas
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JR NZ, .spawnBlocked
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.spawnW1)
    ADD A, B
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JR NZ, .spawnBlocked
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    LD A, (.spawnH1)
    ADD A, C
    LD C, A
    CALL IsPointBlocked
    JR NZ, .spawnBlocked
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.spawnW1)
    ADD A, B
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    LD A, (.spawnH1)
    ADD A, C
    LD C, A
    CALL IsPointBlocked
    JR Z, .spawnPosOk
.spawnBlocked:
    LD A, (.spawnTries)
    DEC A
    LD (.spawnTries), A
    JP NZ, .spawnRetry

    ; Todos los intentos fallaron → cancelar spawn
    LD (IX+ENT_TYPE), TYPE_NONE
    RET

.spawnTries: DEFB 0
.spawnW1:    DEFB 0
.spawnH1:    DEFB 0
.spawnSeed:  DEFB 137            ; Semilla rotante para dispersar posiciones

.spawnPosOk:
    ; Velocidades aleatorias
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

    ; Inicializar old pos = pos actual
    LD A, (IX+ENT_POSX)
    LD (IX+ENT_OLDX), A
    LD (IX+ENT_DRAWX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
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
    ; Obtener dims del player una sola vez
    LD A, (EntityTable + ENT_SPRITEID)
    CALL GetSpriteDims          ; B=playerW, C=playerH
    LD A, B
    LD (.plW), A
    LD A, C
    LD (.plH), A

    LD IX, EntityTable + (SLOT_IMMORTAL0 * ENT_SIZE)  ; Empezar en slot 1
    LD B, NUM_IMMORTALS + NUM_NASTIES       ; Slots 1-12

.checkLoop:
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .nextEnemy

    ; Skip enemigos muriendo o spawneando (no colisionan)
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    JR Z, .nextEnemy
    CP STATE_SPAWNING
    JR Z, .nextEnemy

    ; Obtener dims del enemigo
    PUSH BC                     ; salvar loop counter
    LD A, (IX+ENT_SPRITEID)
    CALL GetSpriteDims          ; B=enemyW, C=enemyH

    ; AABB X: playerX < enemyX + enemyW AND enemyX < playerX + playerW
    LD A, (IX+ENT_POSX)
    ADD A, B                    ; enemyX + enemyW
    JR C, .xCheck2             ; overflow → condicion siempre true
    LD D, A
    LD A, (EntityTable + ENT_POSX)
    CP D
    JR NC, .nextEnemyPop       ; playerX >= enemyX + enemyW → no overlap

.xCheck2:
    LD A, (EntityTable + ENT_POSX)
    LD D, A
    LD A, (.plW)
    ADD A, D                    ; playerX + playerW
    JR C, .yCheck1             ; overflow → condicion siempre true
    LD D, A
    LD A, (IX+ENT_POSX)
    CP D
    JR NC, .nextEnemyPop       ; enemyX >= playerX + playerW → no overlap

.yCheck1:
    ; AABB Y: playerY < enemyY + enemyH AND enemyY < playerY + playerH
    LD A, (IX+ENT_POSY)
    ADD A, C                    ; enemyY + enemyH
    JR C, .yCheck2             ; overflow → condicion siempre true
    LD D, A
    LD A, (EntityTable + ENT_POSY)
    CP D
    JR NC, .nextEnemyPop       ; playerY >= enemyY + enemyH → no overlap

.yCheck2:
    LD A, (EntityTable + ENT_POSY)
    LD D, A
    LD A, (.plH)
    ADD A, D                    ; playerY + playerH
    JR C, .collision           ; overflow → condicion siempre true
    LD D, A
    LD A, (IX+ENT_POSY)
    CP D
    JR NC, .nextEnemyPop       ; enemyY >= playerY + playerH → no overlap

.collision:
    ; Colision detectada!
    ; Si player esta atacando y enemigo es destructible → matar enemigo
    LD A, (EntityTable + ENT_STATE)         ; player state
    CP STATE_FIGHTING
    JR NZ, .playerHit

    ; Player atacando → destruir enemigo
    BIT ENTF_DESTRUCT, (IX+ENT_FLAGS)
    JR Z, .playerHit               ; No destructible (immortal)

    ; Matar nasty: iniciar animacion puff
    LD (IX+ENT_STATE), STATE_DYING
    LD (IX+ENT_ANIMBASE), SPRID_PUFF
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_PUFF
    LD (IX+ENT_DELTAX), 0          ; Parar movimiento
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_ATTR), WHITE | $40  ; Blanco brillante para el puff
    JR .nextEnemyPop

.playerHit:
    ; Enemigo toca al player → flash atributo (feedback visual basico)
    LD A, RED | $40
    LD (EntityTable + ENT_ATTR), A

.nextEnemyPop:
    POP BC                      ; restaurar loop counter
.nextEnemy:
    LD DE, ENT_SIZE
    ADD IX, DE
    DEC B
    JP NZ, .checkLoop

    ; Restaurar color del player si no colisiona (vuelve a blanco)
    LD A, (EntityTable + ENT_ATTR)
    CP RED | $40
    RET NZ
    ; Solo restaurar si ya no toca nada (el flash dura 1 frame)
    LD A, WHITE | $40
    LD (EntityTable + ENT_ATTR), A
    RET

.plW: DEFB 0
.plH: DEFB 0
