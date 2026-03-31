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
    ; Restaurar atributos del fondo en posicion vieja
    LD D, (IX+ENT_OLDY)
    LD E, (IX+ENT_OLDX)
    CALL RestoreOldAttr
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
    LD B, NUM_MONSTERS + NUM_NASTIES

.peLoop:
    PUSH BC

    ; Calcular IX desde EnemyStepIdx
    LD A, (EnemyStepIdx)
    ADD A, SLOT_MONSTER0
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
    CP NUM_MONSTERS + NUM_NASTIES
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
    CP STATE_SCARED
    JP Z, .peScared

    ; === STATE_RUNNING ===
    ; Auto-transicion: nasty + campanadas activas → STATE_SCARED
    LD A, (BellCount)
    OR A
    JR Z, .peRunning
    LD A, (IX+ENT_TYPE)
    CP TYPE_NASTY
    JR NZ, .peRunning
    LD (IX+ENT_STATE), STATE_SCARED
    LD (IX+ENT_DELTAX), 0           ; Forzar recalculo de direccion
    LD (IX+ENT_DELTAY), 0
    JP .peScared
.peRunning:
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    JP NZ, .peFresh

    ; --- Logica: AI + movimiento + animacion ---
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .peNormalAI
    XOR A
    LD (MonsterKbDespawn), A        ; Reset flag
    CALL UpdateMonster
    LD A, (MonsterKbDespawn)
    OR A
    JP NZ, .peScaredDespawn         ; Knockback offscreen → borrar y despawnear
    JR .peCalcAndDraw
.peNormalAI:
    CALL UpdateEnemy

    ; --- Compartido: CalcDraw + skip check + erase + draw + save ---
.peCalcAndDraw:
    CALL CalcDrawX

    ; --- Skip si nada cambio ---
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
    ; Restaurar atributos del fondo en posicion vieja
    LD D, (IX+ENT_OLDY)
    LD E, (IX+ENT_OLDX)
    CALL RestoreOldAttr
    ; --- Draw nuevo ---
    CALL GetSpriteAddr
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX

    ; Pintar attr nuevo
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
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .peFreshNormal
    CALL UpdateMonster
    JR .peFreshDraw
.peFreshNormal:
    CALL UpdateEnemy
.peFreshDraw:
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
    JP .peSaveOld

    ; === STATE_SCARED: huida hacia borde mas cercano ===
.peScared:
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    JP NZ, .peScaredFresh
    ; Reset flag y ejecutar AI de huida
    XOR A
    LD (NastyFleeDespawn), A
    CALL UpdateNastyFlee
    ; Si llego al borde → borrar sprite y despawnear
    LD A, (NastyFleeDespawn)
    OR A
    JP NZ, .peScaredDespawn
    ; Normal: compartir erase+draw con STATE_RUNNING
    JP .peCalcAndDraw

.peScaredFresh:
    RES ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    XOR A
    LD (NastyFleeDespawn), A
    CALL UpdateNastyFlee
    LD A, (NastyFleeDespawn)
    OR A
    JR NZ, .peScaredFreshDespawn
    JP .peFreshDraw

.peScaredDespawn:
    ; Erase viejo (XOR) y desactivar
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
    LD (IX+ENT_TYPE), TYPE_NONE
    LD (IX+ENT_STATE), STATE_IDLE
    RET

.peScaredFreshDespawn:
    LD (IX+ENT_TYPE), TYPE_NONE
    LD (IX+ENT_STATE), STATE_IDLE
    RET

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

    ; Sin input → idle (salvo si ataque en curso)
    LD A, B
    OR C
    JR NZ, .notIdle
    ; Comprobar si ataque sigue activo
    LD A, (AttackTimer)
    OR A
    JR NZ, .attackStillActive
    LD (IX+ENT_STATE), STATE_IDLE
    ; Dir actual = none (bits 0-3), mantener lastHDir (bits 4-7)
    LD A, (IX+ENT_DIR)
    AND $F0                     ; Limpiar dir actual, mantener lastHDir
    LD (IX+ENT_DIR), A
    RET
.attackStillActive:
    ; Ataque en curso sin input de movimiento: decrementar y mantener fighting
    DEC A
    LD (AttackTimer), A
    LD (IX+ENT_STATE), STATE_FIGHTING
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

    ; --- Attack timer: una pulsacion = ciclo completo de animacion ---
    LD A, (AttackTimer)
    OR A
    JR Z, .noActiveAttack
    ; Ataque en curso: decrementar timer
    DEC A
    LD (AttackTimer), A
    LD (IX+ENT_STATE), STATE_FIGHTING
    RET
.noActiveAttack:
    ; No hay ataque activo: comprobar si SPACE inicia uno nuevo
    LD A, (InputFire)
    OR A
    JR Z, .running
    ; Iniciar nuevo ataque: timer = ANIM_FRAMES_FIGHT * ANIM_DELAY_FIGHT
    LD A, ANIM_FRAMES_FIGHT * ANIM_DELAY_FIGHT
    LD (AttackTimer), A
    ; Limpiar marcas de golpe (nuevo ciclo de ataque)
    XOR A
    LD (MonsterHitThisAttack), A
    LD (MonsterHitThisAttack+1), A
    LD (MonsterHitThisAttack+2), A
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
    ; Check colision X (paredes)
    CALL CheckEntityCollision
    JR NZ, .revertX
    ; Check colision X (monsters) - cuerpo solido, espada puede solapar
    CALL CheckPlayerMonsterOverlap
    JR Z, .xOk                 ; No overlap → ok
    ; Hay overlap: comprobar si ya existia antes del movimiento
    LD A, (IX+ENT_POSX)
    LD (.tmpNewX), A
    LD A, (.savedX)
    LD (IX+ENT_POSX), A        ; Temporalmente volver a pos vieja
    CALL CheckPlayerMonsterOverlap
    PUSH AF
    LD A, (.tmpNewX)
    LD (IX+ENT_POSX), A        ; Restaurar pos nueva
    POP AF
    JR NZ, .xOk                ; Ya solapaba antes → permitir (escape)
.revertX:
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
    ; Check colision Y (paredes)
    CALL CheckEntityCollision
    JR NZ, .revertY
    ; Check colision Y (monsters)
    CALL CheckPlayerMonsterOverlap
    JR Z, .yOk
    ; Overlap: comprobar si ya existia antes del movimiento
    LD A, (IX+ENT_POSY)
    LD (.tmpNewY), A
    LD A, (.savedY)
    LD (IX+ENT_POSY), A
    CALL CheckPlayerMonsterOverlap
    PUSH AF
    LD A, (.tmpNewY)
    LD (IX+ENT_POSY), A
    POP AF
    JR NZ, .yOk                ; Ya solapaba → permitir (escape)
.revertY:
    LD A, (.savedY)
    LD (IX+ENT_POSY), A        ; Revertir Y
.yOk:
    RET

.speed:  DEFB 0
.savedX: DEFB 0
.savedY: DEFB 0
.tmpNewX: DEFB 0
.tmpNewY: DEFB 0

; ==============================================================================
; CheckPlayerMonsterOverlap - Bloquear player contra monsters (colision solida)
; ==============================================================================
; IX = player entity. Comprueba AABB con todos los monsters activos.
; Usa GetSpriteDims para dimensiones reales (soporta monsters de cualquier tamaño).
; Retorna Z=libre, NZ=bloqueado por algun monster.
; ==============================================================================
CheckPlayerMonsterOverlap:
    ; Guardar IX (player)
    PUSH IX
    ; Siempre usar ancho de CUERPO (16px), no espada (24px)
    ; Asi la espada puede solapar pero el cuerpo no
    LD A, 16
    LD (.cpmoPlW), A
    LD A, 21                            ; Altura player fija
    LD (.cpmoPlH), A
    ; Player pos
    POP IX
    PUSH IX
    LD A, (IX+ENT_POSX)
    LD (.cpmoPlX), A
    LD A, (IX+ENT_POSY)
    LD (.cpmoPlY), A

    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
.cpmoLoop:
    PUSH BC
    ; Solo monsters activos, no muriendo/spawneando, no stunned
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .cpmoNext
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    JR Z, .cpmoNext
    CP STATE_SPAWNING
    JR Z, .cpmoNext

    ; Obtener dims del monster
    LD A, (IX+ENT_SPRITEID)
    CALL GetSpriteDims                 ; B=monW, C=monH

    ; AABB: playerX < monX + monW AND monX < playerX + plW
    LD A, (IX+ENT_POSX)
    ADD A, B                           ; monX + monW
    JR C, .cpmoXCheck2                 ; overflow → siempre true
    LD D, A
    LD A, (.cpmoPlX)
    CP D
    JR NC, .cpmoNext                   ; playerX >= monX + monW → no overlap
.cpmoXCheck2:
    LD A, (.cpmoPlX)
    LD D, A
    LD A, (.cpmoPlW)
    ADD A, D                           ; playerX + plW
    JR C, .cpmoYCheck1
    LD D, A
    LD A, (IX+ENT_POSX)
    CP D
    JR NC, .cpmoNext                   ; monX >= playerX + plW → no overlap
.cpmoYCheck1:
    ; AABB Y: playerY < monY + monH AND monY < playerY + plH
    LD A, (IX+ENT_POSY)
    ADD A, C                           ; monY + monH
    JR C, .cpmoYCheck2
    LD D, A
    LD A, (.cpmoPlY)
    CP D
    JR NC, .cpmoNext                   ; playerY >= monY + monH → no overlap
.cpmoYCheck2:
    LD A, (.cpmoPlY)
    LD D, A
    LD A, (.cpmoPlH)
    ADD A, D                           ; playerY + plH
    JR C, .cpmoHit
    LD D, A
    LD A, (IX+ENT_POSY)
    CP D
    JR NC, .cpmoNext                   ; monY >= playerY + plH → no overlap
.cpmoHit:
    ; Overlap! Bloqueado
    POP BC
    POP IX
    OR 1                               ; NZ = bloqueado
    RET
.cpmoNext:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    DJNZ .cpmoLoop
    ; Ningun overlap
    POP IX
    XOR A                              ; Z = libre
    RET

.cpmoPlX:  DEFB 0
.cpmoPlY:  DEFB 0
.cpmoPlW:  DEFB 0
.cpmoPlH:  DEFB 0

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
    ; Si es animacion de ataque → SFX al inicio del primer swing
    LD A, D
    CP SPRID_ATTACK_EAST
    JR Z, .newAnimAttackSfx
    CP SPRID_ATTACK_WEST
    JR NZ, .newAnimNoSfx
.newAnimAttackSfx:
    PUSH BC
    PUSH DE
    LD HL, SFX_Attack
    CALL PlaySFX
    POP DE
    POP BC
.newAnimNoSfx:
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

    ; Paso: si el player esta corriendo, reproducir SFX cada 2 frames de anim
    LD A, (IX+ENT_STATE)
    CP STATE_RUNNING
    JR NZ, .noFootstep
    LD A, (FootstepToggle)
    XOR 1
    LD (FootstepToggle), A
    JR Z, .noFootstep
    PUSH BC
    PUSH DE
    LD HL, SFX_Footstep
    CALL PlaySFX
    POP DE
    POP BC
.noFootstep:

    LD A, (IX+ENT_SPRITEID)
    INC A
    ; ¿Fuera de rango?
    LD B, A                     ; B = nuevo SpriteID
    SUB D                       ; A = frame relativo (nuevo - animBase)
    CP E                        ; ¿>= num_frames?
    JR C, .frameOk
    LD B, D                     ; Reset al AnimBase
    ; Si es animacion de ataque → SFX en cada reinicio del ciclo
    LD A, D
    CP SPRID_ATTACK_EAST
    JR Z, .wrapAttackSfx
    CP SPRID_ATTACK_WEST
    JR NZ, .frameOk
.wrapAttackSfx:
    PUSH BC
    PUSH DE
    LD HL, SFX_Attack
    CALL PlaySFX
    POP DE
    POP BC
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
; UpdateMonster - AI de persecucion lenta, erratica, con evasion de obstaculos
; ==============================================================================
; IX = entidad TYPE_MONSTER en STATE_RUNNING.
; Persigue al player lenta e inexorablemente (MONSTER_SPEED=1).
; 25% de frames no se mueve (erraticidad). Rodea BG sprites.
; Persistencia: mantiene direccion mientras sea pasable y acerque al player.
; ==============================================================================
UpdateMonster:
    ; --- Stun: knockback + pausa tras golpe del player ---
    LD A, (IX+ENT_DIR)              ; ENT_DIR = stun counter (0=normal)
    OR A
    JP Z, .moNormal
    DEC (IX+ENT_DIR)
    JR NZ, .moStunActive
    ; Stun terminado: comprobar si el monster debe morir (5+ golpes)
    LD A, (IX+ENT_FLAGS)
    AND $F0
    CP MONSTER_MAX_HITS * 16            ; 5 * 16 = $50
    JR NC, .moStartDying
    ; Sigue vivo: limpiar deltas para forzar recalculo de persecucion
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    JP .moNormal

.moStartDying:
    ; Monster muere! Iniciar animacion puff
    LD (IX+ENT_STATE), STATE_DYING
    LD (IX+ENT_ANIMBASE), SPRID_PUFF
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_PUFF
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_DIR), 0                  ; Limpiar para forzar respawn random
    LD (IX+ENT_ATTR), WHITE | $40       ; Blanco brillante para puff
    RET

.moStunActive:
    ; Fase knockback: timer >= PAUSE → moverse con deltas invertidos
    CP MONSTER_STUN_PAUSE
    JP C, .moAnimate                ; Fase pausa: no moverse, solo animar
    ; Knockback: aplicar movimiento con collision check
    LD D, (IX+ENT_DELTAX)
    LD E, (IX+ENT_DELTAY)
    LD A, D
    OR E
    JP Z, .moAnimate
    ; --- Comprobar si el knockback choca con algo ---
    ; Primero: colision con fondo (paredes)
    PUSH DE
    LD A, (IX+ENT_POSX)
    LD (.moSvX), A
    LD A, (IX+ENT_POSY)
    LD (.moSvY), A
    LD A, (IX+ENT_POSX)
    ADD A, D
    LD (IX+ENT_POSX), A
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    CALL CheckEnemyCollision
    JP NZ, .moKbWallBlock               ; Bloqueado por pared
    ; Pared libre: comprobar impacto con otro monster (billar)
    CALL .moCheckOverlap
    JR NZ, .moKbBilliard                ; Impacto! → transferir fuerza
    ; Libre: restaurar pos y aplicar movimiento
    LD A, (.moSvX)
    LD (IX+ENT_POSX), A
    LD A, (.moSvY)
    LD (IX+ENT_POSY), A
    POP DE
    JP .moKbApply
.moKbBilliard:
    ; Billar: A para en su sitio, B hereda la fuerza
    LD A, (.moSvX)
    LD (IX+ENT_POSX), A
    LD A, (.moSvY)
    LD (IX+ENT_POSY), A
    POP DE
    ; Transferir knockback al monster impactado
    PUSH IX
    LD IX, (.moHitMonster)
    ; Solo transferir si no esta ya en stun
    LD A, (IX+ENT_DIR)
    OR A
    JR NZ, .moKbBilliardDone
    ; B hereda misma direccion pero fuerza reducida (billar secundario)
    LD A, D
    OR A
    JR Z, .moBillNoX
    BIT 7, D
    JR NZ, .moBillXNeg
    LD A, MONSTER_KB_SPEED - 1           ; 3px (entre 2 y 4)
    JR .moBillSetX
.moBillXNeg:
    LD A, -(MONSTER_KB_SPEED - 1)
.moBillSetX:
    LD (IX+ENT_DELTAX), A
.moBillNoX:
    LD A, E
    OR A
    JR Z, .moBillNoY
    BIT 7, E
    JR NZ, .moBillYNeg
    LD A, MONSTER_KB_SPEED - 1
    JR .moBillSetY
.moBillYNeg:
    LD A, -(MONSTER_KB_SPEED - 1)
.moBillSetY:
    LD (IX+ENT_DELTAY), A
.moBillNoY:
    LD (IX+ENT_DIR), MONSTER_STUN_PAUSE + 6  ; 18 frames: 6 de knockback + 12 de pausa
.moKbBilliardDone:
    POP IX
    ; A continua con fuerza reducida (no para del todo)
    ; Reducir velocidad de A a la mitad
    LD A, (IX+ENT_DELTAX)
    SRA A                               ; /2 con signo
    LD (IX+ENT_DELTAX), A
    LD D, A
    LD A, (IX+ENT_DELTAY)
    SRA A
    LD (IX+ENT_DELTAY), A
    LD E, A
    ; Reducir stun restante de A
    LD A, (IX+ENT_DIR)
    CP MONSTER_STUN_PAUSE + 2
    JP C, .moStunStop                   ; Casi sin stun → parar
    SUB 4                               ; Quitar 4 frames de knockback
    LD (IX+ENT_DIR), A
    ; Aplicar movimiento reducido de A
    LD A, (.moSvX)
    LD (IX+ENT_POSX), A
    LD A, (.moSvY)
    LD (IX+ENT_POSY), A
    JP .moKbApply
.moKbWallBlock:
    ; Bloqueado por pared: restaurar pos, intentar slide por eje individual
    LD A, (.moSvX)
    LD (IX+ENT_POSX), A
    LD A, (.moSvY)
    LD (IX+ENT_POSY), A
    POP DE
    ; Intentar solo eje X (mantener direccion del golpe)
    LD A, D
    OR A
    JR Z, .moKbSlideY                   ; Sin deltaX → probar Y directamente
    PUSH DE
    LD E, 0
    CALL .moTryPassable
    POP DE
    JR NZ, .moKbSlideY
    ; Slide en X funciona
    LD E, 0
    LD (IX+ENT_DELTAY), 0
    JP .moKbApply
.moKbSlideY:
    ; Intentar solo eje Y (mantener direccion del golpe)
    LD A, E
    OR A
    JR Z, .moKbSlideStop                ; Sin deltaY → todo bloqueado
    PUSH DE
    LD D, 0
    CALL .moTryPassable
    POP DE
    JR NZ, .moKbSlideStop
    ; Slide en Y funciona
    LD D, 0
    LD (IX+ENT_DELTAX), 0
    JP .moKbApply
.moKbSlideStop:
    JP .moStunStop
    ; (moKbMonsterHit eliminado - reemplazado por moKbBilliard arriba)
.moKbApply:
    LD A, (IX+ENT_POSX)
    ADD A, D
    LD (IX+ENT_POSX), A
    ; Comprobar bordes X
    CP SCREEN_MAX_X
    JR NC, .moKbOffscreen               ; Derecha o underflow pasado izquierda
    ; Borde izquierdo: si X < KB_SPEED y empujando a la izquierda
    CP MONSTER_KB_SPEED
    JR NC, .moKbXOk
    BIT 7, D                            ; Delta X negativo?
    JR NZ, .moKbOffscreen               ; Si, empujando izquierda → offscreen
.moKbXOk:
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    ; Comprobar bordes Y
    CP SCREEN_MAX_Y
    JR NC, .moKbOffscreen               ; Pasado borde inferior
    ; Borde superior: si Y < MIN+KB_SPEED y empujando arriba
    CP SCREEN_MIN_Y + MONSTER_KB_SPEED
    JR NC, .moKbYOk
    BIT 7, E                            ; Delta Y negativo?
    JR NZ, .moKbOffscreen               ; Si, empujando arriba → offscreen
.moKbYOk:
    JP .moAnimate
.moKbOffscreen:
    ; Determinar que eje salio de pantalla y clampear SOLO ese eje
    ; (el otro eje mantiene su posicion valida del gameplay)
    LD A, (IX+ENT_POSX)
    CP SCREEN_MAX_X
    JR NC, .moKbExitX                   ; X >= MAX (derecha o underflow izquierda)
    ; Proximidad izquierda: X < KB_SPEED y empujando izquierda
    CP MONSTER_KB_SPEED
    JR NC, .moKbNotLeftExit
    LD A, (IX+ENT_DELTAX)
    BIT 7, A
    JR NZ, .moKbExitX                   ; Empujando izquierda → salida por X
.moKbNotLeftExit:
    ; X valido → salio por Y
    LD A, (IX+ENT_DELTAY)
    BIT 7, A
    JR NZ, .moKbExitTop
    LD (IX+ENT_POSY), SCREEN_MAX_Y - 1 ; Salio por abajo
    LD A, DIR_S
    JR .moKbClampDone
.moKbExitTop:
    LD (IX+ENT_POSY), SCREEN_MIN_Y     ; Salio por arriba
    LD A, DIR_N
    JR .moKbClampDone
.moKbExitX:
    ; Salio por X → clampear X, mantener Y
    LD A, (IX+ENT_DELTAX)
    BIT 7, A
    JR NZ, .moKbExitLeft
    LD (IX+ENT_POSX), SCREEN_MAX_X - 1 ; Salio por la derecha
    LD A, DIR_E
    JR .moKbClampDone
.moKbExitLeft:
    LD (IX+ENT_POSX), 0                ; Salio por la izquierda
    LD A, DIR_W
.moKbClampDone:
    ; Guardar direccion de salida en B (A se necesita para check letal)
    LD B, A
    ; Si golpe letal (5+ hits), morir con puff en el borde en vez de salir
    LD A, (IX+ENT_FLAGS)
    AND $F0
    CP MONSTER_MAX_HITS * 16
    JR NC, .moKbLethal
    ; No letal: guardar direccion y despawnear normalmente
    LD A, B
    JR .moKbNotLethal
.moKbLethal:
    JP .moStartDying

.moKbNotLethal:
    ; Guardar direccion de salida en ENT_DIR (para tracking cross-room)
    LD (IX+ENT_DIR), A
    ; Señalizar despawn para que ProcessOneEnemy borre el sprite
    LD A, 1
    LD (MonsterKbDespawn), A
    ; Iniciar cooldown de respawn
    LD A, MONSTER_RESPAWN_DELAY
    LD (TryRespawnMonsters.rmTimer), A
    RET
.moStunStop:
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    JP .moAnimate

.moNormal:
    ; --- Escape de wall: si estamos dentro de un BG sprite, empujar fuera ---
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JR Z, .moNotInWall
    ; Dentro de wall! Mover hacia el player para escapar
    LD A, (EntityTable + ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSX)
    CP B
    JR NC, .moWallLeft
    ADD A, 2                            ; Player a la derecha → mover derecha
    JR .moWallSetX
.moWallLeft:
    SUB 2                               ; Player a la izquierda → mover izquierda
.moWallSetX:
    LD (IX+ENT_POSX), A
    LD A, (EntityTable + ENT_POSY)
    LD B, A
    LD A, (IX+ENT_POSY)
    CP B
    JR NC, .moWallUp
    ADD A, 2                            ; Player abajo → mover abajo
    JR .moWallSetY
.moWallUp:
    SUB 2                               ; Player arriba → mover arriba
.moWallSetY:
    LD (IX+ENT_POSY), A
    JP .moAnimate                       ; Solo animar este frame, seguir escapando el siguiente

.moNotInWall:
    ; --- Erraticidad: 25% chance de no moverse ---
    LD A, R
    AND $03
    JR NZ, .moDoMove
    ; Skip movimiento → solo animar
    JP .moAnimate

.moDoMove:
    ; --- Posicion del player ---
    LD A, (EntityTable + ENT_POSX)
    LD (.moPX), A
    LD A, (EntityTable + ENT_POSY)
    LD (.moPY), A

    ; --- Persistencia: intentar continuar direccion actual ---
    LD D, (IX+ENT_DELTAX)
    LD E, (IX+ENT_DELTAY)
    LD A, D
    OR E
    JR Z, .moRecalc                     ; Sin direccion → recalcular
    CALL .moTryPassable
    JR NZ, .moRecalc                    ; Bloqueado → recalcular
    ; Pasable: comprobar que sigue acercando al player
    LD A, D
    OR A
    JR Z, .moChkPersistY
    BIT 7, D
    JR NZ, .moChkPersistLeft
    ; Moviendo derecha: ok si playerX >= monsterX
    LD A, (.moPX)
    CP (IX+ENT_POSX)
    JP NC, .moApply
    JP .moRecalc
.moChkPersistLeft:
    ; Moviendo izquierda: ok si playerX <= monsterX
    LD B, A                             ; save
    LD A, (.moPX)
    LD B, A
    LD A, (IX+ENT_POSX)
    CP B
    JP NC, .moApply
    JP .moRecalc
.moChkPersistY:
    BIT 7, E
    JR NZ, .moChkPersistUp
    ; Moviendo abajo: ok si playerY >= monsterY
    LD A, (.moPY)
    CP (IX+ENT_POSY)
    JP NC, .moApply
    JP .moRecalc
.moChkPersistUp:
    ; Moviendo arriba: ok si playerY <= monsterY
    LD A, (.moPY)
    LD B, A
    LD A, (IX+ENT_POSY)
    CP B
    JP NC, .moApply
    ; Ya no acerca → recalcular

.moRecalc:
    ; --- Calcular direccion al player ---
    ; Delta X: sign(playerX - monsterX)
    LD A, (.moPX)
    SUB (IX+ENT_POSX)                  ; A = playerX - monsterX
    JR Z, .moNoDx
    LD A, MONSTER_SPEED
    JR NC, .moDxDone                    ; playerX > monsterX → +speed
    LD A, -MONSTER_SPEED                ; playerX < monsterX → -speed
    JR .moDxDone
.moNoDx:
    XOR A                               ; Mismo X → no mover en X
.moDxDone:
    LD (.moHDx), A

    ; Delta Y: sign(playerY - monsterY)
    LD A, (.moPY)
    SUB (IX+ENT_POSY)                  ; A = playerY - monsterY
    JR Z, .moNoDy
    LD A, MONSTER_SPEED
    JR NC, .moDyDone                    ; playerY > monsterY → +speed
    LD A, -MONSTER_SPEED
    JR .moDyDone
.moNoDy:
    XOR A
.moDyDone:
    LD (.moVDy), A

    ; --- Eje primario: mayor diferencia absoluta ---
    LD A, (.moPX)
    SUB (IX+ENT_POSX)
    JR NC, .moAbsDxOk
    NEG
.moAbsDxOk:
    LD B, A                             ; B = |dx|
    LD A, (.moPY)
    SUB (IX+ENT_POSY)
    JR NC, .moAbsDyOk
    NEG
.moAbsDyOk:
    ; A = |dy|, B = |dx|
    CP B
    JR NC, .moVertPrim                  ; |dy| >= |dx| → vertical primario

    ; --- Horizontal primario ---
    ; Candidatos: (hDx,0), (0,vDy), (0,-vDy), (-hDx,0)
    LD HL, .moCandidates
    LD A, (.moHDx)
    LD (HL), A                          ; c0.dx = hDx
    INC HL
    XOR A
    LD (HL), A                          ; c0.dy = 0
    INC HL
    LD (HL), A                          ; c1.dx = 0
    INC HL
    LD A, (.moVDy)
    LD (HL), A                          ; c1.dy = vDy
    INC HL
    XOR A
    LD (HL), A                          ; c2.dx = 0
    INC HL
    LD A, (.moVDy)
    NEG
    LD (HL), A                          ; c2.dy = -vDy (rodear)
    INC HL
    LD A, (.moHDx)
    NEG
    LD (HL), A                          ; c3.dx = -hDx (backtrack)
    INC HL
    XOR A
    LD (HL), A                          ; c3.dy = 0
    JR .moTryCandidates

.moVertPrim:
    ; --- Vertical primario ---
    ; Candidatos: (0,vDy), (hDx,0), (-hDx,0), (0,-vDy)
    LD HL, .moCandidates
    XOR A
    LD (HL), A                          ; c0.dx = 0
    INC HL
    LD A, (.moVDy)
    LD (HL), A                          ; c0.dy = vDy
    INC HL
    LD A, (.moHDx)
    LD (HL), A                          ; c1.dx = hDx
    INC HL
    XOR A
    LD (HL), A                          ; c1.dy = 0
    INC HL
    LD A, (.moHDx)
    NEG
    LD (HL), A                          ; c2.dx = -hDx (rodear)
    INC HL
    XOR A
    LD (HL), A                          ; c2.dy = 0
    INC HL
    LD (HL), A                          ; c3.dx = 0
    INC HL
    LD A, (.moVDy)
    NEG
    LD (HL), A                          ; c3.dy = -vDy (backtrack)

.moTryCandidates:
    ; --- Probar 4 candidatos ---
    LD HL, .moCandidates
    LD B, 4
.moLoop:
    LD D, (HL)
    INC HL
    LD E, (HL)
    INC HL
    ; Skip candidatos con delta 0,0 (player en misma linea en un eje)
    LD A, D
    OR E
    JR Z, .moLoopSkip
    PUSH HL
    PUSH BC
    CALL .moTryPassable
    POP BC
    POP HL
    JR Z, .moApply
.moLoopSkip:
    DJNZ .moLoop
    ; Todo bloqueado: no moverse
    JP .moAnimate

.moApply:
    ; D = deltaX, E = deltaY
    LD (IX+ENT_DELTAX), D
    LD (IX+ENT_DELTAY), E
    ; Aplicar movimiento
    LD A, (IX+ENT_POSX)
    ADD A, D
    LD (IX+ENT_POSX), A
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    ; Clamp X a limites de pantalla (estricto)
    LD A, (IX+ENT_POSX)
    CP SCREEN_MAX_X
    JR C, .moXOk
    LD A, SCREEN_MAX_X - 1
    LD (IX+ENT_POSX), A
.moXOk:
    ; Clamp Y suave: permite rango extendido 0-199 para clipping de entrada
    LD A, (IX+ENT_POSY)
    CP 200
    JR C, .moYOk
    ; Y >= 200: underflow (fue al negativo) → clampear a 0
    XOR A
    LD (IX+ENT_POSY), A
.moYOk:

.moAnimate:
    ; --- Animacion (misma logica que UpdateEnemy) ---
    LD A, (IX+ENT_DELTAX)
    LD C, ENEMY_FRAMES_RIGHT
    BIT 7, A
    JR Z, .moAnimDir
    LD C, ENEMY_FRAMES_LEFT
.moAnimDir:
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .moAnimDone
    LD A, ENEMY_ANIM_DELAY
    LD (IX+ENT_ANIMTIMER), A
    LD A, (IX+ENT_SPRITEID)
    LD B, A
    SUB (IX+ENT_ANIMBASE)
    AND 1
    JR NZ, .moFrameReset
    INC B
    JR .moFrameSet
.moFrameReset:
    DEC B
.moFrameSet:
    LD (IX+ENT_SPRITEID), B
.moAnimDone:
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)
    AND 1
    ADD A, (IX+ENT_ANIMBASE)
    ADD A, C
    LD (IX+ENT_SPRITEID), A
    RET

; --- Subrutina: comprobar pasabilidad + no solaparse con otros monsters ---
; D=deltaX, E=deltaY. Retorna Z=pasable, NZ=bloqueado. Preserva D,E.
.moTryPassable:
    PUSH DE
    ; Guardar posicion actual
    LD A, (IX+ENT_POSX)
    LD (.moSvX), A
    LD A, (IX+ENT_POSY)
    LD (.moSvY), A
    ; Posicion de test
    LD A, (IX+ENT_POSX)
    ADD A, D
    LD (IX+ENT_POSX), A
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    ; Check colision con fondo
    CALL CheckEnemyCollision
    JR NZ, .moPassRestore               ; Bloqueado por fondo
    ; Check solapamiento con otros monsters
    CALL .moCheckOverlap
    JR NZ, .moPassRestore               ; Bloqueado por otro monster
    ; Check solapamiento con player
    CALL .moCheckPlayerOverlap
.moPassRestore:
    ; Restaurar posicion (preservar flags)
    PUSH AF
    LD A, (.moSvX)
    LD (IX+ENT_POSX), A
    LD A, (.moSvY)
    LD (IX+ENT_POSY), A
    POP AF
    POP DE
    RET

; --- Subrutina: comprobar solapamiento con otros monsters ---
; IX = monster actual (con posicion de test ya aplicada).
; Retorna Z=no solapa, NZ=solapa con otro monster.
; Compara AABB: overlap si |thisX - otherX| < 16 AND |thisY - otherY| < 16.
.moCheckOverlap:
    PUSH IX
    ; Guardar posicion de test
    LD A, (IX+ENT_POSX)
    LD (.moTestX), A
    LD A, (IX+ENT_POSY)
    LD (.moTestY), A
    ; Calcular direccion del slot actual para comparar
    PUSH IX
    POP HL                              ; HL = direccion del monster actual
    LD (.moSelfAddr), HL
    ; Iterar los slots de monsters
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
.moOvLoop:
    ; Saltar si es el mismo slot
    PUSH IX
    POP HL
    LD DE, (.moSelfAddr)
    OR A                                ; Clear carry
    SBC HL, DE
    JP Z, .moOvNext                     ; Mismo slot → skip
    ; Saltar si slot vacio
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .moOvNext
    ; Primero: ya solapan en posicion original?
    ; Si si, solo permitir si el movimiento SEPARA (aumenta distancia)
    LD A, (.moSvX)
    SUB (IX+ENT_POSX)
    JR NC, .moOvCurAbsX
    NEG
.moOvCurAbsX:
    CP 16
    JR NC, .moOvNotCurrent              ; No solapan actualmente → comprobar test pos
    LD A, (.moSvY)
    SUB (IX+ENT_POSY)
    JR NC, .moOvCurAbsY
    NEG
.moOvCurAbsY:
    CP 16
    JR NC, .moOvNotCurrent              ; No solapan actualmente
    ; YA solapan → comparar distancias: solo permitir si se separan
    ; Dist actual = |svX - otherX| + |svY - otherY|
    LD A, (.moSvX)
    SUB (IX+ENT_POSX)
    JR NC, .moOvDcX
    NEG
.moOvDcX:
    LD D, A                             ; D = |svX - otherX|
    LD A, (.moSvY)
    SUB (IX+ENT_POSY)
    JR NC, .moOvDcY
    NEG
.moOvDcY:
    ADD A, D                            ; A = dist actual (manhattan)
    LD D, A                             ; D = dist actual
    ; Dist test = |testX - otherX| + |testY - otherY|
    LD A, (.moTestX)
    SUB (IX+ENT_POSX)
    JR NC, .moOvDtX
    NEG
.moOvDtX:
    LD E, A                             ; E = |testX - otherX|
    LD A, (.moTestY)
    SUB (IX+ENT_POSY)
    JR NC, .moOvDtY
    NEG
.moOvDtY:
    ADD A, E                            ; A = dist test
    CP D
    JR NC, .moOvNext                    ; dist test >= dist actual → se separan → ok
    ; Se acercan o igual → bloquear (NZ ya esta por CP)
    ; Guardar hit monster y reportar solapamiento
    PUSH IX
    POP HL
    LD (.moHitMonster), HL
    POP IX
    OR 1
    RET
.moOvNotCurrent:
    ; AABB test pos: |testX - otherX| < 16
    LD A, (.moTestX)
    SUB (IX+ENT_POSX)
    JR NC, .moOvAbsX
    NEG
.moOvAbsX:
    CP 16
    JR NC, .moOvNext                    ; No solaparia en X
    ; |testY - otherY| < 16
    LD A, (.moTestY)
    SUB (IX+ENT_POSY)
    JR NC, .moOvAbsY
    NEG
.moOvAbsY:
    CP 16
    JR NC, .moOvNext                    ; No solapa en Y
    ; Solapa! Guardar direccion del monster con el que chocamos
    PUSH IX
    POP HL
    LD (.moHitMonster), HL
    POP IX
    OR 1                                ; NZ = solapa
    RET
.moOvNext:
    LD DE, ENT_SIZE
    ADD IX, DE
    DEC B
    JP NZ, .moOvLoop
    ; Ningun solapamiento
    POP IX
    XOR A                               ; Z = ok
    RET

; --- Subrutina: comprobar solapamiento con el player ---
; IX = monster (con posicion de test). Retorna Z=libre, NZ=bloqueado.
.moCheckPlayerOverlap:
    ; Obtener dims del monster actual
    LD A, (IX+ENT_SPRITEID)
    CALL GetSpriteDims                  ; B=monW, C=monH
    ; AABB: monX < playerX + playerW AND playerX < monX + monW
    LD A, (EntityTable + ENT_POSX)
    LD D, A                             ; D = playerX
    ; playerX + playerW (asumimos 16px, se puede refinar con GetSpriteDims)
    ADD A, 16
    JR C, .moCpXCheck2                  ; overflow
    LD E, A                             ; E = playerX + 16
    LD A, (IX+ENT_POSX)
    CP E
    JR NC, .moCpOk                      ; monX >= playerX + 16 → no overlap
.moCpXCheck2:
    LD A, (IX+ENT_POSX)
    ADD A, B                            ; monX + monW
    JR C, .moCpYCheck1
    LD E, A
    LD A, D                             ; playerX
    CP E
    JR NC, .moCpOk                      ; playerX >= monX + monW → no overlap
.moCpYCheck1:
    ; AABB Y
    LD A, (EntityTable + ENT_POSY)
    LD D, A                             ; D = playerY
    ADD A, 21                           ; playerH (21px)
    JR C, .moCpYCheck2
    LD E, A
    LD A, (IX+ENT_POSY)
    CP E
    JR NC, .moCpOk                      ; monY >= playerY + 21 → no overlap
.moCpYCheck2:
    LD A, (IX+ENT_POSY)
    ADD A, C                            ; monY + monH
    JR C, .moCpBlocked
    LD E, A
    LD A, D
    CP E
    JR NC, .moCpOk                      ; playerY >= monY + monH → no overlap
.moCpBlocked:
    OR 1                                ; NZ = bloqueado por player
    RET
.moCpOk:
    XOR A                               ; Z = libre
    RET

; --- Variables locales ---
.moTestX:       DEFB 0
.moTestY:       DEFB 0
.moSelfAddr:    DEFW 0
.moPX:          DEFB 0
.moPY:          DEFB 0
.moHDx:         DEFB 0
.moVDy:         DEFB 0
.moSvX:         DEFB 0
.moSvY:         DEFB 0
.moCandidates:  DEFS 8              ; 4 pares (dx, dy)

.moHitMonster:  DEFW 0              ; Direccion del monster con el que chocamos
AttackTimer:      DEFB 0             ; Frames restantes del ciclo de ataque actual
MonsterKbDespawn: DEFB 0            ; Flag: monster salio de pantalla por knockback
MonstersActive:   DEFB 0            ; Flag: monsters han sido invocados (00:30+)
MonsterHitThisAttack: DEFB 0, 0, 0  ; Bitmask: monster ya golpeado este ciclo de attack
PrevPlayerState:  DEFB 0            ; Estado del player en el frame anterior

; ==============================================================================
; UpdateNastyFlee - Huida con colision, evasion del player y backtracking
; ==============================================================================
; IX = entidad nasty en STATE_SCARED.
; Persistencia: continua en la direccion actual si sigue pasable.
; Si bloqueado: recalcula con 4 candidatos (hacia bordes + opuestos).
; Prioridad: pasable+sin_player > pasable > no moverse.
; Si llega al borde, pone NastyFleeDespawn=1 para que ProcessOneEnemy lo borre.
; ==============================================================================
UpdateNastyFlee:
    ; --- Posicion del player ---
    LD A, (EntityTable + ENT_POSX)
    LD (.flPX), A
    LD A, (EntityTable + ENT_POSY)
    LD (.flPY), A

    ; --- Persistencia: intentar continuar en la direccion actual ---
    LD D, (IX+ENT_DELTAX)
    LD E, (IX+ENT_DELTAY)
    LD A, D
    OR E
    JR Z, .flRecalc                 ; Sin direccion → recalcular
    CALL .flTryPassable
    JP Z, .flApply                  ; Sigue pasable → continuar

.flRecalc:
    ; --- Borde horizontal mas cercano ---
    LD A, (IX+ENT_POSX)
    LD B, A                         ; B = distLeft
    LD A, SCREEN_MAX_X
    SUB (IX+ENT_POSX)              ; A = distRight
    CP B
    JR NC, .flLeftNear
    LD B, A
    LD C, ENEMY_SPEED               ; → derecha
    JR .flHDone
.flLeftNear:
    LD A, ENEMY_SPEED
    NEG
    LD C, A                         ; → izquierda
.flHDone:
    LD A, B
    LD (.flHDist), A
    LD A, C
    LD (.flHDx), A

    ; --- Borde vertical mas cercano ---
    LD A, (IX+ENT_POSY)
    SUB SCREEN_MIN_Y
    LD B, A                         ; B = distTop
    LD A, SCREEN_MAX_Y
    SUB (IX+ENT_POSY)              ; A = distBottom
    CP B
    JR NC, .flTopNear
    LD B, A
    LD C, ENEMY_SPEED               ; → abajo
    JR .flVDone
.flTopNear:
    LD A, ENEMY_SPEED
    NEG
    LD C, A                         ; → arriba
.flVDone:
    LD A, B
    LD (.flVDist), A
    LD A, C
    LD (.flVDy), A

    ; --- Penalizar bordes sin salida (dist=255) ---
    CALL .flCheckHEdge              ; A=1 si borde H tiene salida, 0 si no
    OR A
    JR NZ, .flHEdgeOk
    LD A, 255
    LD (.flHDist), A                ; Sin salida → maxima distancia
.flHEdgeOk:
    CALL .flCheckVEdge
    OR A
    JR NZ, .flVEdgeOk
    LD A, 255
    LD (.flVDist), A
.flVEdgeOk:

    ; --- Construir tabla de 4 candidatos ---
    ; Orden: primario, secundario, anti-secundario, anti-primario
    ; Primario = eje con menor distancia al borde
    LD A, (.flHDist)
    LD B, A
    LD A, (.flVDist)
    CP B
    JR NC, .flHorizPrim             ; vDist >= hDist → horiz primario

    ; Vertical primario: (0,vDy), (hDx,0), (-hDx,0), (0,-vDy)
    LD HL, .flCandidates
    XOR A
    LD (HL), A                      ; c0.dx = 0
    INC HL
    LD A, (.flVDy)
    LD (HL), A                      ; c0.dy = vDy
    INC HL
    LD A, (.flHDx)
    LD (HL), A                      ; c1.dx = hDx
    INC HL
    XOR A
    LD (HL), A                      ; c1.dy = 0
    INC HL
    LD A, (.flHDx)
    NEG
    LD (HL), A                      ; c2.dx = -hDx
    INC HL
    XOR A
    LD (HL), A                      ; c2.dy = 0
    INC HL
    LD (HL), A                      ; c3.dx = 0
    INC HL
    LD A, (.flVDy)
    NEG
    LD (HL), A                      ; c3.dy = -vDy
    JR .flTryCandidates

.flHorizPrim:
    ; Horiz primario: (hDx,0), (0,vDy), (0,-vDy), (-hDx,0)
    LD HL, .flCandidates
    LD A, (.flHDx)
    LD (HL), A                      ; c0.dx = hDx
    INC HL
    XOR A
    LD (HL), A                      ; c0.dy = 0
    INC HL
    LD (HL), A                      ; c1.dx = 0
    INC HL
    LD A, (.flVDy)
    LD (HL), A                      ; c1.dy = vDy
    INC HL
    XOR A
    LD (HL), A                      ; c2.dx = 0
    INC HL
    LD A, (.flVDy)
    NEG
    LD (HL), A                      ; c2.dy = -vDy
    INC HL
    LD A, (.flHDx)
    NEG
    LD (HL), A                      ; c3.dx = -hDx
    INC HL
    XOR A
    LD (HL), A                      ; c3.dy = 0

.flTryCandidates:
    ; --- Pass 1: pasable + sin player ---
    LD HL, .flCandidates
    LD B, 4
.flLoop1:
    LD D, (HL)
    INC HL
    LD E, (HL)
    INC HL
    PUSH HL
    PUSH BC
    CALL .flTryMove
    POP BC
    POP HL
    JR Z, .flApply
    DJNZ .flLoop1

    ; --- Pass 2: solo pasable (ignorar player) ---
    LD HL, .flCandidates
    LD B, 4
.flLoop2:
    LD D, (HL)
    INC HL
    LD E, (HL)
    INC HL
    PUSH HL
    PUSH BC
    CALL .flTryPassable
    POP BC
    POP HL
    JR Z, .flApply
    DJNZ .flLoop2

    ; --- Todo bloqueado: no moverse ---
    JP .flAnimate

.flApply:
    ; D = deltaX, E = deltaY elegidos
    LD (IX+ENT_DELTAX), D
    LD (IX+ENT_DELTAY), E
    ; --- Aplicar movimiento ---
    LD A, (IX+ENT_POSX)
    ADD A, D
    LD (IX+ENT_POSX), A
    ; Borde derecho o underflow pasado el izquierdo (>=232)
    CP SCREEN_MAX_X
    JP NC, .flReachedEdge
    ; Borde izquierdo: posicion < ENEMY_SPEED → ya esta en el borde
    CP ENEMY_SPEED
    JP C, .flReachedEdge
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    ; Borde superior: posicion < MIN_Y + ENEMY_SPEED → en el borde
    CP SCREEN_MIN_Y + ENEMY_SPEED
    JP C, .flReachedEdge
    ; Borde inferior (>=171)
    CP SCREEN_MAX_Y
    JP NC, .flReachedEdge

.flAnimate:
    ; --- Animacion ---
    LD A, (IX+ENT_DELTAX)
    LD C, ENEMY_FRAMES_RIGHT
    BIT 7, A
    JR Z, .flAnimDir
    LD C, ENEMY_FRAMES_LEFT
.flAnimDir:
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .flAnimDone
    LD A, ENEMY_ANIM_DELAY
    LD (IX+ENT_ANIMTIMER), A
    LD A, (IX+ENT_SPRITEID)
    LD B, A
    SUB (IX+ENT_ANIMBASE)
    AND 1
    JR NZ, .flFrameReset
    INC B
    JR .flFrameSet
.flFrameReset:
    DEC B
.flFrameSet:
    LD (IX+ENT_SPRITEID), B
.flAnimDone:
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)
    AND 1
    ADD A, (IX+ENT_ANIMBASE)
    ADD A, C
    LD (IX+ENT_SPRITEID), A
    RET

.flReachedEdge:
    LD A, 1
    LD (NastyFleeDespawn), A
    RET

; --- Subrutina: pasable + evasion player ---
; D=deltaX, E=deltaY. Retorna Z=valido, NZ=invalido. Preserva D,E.
.flTryMove:
    CALL .flTryPassable
    RET NZ
    JP .flCheckPlayer

; --- Subrutina: comprobar pasabilidad ---
; D=deltaX, E=deltaY. Retorna Z=pasable, NZ=bloqueado. Preserva D,E.
.flTryPassable:
    PUSH DE
    LD A, (IX+ENT_POSX)
    LD (.flSvX), A
    LD A, (IX+ENT_POSY)
    LD (.flSvY), A
    LD A, (IX+ENT_POSX)
    ADD A, D
    LD (IX+ENT_POSX), A
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    CALL CheckEnemyCollision
    PUSH AF
    LD A, (.flSvX)
    LD (IX+ENT_POSX), A
    LD A, (.flSvY)
    LD (IX+ENT_POSY), A
    POP AF
    POP DE
    RET

; --- Subrutina: comprobar evasion del player ---
; D=deltaX, E=deltaY. Retorna Z=ok, NZ=player bloquea. Preserva D,E.
.flCheckPlayer:
    LD A, D
    OR A
    JR Z, .flChkPVert
    ; --- Movimiento horizontal ---
    BIT 7, D
    JR NZ, .flChkPLeft
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.flPX)
    CP B
    JR C, .flPOk
    JR Z, .flPOk
    JR .flChkPYDist
.flChkPLeft:
    LD A, (.flPX)
    LD B, A
    LD A, (IX+ENT_POSX)
    CP B
    JR C, .flPOk
    JR Z, .flPOk
.flChkPYDist:
    LD A, (IX+ENT_POSY)
    LD B, A
    LD A, (.flPY)
    SUB B
    JR NC, .flYPos
    NEG
.flYPos:
    CP FLEE_PLAYER_AVOID
    JR NC, .flPOk
    OR 1
    RET

.flChkPVert:
    ; --- Movimiento vertical ---
    BIT 7, E
    JR NZ, .flChkPUp
    LD A, (IX+ENT_POSY)
    LD B, A
    LD A, (.flPY)
    CP B
    JR C, .flPOk
    JR Z, .flPOk
    JR .flChkPXDist
.flChkPUp:
    LD A, (.flPY)
    LD B, A
    LD A, (IX+ENT_POSY)
    CP B
    JR C, .flPOk
    JR Z, .flPOk
.flChkPXDist:
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.flPX)
    SUB B
    JR NC, .flXPos
    NEG
.flXPos:
    CP FLEE_PLAYER_AVOID
    JR NC, .flPOk
    OR 1
    RET

.flPOk:
    XOR A
    RET

; --- Subrutina: comprobar si el borde horizontal objetivo tiene salida ---
; Segun signo de .flHDx: <0 → columna 0 (izq), >0 → columna 31 (der).
; Retorna A=1 si hay al menos una celda libre, A=0 si todo bloqueado.
.flCheckHEdge:
    LD A, (.flHDx)
    BIT 7, A
    JR NZ, .flChkELeft
    LD HL, CollisionMap + 31        ; Columna derecha
    JR .flChkEHLoop
.flChkELeft:
    LD HL, CollisionMap             ; Columna izquierda
.flChkEHLoop:
    LD B, 22
.flChkEHL:
    LD A, (HL)
    OR A
    JR Z, .flEdgeFound              ; Celda libre → salida existe
    LD DE, 32
    ADD HL, DE
    DJNZ .flChkEHL
    XOR A                           ; A=0: sin salida
    RET

; --- Subrutina: comprobar si el borde vertical objetivo tiene salida ---
; Segun signo de .flVDy: <0 → fila 0 (arriba), >0 → fila 21 (abajo).
; Retorna A=1 si hay al menos una celda libre, A=0 si todo bloqueado.
.flCheckVEdge:
    LD A, (.flVDy)
    BIT 7, A
    JR NZ, .flChkETop
    LD HL, CollisionMap + (21 * 32) ; Fila inferior
    JR .flChkEVLoop
.flChkETop:
    LD HL, CollisionMap             ; Fila superior
.flChkEVLoop:
    LD B, 32
.flChkEVL:
    LD A, (HL)
    OR A
    JR Z, .flEdgeFound
    INC HL
    DJNZ .flChkEVL
    XOR A                           ; A=0: sin salida
    RET

.flEdgeFound:
    LD A, 1                         ; A=1: tiene salida
    RET

; --- Variables locales ---
.flPX:          DEFB 0
.flPY:          DEFB 0
.flHDist:       DEFB 0
.flHDx:         DEFB 0
.flVDist:       DEFB 0
.flVDy:         DEFB 0
.flSvX:         DEFB 0
.flSvY:         DEFB 0
.flCandidates:  DEFS 8              ; 4 pares (dx, dy)

NastyFleeDespawn: DEFB 0

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
    ; Monsters: breve pausa antes de empezar a perseguir
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .spNotMonster
    LD (IX+ENT_DIR), MONSTER_STUN_PAUSE ; Pausa sin knockback (deltas=0)
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
.spNotMonster:
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
    ; Bloquear spawn durante campanadas de medianoche
    LD A, (BellCount)
    OR A
    RET NZ
    ; Bloquear spawn en N2 y A1 (no reaparecen hasta A2)
    LD A, (CurrentTimeOfDay)
    CP 4                        ; N2
    RET Z
    CP 5                        ; A1
    RET Z
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
    AND $07                     ; 0-7
    CP 6                        ; >= 6? wrap around
    JR C, .typeOk
    SUB 6                       ; 6→0, 7→1
.typeOk:
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
    ; SFX de spawn
    LD HL, SFX_EnemySpawn
    CALL PlaySFX
    RET

; --- Tabla de tipos de nasty (SpriteID base) ---
NastyTypeTable:
    DEFB SPRID_ENEMY_0          ; Spider
    DEFB SPRID_ENEMY_1          ; Scorpion
    DEFB SPRID_ENEMY_2          ; Bat
    DEFB SPRID_ENEMY_3          ; Snake
    DEFB SPRID_ENEMY_4          ; Eagle
    DEFB SPRID_ENEMY_5          ; Rat

; ==============================================================================
; SpawnMonsters - Invoca 3 monstruos placeholder en slots MONSTER0..+2
; ==============================================================================
; Llamado cuando el reloj llega a 00:30 (medianoche y media).
; Usa sprites de nasty como placeholder. Monstruos NO son destructibles.
; ==============================================================================
MONSTERS_TO_SPAWN EQU 3

SpawnMonsters:
    LD A, 1
    LD (MonstersActive), A
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
    LD C, 0                             ; Indice para tipo de sprite
.smLoop:
    PUSH BC
    ; Solo spawnear si el slot esta vacio
    LD A, (IX+ENT_TYPE)
    OR A
    JR NZ, .smSkip

    ; Elegir sprite placeholder (rota entre 3 primeros tipos de nasty)
    LD A, C
    LD HL, MonsterTypeTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)

    ; Configurar entidad
    LD (IX+ENT_DIR), A                  ; ANIMBASE real (temporal, se restaura tras spawn)
    LD (IX+ENT_TYPE), TYPE_MONSTER
    LD (IX+ENT_STATE), STATE_SPAWNING
    LD (IX+ENT_SPRITEID), SPRID_SPAWN
    LD (IX+ENT_ANIMBASE), SPRID_SPAWN
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_SPAWN
    LD (IX+ENT_FLAGS), (1 << ENTF_VISIBLE) | (1 << ENTF_SOLID) | (1 << ENTF_NEWSPAWN)

    ; Color: blanco brillante (placeholder llamativo)
    LD (IX+ENT_ATTR), $47              ; WHITE + BRIGHT

    ; Posicion aleatoria con collision check
    CALL .smFindPos

    ; Monsters arrancan quietos (deltas=0, pequeño stun para pausa inicial)
    XOR A
.smSetDx:
    LD (IX+ENT_DELTAX), A
.smSetDy:
    LD (IX+ENT_DELTAY), A

    ; Inicializar old pos
    LD A, (IX+ENT_POSX)
    LD (IX+ENT_OLDX), A
    LD (IX+ENT_DRAWX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A

.smSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    INC C
    DJNZ .smLoop
    RET

; --- Buscar posicion valida para monstruo (3 reintentos) ---
.smFindPos:
    LD A, 3
    LD (.smTries), A
.smRetry:
    ; Semilla rotante para dispersar posiciones entre monsters
    LD A, (.smSeed)
    ADD A, 73                           ; Primo, buena dispersion
    LD (.smSeed), A
    LD B, A
    LD A, R
    XOR B                               ; Mezclar semilla con R
    AND $F8                             ; Multiplos de 8
    ADD A, 16
    CP SCREEN_MAX_X - 16
    JR C, .smXOk
    LD A, 100
.smXOk:
    LD (IX+ENT_POSX), A
    LD A, (.smSeed)
    ADD A, 47                           ; Segundo primo
    LD (.smSeed), A
    LD B, A
    LD A, R
    XOR B
    AND $78
    ADD A, SCREEN_MIN_Y + 16
    CP SCREEN_MAX_Y - 16
    JR C, .smYOk
    LD A, 80
.smYOk:
    LD (IX+ENT_POSY), A
    ; Comprobar colision en las 4 esquinas
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JR NZ, .smBlocked
    LD A, (IX+ENT_POSX)
    ADD A, 15
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JR NZ, .smBlocked
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 15
    LD C, A
    CALL IsPointBlocked
    JR NZ, .smBlocked
    LD A, (IX+ENT_POSX)
    ADD A, 15
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 15
    LD C, A
    CALL IsPointBlocked
    RET Z                               ; Posicion valida
.smBlocked:
    LD A, (.smTries)
    DEC A
    LD (.smTries), A
    JR NZ, .smRetry
    ; Fallback: cancelar spawn
    LD (IX+ENT_TYPE), TYPE_NONE
    RET

.smTries: DEFB 0
.smSeed:  DEFB 211                        ; Semilla rotante (primo inicial)

; --- Tabla de sprites placeholder para monstruos ---
MonsterTypeTable:
    DEFB SPRID_ENEMY_0                  ; Placeholder: Spider
    DEFB SPRID_ENEMY_1                  ; Placeholder: Scorpion
    DEFB SPRID_ENEMY_2                  ; Placeholder: Bat

; ==============================================================================
; TryRespawnMonsters - Rellena slots de monster vacios (mantener siempre 3)
; ==============================================================================
; Llamado cada frame desde main loop. Si MonstersActive y algun slot esta
; vacio, spawnea un nuevo monster con animacion de aparicion.
; ==============================================================================
TryRespawnMonsters:
    LD A, (MonstersActive)
    OR A
    RET Z                               ; Monsters no activados aun
    ; Cooldown timer: si hay slot vacio, contar frames antes de respawn
    LD A, (.rmTimer)
    OR A
    JR Z, .rmCheckSlots
    DEC A
    LD (.rmTimer), A
    RET                                 ; Aun en cooldown
.rmCheckSlots:
    ; Buscar si hay algun slot vacio
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
    LD C, 0
.rmLoop:
    PUSH BC
    LD A, (IX+ENT_TYPE)
    OR A
    JP NZ, .rmSkip
    ; Slot vacio → respawnear
    ; ENT_DIR=0 → murio (random pos), ENT_DIR=dir → knockback offscreen (edge pos)
    LD A, (IX+ENT_DIR)
    OR A
    JR Z, .rmRandomPos
    ; Knockback offscreen: comprobar posicion del borde
    CALL .rmCheckPos
    JR Z, .rmPosOk
    ; Posicion bloqueada → buscar posicion libre cercana en el borde
    ; Intentar desplazar ±8, ±16, ±24 pixeles en eje perpendicular
    LD D, 3                             ; 3 intentos
.rmNudge:
    LD A, D
    RLCA
    RLCA
    RLCA                                ; D × 8
    LD E, A
    ; Probar +offset
    LD A, (ScreenTransition)
    CP DIR_E
    JR Z, .rmNudgeY
    CP DIR_W
    JR Z, .rmNudgeY
    ; Transicion vertical → nudge en X
    LD A, (IX+ENT_POSX)
    ADD A, E
    LD (IX+ENT_POSX), A
    CALL .rmCheckPos
    JR Z, .rmPosOk
    ; Revertir y probar -offset
    LD A, (IX+ENT_POSX)
    SUB E
    SUB E
    LD (IX+ENT_POSX), A
    CALL .rmCheckPos
    JR Z, .rmPosOk
    ; Revertir
    LD A, (IX+ENT_POSX)
    ADD A, E
    LD (IX+ENT_POSX), A
    JR .rmNudgeNext
.rmNudgeY:
    ; Transicion horizontal → nudge en Y
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    CALL .rmCheckPos
    JR Z, .rmPosOk
    LD A, (IX+ENT_POSY)
    SUB E
    SUB E
    LD (IX+ENT_POSY), A
    CALL .rmCheckPos
    JR Z, .rmPosOk
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
.rmNudgeNext:
    DEC D
    JR NZ, .rmNudge
    ; Todo bloqueado → fallback random
.rmRandomPos:
    ; Death respawn: limpiar hit count (nibble alto de FLAGS)
    LD A, (IX+ENT_FLAGS)
    AND $0F
    LD (IX+ENT_FLAGS), A
    LD (IX+ENT_TYPE), $FF               ; Marcador temporal (smFindPos pone 0 si falla)
    CALL SpawnMonsters.smFindPos
    LD A, (IX+ENT_TYPE)
    OR A
    JP Z, .rmSkip                       ; smFindPos fallo (TYPE_NONE)
.rmPosOk:
    ; Aparecer directamente corriendo (sin animacion de spawn)
    ; Usar MonsterTypeTable[C] para sprite (ANIMBASE puede estar corrupto tras puff)
    POP BC
    PUSH BC                             ; Recuperar C=indice sin perderlo
    LD A, C
    LD HL, MonsterTypeTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                          ; A = sprite base real
    LD (IX+ENT_ANIMBASE), A             ; Restaurar ANIMBASE correcto
    LD (IX+ENT_TYPE), TYPE_MONSTER
    LD (IX+ENT_STATE), STATE_RUNNING
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMTIMER), ENEMY_ANIM_DELAY
    ; Preservar hit count (nibble alto de FLAGS) para knockback cross-room
    LD A, (IX+ENT_FLAGS)
    AND $F0                             ; Conservar hit count
    LD D, A                             ; D = hit count nibble
    OR (1 << ENTF_VISIBLE) | (1 << ENTF_SOLID) | (1 << ENTF_NEWSPAWN)
    LD (IX+ENT_FLAGS), A
    ; Color segun hit count
    LD A, D
    RRCA
    RRCA
    RRCA
    RRCA
    LD HL, CheckPlayerEnemyCollision.kbHitColors
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (IX+ENT_ATTR), A
    ; ENT_DIR=0 → death respawn (spawn animation). ENT_DIR=dir → siguiendo (directo)
    LD A, (IX+ENT_DIR)
    OR A
    JR NZ, .rmAlive
    ; Death respawn → animacion de spawn
    LD A, (IX+ENT_ANIMBASE)
    LD (IX+ENT_DIR), A                  ; Guardar ANIMBASE real para restaurar tras spawn
    LD (IX+ENT_STATE), STATE_SPAWNING
    LD (IX+ENT_SPRITEID), SPRID_SPAWN
    LD (IX+ENT_ANIMBASE), SPRID_SPAWN
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_SPAWN
    JR .rmSetDeltas
.rmAlive:
    ; Knockback cross-room → directo corriendo con pausa
    LD (IX+ENT_DIR), MONSTER_STUN_PAUSE
.rmSetDeltas:
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    ; Inicializar old pos
    LD A, (IX+ENT_POSX)
    LD (IX+ENT_OLDX), A
    LD (IX+ENT_DRAWX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    ; Solo spawnear UNO por llamada; resetear timer para el siguiente
    POP BC
    LD A, MONSTER_ENTRY_GAP
    LD (.rmTimer), A
    RET

.rmSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    INC C
    DEC B
    JP NZ, .rmLoop
    RET

; --- Comprobar 4 esquinas de sprite 16x16 contra CollisionMap ---
; IX = entidad. Retorna Z=libre, NZ=bloqueado.
.rmCheckPos:
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    RET NZ
    LD A, (IX+ENT_POSX)
    ADD A, 15
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    RET NZ
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 15
    LD C, A
    CALL IsPointBlocked
    RET NZ
    LD A, (IX+ENT_POSX)
    ADD A, 15
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 15
    LD C, A
    JP IsPointBlocked               ; tail call

.rmTimer: DEFB 0

; ==============================================================================
; RepositionMonstersAtEntry - Reposicionar monsters al borde de entrada
; ==============================================================================
; Llamado tras cambio de pantalla. Los monsters aparecen por el mismo borde
; por donde entro el player, escalonados para entrar uno tras otro.
; ScreenTransition contiene la direccion de la transicion (DIR_N/S/E/W).
; ==============================================================================
MONSTER_ENTRY_BASE  EQU 50          ; Frames antes del primer monster (~1s)
MONSTER_ENTRY_GAP   EQU 40          ; Frames entre cada monster (~0.8s)

RepositionMonstersAtEntry:
    LD A, (MonstersActive)
    OR A
    RET Z

    ; === Determinar si volvemos a la room guardada ===
    LD A, (.reSavedRoomX)
    CP $FF
    JR Z, .reNotReturning               ; No hay room guardada
    LD B, A
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .reNotReturning
    LD A, (.reSavedRoomY)
    LD B, A
    LD A, (CurrentScreenY)
    CP B
    JR NZ, .reNotReturning
    LD A, 1
    JR .reSetReturn
.reNotReturning:
    XOR A
.reSetReturn:
    LD (.reReturning), A                ; 1=volvemos a room guardada, 0=no

    ; === Guardar estado actual si hay algun monster activo ===
    LD A, (.reReturning)
    OR A
    JR NZ, .reSkipSave                  ; Si volvemos, no sobreescribir el buffer
    ; Comprobar si algun slot tiene TYPE_MONSTER
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
.reCheckAny:
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR Z, .reDoSave
    LD DE, ENT_SIZE
    ADD IX, DE
    DJNZ .reCheckAny
    JR .reSkipSave                      ; Ningun monster activo
.reDoSave:
    ; Guardar entities y room actual como "room anterior"
    LD HL, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD DE, .reSavedMonsters
    LD BC, MONSTERS_TO_SPAWN * ENT_SIZE
    LDIR
    ; Calcular coords de la room que dejamos
    LD A, (ScreenTransition)
    LD D, A
    LD A, (CurrentScreenX)
    LD B, A
    LD A, D
    CP DIR_E
    JR NZ, .reSvNotE
    LD A, B
    DEC A
    JR .reSvSetX
.reSvNotE:
    LD A, D
    CP DIR_W
    JR NZ, .reSvXSame
    LD A, B
    INC A
    JR .reSvSetX
.reSvXSame:
    LD A, B
.reSvSetX:
    LD (.reSavedRoomX), A
    LD A, (CurrentScreenY)
    LD B, A
    LD A, D
    CP DIR_S
    JR NZ, .reSvNotS
    LD A, B
    DEC A
    JR .reSvSetY
.reSvNotS:
    LD A, D
    CP DIR_N
    JR NZ, .reSvYSame
    LD A, B
    INC A
    JR .reSvSetY
.reSvYSame:
    LD A, B
.reSvSetY:
    LD (.reSavedRoomY), A
.reSkipSave:

    ; === Procesar cada monster individualmente ===
    LD A, (EntityTable + ENT_POSX)
    LD (.rePlayerX), A
    LD A, (EntityTable + ENT_POSY)
    LD (.rePlayerY), A

    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
    LD C, 0
.reLoop:
    PUSH BC

    ; --- Per-monster: decidir restaurar o reposicionar ---
    ; Si volvemos a room guardada Y este monster es TYPE_NONE → restaurar del buffer
    LD A, (.reReturning)
    OR A
    JR Z, .reNoRestoreThis
    LD A, (IX+ENT_TYPE)
    OR A
    JR NZ, .reNoRestoreThis             ; TYPE_MONSTER = ya aparecio → sigue al player
    ; TYPE_NONE = no aparecio aun → restaurar del buffer
    PUSH IX
    POP DE                              ; DE = destino (entity slot)
    ; Calcular offset en buffer: C * ENT_SIZE
    LD A, C
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; HL = C * 16 = C * ENT_SIZE
    LD BC, .reSavedMonsters
    ADD HL, BC                          ; HL = fuente en buffer
    LD BC, ENT_SIZE
    LDIR                                ; Copiar 16 bytes del buffer al slot
    ; Marcar NEWSPAWN y actualizar old pos
    SET ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    LD A, (IX+ENT_POSX)
    LD (IX+ENT_OLDX), A
    LD (IX+ENT_DRAWX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    JP .reSkip

.reNoRestoreThis:
    LD A, (IX+ENT_TYPE)
    OR A
    JP NZ, .reReposition                ; TYPE_MONSTER → sigue al player
    LD A, (IX+ENT_DIR)
    OR A
    JP Z, .reReposition                 ; DIR=0 → death, reposicionar

    ; TYPE_NONE con direccion: ¿echado a ESTA room o a OTRA?
    LD D, A                             ; D = ENT_DIR
    LD A, (ScreenTransition)
    CP D
    JR Z, .reKnockedHere                ; DIR=transition → echado a ESTA room
    ; DIR diferente: verificar que esta en un borde (knockback real, no stale)
    LD A, (IX+ENT_POSX)
    CP 2
    JR C, .reKnockedOther
    CP SCREEN_MAX_X - 2
    JR NC, .reKnockedOther
    LD A, (IX+ENT_POSY)
    CP SCREEN_MIN_Y + 2
    JR C, .reKnockedOther
    CP SCREEN_MAX_Y - 2
    JR NC, .reKnockedOther
    JR .reReposition                    ; No en borde → stale, reposicionar
.reKnockedOther:
    JP .reSkip                          ; Echado a otra room → no tocar

.reKnockedHere:
    ; Monster echado a ESTA room → activar inmediatamente 40px dentro
    LD A, (ScreenTransition)
    CP DIR_E
    JR Z, .reHereLeft
    CP DIR_W
    JR Z, .reHereRight
    CP DIR_S
    JR Z, .reHereTop
    ; DIR_N → player entra por abajo, monster 40px desde abajo
    LD (IX+ENT_POSY), SCREEN_MAX_Y - 40
    JR .reHereActivate
.reHereLeft:
    LD (IX+ENT_POSX), 40
    JR .reHereActivate
.reHereRight:
    LD (IX+ENT_POSX), SCREEN_MAX_X - 40
    JR .reHereActivate
.reHereTop:
    LD (IX+ENT_POSY), SCREEN_MIN_Y + 40
.reHereActivate:
    ; Activar directamente corriendo
    LD A, (IX+ENT_ANIMBASE)
    LD (IX+ENT_TYPE), TYPE_MONSTER
    LD (IX+ENT_STATE), STATE_RUNNING
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMTIMER), ENEMY_ANIM_DELAY
    LD A, (IX+ENT_FLAGS)
    AND $F0
    OR (1 << ENTF_VISIBLE) | (1 << ENTF_SOLID) | (1 << ENTF_NEWSPAWN)
    LD (IX+ENT_FLAGS), A
    LD (IX+ENT_DIR), 0
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD A, (IX+ENT_POSX)
    LD (IX+ENT_OLDX), A
    LD (IX+ENT_DRAWX), A
    LD A, (IX+ENT_POSY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    JP .reSkip

.reReposition:
    ; Monster entra por donde entro el player
    LD A, (ScreenTransition)
    CP DIR_E
    JR Z, .reFromLeft
    CP DIR_W
    JR Z, .reFromRight
    CP DIR_S
    JR Z, .reFromTop
    ; DIR_N: entran por ABAJO (fuera de pantalla, clipping gradual)
    LD (IX+ENT_POSY), 192              ; Totalmente fuera → se asoman al subir
    LD A, (.rePlayerX)
    JR .reSetPerp

.reFromLeft:
    LD (IX+ENT_POSX), 0                ; Borde izquierdo (X clipping no implementado aun)
    LD A, (.rePlayerY)
    JR .reSetPerpY

.reFromRight:
    LD (IX+ENT_POSX), SCREEN_MAX_X - 2
    LD A, (.rePlayerY)
    JR .reSetPerpY

.reFromTop:
    LD (IX+ENT_POSY), 2                 ; Sobre el HUD → clipping gradual (attrs protegidos)
    LD A, (.rePlayerX)

.reSetPerp:
    LD D, A
    LD A, C
    RLCA
    RLCA
    RLCA                                ; C × 8
    ADD A, D
    LD (IX+ENT_POSX), A
    JR .reApply

.reSetPerpY:
    LD D, A
    LD A, C
    RLCA
    RLCA
    RLCA
    ADD A, D
    LD (IX+ENT_POSY), A

.reApply:
    ; Desactivar slot (invisible) pero preservar posicion, ANIMBASE y hit count
    LD (IX+ENT_TYPE), TYPE_NONE
    LD (IX+ENT_STATE), STATE_IDLE
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    ; ENT_DIR = direccion de transicion (NO 0, para que TryRespawnMonsters
    ; use la posicion del borde en vez de random)
    LD A, (ScreenTransition)
    LD (IX+ENT_DIR), A

.reSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    INC C
    DEC B
    JP NZ, .reLoop

    ; Iniciar timer para el primer monster
    LD A, MONSTER_ENTRY_BASE
    LD (TryRespawnMonsters.rmTimer), A
    RET

.rePlayerX:     DEFB 0
.rePlayerY:     DEFB 0
.reReturning:   DEFB 0                  ; 1=volvemos a room guardada

; --- Buffer de room anterior (para restaurar si volvemos antes de que aparezcan) ---
.reSavedRoomX:      DEFB $FF            ; $FF = sin room guardada
.reSavedRoomY:      DEFB $FF
.reSavedMonsters:   DEFS MONSTERS_TO_SPAWN * ENT_SIZE

; ==============================================================================
; CheckPlayerEnemyCollision - Colision jugador contra todos los enemigos
; ==============================================================================
; ResetAttrBlock - Limpiar atributos en una posicion (3x2 celdas)
; ==============================================================================
; D = pixelY, E = pixelX. Pinta $07 (blanco/negro) en las celdas ocupadas.
; ==============================================================================
ResetAttrBlock:
    ; Calcular attr address: ATTR_BASE + (Y/8)*32 + (X/8)
    LD A, D
    RRCA
    RRCA
    RRCA
    AND $1F                             ; charY = Y/8
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; HL = charY * 32
    LD A, E
    RRCA
    RRCA
    RRCA
    AND $1F                             ; charX = X/8
    LD E, A
    LD D, 0
    ADD HL, DE                          ; HL = charY*32 + charX
    LD DE, ATTR_BASE
    ADD HL, DE                          ; HL = attribute address
    ; Pintar 3 columnas × 2 filas con $07
    LD A, $07
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD (HL), A
    LD DE, 30                           ; siguiente fila: +32-2
    ADD HL, DE
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD (HL), A
    RET

; ==============================================================================
; Llamado desde el main loop despues de ProcessEntities.
; Comprueba bounding box overlap entre player y cada enemigo activo.
; ==============================================================================
CheckPlayerEnemyCollision:
    ; NO usar IY — el handler IM 1 del ROM necesita IY=$5C3A.
    ; Detectar inicio de nuevo ciclo de attack: limpiar hit marks
    LD A, (EntityTable + ENT_STATE)
    LD D, A                             ; D = estado actual
    LD A, (PrevPlayerState)
    LD E, A                             ; E = estado previo
    LD A, D
    LD (PrevPlayerState), A             ; Guardar estado actual
    LD A, E                             ; A = estado previo
    CP STATE_FIGHTING
    JR Z, .noNewAttack                  ; Ya estaba peleando → no limpiar
    LD A, D
    CP STATE_FIGHTING
    JR NZ, .noNewAttack                 ; No empezo a pelear → no limpiar
    ; Transicion a STATE_FIGHTING → nuevo ciclo de attack
    XOR A
    LD (MonsterHitThisAttack), A
    LD (MonsterHitThisAttack+1), A
    LD (MonsterHitThisAttack+2), A
.noNewAttack:
    ; Obtener dims del player una sola vez
    LD A, (EntityTable + ENT_SPRITEID)
    CALL GetSpriteDims          ; B=playerW, C=playerH
    LD A, B
    LD (.plW), A
    LD A, C
    LD (.plH), A

    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)  ; Empezar en slot 1
    LD B, NUM_MONSTERS + NUM_NASTIES       ; Slots 1-12

.checkLoop:
    LD A, (IX+ENT_TYPE)
    OR A
    JP Z, .nextEnemy

    ; Skip enemigos muriendo o spawneando (no colisionan)
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    JP Z, .nextEnemy
    CP STATE_SPAWNING
    JP Z, .nextEnemy
    ; Skip monsters en stun/knockback (no hacen daño)
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .notStunned
    LD A, (IX+ENT_DIR)
    OR A
    JP NZ, .nextEnemy
.notStunned:

    ; Obtener dims del enemigo
    PUSH BC                     ; salvar loop counter
    LD A, (IX+ENT_SPRITEID)
    CALL GetSpriteDims          ; B=enemyW, C=enemyH

    ; AABB X con margen de proximidad (+2px para daño adyacente)
    LD A, (IX+ENT_POSX)
    ADD A, B
    ADD A, 2                    ; enemyX + enemyW + margen
    JR C, .xCheck2             ; overflow → condicion siempre true
    LD D, A
    LD A, (EntityTable + ENT_POSX)
    CP D
    JP NC, .nextEnemyPop       ; playerX >= enemyX + enemyW → no overlap

.xCheck2:
    LD A, (EntityTable + ENT_POSX)
    LD D, A
    LD A, (.plW)
    ADD A, D
    ADD A, 2                    ; playerX + playerW + margen
    JR C, .yCheck1             ; overflow → condicion siempre true
    LD D, A
    LD A, (IX+ENT_POSX)
    CP D
    JP NC, .nextEnemyPop       ; enemyX >= playerX + playerW → no overlap

.yCheck1:
    ; AABB Y con margen
    LD A, (IX+ENT_POSY)
    ADD A, C
    ADD A, 2                    ; enemyY + enemyH + margen
    JR C, .yCheck2             ; overflow → condicion siempre true
    LD D, A
    LD A, (EntityTable + ENT_POSY)
    CP D
    JP NC, .nextEnemyPop       ; playerY >= enemyY + enemyH → no overlap

.yCheck2:
    LD A, (EntityTable + ENT_POSY)
    LD D, A
    LD A, (.plH)
    ADD A, D
    ADD A, 2                    ; playerY + playerH + margen
    JR C, .collision           ; overflow → condicion siempre true
    LD D, A
    LD A, (IX+ENT_POSY)
    CP D
    JP NC, .nextEnemyPop       ; enemyY >= playerY + playerH → no overlap

.collision:
    ; Colision detectada!
    ; Si player esta atacando y enemigo es destructible → matar enemigo
    LD A, (EntityTable + ENT_STATE)         ; player state
    CP STATE_FIGHTING
    JP NZ, .playerHit

    ; Player atacando → destruir enemigo o knockback monster
    BIT ENTF_DESTRUCT, (IX+ENT_FLAGS)
    JP NZ, .killNasty              ; Destructible → matar
    ; No destructible (monster) → knockback
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JP NZ, .playerHit              ; No es monster → hit normal
    ; Comprobar si ya fue golpeado en ESTE ciclo de attack
    PUSH IX
    POP HL
    LD DE, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    OR A
    SBC HL, DE                          ; HL = offset desde MONSTER0
    ; HL / ENT_SIZE = indice monster (0, 1, 2)
    LD A, L
    RRCA
    RRCA
    RRCA
    RRCA                                ; /16 = ENT_SIZE
    AND $03                             ; indice 0-2
    LD E, A
    LD D, 0
    LD HL, MonsterHitThisAttack
    ADD HL, DE
    LD A, (HL)
    OR A
    JP NZ, .nextEnemyPop               ; Ya golpeado este ciclo → ignorar
    LD (HL), 1                          ; Marcar como golpeado
    ; Knockback: direccion segun teclas de direccion del player
    LD A, (InputDirection)
    OR A
    JR Z, .kbFromPos                ; Sin direccion → usar posicion relativa
    LD D, A                         ; D = input bits
    ; Eje X: DIR_E(4) → empujar derecha, DIR_W(8) → empujar izquierda
    XOR A
    BIT 2, D                        ; DIR_E
    JR Z, .kbNoRight
    LD A, MONSTER_KB_SPEED
.kbNoRight:
    BIT 3, D                        ; DIR_W
    JR Z, .kbSetX
    LD A, -MONSTER_KB_SPEED
    JR .kbSetX
.kbFromPos:
    ; Fallback: empujar segun posicion relativa al player
    LD A, (IX+ENT_POSX)
    LD D, A
    LD A, (EntityTable + ENT_POSX)
    CP D
    JR NC, .kbPosLeft
    LD A, MONSTER_KB_SPEED          ; Monster a la derecha → empujar derecha
    JR .kbSetX
.kbPosLeft:
    LD A, -MONSTER_KB_SPEED         ; Monster a la izquierda → empujar izq
.kbSetX:
    LD (IX+ENT_DELTAX), A
    ; Eje Y: desde teclas o posicion relativa
    LD A, (InputDirection)
    OR A
    JR Z, .kbYFromPos
    LD D, A
    XOR A
    BIT 1, D                        ; DIR_S
    JR Z, .kbNoDown
    LD A, MONSTER_KB_SPEED
.kbNoDown:
    BIT 0, D                        ; DIR_N
    JR Z, .kbSetY
    LD A, -MONSTER_KB_SPEED
    JR .kbSetY
.kbYFromPos:
    LD A, (IX+ENT_POSY)
    LD D, A
    LD A, (EntityTable + ENT_POSY)
    CP D
    JR NC, .kbPosUp
    LD A, MONSTER_KB_SPEED          ; Monster abajo → empujar abajo
    JR .kbSetY
.kbPosUp:
    LD A, -MONSTER_KB_SPEED         ; Monster arriba → empujar arriba
.kbSetY:
    LD (IX+ENT_DELTAY), A
    ; Incrementar hit counter (bits 4-7 de ENT_FLAGS)
    LD A, (IX+ENT_FLAGS)
    ADD A, $10                          ; +1 en nibble alto
    LD (IX+ENT_FLAGS), A
    ; DEBUG: color segun golpes (blanco→verde→cyan→amarillo→rojo→magenta)
    AND $F0
    RRCA
    RRCA
    RRCA
    RRCA                                ; A = hit count (0-5)
    LD HL, .kbHitColors
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (IX+ENT_ATTR), A
    ; Iniciar stun timer (usa ENT_DIR como contador)
    LD (IX+ENT_DIR), MONSTER_STUN_TOTAL
    ; SFX de golpe al monster
    PUSH IX
    PUSH BC
    LD HL, SFX_EnemyDeath
    CALL PlaySFX
    POP BC
    POP IX
    JR .nextEnemyPop

; DEBUG: tabla de colores por golpes recibidos
.kbHitColors:
    DEFB $47                            ; 0 hits: blanco brillante (no deberia usarse)
    DEFB $44                            ; 1 hit:  verde brillante
    DEFB $45                            ; 2 hits: cyan brillante
    DEFB $46                            ; 3 hits: amarillo brillante
    DEFB $42                            ; 4 hits: rojo brillante
    DEFB $43                            ; 5 hits: magenta brillante

.killNasty:

    ; Matar nasty: iniciar animacion puff
    LD (IX+ENT_STATE), STATE_DYING
    LD (IX+ENT_ANIMBASE), SPRID_PUFF
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_PUFF
    LD (IX+ENT_DELTAX), 0          ; Parar movimiento
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_ATTR), WHITE | $40  ; Blanco brillante para el puff
    ; SFX de muerte de enemigo
    PUSH IX
    PUSH BC
    LD HL, SFX_EnemyDeath
    CALL PlaySFX
    POP BC
    POP IX
    JR .nextEnemyPop

.playerHit:
    ; Enemigo toca al player → flash atributo (feedback visual basico)
    LD A, RED | $40
    LD (EntityTable + ENT_ATTR), A
    ; SFX de golpe al player
    PUSH IX
    PUSH BC
    LD HL, SFX_PlayerHit
    CALL PlaySFX
    POP BC
    POP IX

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
