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
; ReadInput - Lee teclado + joystick y genera direccion + fuego
; ==============================================================================
; Universal Control: QAOP + Kempston + Sinclair 1, fusionados en D.
; D bits: 0=N, 1=S, 2=E, 3=W.  E bit 0 = Fire.
; ==============================================================================
ReadInput:
    LD D, 0             ; D = direcciones acumuladas
    LD E, 0             ; E = fuego acumulado

    ; -- 1. QAOP --
    LD BC, $FBFE        ; Fila Q-W-E-R-T
    IN A, (C)
    BIT 0, A            ; Q = Arriba
    JR NZ, .no_q
    SET 0, D
.no_q:
    LD BC, $FDFE        ; Fila A-S-D-F-G
    IN A, (C)
    BIT 0, A            ; A = Abajo
    JR NZ, .no_a
    SET 1, D
.no_a:
    LD BC, $DFFE        ; Fila P-O-I-U-Y
    IN A, (C)
    BIT 1, A            ; O = Izquierda
    JR NZ, .no_o
    SET 3, D
.no_o:
    BIT 0, A            ; P = Derecha (misma lectura de puerto)
    JR NZ, .no_p
    SET 2, D
.no_p:

    ; -- 2. KEMPSTON JOYSTICK (Puerto 31) --
    ; Kempston: bit 0=Right, 1=Left, 2=Down, 3=Up, 4=Fire
    IN A, (31)
    LD C, A             ; guardar para fire
    BIT 3, A            ; Up
    JR Z, .no_k_up
    SET 0, D
.no_k_up:
    BIT 2, A            ; Down
    JR Z, .no_k_down
    SET 1, D
.no_k_down:
    BIT 1, A            ; Left
    JR Z, .no_k_left
    SET 3, D
.no_k_left:
    BIT 0, A            ; Right
    JR Z, .no_k_right
    SET 2, D
.no_k_right:
    BIT 4, C            ; Kempston Fire
    JR Z, .no_k_fire
    SET 0, E
.no_k_fire:

    ; -- 3. SINCLAIR 1 (Puerto $F7FE, teclas 1-5) --
    ; 1=Left, 2=Right, 3=Down, 4=Up, 5=Fire
    LD BC, $F7FE
    IN A, (C)
    BIT 3, A            ; Tecla 4 = Up
    JR NZ, .no_s1_up
    SET 0, D
.no_s1_up:
    BIT 2, A            ; Tecla 3 = Down
    JR NZ, .no_s1_down
    SET 1, D
.no_s1_down:
    BIT 0, A            ; Tecla 1 = Left
    JR NZ, .no_s1_left
    SET 3, D
.no_s1_left:
    BIT 1, A            ; Tecla 2 = Right
    JR NZ, .no_s1_right
    SET 2, D
.no_s1_right:
    BIT 4, A            ; Tecla 5 = Fire
    JR NZ, .no_s1_fire
    SET 0, E
.no_s1_fire:

    ; -- 4. SPACE = Fire (teclado) --
    LD BC, $7FFE        ; Fila SPACE-SS-M-N-B
    IN A, (C)
    BIT 0, A            ; SPACE
    JR NZ, .no_space
    SET 0, E
.no_space:

    ; -- 5. Volcar D → InputDirection, E → InputFire --
    LD A, E
    LD (InputFire), A

    ; -- 6. Cancelar opuestos --
    LD A, D
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

    ; Resetear spawn timer (delay antes del primer nasty), round-robin y pending erase
    LD A, SPAWN_INTERVAL
    LD (SpawnTimer), A
    XOR A
    LD (EnemyStepIdx), A
    LD (PendingEraseCount), A
    RET

; ==============================================================================
; ComputePlayerDrawY - Calcula PlayerDrawY = POSY + (1 si hay celda ocupada justo encima)
; ==============================================================================
; Dibuja el player 1 px más abajo solo cuando tiene un char sólido justo encima
; (techo pegado). En espacios abiertos, el sprite se dibuja sin offset — evita
; que los pies parezcan hundirse en el suelo.
; ==============================================================================
ComputePlayerDrawY:
    LD A, (EntityTable + ENT_POSX)
    ADD A, 8                    ; center X del player
    LD B, A
    LD A, (EntityTable + ENT_POSY)
    LD C, A
    LD (PlayerDrawY), A         ; default: sin offset
    OR A
    RET Z
    DEC C                       ; Y - 1 (pixel justo encima de la cabeza)
    CALL IsPointBlocked
    RET Z                       ; libre → sin offset
    LD A, (EntityTable + ENT_POSY)
    INC A
    LD (PlayerDrawY), A         ; techo pegado → offset +1
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
    CALL ComputePlayerDrawY

    ; --- Skip si nada cambio (compara DESPUES de logica) ---
    LD A, (IX+ENT_DRAWX)
    CP (IX+ENT_OLDX)
    JR NZ, .plDoErase
    LD A, (PlayerDrawY)         ; Y renderizado actual (POSY o POSY+1 según ceiling)
    CP (IX+ENT_OLDY)
    JR NZ, .plDoErase
    LD A, (IX+ENT_SPRITEID)
    CP (IX+ENT_OLDSPRID)
    JR NZ, .plDoErase
    ; Nada cambio: pero si PlayerHitTimer activo, repintar attrs
    LD A, (PlayerHitTimer)
    OR A
    JR NZ, .plRepaintAttr
    RET                                 ; Nada cambio → skip todo
.plRepaintAttr:
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    CALL GetSpriteAddr
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    ; Reducir altura de attrs en 1 para no invadir fila inferior
    LD A, (EntityAttrH)
    CP 2
    JR C, .plAttrHOk
    DEC A
    LD (EntityAttrH), A
.plAttrHOk:
    POP IX
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr
    RET

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
    LD D, (IX+ENT_OLDY)                 ; OLDY ya incluye el +1 visual (se guarda así en plSaveOld)
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
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX

    ; Pintar attr
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    ; Reducir altura attr en 1 si es 4+ (última fila contiene muy pocos pixels
    ; del sprite pero invade el char BG inferior con el color del player)
    LD A, (EntityAttrH)
    CP 4
    JR C, .plAttrHOk2
    DEC A
    LD (EntityAttrH), A
.plAttrHOk2:
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr

    ; Guardar old = actual (con offset visual +1 para que el próximo erase coincida)
.plSaveOld:
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (PlayerDrawY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    RET

    ; --- Primer frame (pantalla recien dibujada): logica + draw, sin erase ---
.plFresh:
    RES ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    CALL UpdatePlayer
    CALL CalcDrawX
    CALL ComputePlayerDrawY
    CALL GetSpriteAddr

    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    ; Reducir altura attr en 1 si es 4+ (evita invadir char BG inferior)
    LD A, (EntityAttrH)
    CP 4
    JR C, .plAttrHOk3
    DEC A
    LD (EntityAttrH), A
.plAttrHOk3:
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr

    LD A, (PlayerDrawY)
    LD D, A
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
    CP STATE_ATTACKING
    JP Z, .peAttacking

    ; === STATE_RUNNING ===
    ; Auto-transicion: nasty/monster + ScareTimer activo → STATE_SCARED
    LD A, (ScareTimer)
    OR A
    JR Z, .peRunning
    LD A, (IX+ENT_TYPE)
    CP TYPE_NASTY
    JR Z, .peDoScare
    CP TYPE_MONSTER
    JR NZ, .peRunning
    ; Monster: limpiar stun antes de asustar
    LD (IX+ENT_DIR), 0
.peDoScare:
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
    ; --- Pintar attr nuevo ANTES de dibujar sprite (evita flash bg) ---
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
    ; --- Draw sprite nuevo ---
    LD D, (IX+ENT_POSY)
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX

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

    ; === STATE_ATTACKING: nasty depredador lanzandose ===
.peAttacking:
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    JP NZ, .peFresh
    CALL UpdatePredatorAttack
    JP .peCalcAndDraw

    ; === STATE_SCARED: pausa dramatica + huida ===
.peScared:
    BIT ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    JP NZ, .peScaredFresh

    ; Fase de pausa (ScareTimer > SCARE_FLEE_THRESHOLD): quieto mirando lados
    LD A, (ScareTimer)
    CP SCARE_FLEE_THRESHOLD + 1
    JR C, .peScaredFlee
    ; Parado: alternar sprite L/R cada 8 frames para "mirar lados"
    LD A, (IX+ENT_DELTAX)
    LD (IX+ENT_DELTAX), 0              ; No moverse
    LD (IX+ENT_DELTAY), 0
    ; Usar ANIMTIMER para alternar direccion visual
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .peScaredNoFlip
    LD (IX+ENT_ANIMTIMER), 8            ; Reset timer
    ; Alternar entre frames derecha e izquierda
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)               ; offset dentro del tipo
    XOR 2                               ; toggle bit 1: 0↔2 (R↔L)
    ADD A, (IX+ENT_ANIMBASE)
    LD (IX+ENT_SPRITEID), A
.peScaredNoFlip:
    JP .peCalcAndDraw

.peScaredFlee:
    ; Campanada 5+: huir hacia el borde
    XOR A
    LD (NastyFleeDespawn), A
    CALL UpdateNastyFlee
    LD A, (NastyFleeDespawn)
    OR A
    JP NZ, .peScaredDespawn
    JP .peCalcAndDraw

.peScaredFresh:
    RES ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    ; Mismo check: pausa o huida
    LD A, (ScareTimer)
    CP SCARE_FLEE_THRESHOLD + 1
    JR C, .peScaredFreshFlee
    ; Pausa: solo dibujar sin moverse
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    JP .peFreshDraw
.peScaredFreshFlee:
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
    ; Comprobar si ataque sigue activo (gestionado por SwordMode dispatch)
    LD A, (AttackTimer)
    OR A
    JR NZ, .notIdle             ; Ataque en curso → no poner idle, dejar al dispatch
    LD (IX+ENT_STATE), STATE_IDLE
    ; Dir actual = none (bits 0-3), mantener lastHDir (bits 4-7)
    LD A, (IX+ENT_DIR)
    AND $F0                     ; Limpiar dir actual, mantener lastHDir
    LD (IX+ENT_DIR), A
    ; Limpiar debounce de ataque (SPACE no pulsado = permitir siguiente)
    XOR A
    LD (AttackDebounce), A
    RET

.notIdle:
    ; Guardar direccion actual en bits 0-3
    LD A, (IX+ENT_DIR)
    AND $F0                     ; Mantener lastHDir
    OR B                        ; Añadir dir actual
    LD (IX+ENT_DIR), A

    ; Actualizar lastHDir si hay componente E/W (solo si no esta atacando)
    LD A, (AttackTimer)
    OR A
    JR NZ, .noHorizUpdate       ; Atacando → congelar lastHDir
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

    ; --- Consumir/regenerar stamina ---
    CALL UpdateStamina
    ; --- Auto-select sword mode segun stamina ---
    CALL SelectSwordMode
    ; --- Dispatch segun SwordMode ---
    LD A, (SwordMode)
    OR A
    JR Z, .swordModeB
    CP 1
    JR Z, .swordModeC
    CP 2
    JP Z, .swordModeFree

    ; === MODO B: Cooldown fijo tras atacar ===
.swordModeB:
    LD A, (AttackCooldown)
    OR A
    JR Z, .bNoCooldown
    DEC A
    LD (AttackCooldown), A
    JP NZ, .running                     ; En cooldown: no puede atacar
    ; Cooldown terminado: restaurar color blanco
    CALL .setPlayerWhite
    JP .running
.bNoCooldown:
    LD A, (AttackTimer)
    OR A
    JR Z, .bNoActive
    DEC A
    LD (AttackTimer), A
    JR NZ, .bActive
    ; Swing terminado: iniciar cooldown + color azul
    LD A, ATTACK_COOLDOWN_FRAMES
    LD (AttackCooldown), A
    CALL .setPlayerBlue
.bActive:
    LD (IX+ENT_STATE), STATE_FIGHTING
    RET
.bNoActive:
    LD A, (InputFire)
    OR A
    JP Z, .running
    LD A, ATTACK_SWING_FRAMES
    LD (AttackTimer), A
    JR .startAttack

    ; === MODO C: Swing fijo con debounce ===
.swordModeC:
    LD A, (AttackTimer)
    OR A
    JR Z, .cNoActive
    DEC A
    LD (AttackTimer), A
    LD (IX+ENT_STATE), STATE_FIGHTING
    RET
.cNoActive:
    LD A, (InputFire)
    OR A
    JP Z, .attackReleased
    LD A, (AttackDebounce)
    OR A
    JP NZ, .running                     ; Aun mantenido → no re-atacar
    LD A, 1
    LD (AttackDebounce), A
    LD A, ATTACK_SWING_FRAMES
    LD (AttackTimer), A
    JR .startAttack

    ; === MODO LIBRE: mantener SPACE = atacar continuo (stamina alta) ===
.swordModeFree:
    LD A, (AttackTimer)
    OR A
    JR Z, .fNoActive
    DEC A
    LD (AttackTimer), A
    LD (IX+ENT_STATE), STATE_FIGHTING
    RET
.fNoActive:
    LD A, (InputFire)
    OR A
    JR Z, .running
    LD A, ATTACK_SWING_FRAMES
    LD (AttackTimer), A
    JR .startAttack

    ; === Helpers de color para cooldown ===
.setPlayerBlue:
    LD A, (PlayerHitTimer)
    OR A
    RET NZ                              ; En flash de daño → no cambiar
    LD A, BLUE | $40
    LD (EntityTable + ENT_ATTR), A
    RET
.setPlayerWhite:
    LD A, (PlayerHitTimer)
    OR A
    RET NZ                              ; En flash de daño → no cambiar
    LD A, WHITE | $40
    LD (EntityTable + ENT_ATTR), A
    RET

    ; === Comun: iniciar ataque ===
    ; AttackTimer ya viene cargado con ATTACK_SWING_FRAMES (valor base).
    ; Recalculamos usando el delay boosteado real para que la animacion
    ; no wrappee: timer = ANIM_FRAMES_FIGHT * delay_boosteado.
.startAttack:
    XOR A
    LD (MonsterHitThisAttack), A
    LD (MonsterHitThisAttack+1), A
    LD (MonsterHitThisAttack+2), A

    ; Timer = ANIM_FRAMES_FIGHT * ANIM_DELAY_FIGHT (fijo, 25fps constante)
    LD A, ANIM_FRAMES_FIGHT * ANIM_DELAY_FIGHT
    LD (AttackTimer), A

    ; Marcar que el SFX de este ciclo aun no sono
    ; (evita doble: newAnimSfx + wrapSfx en el mismo ciclo)
    XOR A
    LD (AttackSfxPlayed), A

    LD (IX+ENT_STATE), STATE_FIGHTING
    RET

.attackReleased:
    XOR A
    LD (AttackDebounce), A              ; SPACE soltado: permitir siguiente ataque
.running:
    ; Si no hay direccion, poner idle en vez de running
    LD A, (InputDirection)
    OR A
    JR NZ, .runningOk
    LD (IX+ENT_STATE), STATE_IDLE
    RET
.runningOk:
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

    ; Determinar velocidad base segun estado
    LD A, (IX+ENT_STATE)
    CP STATE_FIGHTING
    LD A, SPEED_RUN
    JR NZ, .gotBaseSpeed
    LD A, SPEED_FIGHT
.gotBaseSpeed:
    LD (.speed), A
    LD (PlayerCurrentSpeed), A      ; Debug: guardar para HUD

    ; --- Movimiento horizontal (con colision) ---
    LD A, (IX+ENT_POSX)
    LD (.savedX), A

    LD A, (IX+ENT_DIR)
    BIT 2, A
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
    BIT 3, A
    JR Z, .noW
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.speed)
    LD C, A
    LD A, B
    SUB C
    JR NC, .clampW
    XOR A
.clampW:
    LD (IX+ENT_POSX), A
.noW:
    CALL CheckEntityCollision
    JR NZ, .tryStepUpX
    CALL CheckPlayerMonsterOverlap
    JR Z, .xOk
    LD A, (IX+ENT_POSX)
    LD (.tmpNewX), A
    LD A, (.savedX)
    LD (IX+ENT_POSX), A
    CALL CheckPlayerMonsterOverlap
    PUSH AF
    LD A, (.tmpNewX)
    LD (IX+ENT_POSX), A
    POP AF
    JR NZ, .xOk
    JR .revertX
.tryStepUpX:
    ; Step-up: si hay hueco de 8px arriba, subir para superar el borde
    LD A, (IX+ENT_POSY)
    CP SCREEN_MIN_Y + 8
    JR C, .revertX              ; muy arriba, sin margen
    LD (.savedYStep), A
    SUB 8
    LD (IX+ENT_POSY), A
    CALL CheckEntityCollision
    JR NZ, .stepFail
    CALL CheckPlayerMonsterOverlap
    JR NZ, .stepFail
    JR .xOk                     ; step-up OK: X y Y-8 comprometidos
.stepFail:
    LD A, (.savedYStep)
    LD (IX+ENT_POSY), A
.revertX:
    LD A, (.savedX)
    LD (IX+ENT_POSX), A
.xOk:

    ; --- Movimiento vertical (con colision) ---
    LD A, (IX+ENT_POSY)
    LD (.savedY), A

    LD A, (IX+ENT_DIR)
    BIT 1, A
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
    BIT 0, A
    JR Z, .noN
    LD A, (IX+ENT_POSY)
    LD B, A
    LD A, (.speed)
    LD C, A
    LD A, B
    SUB C
    JR C, .toMinY
    CP SCREEN_MIN_Y
    JR NC, .clampN
.toMinY:
    LD A, SCREEN_MIN_Y
.clampN:
    LD (IX+ENT_POSY), A
.noN:
    CALL CheckEntityCollision
    JR NZ, .revertY
    CALL CheckPlayerMonsterOverlap
    JR Z, .yOk
    LD A, (IX+ENT_POSY)
    LD (.tmpNewY), A
    LD A, (.savedY)
    LD (IX+ENT_POSY), A
    CALL CheckPlayerMonsterOverlap
    PUSH AF
    LD A, (.tmpNewY)
    LD (IX+ENT_POSY), A
    POP AF
    JR NZ, .yOk
.revertY:
    LD A, (.savedY)
    LD (IX+ENT_POSY), A
.yOk:
    RET

.speed:  DEFB 0
; Tablas de boost: [entero, fraccion_256] por nivel de enemigos
; Fraccion: 128=+0.5, 64=+0.25, 192=+0.75
; Monsters usan un grado menos que nasties (ralentizan menos la CPU)
.savedX: DEFB 0
.savedY: DEFB 0
.tmpNewX: DEFB 0
.tmpNewY: DEFB 0
.savedYStep: DEFB 0

; ==============================================================================
; CheckPlayerMonsterOverlap - Bloquear player contra monsters (colision solida)
; ==============================================================================
; IX = player entity. Comprueba AABB con todos los monsters activos.
; Usa GetSpriteDims para dimensiones reales (soporta monsters de cualquier tamaño).
; Retorna Z=libre, NZ=bloqueado por algun monster.
; ==============================================================================
CheckPlayerMonsterOverlap:
    ; Debug noclip: Z = libre siempre (sin bloqueo por monsters)
    LD A, (NoclipMode)
    OR A
    JR Z, .cpmoReal
    XOR A
    RET
.cpmoReal:
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
    ; Debug noclip: Z = libre siempre
    LD A, (NoclipMode)
    OR A
    JR Z, .normalColl
    XOR A
    RET
.normalColl:
    ; Offsets segun animacion (sprites 24px de ataque)
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
    RET NZ

    ; Punto 5: centro borde izquierdo (X-collL, Y+10)
    LD A, (.collL)
    LD B, A
    LD A, (IX+ENT_POSX)
    SUB B
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 10
    LD C, A
    CALL IsPointBlocked
    RET NZ

    ; Punto 6: centro borde derecho (X+collW, Y+10)
    LD A, (.collW)
    LD B, A
    LD A, (IX+ENT_POSX)
    ADD A, B
    LD B, A
    LD A, (IX+ENT_POSY)
    ADD A, 10
    LD C, A
    CALL IsPointBlocked
    RET NZ

    ; Punto 7: centro cuerpo superior (X+8, Y)
    LD A, (IX+ENT_POSX)
    ADD A, 8
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    RET NZ

    ; Punto 8: centro cuerpo inferior (X+8, Y+20)
    LD A, (IX+ENT_POSX)
    ADD A, 8
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
    ; D = nuevo AnimBase, E = num frames, C = delay (fijo, 25fps constante)
    ; ¿Cambio de animacion?
    LD A, (IX+ENT_ANIMBASE)
    CP D
    JP Z, .sameAnim

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
    LD A, 1
    LD (AttackSfxPlayed), A         ; Marcar: ya sono este ciclo
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

    ; Paso: si el player esta corriendo, reproducir "tic-tac" alternado
    LD A, (IX+ENT_STATE)
    CP STATE_RUNNING
    JR NZ, .noFootstep
    LD A, (FootstepToggle)
    XOR 1
    LD (FootstepToggle), A
    PUSH BC
    PUSH DE
    LD HL, SFX_FootstepTic
    JR NZ, .playStep
    LD HL, SFX_FootstepTac
.playStep:
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
    ; Si es animacion de ataque → SFX en wrap (si no sono ya este ciclo)
    LD A, D
    CP SPRID_ATTACK_EAST
    JR Z, .checkWrapSfx
    CP SPRID_ATTACK_WEST
    JR NZ, .frameOk
.checkWrapSfx:
    LD A, (AttackSfxPlayed)
    OR A
    JR NZ, .wrapSfxSkip             ; Ya sono en newAnim → skip este ciclo
    PUSH BC
    PUSH DE
    LD HL, SFX_Attack
    CALL PlaySFX
    POP DE
    POP BC
    JR .frameOk
.wrapSfxSkip:
    XOR A
    LD (AttackSfxPlayed), A         ; Limpiar flag para el proximo ciclo
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
; ==============================================================================
; CheckPredatorAttack - Comprueba si nasty debe lanzarse como depredador
; ==============================================================================
; IX = nasty en STATE_RUNNING. Si alineado con player y es depredador
; activo en el ciclo actual, transiciona a STATE_ATTACKING.
; ==============================================================================
; ==============================================================================
; UpdateStamina - Consume stamina al atacar, regenera al no atacar
; ==============================================================================
UpdateStamina:
    ; --- Regenerar salud (siempre, lento) ---
    LD A, (PlayerHealth)
    CP HEALTH_MAX
    JR Z, .usHealthFull
    LD HL, HealthRegenCtr
    INC (HL)
    LD A, (HL)
    CP HEALTH_REGEN_RATE
    JR C, .usHealthFull
    LD (HL), 0
    LD A, (PlayerHealth)
    INC A
    LD (PlayerHealth), A
.usHealthFull:
    ; --- Stamina: consumir o regenerar ---
    LD A, (IX+ENT_STATE)
    CP STATE_FIGHTING
    JR Z, .usDrain
    ; No atacando: regenerar
    LD A, (PlayerStamina)
    CP STAMINA_MAX
    RET Z                               ; Ya al maximo
    LD HL, StaminaRegenCtr
    INC (HL)
    LD A, (HL)
    CP STAMINA_REGEN_RATE
    RET C                               ; Aun no toca
    LD (HL), 0                          ; Reset counter
    LD A, (PlayerStamina)
    INC A
    LD (PlayerStamina), A
    RET
.usDrain:
    ; Atacando: consumir stamina
    LD A, (PlayerStamina)
    OR A
    RET Z                               ; Ya vacia
    LD HL, StaminaDrainCtr
    INC (HL)
    LD A, (HL)
    CP STAMINA_DRAIN_RATE
    RET C
    LD (HL), 0
    LD A, (PlayerStamina)
    DEC A
    LD (PlayerStamina), A
    ; Si stamina llega a 0, dar 1 punto tras cooldown
    OR A
    RET NZ
    LD A, 1
    LD (PlayerStamina), A               ; Minimo 1 para un swing
    RET

; ==============================================================================
; SelectSwordMode - Elige modo de espada segun nivel de stamina
; ==============================================================================
SelectSwordMode:
    LD A, (PlayerStamina)
    CP STAMINA_THRESHOLD_HIGH
    JR C, .smNotHigh
    LD A, 2                             ; Libre (continuo)
    JR .smSet
.smNotHigh:
    CP STAMINA_THRESHOLD_MID
    JR C, .smNotMid
    LD A, 1                             ; Fixed swing
    JR .smSet
.smNotMid:
    XOR A                               ; Cooldown (0)
.smSet:
    LD (SwordMode), A
    RET

; ==============================================================================
; GetStaminaColor - Devuelve color del player segun estado actual
; ==============================================================================
; Salida: A = atributo de color (bright)
; ==============================================================================
GetStaminaColor:
    LD A, (SwordMode)
    OR A
    JR NZ, .gscWhite                   ; Modo C o libre → blanco
    LD A, (AttackCooldown)
    OR A
    JR Z, .gscWhite
    LD A, BLUE | $40                    ; Modo B + cooldown activo → azul
    RET
.gscWhite:
    LD A, WHITE | $40                   ; Normal → blanco
    RET

; ==============================================================================
; CheckWellPickup - Recupera salud y stamina si el player pisa un pozo
; ==============================================================================
CheckWellPickup:
    LD A, (WellActive)
    OR A
    RET Z                               ; No hay pozo en esta pantalla
    ; Ya esta al maximo? No hacer nada
    LD A, (PlayerHealth)
    CP HEALTH_MAX
    JR NZ, .cwDoCheck
    LD A, (PlayerStamina)
    CP STAMINA_MAX
    RET Z                               ; Ambos al maximo → nada
.cwDoCheck:
    ; AABB con margen de 8px (1 celda) por cada lado:
    ; playerX < wellX+24 AND wellX-8 < playerX+16
    ; playerY < wellY+24 AND wellY-8 < playerY+21
    ; --- Check X ---
    LD A, (WellPosX)
    ADD A, 24                           ; C = wellX + 16 + 8 (wellRight + margen)
    LD C, A
    LD A, (EntityTable + ENT_POSX)      ; A = playerX
    CP C                                ; playerX < wellRight+margen?
    JR NC, .cwNoOverlap                 ; no → fuera
    LD A, (EntityTable + ENT_POSX)
    ADD A, 24                           ; C = playerX + 16 + 8 (playerRight + margen)
    LD C, A
    LD A, (WellPosX)                    ; A = wellX
    CP C                                ; wellX < playerRight+margen?
    JR NC, .cwNoOverlap                 ; no → fuera
    ; --- Check Y ---
    LD A, (WellPosY)
    ADD A, 24                           ; C = wellY + 16 + 8
    LD C, A
    LD A, (EntityTable + ENT_POSY)      ; A = playerY
    CP C                                ; playerY < wellBottom+margen?
    JR NC, .cwNoOverlap                 ; no → fuera
    LD A, (EntityTable + ENT_POSY)
    ADD A, 29                           ; C = playerY + 21 + 8
    LD C, A
    LD A, (WellPosY)                    ; A = wellY
    CP C                                ; wellY < playerBottom+margen?
    JR NC, .cwNoOverlap                 ; no → fuera
    ; --- Overlap! Recuperar salud y stamina ---
    LD A, HEALTH_MAX
    LD (PlayerHealth), A
    LD A, STAMINA_MAX
    LD (PlayerStamina), A
    ; Flash HUD y SFX
    LD A, 10                            ; 10 frames a 25fps = 0.4s (era 20 a 50fps)
    LD (WellFlashTimer), A
    LD HL, SFX_WellRecover
    CALL PlaySFX
.cwNoOverlap:
    RET

; ==============================================================================
CheckPredatorAttack:
    ; Buscar tipo depredador en PredatorTable
    LD A, (IX+ENT_ANIMBASE)
    SUB SPRID_ENEMY_0
    SRL A
    SRL A                               ; indice = (ANIMBASE - ENEMY_0) / 4
    LD HL, PredatorTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                          ; A = byte predador
    OR A
    RET Z                               ; PRED_NONE → no es depredador

    ; Comprobar ciclo minimo: bits 2-3 = ciclo requerido
    LD B, A                             ; B = byte predador completo
    SRL A
    SRL A                               ; A = ciclo requerido (1-3)
    LD C, A
    LD A, (DayCycleCount)
    CP C
    RET C                               ; DayCycleCount < ciclo requerido → no atacar

    ; Calcular velocidad de ataque segun ciclo
    LD A, (DayCycleCount)
    CP 4
    JR C, .cpSpeedOk
    LD A, 3                             ; Cap en 3
.cpSpeedOk:
    LD HL, PredatorSpeedTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (.cpSpeed), A

    ; Tipo depredador activo: comprobar alineacion
    LD A, B
    AND $03                             ; A = tipo (1=arriba, 2=abajo, 3=horizontal)
    CP PRED_HORIZONTAL
    JR Z, .cpHorizontal

    ; === Vertical (arriba/abajo): comprobar |nastyX - playerX| < PRED_ALIGN_DIST ===
    LD C, A                             ; C = tipo (1 o 2)
    LD A, (IX+ENT_POSX)
    LD D, A
    LD A, (EntityTable + ENT_POSX)
    SUB D
    JR NC, .cpAbsX
    NEG
.cpAbsX:
    CP PRED_ALIGN_DIST
    RET NC                              ; No alineado en X

    ; Comprobar posicion relativa Y
    LD A, C
    CP PRED_FROM_ABOVE
    JR Z, .cpFromAbove
    ; Desde abajo: nastyY > playerY
    LD A, (IX+ENT_POSY)
    LD D, A
    LD A, (EntityTable + ENT_POSY)
    CP D
    RET NC                              ; playerY >= nastyY → no esta abajo
    ; Lanzarse hacia arriba
    LD A, (.cpSpeed)
    NEG
    LD (IX+ENT_DELTAY), A
    LD (IX+ENT_DELTAX), 0
    JR .cpActivate
.cpFromAbove:
    ; Desde arriba: nastyY < playerY
    LD A, (EntityTable + ENT_POSY)
    LD D, A
    LD A, (IX+ENT_POSY)
    CP D
    RET NC                              ; nastyY >= playerY → no esta arriba
    ; Lanzarse hacia abajo
    LD A, (.cpSpeed)
    LD (IX+ENT_DELTAY), A
    LD (IX+ENT_DELTAX), 0
    JR .cpActivate

.cpHorizontal:
    ; === Horizontal: comprobar |nastyY - playerY| < PRED_ALIGN_DIST ===
    LD A, (IX+ENT_POSY)
    LD D, A
    LD A, (EntityTable + ENT_POSY)
    SUB D
    JR NC, .cpAbsY
    NEG
.cpAbsY:
    CP PRED_ALIGN_DIST
    RET NC                              ; No alineado en Y
    ; Lanzarse hacia el player en X
    LD A, (EntityTable + ENT_POSX)
    LD D, A
    LD A, (IX+ENT_POSX)
    CP D
    JR NC, .cpChargeLeft
    ; Player esta a la derecha
    LD A, (.cpSpeed)
    LD (IX+ENT_DELTAX), A
    JR .cpChargeSetY
.cpChargeLeft:
    LD A, (.cpSpeed)
    NEG
    LD (IX+ENT_DELTAX), A
.cpChargeSetY:
    LD (IX+ENT_DELTAY), 0

.cpActivate:
    LD (IX+ENT_STATE), STATE_ATTACKING
    RET

.cpSpeed: DEFB 0

; ==============================================================================
; UpdatePredatorAttack - Movimiento recto del nasty depredador
; ==============================================================================
; IX = nasty en STATE_ATTACKING. Se mueve recto a PREDATOR_SPEED.
; Si choca con pared/borde, vuelve a STATE_RUNNING con velocidad normal.
; ==============================================================================
UpdatePredatorAttack:
    ; Guardar posicion para revert
    LD A, (IX+ENT_POSX)
    LD (.paOldX), A
    LD A, (IX+ENT_POSY)
    LD (.paOldY), A

    ; Aplicar movimiento X
    LD A, (IX+ENT_POSX)
    ADD A, (IX+ENT_DELTAX)
    CP SCREEN_MAX_X
    JR NC, .paRevert                    ; Fuera de rango X
    CP 1
    JR C, .paRevert
    LD (IX+ENT_POSX), A

    ; Aplicar movimiento Y
    LD A, (IX+ENT_POSY)
    ADD A, (IX+ENT_DELTAY)
    CP SCREEN_MAX_Y
    JR NC, .paRevert                    ; Fuera de rango Y
    CP SCREEN_MIN_Y
    JR C, .paRevert
    LD (IX+ENT_POSY), A

    ; Comprobar colision con fondo
    CALL CheckEnemyCollision
    JR NZ, .paRevert                    ; Choco con pared

    ; --- Animacion durante ataque ---
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .paAnimDone
    LD A, 4                             ; Delay fijo rapido durante ataque
    LD (IX+ENT_ANIMTIMER), A
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)
    AND 1
    LD A, (IX+ENT_SPRITEID)
    JR NZ, .paFrame1
    INC A                               ; Frame 0 → 1
    JR .paFrameSet
.paFrame1:
    DEC A                               ; Frame 1 → 0
.paFrameSet:
    LD (IX+ENT_SPRITEID), A
.paAnimDone:
    RET                                 ; Sigue atacando

.paRevert:
    ; Revertir posicion y volver a STATE_RUNNING con velocidades aleatorias
    LD A, (.paOldX)
    LD (IX+ENT_POSX), A
    LD A, (.paOldY)
    LD (IX+ENT_POSY), A
    LD (IX+ENT_STATE), STATE_RUNNING
    ; Velocidades aleatorias en ambos ejes (como al spawnear)
    LD A, R
    BIT 2, A
    JR Z, .paRndRight
    LD A, (CurrentEnemySpeed)
    NEG
    JR .paRndSetDX
.paRndRight:
    LD A, (CurrentEnemySpeed)
.paRndSetDX:
    LD (IX+ENT_DELTAX), A
    LD A, R
    BIT 3, A
    JR Z, .paRndDown
    LD A, (CurrentEnemySpeed)
    NEG
    JR .paRndSetDY
.paRndDown:
    LD A, (CurrentEnemySpeed)
.paRndSetDY:
    LD (IX+ENT_DELTAY), A
    ; Restaurar timer de animacion normal
    LD A, (CurrentEnemyAnimDelay)
    LD (IX+ENT_ANIMTIMER), A
    RET

.paOldX: DEFB 0
.paOldY: DEFB 0

; ==============================================================================
UpdateEnemy:
    ; --- Comprobar si debe lanzarse como depredador ---
    CALL CheckPredatorAttack
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
    LD A, (CurrentEnemyAnimDelay)         ; Delay escalado por ciclo
    LD B, A
    LD A, (IX+ENT_ANIMBASE)
    CP SPRID_ENEMY_5
    LD A, B
    JR NZ, .eAnimDelaySet
    SRL A                               ; Rata: mitad del delay
    OR A
    JR NZ, .eAnimDelaySet
    INC A                               ; Minimo 1
.eAnimDelaySet:
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
    ; Stun terminado: sigue vivo, limpiar deltas para recalculo de persecucion
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    JP .moNormal

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
    ; --- Comprobar si el knockback sale de pantalla (antes de colision) ---
    PUSH DE
    LD A, (IX+ENT_POSX)
    LD (.moSvX), A
    LD A, (IX+ENT_POSY)
    LD (.moSvY), A
    ; Calcular nueva posicion
    LD A, (IX+ENT_POSX)
    ADD A, D
    LD (IX+ENT_POSX), A
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    ; Comprobar bordes ANTES de colision con paredes
    LD A, (IX+ENT_POSX)
    CP SCREEN_MAX_X
    JR NC, .moKbPreOffscreen
    CP MONSTER_KB_SPEED
    JR C, .moKbPreOffscreenMaybeX
.moKbPreBorderXOk:
    LD A, (IX+ENT_POSY)
    CP SCREEN_MAX_Y
    JR NC, .moKbPreOffscreen
    CP SCREEN_MIN_Y + MONSTER_KB_SPEED
    JR C, .moKbPreOffscreenMaybeY
.moKbPreBorderOk:
    ; Dentro de pantalla: comprobar colision con paredes
    CALL CheckEnemyCollision
    JP NZ, .moKbWallBlock               ; Bloqueado por pared
    JR .moKbNotBlocked
.moKbPreOffscreenMaybeX:
    BIT 7, D
    JR NZ, .moKbPreOffscreen
    JR .moKbPreBorderXOk
.moKbPreOffscreenMaybeY:
    BIT 7, E
    JR NZ, .moKbPreOffscreen
    JR .moKbPreBorderOk
.moKbPreOffscreen:
    ; Sale de pantalla: restaurar pos y saltar directo a offscreen handler
    LD A, (.moSvX)
    LD (IX+ENT_POSX), A
    LD A, (.moSvY)
    LD (IX+ENT_POSY), A
    POP DE
    JP .moKbOffscreen
.moKbNotBlocked:
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
    ; Monster empujado fuera (Regla 4). Guarda borde de salida en ENT_DIR,
    ; desaparece MAI_LINGER_PUSHED frames (~2s) y vuelve por ese mismo
    ; borde con MAI_REENTRY_OFFSET aplicado.
    LD (IX+ENT_DIR), A
    ; Señalizar despawn
    LD A, 1
    LD (MonsterKbDespawn), A
    ; Bloquear TryRespawnMonsters durante regreso
    LD A, MAI_LINGER_PUSHED
    LD (TryRespawnMonsters.rmTimer), A
    ; Timer de regreso individual
    PUSH IX
    POP HL
    LD DE, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    OR A
    SBC HL, DE
    SRL L
    SRL L
    SRL L
    SRL L                               ; L = indice monster (0-2)
    LD DE, MonsterReturnTimer
    ADD HL, DE
    LD (HL), MAI_LINGER_PUSHED
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

    ; --- Computar hDx, vDy (sign del delta al player en cada eje) ---
    LD A, (.moPX)
    SUB (IX+ENT_POSX)
    JR Z, .moNoDx
    LD A, MONSTER_SPEED
    JR NC, .moDxDone
    LD A, -MONSTER_SPEED
    JR .moDxDone
.moNoDx:
    XOR A
.moDxDone:
    LD (.moHDx), A

    LD A, (.moPY)
    SUB (IX+ENT_POSY)
    JR Z, .moNoDy
    LD A, MONSTER_SPEED
    JR NC, .moDyDone
    LD A, -MONSTER_SPEED
    JR .moDyDone
.moNoDy:
    XOR A
.moDyDone:
    LD (.moVDy), A

    ; --- Sobre el player? No mover ---
    LD A, (.moHDx)
    LD B, A
    LD A, (.moVDy)
    OR B
    JP Z, .moAnimate

    ; --- Randomizar eje alineado (romper trampa de alineamiento) ---
    ; Cuando player esta en linea recta (hDx=0 o vDy=0), sin este paso los
    ; candidates perpendiculares son (0,0) y se saltan → solo queda greedy
    ; y backtrack → oscilacion frente a un muro. Randomizar el eje 0 da
    ; candidates laterales que permiten rodear.
    LD A, (.moHDx)
    OR A
    JR NZ, .moHdxOk
    LD A, R
    AND 1
    LD A, MONSTER_SPEED
    JR NZ, .moHdxSet
    NEG
.moHdxSet:
    LD (.moHDx), A
.moHdxOk:
    LD A, (.moVDy)
    OR A
    JR NZ, .moVdyOk
    LD A, R
    AND 1
    LD A, MONSTER_SPEED
    JR NZ, .moVdySet
    NEG
.moVdySet:
    LD (.moVDy), A
.moVdyOk:

    ; --- Try 1: greedy primary ---
    ; Usa eje de mayor diferencia. Si pasable → apply.
    LD A, (.moPX)
    SUB (IX+ENT_POSX)
    JR NC, .moGrAbsDxOk
    NEG
.moGrAbsDxOk:
    LD B, A
    LD A, (.moPY)
    SUB (IX+ENT_POSY)
    JR NC, .moGrAbsDyOk
    NEG
.moGrAbsDyOk:
    CP B
    JR NC, .moGreedyVert
    ; Greedy horizontal
    LD A, (.moHDx)
    LD D, A
    LD E, 0
    JR .moGreedyTry
.moGreedyVert:
    LD D, 0
    LD A, (.moVDy)
    LD E, A
.moGreedyTry:
    CALL .moTryPassable
    JP Z, .moApply

    ; --- Try 2: persistence (direccion actual) ---
    ; Commit a rodeo en curso. Si la direccion previa sigue pasable, usarla
    ; aunque no sea la greedy — esto permite cruzar obstaculos largos sin
    ; volver atras ante el primer muro bloqueante.
    LD D, (IX+ENT_DELTAX)
    LD E, (IX+ENT_DELTAY)
    LD A, D
    OR E
    JR Z, .moRecalc
    CALL .moTryPassable
    JP Z, .moApply

.moRecalc:
    ; --- Try 3: full recalc, 4 candidates ordenados ---
    ; hDx/vDy ya estan computados + randomizados arriba. Solo elegir eje
    ; primario y setup candidatos.

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
    ; --- Direccion del sprite ---
    ; Durante stun/knockback: mira al player (mientras recibe el golpe).
    ; En movimiento normal: mira hacia donde se mueve (sign de DELTAX).
    ; Si DELTAX=0 (parado o moviendose solo en Y): conservar orientacion
    ; actual leyendo el offset del SPRITEID dentro del ANIMBASE.
    LD A, (IX+ENT_DIR)              ; stun counter (0=normal)
    OR A
    JR NZ, .moAnimFacePlayer        ; en stun → cara al player
    LD A, (IX+ENT_DELTAX)
    OR A
    JR Z, .moAnimKeepDir            ; deltaX=0 → conservar
    BIT 7, A
    LD C, MONSTER_FRAMES_RIGHT
    JR Z, .moAnimDir                ; positivo → derecha
    LD C, MONSTER_FRAMES_LEFT
    JR .moAnimDir
.moAnimKeepDir:
    ; Offset actual dentro del ANIMBASE: si >= MONSTER_FRAMES_LEFT, izq.
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)
    CP MONSTER_FRAMES_LEFT
    LD C, MONSTER_FRAMES_LEFT
    JR NC, .moAnimDir
    LD C, MONSTER_FRAMES_RIGHT
    JR .moAnimDir
.moAnimFacePlayer:
    LD A, (EntityTable + ENT_POSX)
    LD C, MONSTER_FRAMES_RIGHT
    CP (IX+ENT_POSX)
    JR NC, .moAnimDir
    LD C, MONSTER_FRAMES_LEFT
.moAnimDir:
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .moAnimDone
    LD A, ENEMY_ANIM_DELAY
    LD (IX+ENT_ANIMTIMER), A
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)              ; A = offset absoluto (0-7)
    AND MONSTER_BOUNCE_LEN - 1         ; A = offset dentro del grupo dir (0-3)
    INC A
    CP MONSTER_BOUNCE_LEN
    JR C, .moFrameSet
    XOR A                               ; Wrap: 4 → 0
.moFrameSet:
    ADD A, C                            ; + offset de direccion (0 o 4)
    ADD A, (IX+ENT_ANIMBASE)
    LD (IX+ENT_SPRITEID), A
.moAnimDone:
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
AttackCooldown:   DEFB 0             ; Frames de cooldown tras atacar
AttackDebounce:   DEFB 0             ; Debounce: debe soltar SPACE antes de re-atacar
AttackSfxPlayed:  DEFB 0             ; Flag: SFX ya sono en este ciclo de ataque
SwordMode:        DEFB 1             ; 0=B cooldown, 1=C swing fijo, 2=A stamina
PlayerHealth:     DEFB HEALTH_MAX    ; 0-16
PlayerStamina:    DEFB STAMINA_MAX   ; 0-16
StaminaDrainCtr:  DEFB 0             ; Sub-counter para consumo de stamina
StaminaRegenCtr:  DEFB 0             ; Sub-counter para regeneracion
HealthRegenCtr:   DEFB 0             ; Sub-counter para regeneracion de salud
MonsterKbDespawn: DEFB 0            ; Flag: monster salio de pantalla por knockback
MonstersActive:   DEFB 0            ; Flag: monsters han sido invocados (00:30+)
MonsterReturnTimer: DEFB 0, 0, 0    ; Timer de regreso por monster (0=inactivo)
; Posicion guardada de cada monster en su room (para knockback cross-room)
; Por monster: roomX, roomY, posX, posY. $FF en roomX = no guardado.
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
    LD A, (CurrentEnemySpeed)
    LD C, A                         ; → derecha
    JR .flHDone
.flLeftNear:
    LD A, (CurrentEnemySpeed)
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
    LD A, (CurrentEnemySpeed)
    LD C, A                         ; → abajo
    JR .flVDone
.flTopNear:
    LD A, (CurrentEnemySpeed)
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

    ; --- Pass 3: diagonales (salir de pockets entre bg sprites) ---
    ; Prueba las 4 combinaciones de (+/-hDx, +/-vDy). Prioriza la que
    ; va hacia el borde mas cercano (hDx,vDy).
    LD A, (.flHDx)
    LD D, A
    LD A, (.flVDy)
    LD E, A
    CALL .flTryPassable
    JP Z, .flApply
    LD A, (.flHDx)
    NEG
    LD D, A
    LD A, (.flVDy)
    LD E, A
    CALL .flTryPassable
    JP Z, .flApply
    LD A, (.flHDx)
    LD D, A
    LD A, (.flVDy)
    NEG
    LD E, A
    CALL .flTryPassable
    JP Z, .flApply
    LD A, (.flHDx)
    NEG
    LD D, A
    LD A, (.flVDy)
    NEG
    LD E, A
    CALL .flTryPassable
    JP Z, .flApply

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
    ; Borde izquierdo: posicion < CurrentEnemySpeed → ya esta en el borde
    LD B, A                             ; B = posX
    LD A, (CurrentEnemySpeed)
    LD C, A                             ; C = speed
    LD A, B
    CP C
    JP C, .flReachedEdge
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    ; Borde superior: posicion < MIN_Y + speed → en el borde
    LD B, A                             ; B = posY
    LD A, SCREEN_MIN_Y
    ADD A, C                            ; A = MIN_Y + speed
    LD C, A
    LD A, B
    CP C
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
ScareTimer:       DEFB 0              ; Countdown pausa+huida (compartido bells/dawn)

; ==============================================================================
; UpdateScareTimer - Decrementa ScareTimer cada frame
; ==============================================================================
UpdateScareTimer:
    LD A, (ScareTimer)
    OR A
    RET Z
    DEC A
    LD (ScareTimer), A
    RET

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
    ; Testea TODAS las celdas del bbox del enemigo en CollisionMap
    ; (no solo las 4 esquinas: podian dejar pasar obstaculos pequenyos
    ; como el pozo o el bench cuando el enemigo cae desalineado).
    LD A, (IX+ENT_SPRITEID)
    CALL GetSpriteDims              ; B=W_px, C=H_px
    ; --- Char X range ---
    LD A, (IX+ENT_POSX)
    LD D, A                         ; D = posX
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (.ecXlo), A                  ; charXlo
    LD A, D
    ADD A, B
    DEC A                           ; posX + W - 1
    RRCA
    RRCA
    RRCA
    AND $1F
    LD E, A                         ; E = charXhi
    LD A, (.ecXlo)
    LD D, A
    LD A, E
    SUB D
    INC A                           ; width_chars
    LD (.ecWc), A
    ; --- Char Y range ---
    LD A, (IX+ENT_POSY)
    LD B, A                         ; B = posY (salvar)
    RRCA
    RRCA
    RRCA
    AND $1F
    SUB BG_Y_OFFSET
    LD (.ecYlo), A
    LD A, B
    ADD A, C
    DEC A                           ; posY + H - 1
    RRCA
    RRCA
    RRCA
    AND $1F
    SUB BG_Y_OFFSET
    LD B, A                         ; B = charYhi
    LD A, (.ecYlo)
    NEG
    ADD A, B
    INC A                           ; height_chars
    LD (.ecHc), A
    ; --- HL = CollisionMap + charYlo*32 + charXlo ---
    LD A, (.ecYlo)
    CP 22
    JR NC, .ecFree                  ; fuera de rango (underflow HUD o abajo)
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                      ; *32
    LD A, (.ecXlo)
    ADD A, L
    LD L, A
    JR NC, .ecNoCarry
    INC H
.ecNoCarry:
    LD DE, CollisionMap
    ADD HL, DE
    ; --- Loop filas x columnas ---
    LD A, (.ecHc)
    LD C, A                         ; C = filas restantes
.ecRowLoop:
    PUSH HL
    LD A, (.ecWc)
    LD B, A                         ; B = cols restantes
.ecColLoop:
    LD A, (HL)
    OR A
    JR NZ, .ecBlocked
    INC HL
    DJNZ .ecColLoop
    POP HL
    LD DE, 32
    ADD HL, DE                      ; siguiente fila
    DEC C
    JR NZ, .ecRowLoop
.ecFree:
    XOR A                           ; Z = libre
    RET
.ecBlocked:
    POP HL
    OR A                            ; NZ = bloqueado (A != 0 por el LD A,(HL) previo)
    RET

.ecXlo: DEFB 0
.ecYlo: DEFB 0
.ecWc:  DEFB 0
.ecHc:  DEFB 0

; ==============================================================================
; CountActiveNasties / CountActiveMonsters
; ==============================================================================
; Cuentan enemigos vivos por tipo (excluyen DYING, SPAWNING y SCARED).
; Ambas usan _CountSlots internamente.
; Salida: A = numero de enemigos activos. Machaca: B, C, DE, HL. Preserva: IX
; ==============================================================================
CountActiveNasties:
    LD HL, EntityTable + (SLOT_NASTY0 * ENT_SIZE) + ENT_TYPE
    LD B, NUM_NASTIES
    JR _CountSlots

CountActiveMonsters:
    LD HL, EntityTable + (SLOT_MONSTER0 * ENT_SIZE) + ENT_TYPE
    LD B, NUM_MONSTERS

_CountSlots:
    LD C, 0                         ; Contador
.countLoop:
    LD A, (HL)
    OR A
    JR Z, .countNext                ; Slot vacio: no contar
    ; Comprobar estado: excluir DYING, SPAWNING y SCARED
    PUSH DE
    LD DE, ENT_STATE - ENT_TYPE     ; Offset de TYPE a STATE = 1
    ADD HL, DE
    LD A, (HL)
    SBC HL, DE                      ; Restaurar HL a ENT_TYPE
    POP DE
    CP STATE_DYING
    JR Z, .countNext
    CP STATE_SPAWNING
    JR Z, .countNext
    CP STATE_SCARED
    JR Z, .countNext
    INC C
.countNext:
    LD DE, ENT_SIZE
    ADD HL, DE
    DJNZ .countLoop
    LD A, C
    RET

; ==============================================================================
; TrySpawnNasty - Intenta crear un nasty en un slot vacio
; ==============================================================================
; Llamado cada frame. Solo spawnea cuando el timer llega a 0.
; ==============================================================================
TrySpawnNasty:
    ; Cooldown tras cambio de pantalla / inicio
    LD A, (SpawnTimer)
    OR A
    JR Z, .spawnReady
    DEC A
    LD (SpawnTimer), A
    RET
.spawnReady:
    ; Bloquear spawn durante pausa/huida (campanadas o amanecer)
    LD A, (ScareTimer)
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
    ; Elegir tipo de nasty (pseudo-random, 4 tipos por tabla)
    LD A, R
    AND $03                     ; 0-3 (NUM_NASTY_TYPES = 4)
    LD L, A
    LD H, 0
    LD DE, (CurrentNastyTable)
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

    ; Color segun tipo (cada tipo tiene color fijo)
    LD A, (IX+ENT_DIR)          ; ANIMBASE real (guardado arriba)
    LD HL, NastyColorTable
    PUSH DE
    LD DE, SPRID_ENEMY_0
    SUB E                       ; A = SPRID offset desde ENEMY_0
    SRL A
    SRL A                       ; A = indice de tipo (cada 4 SPRIDs)
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    POP DE
.setAttr:
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
    JR NZ, .spawnBlocked
    ; Comprobar solapamiento con player (AABB 16px margen)
    LD A, (EntityTable + ENT_POSX)
    SUB (IX+ENT_POSX)
    JR NC, .spAbsX
    NEG
.spAbsX:
    CP 24                               ; margen generoso para no aparecer pegado
    JR C, .spawnBlocked
    LD A, (EntityTable + ENT_POSY)
    SUB (IX+ENT_POSY)
    JR NC, .spAbsY
    NEG
.spAbsY:
    CP 24
    JR Z, .spawnPosOk
    JR NC, .spawnPosOk
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
    LD A, (CurrentEnemySpeed)
    NEG
    JR .setDX
.dxPos:
    LD A, (CurrentEnemySpeed)
.setDX:
    LD (IX+ENT_DELTAX), A
    LD A, R
    BIT 3, A
    JR Z, .dyPos
    LD A, (CurrentEnemySpeed)
    NEG
    JR .setDY
.dyPos:
    LD A, (CurrentEnemySpeed)
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

; ==============================================================================
; UpdateEnemySpeed - Actualiza velocidad base de nasties segun ciclo
; ==============================================================================
UpdateEnemySpeed:
    LD A, (DayCycleCount)
    DEC A                               ; 0-based index
    CP 10
    JR C, .uesOk
    LD A, 9                             ; Cap en indice 9
.uesOk:
    PUSH AF                             ; Guardar indice para tabla de anim
    LD HL, EnemySpeedTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                          ; A = velocidad × 2
    ; Calcular velocidad real: A/2, redondeando arriba en frames impares
    SRL A                               ; A = velocidad / 2, carry = resto
    JR NC, .uesNoFrac                   ; Sin resto → velocidad exacta
    ; Hay fraccion .5: alternar +1 en frames impares
    LD B, A                             ; B = parte entera
    LD A, (GameFrameCounter)
    AND 1                               ; 0 en par, 1 en impar
    ADD A, B                            ; Sumar 0 o 1
.uesNoFrac:
    LD (CurrentEnemySpeed), A
    ; Leer delay de animacion para este ciclo
    POP AF                              ; A = indice 0-based
    LD HL, EnemyAnimDelayTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (CurrentEnemyAnimDelay), A
    RET

; Velocidad base nasties por ciclo (valor × 2 para soportar .5)
; Valor real: 2=1px, 3=1.5px, 4=2px, 5=2.5px, 6=3px
EnemySpeedTable:
    DEFB 2                              ; Ciclo 1: 1px
    DEFB 3                              ; Ciclo 2: 1.5px
    DEFB 4                              ; Ciclo 3: 2px
    DEFB 5                              ; Ciclo 4: 2.5px
    DEFB 6                              ; Ciclo 5: 3px
    DEFB 7                              ; Ciclo 6: 3.5px
    DEFB 8                              ; Ciclo 7: 4px
    DEFB 9                              ; Ciclo 8: 4.5px
    DEFB 10                             ; Ciclo 9: 5px
    DEFB 12                             ; Ciclo 10: 6px

; Delay de animacion nasties por ciclo (menor = mas rapido)
; La rata usara la mitad de estos valores
EnemyAnimDelayTable:                    ; Ajustado a 25fps (mitad de los valores a 50fps)
    DEFB 4                              ; Ciclo 1: 4 frames = 160ms (era 8 a 50fps)
    DEFB 4                              ; Ciclo 2 (era 7, redondeado)
    DEFB 3                              ; Ciclo 3 (era 6)
    DEFB 3                              ; Ciclo 4 (era 5, redondeado)
    DEFB 2                              ; Ciclo 5 (era 4)
    DEFB 2                              ; Ciclo 6 (era 4)
    DEFB 2                              ; Ciclo 7 (era 3, min 2 para fluidez)
    DEFB 2                              ; Ciclo 8 (era 3, min 2)
    DEFB 1                              ; Ciclo 9 (era 2)
    DEFB 1                              ; Ciclo 10 (era 2)

; ==============================================================================
; KillAllActiveNasties - Todos los nasties activos pasan a STATE_DYING
; ==============================================================================
; Llamado al terminar la ultima campanada: los nasties que sigan vivos en
; pantalla mueren (puff anim). Ignora slots vacios, ya dying/spawning.
; ==============================================================================
KillAllActiveNasties:
    LD IX, EntityTable + (SLOT_NASTY0 * ENT_SIZE)
    LD B, NUM_NASTIES
.kanLoop:
    PUSH BC
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .kanSkip                  ; slot vacio
    CP TYPE_NASTY
    JR NZ, .kanSkip                 ; no es nasty
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    JR Z, .kanSkip
    CP STATE_SPAWNING
    JR Z, .kanSkip
    ; Transicionar a STATE_DYING con puff
    LD (IX+ENT_STATE), STATE_DYING
    LD (IX+ENT_ANIMBASE), SPRID_PUFF
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_PUFF
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_ATTR), WHITE | $40
.kanSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    DJNZ .kanLoop
    RET

; ==============================================================================
; KillAllActiveMonsters - Todos los monsters activos pasan a STATE_DYING
; ==============================================================================
; Llamado al entrar en A2 (amanecer tardio): los monsters que sigan vivos
; mueren con puff. Tambien limpia MonstersActive para evitar respawn.
; ==============================================================================
KillAllActiveMonsters:
    XOR A
    LD (MonstersActive), A              ; No respawnear mas
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, NUM_MONSTERS
.kamLoop:
    PUSH BC
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .kamSkip                      ; slot vacio
    CP TYPE_MONSTER
    JR NZ, .kamSkip                     ; no es monster
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    JR Z, .kamSkip
    CP STATE_SPAWNING
    JR Z, .kamSkip
    LD (IX+ENT_STATE), STATE_DYING
    LD (IX+ENT_ANIMBASE), SPRID_PUFF
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_PUFF
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_ATTR), WHITE | $40
.kamSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    DJNZ .kamLoop
    RET

; --- Tabla de tipos de nasty (SpriteID base) ---
; --- Tablas de nasties por momento del dia ---
NUM_NASTY_TYPES EQU 4
DiurnalTypeTable:                       ; DY, C1, A2
    DEFB SPRID_ENEMY_4          ; Eagle
    DEFB SPRID_ENEMY_0          ; Spider
    DEFB SPRID_ENEMY_6          ; Goat (placeholder)
    DEFB SPRID_ENEMY_3          ; Snake
CrepuscularTypeTable:                   ; C2, N1
    DEFB SPRID_ENEMY_5          ; Rat
    DEFB SPRID_ENEMY_2          ; Bat
    DEFB SPRID_ENEMY_1          ; Scorpion
    DEFB SPRID_ENEMY_7          ; RabidCat (placeholder)

; --- Colores por tipo de nasty (indexado por (SPRID - SPRID_ENEMY_0) / 4) ---
NastyColorTable:
    DEFB RED | $40              ; Enemy 0: Spider - rojo
    DEFB MAGENTA | $40          ; Enemy 1: Scorpion - magenta
    DEFB RED | $40              ; Enemy 2: Bat - rojo
    DEFB GREEN | $40            ; Enemy 3: Snake - verde
    DEFB YELLOW | $40           ; Enemy 4: Eagle - amarillo
    DEFB CYAN | $40             ; Enemy 5: Rat - cyan
    DEFB CYAN | $40             ; Enemy 6: Goat - cyan
    DEFB BLUE                   ; Enemy 7: RabidCat - azul oscuro

; --- Tabla de comportamiento depredador ---
; Indexado por (SPRID - SPRID_ENEMY_0) / 4
; Bits 0-1: tipo (0=none, 1=arriba, 2=abajo, 3=horizontal)
; Bits 2-3: ciclo minimo requerido (1=ciclo1, 2=ciclo2, 3=ciclo3)
PredatorTable:
    DEFB PRED_NONE                              ; Enemy 0: Spider - no predador
    DEFB PRED_FROM_BELOW | (2 << 2)             ; Enemy 1: Scorpion - abajo, ciclo 2
    DEFB PRED_FROM_ABOVE | (1 << 2)             ; Enemy 2: Bat - arriba, ciclo 1
    DEFB PRED_FROM_BELOW | (2 << 2)             ; Enemy 3: Snake - abajo, ciclo 2
    DEFB PRED_FROM_ABOVE | (1 << 2)             ; Enemy 4: Eagle - arriba, ciclo 1
    DEFB PRED_NONE                              ; Enemy 5: Rat - no predador
    DEFB PRED_HORIZONTAL | (3 << 2)             ; Enemy 6: Goat - horizontal, ciclo 3
    DEFB PRED_HORIZONTAL | (3 << 2)             ; Enemy 7: RabidCat - horizontal, ciclo 3

; --- Velocidad de ataque por ciclo (indexado por DayCycleCount, cap en 3) ---
PredatorSpeedTable:
    DEFB 2                              ; Ciclo 0 (no deberia usarse)
    DEFB 2                              ; Ciclo 1: lento
    DEFB 3                              ; Ciclo 2: intermedio
    DEFB 4                              ; Ciclo 3+: rapido

DayCycleCount:  DEFB 1              ; Numero de ciclo actual (empieza en 1)

CurrentNastyTable: DEFW DiurnalTypeTable

; ==============================================================================
; UpdateNastyTable - Selecciona tabla de nasties segun CurrentTimeOfDay
; ==============================================================================
; Fases 0(DY), 1(C1), 6(A2) → DiurnalTypeTable
; Fases 2(C2), 3(N1) → CrepuscularTypeTable
; Fases 4(N2), 5(A1) → no importa (spawn bloqueado)
; ==============================================================================
UpdateNastyTable:
    LD A, (CurrentTimeOfDay)
    CP 2
    JR Z, .crepuscular
    CP 3
    JR Z, .crepuscular
    ; Diurnal (0, 1, 6) o fases sin spawn (4, 5)
    LD HL, DiurnalTypeTable
    JR .setTable
.crepuscular:
    LD HL, CrepuscularTypeTable
.setTable:
    LD (CurrentNastyTable), HL
    RET

; ==============================================================================
; ScareAllMonsters - Monsters huyen al amanecer (como nasties en campanadas)
; ==============================================================================
ScareAllMonsters:
    XOR A
    LD (MonstersActive), A              ; No respawnear mas
    LD A, SCARE_TIMER_DAWN
    LD (ScareTimer), A
    ; Los monsters transicionaran a STATE_SCARED en ProcessOneEnemy
    ; via el check de ScareTimer > 0
    RET

; ==============================================================================
; SpawnMonsters - Invoca 3 monstruos placeholder en slots MONSTER0..+2
; ==============================================================================
; Llamado cuando el reloj llega a 00:30 (medianoche y media).
; ==============================================================================

; ==============================================================================
; MONSTER SPAWN/REPOSITION SYSTEM (simplified, robust)
; ==============================================================================
; ALL monsters ALWAYS appear at LastEntryPosX/Y (player's entry position).
; This is the ONLY guaranteed safe position (player fits there, 16x21).
; No nudge, no border scan, no MonsterSave, no buffer restore.
; ==============================================================================
; MONSTER SPAWN/REPOSITION SYSTEM (robust, simplified)
; ==============================================================================
; ALL monsters ALWAYS appear at LastEntryPosX/Y (player entry position).
; This is the ONLY guaranteed safe position (player fits 16x21 there).
; No nudge, no border scan, no MonsterSave, no buffer restore.
; ==============================================================================
MONSTERS_TO_SPAWN   EQU 3
MONSTER_ENTRY_BASE  EQU 50          ; Frames antes del primer monster (~1s)
MONSTER_ENTRY_GAP   EQU 40          ; Frames entre cada monster (~0.8s)

; ==============================================================================
; SpawnMonsters - Primera aparicion tras campanadas
; ==============================================================================
SpawnMonsters:
    LD A, (MonstersActive)
    OR A
    RET NZ
    LD A, 1
    LD (MonstersActive), A
    CALL ShuffleMonsterTypes
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
    LD C, 0
.smLoop:
    PUSH BC
    LD A, (IX+ENT_TYPE)
    OR A
    JP NZ, .smSkip
    ; Asignar tipo y color
    LD A, C
    LD HL, MonsterTypeTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (IX+ENT_ANIMBASE), A
    LD A, C
    LD HL, MonsterColorTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (IX+ENT_ATTR), A
    ; Posicion: Regla 1 — hueco aleatorio del screen, fallback LastEntryPos.
    PUSH BC
    CALL MaiPickRandomGap           ; A=0 ok, A=1 sin gaps
    OR A
    JR NZ, .smFallbackPos
    LD A, (MaiSpawnX)
    LD (IX+ENT_POSX), A
    LD A, (MaiSpawnY)
    LD (IX+ENT_POSY), A
    JR .smPosDone
.smFallbackPos:
    LD A, (LastEntryPosX)
    LD (IX+ENT_POSX), A
    LD A, (LastEntryPosY)
    LD (IX+ENT_POSY), A
.smPosDone:
    POP BC
    ; TYPE_NONE + DIR!=0 (evita spawn animation en TryRespawnMonsters)
    LD (IX+ENT_TYPE), TYPE_NONE
    LD (IX+ENT_STATE), STATE_IDLE
    LD (IX+ENT_DIR), DIR_N
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
.smSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    INC C
    DEC B
    JP NZ, .smLoop
    LD A, MONSTER_ENTRY_BASE
    LD (TryRespawnMonsters.rmTimer), A
    RET

; --- Barajar tablas tipo/color ---
ShuffleMonsterTypes:
    LD A, R
    AND 3
    RET Z
    CP 1
    JR Z, .shSwap01
    CP 2
    JR Z, .shSwap12
    LD A, (MonsterTypeTable)
    LD D, A
    LD A, (MonsterTypeTable + 2)
    LD (MonsterTypeTable), A
    LD A, D
    LD (MonsterTypeTable + 2), A
    LD A, (MonsterColorTable)
    LD D, A
    LD A, (MonsterColorTable + 2)
    LD (MonsterColorTable), A
    LD A, D
    LD (MonsterColorTable + 2), A
    RET
.shSwap01:
    LD A, (MonsterTypeTable)
    LD D, A
    LD A, (MonsterTypeTable + 1)
    LD (MonsterTypeTable), A
    LD A, D
    LD (MonsterTypeTable + 1), A
    LD A, (MonsterColorTable)
    LD D, A
    LD A, (MonsterColorTable + 1)
    LD (MonsterColorTable), A
    LD A, D
    LD (MonsterColorTable + 1), A
    RET
.shSwap12:
    LD A, (MonsterTypeTable + 1)
    LD D, A
    LD A, (MonsterTypeTable + 2)
    LD (MonsterTypeTable + 1), A
    LD A, D
    LD (MonsterTypeTable + 2), A
    LD A, (MonsterColorTable + 1)
    LD D, A
    LD A, (MonsterColorTable + 2)
    LD (MonsterColorTable + 1), A
    LD A, D
    LD (MonsterColorTable + 2), A
    RET

MonsterTypeTable:
    DEFB SPRID_MONSTER_0
    DEFB SPRID_MONSTER_1
    DEFB SPRID_MONSTER_2
MonsterColorTable:
    DEFB $44                            ; Zombi: verde
    DEFB $46                            ; Skeleton: amarillo
    DEFB $45                            ; Ghost: cyan

; ==============================================================================
; TryRespawnMonsters - Activa slots TYPE_NONE escalonadamente
; ==============================================================================
TryRespawnMonsters:
    LD A, (CurrentTimeOfDay)
    CP 3
    JR Z, .rmNight
    CP 4
    JR Z, .rmNight
    RET
.rmNight:
    LD A, (MonstersActive)
    OR A
    RET Z
    CALL .rmUpdateReturnTimers
    LD A, (.rmTimer)
    OR A
    JR Z, .rmCheckSlots
    DEC A
    LD (.rmTimer), A
    RET
.rmCheckSlots:
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
    LD C, 0
.rmLoop:
    PUSH BC
    LD A, (IX+ENT_TYPE)
    OR A
    JP NZ, .rmSkip
    ; === Activar SIN tocar POSX/POSY ===
    ; La posicion la fija quien puso TYPE_NONE en este slot:
    ;   - SpawnMonsters: hueco aleatorio via MaiPickRandomGap (Regla 1)
    ;   - rmUpdateReturnTimers: LastEntryPos tras knockback
    ;   - RepositionMonstersAtEntry: LastEntryPos al cambiar room
    ; Antes se sobreescribia aqui con LastEntryPos y machacaba la posicion
    ; de Regla 1.
    ; Tipo: usar ANIMBASE existente, o tabla si es 0
    LD A, (IX+ENT_ANIMBASE)
    OR A
    JR NZ, .rmHasType
    LD A, C
    LD HL, MonsterTypeTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (IX+ENT_ANIMBASE), A
    LD A, C
    LD HL, MonsterColorTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (IX+ENT_ATTR), A
.rmHasType:
    LD A, (IX+ENT_ANIMBASE)
    LD (IX+ENT_TYPE), TYPE_MONSTER
    LD (IX+ENT_STATE), STATE_RUNNING
    ; Facing
    LD D, A
    LD A, (EntityTable + ENT_POSX)
    CP (IX+ENT_POSX)
    JR NC, .rmFaceR
    LD A, D
    ADD A, MONSTER_FRAMES_LEFT
    JR .rmFaceSet
.rmFaceR:
    LD A, D
.rmFaceSet:
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMTIMER), ENEMY_ANIM_DELAY
    LD (IX+ENT_FLAGS), (1 << ENTF_VISIBLE) | (1 << ENTF_SOLID) | (1 << ENTF_NEWSPAWN)
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
    ; Solo UNO por frame
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

.rmTimer: DEFB 0

; --- Timers de regreso: knockback -> MAI_LINGER_PUSHED -> reaparece (Regla 4) ---
; Al expirar, reposiciona segun el borde de salida (guardado en ENT_DIR por
; .moKbOffscreen) aplicando MAI_REENTRY_OFFSET hacia dentro. El eje
; perpendicular al borde se preserva (mantiene la Y/X que tenia al ser
; empujado).
.rmUpdateReturnTimers:
    LD HL, MonsterReturnTimer
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
.rmRtLoop:
    LD A, (HL)
    OR A
    JP Z, .rmRtNext
    DEC A
    LD (HL), A
    JP NZ, .rmRtNext
    ; Timer expiro: elegir un hueco valido del borde de salida y aplicar
    ; MAI_REENTRY_OFFSET hacia dentro. Usa el filtro ScreenGaps para
    ; garantizar que la huella 2x3 del monster cabe en esa celda.
    ; Calcular target coord: axis variable segun borde de salida.
    ; N/S: cx = POSX/8. W/E: cy = (POSY - BG_Y_OFFSET*8)/8.
    LD A, (IX+ENT_DIR)
    CP DIR_N
    JR Z, .rmRtSideN
    CP DIR_S
    JR Z, .rmRtSideS
    CP DIR_E
    JP Z, .rmRtSideE
    CP DIR_W
    JP Z, .rmRtSideW
    JP .rmRtFallback
.rmRtSideN:
    ; target coord = cx = POSX / 8
    LD A, (IX+ENT_POSX)
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (MaiGapTargetCoord), A
    LD A, MAI_SIDE_N
    JR .rmRtPickGap
.rmRtSideS:
    LD A, (IX+ENT_POSX)
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (MaiGapTargetCoord), A
    LD A, MAI_SIDE_S
    JR .rmRtPickGap
.rmRtSideW:
    ; target coord = cy = (POSY - 16) / 8
    LD A, (IX+ENT_POSY)
    SUB SCREEN_MIN_Y
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (MaiGapTargetCoord), A
    LD A, MAI_SIDE_W
    JR .rmRtPickGap
.rmRtSideE:
    LD A, (IX+ENT_POSY)
    SUB SCREEN_MIN_Y
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (MaiGapTargetCoord), A
    LD A, MAI_SIDE_E
.rmRtPickGap:
    CALL MaiPickNearestGapOnSide        ; elige gap del side mas cercano al target
    OR A
    JP NZ, .rmRtFallback
    ; Ajustar MaiSpawnX/Y con MAI_REENTRY_OFFSET hacia dentro. MaiPickRandomGapOnSide
    ; usa MAI_ENTRY_OFFSET (=0) y deja el spawn al borde; aqui lo empujamos 2 chars.
    LD A, (MaiGapSide)
    CP MAI_SIDE_N
    JR Z, .rmRtAdjN
    CP MAI_SIDE_S
    JR Z, .rmRtAdjS
    CP MAI_SIDE_W
    JR Z, .rmRtAdjW
    ; side E
    LD A, (MaiSpawnX)
    SUB MAI_REENTRY_OFFSET
    LD (MaiSpawnX), A
    JR .rmRtApplyGap
.rmRtAdjN:
    LD A, (MaiSpawnY)
    ADD A, MAI_REENTRY_OFFSET
    LD (MaiSpawnY), A
    JR .rmRtApplyGap
.rmRtAdjS:
    LD A, (MaiSpawnY)
    SUB MAI_REENTRY_OFFSET
    LD (MaiSpawnY), A
    JR .rmRtApplyGap
.rmRtAdjW:
    LD A, (MaiSpawnX)
    ADD A, MAI_REENTRY_OFFSET
    LD (MaiSpawnX), A
.rmRtApplyGap:
    LD A, (MaiSpawnX)
    LD (IX+ENT_POSX), A
    LD A, (MaiSpawnY)
    LD (IX+ENT_POSY), A
    JR .rmRtReturnDone
.rmRtFallback:
    ; Sin side valido (raro) o sin gaps en ese side → LastEntryPos
    LD A, (LastEntryPosX)
    LD (IX+ENT_POSX), A
    LD A, (LastEntryPosY)
    LD (IX+ENT_POSY), A
.rmRtReturnDone:
    LD (IX+ENT_DIR), DIR_N                  ; sentinel (!=0 para skip spawn anim)
    XOR A
    LD (.rmTimer), A
.rmRtNext:
    LD DE, ENT_SIZE
    ADD IX, DE
    INC HL
    DEC B
    JP NZ, .rmRtLoop
    RET

; ==============================================================================
; RepositionMonstersAtEntry - Al cambiar de room
; ==============================================================================
RepositionMonstersAtEntry:
    LD A, (MonstersActive)
    OR A
    RET Z
    ; Cancelar timers de regreso
    XOR A
    LD (MonsterReturnTimer), A
    LD (MonsterReturnTimer + 1), A
    LD (MonsterReturnTimer + 2), A
    ; Todos a TYPE_NONE en LastEntryPos
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
.reLoop:
    PUSH BC
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR Z, .reRepos
    OR A
    JR Z, .reRepos
    JR .reSkip
.reRepos:
    ; Regla 2 (interpretacion amplia): cada monster entra por un hueco
    ; aleatorio del BORDE de entrada (no por la X exacta del player).
    ; Fallback a LastEntryPos si no hay gaps validos en ese side.
    CALL MaiGetEntrySide            ; A = side de entrada o $FF
    CP $FF
    JR Z, .reFallback
    CALL MaiPickRandomGapOnSide     ; A=0 ok, A=1 sin gaps en ese side
    OR A
    JR Z, .rePosFromGap
.reFallback:
    LD A, (LastEntryPosX)
    LD (IX+ENT_POSX), A
    LD A, (LastEntryPosY)
    LD (IX+ENT_POSY), A
    JR .rePosDone
.rePosFromGap:
    LD A, (MaiSpawnX)
    LD (IX+ENT_POSX), A
    LD A, (MaiSpawnY)
    LD (IX+ENT_POSY), A
.rePosDone:
    LD (IX+ENT_TYPE), TYPE_NONE
    LD (IX+ENT_STATE), STATE_IDLE
    LD A, (ScreenTransition)
    LD (IX+ENT_DIR), A
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
.reSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    DJNZ .reLoop
    LD A, MONSTER_ENTRY_BASE
    LD (TryRespawnMonsters.rmTimer), A
    RET

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
    LD (.enW), A                ; guardar (A=B tras GetSpriteDims? no, usar B)
    LD A, B
    LD (.enW), A
    LD A, C
    LD (.enH), A

    ; === AABB CUERPO (16px, sin espada) ===
    ; playerBodyX = ENT_POSX siempre (cuerpo), playerBodyW = 16
    LD A, (IX+ENT_POSX)
    ADD A, B
    ADD A, 4                    ; enemyX + enemyW + margen
    JR C, .bxCheck2
    LD D, A
    LD A, (EntityTable + ENT_POSX)
    CP D
    JR NC, .noBodyOverlap

.bxCheck2:
    LD A, (EntityTable + ENT_POSX)
    ADD A, 16 + 4               ; playerBodyX + 16(cuerpo) + margen
    JR C, .byCheck1
    LD D, A
    LD A, (IX+ENT_POSX)
    CP D
    JR NC, .noBodyOverlap

.byCheck1:
    LD A, (IX+ENT_POSY)
    LD D, A
    LD A, (.enH)
    ADD A, D
    ADD A, 4
    JR C, .byCheck2
    LD D, A
    LD A, (EntityTable + ENT_POSY)
    CP D
    JR NC, .noBodyOverlap

.byCheck2:
    LD A, (EntityTable + ENT_POSY)
    LD D, A
    LD A, (.plH)
    ADD A, D
    ADD A, 4
    JR C, .bodyCollision
    LD D, A
    LD A, (IX+ENT_POSY)
    CP D
    JR NC, .noBodyOverlap

.bodyCollision:
    ; Cuerpo tocado: si atacando → kill sin daño, NUNCA daño al player atacando
    LD A, (EntityTable + ENT_STATE)
    CP STATE_FIGHTING
    JP Z, .swordAction          ; Atacando → kill/knockback, sin daño
    ; No atacando → daño al player, nasty muere
    JP .playerHit

.noBodyOverlap:
    ; Cuerpo no tocado: si player atacando, comprobar AABB espada (ancho completo)
    LD A, (EntityTable + ENT_STATE)
    CP STATE_FIGHTING
    JP NZ, .nextEnemyPop        ; No atacando, no hay overlap de cuerpo → nada

    ; === AABB ESPADA (ancho completo del sprite de ataque) ===
    LD A, (.plW)                ; ancho completo (24px si atacando)
    LD D, A
    ; Calcular playerSwordX: DRAWX (puede ser POSX-8 para attack west)
    LD A, (EntityTable + ENT_DRAWX)
    LD E, A                     ; E = swordX (= drawX)
    ; enemyX + enemyW + margen > swordX ?
    LD A, (IX+ENT_POSX)
    LD H, A
    LD A, (.enW)
    ADD A, H
    ADD A, 4
    JR C, .sxCheck2
    CP E
    JP C, .nextEnemyPop         ; enemyRight < swordX → no overlap
    JP Z, .nextEnemyPop

.sxCheck2:
    ; swordX + swordW + margen > enemyX ?
    LD A, E
    ADD A, D                    ; swordX + plW
    ADD A, 4
    JR C, .syCheck1
    LD D, A
    LD A, (IX+ENT_POSX)
    CP D
    JP NC, .nextEnemyPop

.syCheck1:
    ; Y igual que antes (recheck)
    LD A, (IX+ENT_POSY)
    LD D, A
    LD A, (.enH)
    ADD A, D
    ADD A, 4
    JR C, .syCheck2
    LD D, A
    LD A, (EntityTable + ENT_POSY)
    CP D
    JP NC, .nextEnemyPop

.syCheck2:
    LD A, (EntityTable + ENT_POSY)
    LD D, A
    LD A, (.plH)
    ADD A, D
    ADD A, 4
    JR C, .swordAction
    LD D, A
    LD A, (IX+ENT_POSY)
    CP D
    JP NC, .nextEnemyPop

    ; Espada toca enemigo pero cuerpo no → kill sin daño al player
.swordAction:

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
    ; Inmunidad temporal tras recibir daño (durante flash rojo)
    LD A, (PlayerHitTimer)
    OR A
    JP NZ, .nextEnemyPop                ; Aun en inmunidad → ignorar
    ; Enemigo toca al player → daño al player
    LD A, (PlayerHealth)
    OR A
    JP Z, .nextEnemyPop                 ; Ya muerto, ignorar
    DEC A
    LD (PlayerHealth), A
    ; Flash rojo
    LD A, RED | $40
    LD (EntityTable + ENT_ATTR), A
    LD A, 6                         ; 6 frames a 25fps ~0.24s (era 12 a 50fps)
    LD (PlayerHitTimer), A
    ; Si nasty destructible → muere al tocar al player
    BIT ENTF_DESTRUCT, (IX+ENT_FLAGS)
    JR Z, .playerHitSFX
    LD (IX+ENT_STATE), STATE_DYING
    LD (IX+ENT_ANIMBASE), SPRID_PUFF
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_PUFF
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_ATTR), WHITE | $40
.playerHitSFX:
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

    ; Countdown del flash rojo
    LD A, (PlayerHitTimer)
    OR A
    RET Z
    DEC A
    LD (PlayerHitTimer), A
    RET NZ
    ; Timer llego a 0: restaurar color segun stamina actual
    CALL GetStaminaColor
    LD (EntityTable + ENT_ATTR), A
    RET

.plW: DEFB 0
.plH: DEFB 0
.enW: DEFB 0
.enH: DEFB 0
PlayerHitTimer: DEFB 0
