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

    ; -- Mushroom debuff: si timer != 0, mascara InputFire a 0 + SFX error --
    LD HL, MushroomLockTimer
    LD A, (HL)
    INC HL
    OR (HL)
    JR Z, .noMushLock
    XOR A
    LD (InputFire), A
    ; Player pulsa fire con seta activa: feedback sonoro de "no puedes".
    ; Debounce con NoSwordSoundFlag: 1 sonido por pulsacion (E=0 => libera).
    LD A, E
    OR A
    JR Z, .resetNoSwordFlag
    LD A, (NoSwordSoundFlag)
    OR A
    JR NZ, .noMushLock                   ; ya sono este press, no repetir
    LD A, 1
    LD (NoSwordSoundFlag), A
    PUSH DE                              ; PlaySFX destruye DE; D = direction
    LD HL, SFX_NoSwordError
    CALL PlaySFX
    POP DE
    JR .noMushLock
.resetNoSwordFlag:
    XOR A
    LD (NoSwordSoundFlag), A
.noMushLock:

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
    ; --- Death anim: sprite 16x16 (vs player normal 16x21). Bajar +5 para que la
    ;     base del cadaver coincida con la base del player vivo. SPRITEID en
    ;     [SPRID_PLAYER_DEATH .. SPRID_PLAYER_DEATH+5] = los 6 frames de la anim.
    LD A, (EntityTable + ENT_SPRITEID)
    SUB SPRID_PLAYER_DEATH
    CP 6
    JR NC, .cpdyNotDeath
    LD A, (EntityTable + ENT_POSY)
    ADD A, 5
    LD (PlayerDrawY), A         ; death anim → POSY+5 (sin ceiling check)
    RET
.cpdyNotDeath:
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
; ComputeEnemyDrawY - EnemyDrawY = POSY + (ceiling pegado ? 1 : 0) para
; TYPE_MONSTER, POSY sin offset para otros. IX = entity.
; Mismo concepto que ComputePlayerDrawY: separa 1 px del BG superior para
; no parecer que se hunde en el techo.
; Preserva: IX. Destruye: AF, BC.
; ==============================================================================
ComputeEnemyDrawY:
    LD A, (IX+ENT_POSY)
    LD (EnemyDrawY), A          ; default = POSY
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    RET NZ                      ; no monster → sin offset
    LD A, (IX+ENT_POSX)
    ADD A, 8                    ; center X
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    OR A
    RET Z
    DEC C                       ; Y - 1 (pixel encima de la cabeza)
    CALL IsPointBlocked
    RET Z                       ; libre → sin offset
    LD A, (IX+ENT_POSY)
    INC A
    LD (EnemyDrawY), A          ; techo pegado → offset +1
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
    ; Skip UpdatePlayer durante la fase de muerte (DeathBorderPhase != 0):
    ; el sprite y los deltas estan controlados por OnPlayerHealthDepleted /
    ; UpdateDeathAnim / UpdateDeathBorder. El draw normal sigue corriendo.
    ; Skip tambien durante phase 1 del respawn (countdown 3-2-1): el blink
    ; sincronizado con beats pone SPRITEID a IDLE/BLANK desde UpdateRespawnBlink
    ; y UpdatePlayerAnimation lo sobrescribiria.
    LD A, (DeathBorderPhase)
    OR A
    JR NZ, .plSkipUpdate
    LD A, (PlayerRespawnPhase)
    CP 1
    JR Z, .plSkipUpdate
    CALL UpdatePlayer
.plSkipUpdate:
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
    CALL GetOldSpriteAddr
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
    ; --- Frozen monster gate (durante muerte del player) ---
    ; Skip toda la AI/state dispatch para los monsters; .peCalcAndDraw refresca
    ; el sprite con la nueva pose/posicion fijada por FreezeMonstersFacingCorpse
    ; (primer frame: erase old + draw new; siguientes: skip por SPRITEID/POSX igual).
    LD A, (MonstersFrozen)
    OR A
    JR Z, .peDispatch
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JP Z, .peCalcAndDraw
.peDispatch:
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
    CP TYPE_DEATH
    JR Z, .peDeathAI
    CP TYPE_MONSTER
    JR NZ, .peNormalAI
    XOR A
    LD (MonsterKbDespawn), A        ; Reset flag
    CALL UpdateMonster
    LD A, (MonsterKbDespawn)
    OR A
    JP NZ, .peScaredDespawn         ; Knockback offscreen → borrar y despawnear
    JR .peCalcAndDraw
.peDeathAI:
    CALL UpdateDeath
    JR .peCalcAndDraw
.peNormalAI:
    CALL UpdateEnemy

    ; --- Compartido: CalcDraw + skip check + erase + draw + save ---
.peCalcAndDraw:
    CALL CalcDrawX
    CALL ComputeEnemyDrawY              ; → EnemyDrawY = POSY o POSY+1 (monster+techo)

    ; --- Skip si nada cambio ---
    LD A, (IX+ENT_DRAWX)
    CP (IX+ENT_OLDX)
    JR NZ, .peDoErase
    LD A, (EnemyDrawY)
    CP (IX+ENT_OLDY)
    JR NZ, .peDoErase
    LD A, (IX+ENT_SPRITEID)
    CP (IX+ENT_OLDSPRID)
    RET Z                               ; Nada cambio → skip todo

.peDoErase:
    ; --- Erase viejo ---
    CALL GetOldSpriteAddr
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
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr
    ; --- Draw sprite nuevo ---
    LD A, (EnemyDrawY)
    LD D, A
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
    LD A, (EnemyDrawY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    RET

    ; --- Primer frame (recien spawneado): logic + draw, sin erase ---
.peFresh:
    RES ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    LD A, (IX+ENT_TYPE)
    CP TYPE_DEATH
    JR Z, .peFreshDeath
    CP TYPE_MONSTER
    JR NZ, .peFreshNormal
    CALL UpdateMonster
    JR .peFreshDraw
.peFreshDeath:
    CALL UpdateDeath
    JR .peFreshDraw
.peFreshNormal:
    CALL UpdateEnemy
.peFreshDraw:
    CALL CalcDrawX
    CALL ComputeEnemyDrawY
    CALL GetSpriteAddr

    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr

    LD A, (EnemyDrawY)
    LD D, A
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
    JP C, .peScaredFlee
    ; Pausa: no moverse por DELTAX/DELTAY, alternar sprite L/R cada 8 frames,
    ; y (solo para monsters) agitar POSX/POSY ±1px aleatorio desde orig.
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    ; Shake monster-only (nasties durante bells no se agitan)
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JP NZ, .peScaredSpriteToggle
    ; --- Shake ---
    CALL MaiGetMonsterSlot              ; A = slot (0/1/2)
    LD E, A
    LD D, 0
    LD HL, MonsterAiFlags
    ADD HL, DE
    LD A, (HL)
    BIT 3, A                            ; MAI_FLAG_SHAKE_SAVED
    JR NZ, .peShakeActive
    ; Primer frame: guardar orig POSX/POSY, set flag, saltar shake
    OR MAI_FLAG_SHAKE_SAVED
    LD (HL), A
    LD HL, MonsterShakeOrigX
    ADD HL, DE
    LD A, (IX+ENT_POSX)
    LD (HL), A
    LD HL, MonsterShakeOrigY
    ADD HL, DE
    LD A, (IX+ENT_POSY)
    LD (HL), A
    JR .peScaredSpriteToggle
.peShakeActive:
    ; Pick random direccion cardinal ±1px (4 valores via R & 3)
    LD A, R
    AND 3
    JR Z, .peShakeUp
    DEC A
    JR Z, .peShakeDown
    DEC A
    JR Z, .peShakeLeft
    ; 3: right
    LD B, 1
    LD C, 0
    JR .peShakeApply
.peShakeUp:
    LD B, 0
    LD C, -1
    JR .peShakeApply
.peShakeDown:
    LD B, 0
    LD C, 1
    JR .peShakeApply
.peShakeLeft:
    LD B, -1
    LD C, 0
.peShakeApply:
    ; new POSX = orig + B, new POSY = orig + C
    LD HL, MonsterShakeOrigX
    ADD HL, DE
    LD A, (HL)
    ADD A, B
    LD (IX+ENT_POSX), A
    LD HL, MonsterShakeOrigY
    ADD HL, DE
    LD A, (HL)
    ADD A, C
    LD (IX+ENT_POSY), A
    ; Collision check: si bloqueado → revertir a orig (sin shake este frame)
    CALL CheckEnemyCollision
    JR Z, .peScaredSpriteToggle
    ; Blocked: recompute slot (CheckEnemyCollision destruye DE/HL/BC)
    CALL MaiGetMonsterSlot
    LD E, A
    LD D, 0
    LD HL, MonsterShakeOrigX
    ADD HL, DE
    LD A, (HL)
    LD (IX+ENT_POSX), A
    LD HL, MonsterShakeOrigY
    ADD HL, DE
    LD A, (HL)
    LD (IX+ENT_POSY), A
.peScaredSpriteToggle:
    ; Animacion: toggle L/R cada 8f
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .peScaredNoFlip
    LD (IX+ENT_ANIMTIMER), 8
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)
    XOR 2                               ; toggle bit 1: 0↔2 (R↔L)
    ADD A, (IX+ENT_ANIMBASE)
    LD (IX+ENT_SPRITEID), A
.peScaredNoFlip:
    JP .peCalcAndDraw

.peScaredFlee:
    ; Campanada 5+ / amanecer: huir. Monsters usan UpdateMonsterLeave
    ; (Regla 7: gap persistente + despawn limpio al cruzar). Nasties siguen
    ; con el flee reactivo original.
    XOR A
    LD (NastyFleeDespawn), A
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .peScaredUseNastyFlee
    CALL UpdateMonsterLeave
    JR .peScaredFleeCheckDespawn
.peScaredUseNastyFlee:
    CALL UpdateNastyFlee
.peScaredFleeCheckDespawn:
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
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .peScaredFreshUseNastyFlee
    CALL UpdateMonsterLeave
    JR .peScaredFreshCheckDespawn
.peScaredFreshUseNastyFlee:
    CALL UpdateNastyFlee
.peScaredFreshCheckDespawn:
    LD A, (NastyFleeDespawn)
    OR A
    JR NZ, .peScaredFreshDespawn
    JP .peFreshDraw

.peScaredDespawn:
    ; Erase viejo (XOR) y desactivar
    CALL GetOldSpriteAddr
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
    CALL GetOldSpriteAddr
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

    ; Si UpdateDying lo desactivo (TYPE_NONE), restaurar attrs del rect
    ; del puff (sino quedaria el color del nasty pegado en los BG sprites)
    LD A, (IX+ENT_TYPE)
    OR A
    JR NZ, .peDyingDraw
    LD D, (IX+ENT_OLDY)
    LD E, (IX+ENT_OLDX)
    JP RestoreOldAttr                   ; tail-call: restaura 4x4 chars y RET
.peDyingDraw:

    ; Draw nuevo frame puff (con SetEntityAttr para que el rect 24x24
    ; del puff quede pintado en el color del nasty muerto, ENT_ATTR)
    CALL ComputeEnemyDrawY              ; asegurar EnemyDrawY valido (OLDY save)
    CALL GetSpriteAddr
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr
    LD A, (EnemyDrawY)
    LD D, A
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
    CALL ComputeEnemyDrawY
    CALL GetSpriteAddr
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr
    LD A, (EnemyDrawY)
    LD D, A
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

    CALL GetOldSpriteAddr
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    PUSH IX
    LD IX, (OldSprAddr)
    CALL DrawSprite
    POP IX

    CALL UpdateSpawning

    ; Draw frame spawn (con SetEntityAttr: el rect 24x24 toma el color
    ; del nasty que va a aparecer, ENT_ATTR ya esta preseteado por SpawnOneNasty)
    CALL ComputeEnemyDrawY
    CALL GetSpriteAddr
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr
    LD A, (EnemyDrawY)
    LD D, A
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
    CALL ComputeEnemyDrawY
    CALL GetSpriteAddr
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr
    LD A, (EnemyDrawY)
    LD D, A
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
    ; Paging INLINE. No usar CALL PageBankSlot3 porque su RET leeria del
    ; stack tras cambiar de banco (ver nota en DrawSprite en engine_graphics).
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                  ; bank 6 paginado
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
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                  ; bank 0 de vuelta
    RET

SpriteAddrTemp: DEFW 0

; ==============================================================================
; GetOldSpriteAddr - Obtiene puntero al sprite OLD (frame anterior) de la entidad
; ==============================================================================
; Lee ENT_OLDSPRID de IX, busca en SpriteFrameTable.
; Salida:   DE = puntero al sprite data
;           OldSprAddr = mismo puntero (conveniencia para caller)
; Preserva: IX
; Destruye: A, HL
; ==============================================================================
GetOldSpriteAddr:
    ; Paging inline (ver GetSpriteAddr)
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
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
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

; ==============================================================================
; GetSpriteDims - Lee dimensiones del sprite desde su cabecera
; ==============================================================================
; Entrada: A = SpriteID
; Salida:  B = ancho en pixels (width_bytes * 8), C = alto en pixels
; Destruye: A, DE, HL
; ==============================================================================
GetSpriteDims:
    ; Paging inline (ver GetSpriteAddr). B,C son outputs y LD BC los
    ; destruye al re-paginar; guardamos en SavedB/SavedC (bank 2).
    LD L, A                     ; L = SpriteID (save A antes de clobber)
    LD H, 0
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                  ; bank 6 paginado
    ADD HL, HL
    LD DE, SpriteFrameTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = ptr al sprite data
    LD A, (DE)                  ; width_bytes
    ADD A, A
    ADD A, A
    ADD A, A                    ; × 8 = width_px
    LD B, A
    INC DE
    LD A, (DE)                  ; height_px
    LD C, A
    ; Preservar B,C via memoria (bank 2) antes de clobber por LD BC
    LD A, B
    LD (GsdSavedB), A
    LD A, C
    LD (GsdSavedC), A
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                  ; bank 0 de vuelta
    LD A, (GsdSavedB)
    LD B, A
    LD A, (GsdSavedC)
    LD C, A
    RET

GsdSavedB: DEFB 0
GsdSavedC: DEFB 0

; ==============================================================================
; UpdatePlayer - Actualiza estado, movimiento y animacion del player
; ==============================================================================
; IX = puntero a la entidad del player (slot 0)
; ==============================================================================
UpdatePlayer:
    CALL UpdatePlayerState
    CALL UpdatePlayerMovement
    CALL UpdatePlayerAnimation
    ; Phase 2 grace blink: PlayerRespawnTimer != 0 sólo durante phase 2 aquí
    ; (phase 1 está gateado en ProcessPlayer; phase 0 → timer=0 → no-op).
    ; Toggle SPRITEID a BLANK cada ~2 frames vía bit 1 del GameFrameCounter
    ; (~6 Hz). UpdatePlayerAnimation acaba de fijar el frame normal; este
    ; override solo lo sustituye en frames OFF, dejando la animación viva en
    ; los ON. Slot 0 = player, ENT_SPRITEID=0 → escribir a (EntityTable).
    ; ON frame: si SPRITEID quedó como BLANK del frame OFF anterior porque
    ; la animación (idle, ANIM_DELAY=10) no tickeó este frame, restaurar a
    ; ANIMBASE para que el ON se vea. Sin esto, vista frontal idle queda
    ; invisible toda la gracia (caminando funciona porque ANIM_DELAY_RUN=2
    ; tickea a tiempo y reescribe SPRITEID).
    LD A, (PlayerRespawnTimer)
    OR A
    RET Z
    LD A, (GameFrameCounter)
    AND 2
    JR Z, .pblOffFrame
    ; ON frame: validar SPRITEID — si está como BLANK, restaurar a ANIMBASE
    LD A, (IX+ENT_SPRITEID)
    CP SPRID_PLAYER_BLANK
    RET NZ                              ; sprite válido (anim viva) → keep
    LD A, (IX+ENT_ANIMBASE)
    LD (IX+ENT_SPRITEID), A             ; restaurar al frame base
    RET
.pblOffFrame:
    LD A, SPRID_PLAYER_BLANK
    LD (EntityTable), A
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
    XOR A
    LD (.skipVertical), A       ; reset flag por frame
    LD A, PLAYER_MOVE_TURNS
    LD (PlayerMoveTimer), A     ; Resetear timer

    LD A, (IX+ENT_DIR)
    AND $0F                     ; Dir actual (bits 0-3)
    RET Z                       ; Sin movimiento

    ; Determinar velocidad base segun estado. Speed efectivo vive en RAM
    ; (PlayerSpeedRun/Fight) modificable por buffs rayo/caracol; defaults =
    ; SPEED_RUN/SPEED_FIGHT.
    LD A, (IX+ENT_STATE)
    CP STATE_FIGHTING
    JR Z, .speedFight
    LD A, (PlayerSpeedRun)
    JR .gotBaseSpeed
.speedFight:
    LD A, (PlayerSpeedFight)
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
    ; Step-up minimo: SUB 8 (1 char) un solo intento. Si clarea, acepta y
    ; activa skipVertical (para que el bloque vertical no compense el lift
    ; con input S/N en frames diagonales). Si no clarea, falla y revierte X.
    ; Sin step-down ni iteracion ni snap-to-char: behavior simple y predecible
    ; estilo Sabre Wulf clasico.
    LD A, (IX+ENT_POSY)
    CP SCREEN_MIN_Y + 8
    JR C, .revertX
    LD (.savedYStep), A
    SUB 8
    LD (IX+ENT_POSY), A
    CALL CheckEntityCollision
    JR NZ, .stepFail
    CALL CheckPlayerMonsterOverlap
    JR NZ, .stepFail
    LD A, 1
    LD (.skipVertical), A
    JR .xOk
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

    ; Si el step-up/down ya modifico Y este frame, ignorar input S/N para no
    ; compensar el snap-to-char (causaba desalineacion + rebotes).
    LD A, (.skipVertical)
    OR A
    RET NZ                      ; step-up tomo el frame; no mover Y mas

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
    JR NZ, .revertY             ; sin sidestep: si Y choca, revertir
.yEntColOK:
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
.savedXShift: DEFB 0
; Flag: el step-up/down (X collision) modifico Y este frame -> el bloque
; vertical debe ignorar el input S/N para no compensar el snap. Simetrico
; para sidestep (Y collision): si modifico X, .skipHoriz no aplica porque
; horizontal corre primero. Solo .skipVertical es necesario.
.skipVertical: DEFB 0

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
    ; Solo monsters activos, no muriendo/spawneando/asustados (scared = atravesables)
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .cpmoNext
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    JR Z, .cpmoNext
    CP STATE_SPAWNING
    JR Z, .cpmoNext
    CP STATE_SCARED
    JR Z, .cpmoNext                     ; trembling/flee: atravesable

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
    ; Regen-por-tiempo de salud desactivada para subir dificultad.
    ; Salud solo se recupera por pozo / pickups. Reactivar quitando los `;`
    ; (candidato a difficulty level "fácil" en el futuro).
    ; LD A, (PlayerHealth)
    ; CP HEALTH_MAX
    ; JR Z, .usHealthFull
    ; LD HL, HealthRegenCtr
    ; INC (HL)
    ; LD A, (HL)
    ; CP HEALTH_REGEN_RATE
    ; JR C, .usHealthFull
    ; LD (HL), 0
    ; LD A, (PlayerHealth)
    ; INC A
    ; LD (PlayerHealth), A
.usHealthFull:
    ; --- Stamina: consumir o regenerar ---
    LD A, (IX+ENT_STATE)
    CP STATE_FIGHTING
    JR Z, .usDrain
    ; No atacando: regenerar
    ; Regen-por-tiempo de stamina desactivada para subir dificultad.
    ; Stamina solo se recupera por pozo / pickups. Reactivar quitando los `;`
    ; y eliminando el RET justo debajo (candidato a difficulty level "fácil").
    RET
    ; LD A, (PlayerStamina)
    ; CP STAMINA_MAX
    ; RET Z                               ; Ya al maximo
    ; LD HL, StaminaRegenCtr
    ; INC (HL)
    ; LD A, (HL)
    ; CP STAMINA_REGEN_RATE
    ; RET C                               ; Aun no toca
    ; LD (HL), 0                          ; Reset counter
    ; LD A, (PlayerStamina)
    ; INC A
    ; LD (PlayerStamina), A
    ; RET
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
    ; Cooldown activo? No curar (pozo "agotado" visual en blanco)
    LD HL, (WellCooldownTimer)
    LD A, H
    OR L
    RET NZ                              ; timer > 0 → skip
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
    ; Arrancar cooldown: capturar attrs originales + pintar blanco
    CALL StartWellCooldown
    LD HL, SFX_WellRecover
    CALL PlaySFX
.cwNoOverlap:
    RET

; ==============================================================================
; StartWellCooldown - al usar el pozo: captura originals, pinta blanco, arranca timer
; ==============================================================================
; Lee los 2 attrs actuales de CleanAttrMap (cian "limpio", ignora overlays
; de player/enemigos), los guarda en WellOrigAttrN para restaurar al final
; del cooldown. Luego pinta blanco en VRAM y CleanAttrMap.
; ==============================================================================
StartWellCooldown:
    CALL GetWellBottomOffset            ; HL = offset fila inferior en attr map
    PUSH HL
    LD DE, CleanAttrMap
    ADD HL, DE
    LD A, (HL)
    LD (WellOrigAttr0), A
    INC HL
    LD A, (HL)
    LD (WellOrigAttr1), A
    POP HL
    CALL PaintWellWhiteAt               ; pinta blanco VRAM + CleanAttrMap
    LD HL, WELL_COOLDOWN_FRAMES
    LD (WellCooldownTimer), HL
    RET

; ==============================================================================
; ApplyWellCooldownIfActive - al entrar en la room con cooldown activo
; ==============================================================================
; Solo pinta blanco (no re-captura originals; los almacenados en
; WellOrigAttrN siguen siendo válidos del cooldown inicial). Se llama tras
; CADA DrawBgGfxSprite dentro del loop de DrawScreen y tras SaveCleanAttrs
; para que el flash de cian dure lo mínimo posible.
; ==============================================================================
ApplyWellCooldownIfActive:
    LD A, (WellActive)
    OR A
    RET Z
    LD HL, (WellCooldownTimer)
    LD A, H
    OR L
    RET Z
    CALL GetWellBottomOffset
    JP PaintWellWhiteAt

; ==============================================================================
; GetWellBottomOffset - HL = offset de la celda inferior-izquierda del pozo
; ==============================================================================
; Relativo a attr map (sin base). Para VRAM suma ATTR_BASE, para
; CleanAttrMap suma CleanAttrMap.
; Destruye: A, DE
; ==============================================================================
GetWellBottomOffset:
    LD A, (WellPosY)
    LD H, 0
    LD L, A
    ADD HL, HL
    ADD HL, HL                          ; (pixel_y/8)*32
    LD A, (WellPosX)
    RRCA
    RRCA
    RRCA
    AND $1F
    ADD A, L
    LD L, A
    JR NC, .gwbNoCarry
    INC H
.gwbNoCarry:
    LD DE, 32
    ADD HL, DE                          ; offset fila inferior
    RET

; ==============================================================================
; PaintWellWhiteAt - escribe blanco (L=bright, R=no bright) en VRAM + CleanAttrMap
; ==============================================================================
; IN: HL = offset fila inferior (relativo a attr map)
; ==============================================================================
PaintWellWhiteAt:
    PUSH HL
    ; VRAM
    LD DE, ATTR_BASE
    ADD HL, DE
    LD A, WELL_COOLDOWN_ATTR_L
    LD (HL), A
    INC HL
    LD A, WELL_COOLDOWN_ATTR_R
    LD (HL), A
    POP HL
    ; CleanAttrMap
    LD DE, CleanAttrMap
    ADD HL, DE
    LD A, WELL_COOLDOWN_ATTR_L
    LD (HL), A
    INC HL
    LD A, WELL_COOLDOWN_ATTR_R
    LD (HL), A
    RET

; ==============================================================================
; UpdateWellCooldown - decrementa timer; al llegar a 0 restaura attrs originales
; ==============================================================================
; Llamar 1x por frame. Durante cooldown NO hay repaint: StartWellCooldown ya
; dejó blanco en VRAM y en CleanAttrMap, así que todo restore de entidades
; lee blanco del mapa limpio. Solo en la transición a 0 restauramos cian.
; ==============================================================================
UpdateWellCooldown:
    LD HL, (WellCooldownTimer)
    LD A, H
    OR L
    RET Z                               ; 0 → nada que hacer
    DEC HL
    LD (WellCooldownTimer), HL
    LD A, H
    OR L
    RET NZ                              ; > 0 → esperar
    ; Timer acaba de llegar a 0. Si estamos en la room del pozo, restaurar
    ; attrs originales. Si no, al volver DrawScreen ya dibuja cian normal.
    LD A, (WellActive)
    OR A
    RET Z
    JP RestoreWellOriginalAttrs

; ==============================================================================
; RestoreWellOriginalAttrs - escribe WellOrigAttrN a VRAM y CleanAttrMap
; ==============================================================================
RestoreWellOriginalAttrs:
    CALL GetWellBottomOffset
    PUSH HL
    ; VRAM
    LD DE, ATTR_BASE
    ADD HL, DE
    LD A, (WellOrigAttr0)
    LD (HL), A
    INC HL
    LD A, (WellOrigAttr1)
    LD (HL), A
    POP HL
    ; CleanAttrMap
    LD DE, CleanAttrMap
    ADD HL, DE
    LD A, (WellOrigAttr0)
    LD (HL), A
    INC HL
    LD A, (WellOrigAttr1)
    LD (HL), A
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
    ; Trampa de la iglesia (paso 7): detectar el INTENTO de cruzar la
    ; puerta. POSX/POSY ya tienen la would-be posicion; la puerta abierta
    ; es wall en CollisionMap, asi que el check debe ocurrir antes de
    ; CheckEnemyCollision.
    ; CheckChurchTrap retorna:
    ;   A=0 -> no es trampa, seguir flujo normal (collision check).
    ;   A=1 -> trampa disparada, cutscene activa: salir.
    ;   A=2 -> tipo no esperado en zona de trampa: tratar como wall.
    CALL CheckChurchTrap
    OR A
    JR Z, .moKbCollCheck
    CP 2
    JP Z, .moKbWallBlock                ; tipo no esperado -> rebotar
    POP DE                              ; limpiar PUSH DE previo
    RET                                 ; cutscene activa, salir
.moKbCollCheck:
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
    ; Kb heredado por billar: NO es directo del player.
    ; Limpia el bit -> CheckChurchTrap no disparara la trampa para este kb.
    RES ENTF_KB_DIRECT, (IX+ENT_FLAGS)
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
    ; Elegir eje de salida por MAGNITUD DEL KNOCKBACK, no por el eje que
    ; cruzo el borde primero. Asi el monster sale por el lado que el
    ; player quiso empujar (eje primario) aunque llegue al borde del eje
    ; secundario un frame antes por drift diagonal.
    ;
    ; |DX| vs |DY|: eje primario = mayor magnitud. En empate, horizontal.
    LD A, (IX+ENT_DELTAX)
    BIT 7, A
    JR Z, .moKbAbsDxOk
    NEG
.moKbAbsDxOk:
    LD B, A                             ; B = |dx|
    LD A, (IX+ENT_DELTAY)
    BIT 7, A
    JR Z, .moKbAbsDyOk
    NEG
.moKbAbsDyOk:
    ; A = |dy|, B = |dx|
    CP B
    JR NC, .moKbPrimY                   ; |dy| >= |dx| → Y primario
.moKbPrimX:
    ; Eje primario X → clamp X, mantener Y (clampeado al rango valido)
    LD A, (IX+ENT_DELTAX)
    BIT 7, A
    JR NZ, .moKbExitLeft
    LD (IX+ENT_POSX), SCREEN_MAX_X - 1
    LD A, DIR_E
    JR .moKbClampY
.moKbExitLeft:
    LD (IX+ENT_POSX), 0
    LD A, DIR_W
.moKbClampY:
    ; Proteger POSY: si el drift lo saco de rango, clamparlo al borde
    LD C, A                             ; C = DIR_E/W
    LD A, (IX+ENT_POSY)
    CP SCREEN_MAX_Y
    JR C, .moKbClampYHigh
    ; POSY >= MAX (salio abajo o underflow): clamp a MAX-1
    LD A, SCREEN_MAX_Y - 1
    LD (IX+ENT_POSY), A
    JR .moKbClampXDone
.moKbClampYHigh:
    CP SCREEN_MIN_Y
    JR NC, .moKbClampXDone              ; POSY >= MIN, OK
    LD A, SCREEN_MIN_Y
    LD (IX+ENT_POSY), A
.moKbClampXDone:
    LD A, C
    JR .moKbClampDone

.moKbPrimY:
    ; Eje primario Y → clamp Y, mantener X (clampeado al rango valido)
    LD A, (IX+ENT_DELTAY)
    BIT 7, A
    JR NZ, .moKbExitTop
    LD (IX+ENT_POSY), SCREEN_MAX_Y - 1
    LD A, DIR_S
    JR .moKbClampX
.moKbExitTop:
    LD (IX+ENT_POSY), SCREEN_MIN_Y
    LD A, DIR_N
.moKbClampX:
    LD C, A                             ; C = DIR_N/S
    LD A, (IX+ENT_POSX)
    CP SCREEN_MAX_X
    JR C, .moKbClampXHigh
    LD A, SCREEN_MAX_X - 1
    LD (IX+ENT_POSX), A
    JR .moKbClampYDone
.moKbClampXHigh:
    CP MONSTER_KB_SPEED
    JR NC, .moKbClampYDone              ; POSX >= KB_SPEED, OK
    XOR A
    LD (IX+ENT_POSX), A
.moKbClampYDone:
    LD A, C
.moKbClampDone:
    ; Monster empujado fuera: memoria de ubicacion + timer de regreso.
    ;
    ; Doble comportamiento:
    ; - Si el player PERMANECE en este room: al expirar el timer, el monster
    ;   vuelve por el mismo borde (Regla 4 clasica, via .rmUpdateReturnTimers).
    ; - Si el player CRUZA al room destino antes del timer: el monster ya
    ;   esta alli (RepositionMonstersAtEntry .reInNew path cancela el timer
    ;   y lo activa).
    ; - Si el player cruza a OTRO room distinto: .reSkip cancela el timer.
    ;   El monster queda en destino (memoria) hasta que el player visite.
    ;
    ; Registros: ENT_DIR = exit DIR, MonsterRoomId = destino, MonsterEntryBorder
    ; = MAI_SIDE opuesto, MonsterReturnTimer[slot] = LINGER, despawn = 1.
    LD (IX+ENT_DIR), A                  ; A = DIR_N/S/E/W
    LD (.moKbSavedDir), A
    LD A, 1
    LD (MonsterKbDespawn), A
    ; Calcular slot (0-2) en E, D=0
    PUSH IX
    POP HL
    LD DE, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    OR A
    SBC HL, DE
    SRL L
    SRL L
    SRL L
    SRL L
    LD E, L
    LD D, 0
    ; Clear MAI_FLAG_LEAVING
    LD HL, MonsterAiFlags
    ADD HL, DE
    LD A, (HL)
    AND ~MAI_FLAG_LEAVING & $FF
    LD (HL), A
    ; MonsterRoomId[slot] = neighbor_id (destino)
    LD A, (.moKbSavedDir)
    CALL MaiGetNeighborScreenId
    LD HL, MonsterRoomId
    ADD HL, DE
    LD (HL), A
    ; MonsterEntryBorder[slot] = MAI_SIDE opuesto
    LD A, (.moKbSavedDir)
    CALL MaiDirToEntrySide
    LD HL, MonsterEntryBorder
    ADD HL, DE
    LD (HL), A
    ; MonsterReturnTimer[slot] = LINGER_PUSHED (para regreso si player se queda)
    LD HL, MonsterReturnTimer
    ADD HL, DE
    LD (HL), MAI_LINGER_PUSHED
    RET

.moKbSavedDir: DEFB 0
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
    ; EXCEPCION: Death (TYPE_DEATH) ignora el skip aleatorio. La muerte debe
    ; ser implacable, sin pausas erraticas. En el Sabre Wulf original, FIRE
    ; tampoco tenia esta erraticidad — solo los monsters normales.
    LD A, (IX+ENT_TYPE)
    CP TYPE_DEATH
    JR Z, .moDoMove
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
    ; La muerte usa toda la AI de UpdateMonster (chase + rodeo + 4-candidate)
    ; pero su sprite tiene 4 frames (R0,R1,L0,L1) en vez de 8 → animacion
    ; distinta. Redirigir TYPE_DEATH a DeathAnimate.
    LD A, (IX+ENT_TYPE)
    CP TYPE_DEATH
    JP Z, DeathAnimate
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
    ; Check solapamiento con player. EXCEPCION: Death puede solapar al player
    ; (su gameplay es matarlo al tocarlo). Sin este skip, el chase rechazaba
    ; movimientos que solaparian al player y Death se quedaba 1px adyacente.
    LD A, (IX+ENT_TYPE)
    CP TYPE_DEATH
    JR Z, .moPassRestore                ; Death: skip overlap check (Z desde CP)
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
    PUSH HL
    CALL GetOldSpriteAddr               ; DE = sprite ptr (HL trashed)
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
    IF DEBUG_NO_ENEMIES
    RET
    ENDIF
    ; Bloquear durante la pausa cinematografica post-cutscene de iglesia.
    ; Timer cuenta de 50 (=2s) a 0; key aparece en t=1s; nasties resumen
    ; cuando el timer llega a 0.
    LD A, (PostTrapPauseTimer)
    OR A
    RET NZ
    ; Bloquear durante la fase de muerte del player (yellow + red): nasties
    ; no respawnean hasta que termine el rojo y el player reaparezca en LastEntryPos.
    LD A, (DeathBorderPhase)
    OR A
    RET NZ
    ; Bloquear durante phase 1 del respawn (countdown 3-2-1 sin control).
    ; Al pasar a phase 2 se reinicia SpawnTimer = SPAWN_INTERVAL para que el
    ; primer nasty aparezca con la misma pausa que al entrar a sala nueva.
    LD A, (PlayerRespawnPhase)
    CP 1
    RET Z
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
    ; Si los 3 monsters estan atrapados, los blockers nocturnos (MonstersActive
    ; + N2 + A1) se levantan: la noche queda "vacia" sin captura/persecucion,
    ; rellenamos con nasties crepusculares hasta A2.
    LD A, (MonsterTrappedFlags)
    AND $07
    CP $07
    JR Z, .spawnIgnoreNightBlocks
    ; Bloquear spawn mientras los monsters esten activos (N1+N2+A1).
    ; Sin esto, los nasties spawneados a finales de N1 antes de las campanadas
    ; conviven con los 3 monsters → 6 entidades en EntityTable competiendo por
    ; el budget MAX_ENEMIES_PER_FRAME=2 → ralentizacion percibida en monsters.
    LD A, (MonstersActive)
    OR A
    RET NZ
    ; Bloquear spawn en N2 y A1 (no reaparecen hasta A2)
    LD A, (CurrentTimeOfDay)
    CP 4                        ; N2
    RET Z
    CP 5                        ; A1
    RET Z
.spawnIgnoreNightBlocks:
    ; Spawn UNO por timer-fire para evitar que aparezcan todos a la vez.
    ; Tras un spawn exitoso (TYPE != 0), reset SpawnTimer = SPAWN_GAP y
    ; salir; el siguiente slot vacio esperara el gap. Si todos los slots
    ; estan ocupados o spawn falla, no resetea timer (sigue intentando).
    LD IX, EntityTable + (SLOT_NASTY0 * ENT_SIZE)
    LD B, NUM_NASTIES
.spawnLoop:
    PUSH BC
    LD A, (IX+ENT_TYPE)
    OR A
    JR NZ, .spawnNextSlot
    CALL SpawnOneNasty
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .spawnNextSlot                ; spawn fallo (sin posiciones libres)
    ; Spawn exitoso: gap random 0..7 frames antes del siguiente nasty
    ; (un poco de irregularidad en la cadencia de aparicion).
    LD A, R
    AND $07
    LD (SpawnTimer), A
    POP BC
    RET
.spawnNextSlot:
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
    ; Spawn anim segun momento del dia: nocturno (CrepuscularTypeTable) usa
    ; SPRID_SPAWN_NIGHT, diurno usa SPRID_SPAWN.
    LD A, (CurrentNastyTable)
    CP LOW CrepuscularTypeTable
    JR NZ, .spnDay
    LD A, (CurrentNastyTable + 1)
    CP HIGH CrepuscularTypeTable
    JR NZ, .spnDay
    LD A, SPRID_SPAWN_NIGHT
    JR .spnSet
.spnDay:
    LD A, SPRID_SPAWN
.spnSet:
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMBASE), A
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

    ; Bbox 24x24 fijo para nasties (truco "puff-fit"): el spawn check usa el
    ; mismo bbox que el movimiento (CheckEnemyCollision con TYPE_NASTY → H=24).
    ; Asi el nasty arranca en una celda donde caben los 24x24 del puff/spawn
    ; sin asomar al BG, y movimiento posterior es consistente. Sin esto, nasties
    ; bajos (Bat 8h, Eagle/Rat 9h) spawneaban en sitios que pasaban el viejo
    ; check (14h) pero quedaban atascados al moverse (move-check exige 24h).
    LD A, 23                            ; W-1 = 23 (24 px)
    LD (.spawnW1), A
    LD A, 23                            ; H-1 = 23 (24 px)
    LD (.spawnH1), A

    ; (ZoneCellList se construye en DrawScreen con player pos en la entrada
    ; y filtro Manhattan; lista estatica durante toda la estancia en la sala.
    ; Sin rebuild aqui = sin lag por spawn.)
    ; Posicion aleatoria (con reintentos)
    LD A, 8                             ; mas reintentos: ahora tambien hay min-distance check
    LD (.spawnTries), A
    XOR A
    LD (.spawnIgnoreZone), A            ; primera ronda respeta zona del player

.spawnRetry:
    ; Picker: si .spawnIgnoreZone=0 y la lista de celdas alcanzables tiene
    ; entradas, elegir aleatorio de la lista (garantiza zona del player).
    ; Si fallback (.spawnIgnoreZone=1) o lista vacia: random X/Y de pantalla.
    LD A, (.spawnIgnoreZone)
    OR A
    JR NZ, .spwRandomXY
    LD A, (ZoneCellCount)
    OR A
    JR Z, .spwRandomXY                  ; lista vacia → fallback random
    ; idx = R mod count
    LD B, A                             ; B = count
    LD A, R
.spwIdxLoop:
    CP B
    JR C, .spwIdxOk
    SUB B
    JR .spwIdxLoop
.spwIdxOk:
    LD H, 0
    LD L, A
    ADD HL, HL                          ; idx*2
    LD DE, ZoneCellList
    ADD HL, DE
    LD A, (HL)                          ; cx (ya filtrado Manhattan en BuildZoneCellList)
    ADD A, A
    ADD A, A
    ADD A, A                            ; cx*8
    LD (IX+ENT_POSX), A
    INC HL
    LD A, (HL)                          ; cy
    ADD A, A
    ADD A, A
    ADD A, A                            ; cy*8
    ADD A, SCREEN_MIN_Y
    LD (IX+ENT_POSY), A
    JR .spwPosSet
.spwRandomXY:
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
.spwPosSet:
    ; --- Bounds check: el sprite entero debe caber en pantalla ---
    ; X: POSX + (W-1) NO debe wrap 8-bit (sprite extiende a >$FF se renderiza
    ; recortado en borde izq via wraparound visual).
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.spawnW1)
    ADD A, B
    JP C, .spawnBlocked
    ; Y: POSY + (H-1) < SCREEN_MAX_Y (no invadir HUD inferior).
    LD A, (IX+ENT_POSY)
    LD B, A
    LD A, (.spawnH1)
    ADD A, B
    JP C, .spawnBlocked                 ; wrap Y tambien malo
    CP SCREEN_MAX_Y
    JP NC, .spawnBlocked                ; sprite invade HUD
    ; Comprobar colision: 4 esquinas
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JP NZ, .spawnBlocked
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.spawnW1)
    ADD A, B
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JP NZ, .spawnBlocked
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (IX+ENT_POSY)
    LD C, A
    LD A, (.spawnH1)
    ADD A, C
    LD C, A
    CALL IsPointBlocked
    JP NZ, .spawnBlocked
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
    JP NZ, .spawnBlocked
    ; (Zone garantizada por el picker desde ZoneCellList; si fallback random,
    ; .spawnIgnoreZone=1 y aceptamos cualquier zona.)
    ; --- Solapamiento con player (AABB ambos ejes < 24 px = overlap real) ---
    ; Antes el check era OR (cualquiera de los ejes < 24 → block). Eso es una
    ; CRUZ de exclusion: si player en el pasillo, TODA la fila del pasillo se
    ; rechaza por Y cercana → nunca aparecen nasties en el pasillo. AND es
    ; correcto: solo bloquear si los rectangulos solapan en 2D.
    LD A, (EntityTable + ENT_POSX)
    SUB (IX+ENT_POSX)
    JR NC, .spAbsX
    NEG
.spAbsX:
    CP 24
    JR NC, .spPlayerOk                  ; |dx| >= 24 → no overlap posible, skip Y
    LD A, (EntityTable + ENT_POSY)
    SUB (IX+ENT_POSY)
    JR NC, .spAbsY
    NEG
.spAbsY:
    CP 24
    JR C, .spawnBlocked                 ; |dx| < 24 AND |dy| < 24 → demasiado cerca
.spPlayerOk:
    ; Min-distance check vs otras nasties activas (32 px en cualquier eje).
    ; Sin esto, dos nasties pueden spawnear pegadas y solaparse visualmente.
    PUSH IX
    POP HL                              ; HL = ptr al slot que estamos spawneando
    LD IY, EntityTable + (SLOT_NASTY0 * ENT_SIZE)
    LD B, NUM_NASTIES
.spDistLoop:
    PUSH BC
    PUSH HL
    PUSH IY
    POP DE                              ; DE = ptr al slot vecino
    OR A
    SBC HL, DE                          ; HL == 0 → mismo slot, skip
    POP HL
    JR Z, .spDistNext
    LD A, (IY+ENT_TYPE)
    OR A
    JR Z, .spDistNext                   ; vecino vacio
    ; |dx|
    LD A, (IX+ENT_POSX)
    SUB (IY+ENT_POSX)
    JR NC, .spdAbsX
    NEG
.spdAbsX:
    CP 32
    JR NC, .spDistNext                  ; suficiente separacion en X
    ; |dy|
    LD A, (IX+ENT_POSY)
    SUB (IY+ENT_POSY)
    JR NC, .spdAbsY
    NEG
.spdAbsY:
    CP 32
    JR NC, .spDistNext
    ; Demasiado cerca en ambos ejes → retry
    POP BC
    JR .spawnBlocked
.spDistNext:
    LD DE, ENT_SIZE
    ADD IY, DE
    POP BC
    DJNZ .spDistLoop
    JP .spawnPosOk
.spawnBlocked:
    LD A, (.spawnTries)
    DEC A
    LD (.spawnTries), A
    JP NZ, .spawnRetry
    ; Primera ronda fallida. Si respetabamos zona (8 retries quemados sin
    ; encontrar celda alcanzable), hacer 4 mas ignorando zona como fallback.
    LD A, (.spawnIgnoreZone)
    OR A
    JR NZ, .spawnGiveUp
    LD A, 1
    LD (.spawnIgnoreZone), A
    LD A, 4
    LD (.spawnTries), A
    JP .spawnRetry
.spawnGiveUp:
    ; Todos los intentos fallaron → cancelar spawn
    LD (IX+ENT_TYPE), TYPE_NONE
    RET

.spawnTries:      DEFB 0
.spawnIgnoreZone: DEFB 0
.spawnW1:         DEFB 0
.spawnH1:         DEFB 0
.spawnSeed:       DEFB 137       ; Semilla rotante para dispersar posiciones

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
    ; Si signos coinciden con la ultima nasty spawneada, voltear DELTAY.
    ; Sin esto, R cercanos en frames consecutivos producen direcciones
    ; identicas y las nasties van en paralelo solapadas.
    LD A, (IX+ENT_DELTAX)
    AND $80                             ; bit 7 = signo X
    LD B, A
    LD A, (IX+ENT_DELTAY)
    AND $80                             ; bit 7 = signo Y
    RRCA                                ; mover a bit 6 para diferenciarlo de B
    OR B                                ; A = signX(7) | signY(6)
    LD B, A
    LD A, (LastSpawnDirSigns)
    CP B
    JR NZ, .spawnDirOk
    ; Coincide -> voltear DELTAY (negar)
    LD A, (IX+ENT_DELTAY)
    NEG
    LD (IX+ENT_DELTAY), A
    LD A, B
    XOR $40                             ; recalcular signs cacheados
    LD B, A
.spawnDirOk:
    LD A, B
    LD (LastSpawnDirSigns), A

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
    DEFB 4                              ; Ciclo 1: 2px (subido desde 1px)
    DEFB 5                              ; Ciclo 2: 2.5px
    DEFB 6                              ; Ciclo 3: 3px
    DEFB 7                              ; Ciclo 4: 3.5px
    DEFB 8                              ; Ciclo 5: 4px
    DEFB 9                              ; Ciclo 6: 4.5px
    DEFB 10                             ; Ciclo 7: 5px
    DEFB 11                             ; Ciclo 8: 5.5px
    DEFB 12                             ; Ciclo 9: 6px
    DEFB 14                             ; Ciclo 10: 7px

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
    JR Z, .kanSkip                  ; ya muriendo
    ; SPAWNING no se skipea: peDying erasea OLDSPRID (= spawn frame actual)
    ; y dibuja puff. La muerte del player debe limpiar nasties medio-spawneados.
    ; Transicionar a STATE_DYING con puff (ENT_ATTR queda con el color
    ; del nasty: peDying paintea el rect del puff con ese color)
    CALL SnapPuffPos                ; ajusta POSX/POSY a hueco 24x24 cercano
    LD (IX+ENT_STATE), STATE_DYING
    LD (IX+ENT_ANIMBASE), SPRID_PUFF
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_PUFF
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
.kanSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    DJNZ .kanLoop
    RET

; ==============================================================================
; SnapPuffPos - Ajusta POSX/POSY del nasty para que el puff 24x24 quepa en BG
; ==============================================================================
; Llamado al transicionar a STATE_DYING con puff (KillAllActiveNasties + sword
; hit + player hit destructible). Si la posicion actual ya cabe 24x24, no
; cambia nada. Si no, busca un hueco 24x24-clear en orden de distancia
; creciente (Y arriba/abajo +/-8/+/-16, luego X laterales). Si nada cabe,
; deja la posicion original (puff puede asomar levemente, raro).
; IN:  IX = nasty entity.
; OUT: IX+ENT_POSX/POSY pueden modificarse.
; Destruye: AF, BC, DE, HL.
; ==============================================================================
SnapPuffPos:
    LD A, (IX+ENT_POSX)
    LD (.sppOrigX), A
    AND $F8
    LD (.sppBaseX), A                   ; base char-aligned X
    LD A, (IX+ENT_POSY)
    LD (.sppOrigY), A
    AND $F8
    LD (.sppBaseY), A                   ; base char-aligned Y

    ; 1) Probar la posicion original (puede caber si las 4 char-rows estan libres)
    CALL .sppCheckFit
    RET Z

    ; 2) Probar shifts desde la base char-aligned. Asi cada candidato cubre
    ;    exactamente 3x3 chars (no 4x4 por desalineamiento).
    LD HL, .sppShifts
.sppLoop:
    LD A, (HL)
    INC HL
    LD B, A                             ; dx (signed)
    LD A, (HL)
    INC HL
    CP $80
    JR Z, .sppFail                      ; sentinel
    LD C, A                             ; dy (signed)

    LD A, (.sppBaseX)
    ADD A, B
    LD (IX+ENT_POSX), A
    LD A, (.sppBaseY)
    ADD A, C
    LD (IX+ENT_POSY), A

    PUSH HL
    CALL .sppCheckFit
    POP HL
    RET Z                               ; encontrado
    JR .sppLoop

.sppFail:
    LD A, (.sppOrigX)
    LD (IX+ENT_POSX), A
    LD A, (.sppOrigY)
    LD (IX+ENT_POSY), A
    RET

; --- .sppCheckFit ---
; Z si todas las celdas del bbox 24x24 en (POSX,POSY) son libres en
; CollisionMap y dentro de pantalla; NZ si alguna bloqueada o fuera de bounds.
; Reusa CheckEnemyCollision (que itera TODAS las celdas del bbox) seteando
; temporalmente SPRITEID = SPRID_PUFF (24x24). Esto cubre tanto el caso
; aligned (3x3 chars) como shifted (4x3 chars, overflow byte incluido).
.sppCheckFit:
    ; Bounds: POSX en [0..SCREEN_MAX_X-24], POSY en [SCREEN_MIN_Y..SCREEN_MAX_Y-24]
    LD A, (IX+ENT_POSX)
    CP SCREEN_MAX_X - 23
    JR NC, .sppOutOfBounds
    LD A, (IX+ENT_POSY)
    CP SCREEN_MIN_Y
    JR C, .sppOutOfBounds
    CP SCREEN_MAX_Y - 23
    JR NC, .sppOutOfBounds
    ; Reusa CheckEnemyCollision con SPRID_PUFF (24x24) temporal
    LD A, (IX+ENT_SPRITEID)
    LD (.sppSpritIdSave), A
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    CALL CheckEnemyCollision            ; Z = libre, NZ = bloqueado
    PUSH AF
    LD A, (.sppSpritIdSave)
    LD (IX+ENT_SPRITEID), A
    POP AF
    RET
.sppOutOfBounds:
    OR 1                                ; NZ
    RET

.sppSpritIdSave: DEFB 0

.sppOrigX: DEFB 0
.sppOrigY: DEFB 0
.sppBaseX: DEFB 0
.sppBaseY: DEFB 0
.sppShifts:
    ; Pares (dx, dy) signed bytes, desde la base char-aligned.
    ; Distancia creciente. Sentinel: dy=$80.
    DEFB 0,    0                        ; pura alineacion (orig redondeado a char)
    DEFB 0,   -8                        ; arriba 8
    DEFB 0,    8                        ; abajo 8
    DEFB -8,   0                        ; izq 8
    DEFB 8,    0                        ; der 8
    DEFB 0,  -16                        ; arriba 16
    DEFB 0,   16                        ; abajo 16
    DEFB -8,  -8
    DEFB 8,   -8
    DEFB -8,   8
    DEFB 8,    8
    DEFB 0,  $80                        ; sentinel

; ==============================================================================
; SilentKillDeath - Despawn instantaneo del entity TYPE_DEATH (slot 11) sin puff
; ==============================================================================
; Llamado al morir el player: la muerte desaparece a la vez que los nasties,
; pero sin animacion (los nasties hacen puff, ella no — el puff puede confundir
; con el efecto del player). Erasa el sprite, libera el slot y resetea
; DeathSpawned. No-op si la muerte no esta activa.
; ==============================================================================
SilentKillDeath:
    LD IX, EntityTable + (SLOT_DEATH * ENT_SIZE)
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .skdResetTimer                ; ya inactiva, solo asegurar timer=0
    CALL EraseDeathSprite               ; quitar sprite + restaurar attrs
    XOR A
    LD (IX+ENT_TYPE), A
    LD (DeathSpawned), A
.skdResetTimer:
    ; Resetear contador para que no respawnee inmediatamente. La gracia
    ; correcta arranca cuando el player recupera el control (urb1LastBeat).
    LD HL, 0
    LD (DeathScreenTimer), HL
    ; OJO: NO hacemos stop de musica aqui. Esta rutina la llama
    ; OnPlayerHealthDepleted DESPUES de AY_PlayPlayerDeath; un mute R9 ahora
    ; mataria el sweep recien arrancado. Los callers que necesiten parar la
    ; musica (TriggerChurchTrap) lo hacen explicitamente. Para el caso "Death
    ; despawnea via puff" usar KillDeathIfActive (esa SI hace stop).
    RET

; ==============================================================================
; FreezeMonstersFacingCorpse - Para los monsters mirando al cadaver del player
; ==============================================================================
; Llamado desde OnPlayerHealthDepleted. Para cada monster activo (TYPE_MONSTER,
; no DYING ni SPAWNING):
;   - Set sprite a idle facing-corpse (R o L segun lado del cadaver)
;   - Si esta dentro de 16px (2 celdas) en X e Y del cadaver, retrocede 16px en
;     el eje dominante. Evita walls (CheckEnemyCollision) y otros monsters ya
;     posicionados (CheckMonsterOverlap). Si no cabe, prueba el otro eje.
;     Si tampoco, deja el monster donde estaba.
;   - Set DELTAX=DELTAY=0, DIR=0 (clear stun), STATE=STATE_IDLE
; Tras llamar, MonstersFrozen=1 -> ProcessOneEnemy gate skipea AI; al frame
; siguiente .peCalcAndDraw detecta cambio de SPRITEID/POSX y hace erase+draw.
; UnfreezeMonsters (en urb1LastBeat) limpia el flag al recuperar control.
; ==============================================================================
FreezeMonstersFacingCorpse:
    ; Snapshot de la posicion del cadaver (= player POSX/POSY al morir)
    LD A, (EntityTable + ENT_POSX)
    LD (CorpseX), A
    LD A, (EntityTable + ENT_POSY)
    LD (CorpseY), A
    ; Activar gate ANTES de iterar (asi cualquier ProcessOneEnemy concurrente
    ; ya skipea; no aplica aqui pero por simetria)
    LD A, 1
    LD (MonstersFrozen), A
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, NUM_MONSTERS
.fmcLoop:
    PUSH BC
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .fmcNext
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    JR Z, .fmcNext
    CP STATE_SPAWNING
    JR Z, .fmcNext
    CALL FreezeOneMonster
.fmcNext:
    POP BC
    LD DE, ENT_SIZE
    ADD IX, DE
    DJNZ .fmcLoop
    RET

; --- FreezeOneMonster ---
; IX = monster slot pointer.
; Ajusta facing/sprite, retrocede si esta cerca, deja al monster en idle parado.
; Nota: para monsters, ENT_DIR es el contador de stun (no lastHDir como en el
; player). La facing visual va sólo en SPRITEID (= ANIMBASE + 0 right / +4 left).
FreezeOneMonster:
    ; --- 1) Determinar facing y set SPRITEID a frame idle ---
    ; CorpseX <= POSX -> corpse a la W del monster -> mirar W (left)
    ; CorpseX  > POSX -> corpse a la E del monster -> mirar E (right)
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (CorpseX)
    CP B
    JR Z, .fomFaceW                 ; tied: usar W por convencion
    JR C, .fomFaceW                 ; corpseX < posX -> W
.fomFaceE:
    LD A, (IX+ENT_ANIMBASE)
    ADD A, MONSTER_FRAMES_RIGHT     ; +0 = R0
    LD (IX+ENT_SPRITEID), A
    JR .fomFaceDone
.fomFaceW:
    LD A, (IX+ENT_ANIMBASE)
    ADD A, MONSTER_FRAMES_LEFT      ; +4 = L0
    LD (IX+ENT_SPRITEID), A
.fomFaceDone:

    ; --- 2) Computar |dx| y |dy| ---
    LD A, (CorpseX)
    LD C, A
    LD A, (IX+ENT_POSX)
    SUB C                           ; A = posX - corpseX (signed)
    JR NC, .fomDxPos
    NEG
.fomDxPos:
    LD (.fomAdx), A
    LD A, (CorpseY)
    LD C, A
    LD A, (IX+ENT_POSY)
    SUB C
    JR NC, .fomDyPos
    NEG
.fomDyPos:
    LD (.fomAdy), A

    ; --- 3) Si |dx|>=16 OR |dy|>=16 -> ya esta lejos, no retrocede ---
    LD A, (.fomAdx)
    CP 16
    JP NC, .fomFreeze
    LD A, (.fomAdy)
    CP 16
    JP NC, .fomFreeze

    ; --- 4) Backoff: eje dominante = mayor |delta|; tie -> X ---
    LD A, (.fomAdx)
    LD B, A
    LD A, (.fomAdy)
    CP B                            ; A=|dy|, B=|dx|; CY si |dy|<|dx|
    JR C, .fomTryX
    JR Z, .fomTryX
    ; |dy| > |dx| -> intentar Y primero
    CALL TryBackoffY
    JR Z, .fomFreeze                ; ok
    CALL TryBackoffX
    JR .fomFreeze
.fomTryX:
    CALL TryBackoffX
    JR Z, .fomFreeze
    CALL TryBackoffY

.fomFreeze:
    ; Detener movimiento, clear stun (DIR=0), state IDLE.
    ; Facing ya esta en SPRITEID (= ANIMBASE+0 right o +4 left).
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_DIR), 0
    LD (IX+ENT_STATE), STATE_IDLE
    RET

.fomAdx: DEFB 0
.fomAdy: DEFB 0

; --- TryBackoffX: intenta retroceder 16px en X. Z=ok, NZ=blocked ---
; IX = monster slot. Si OK, POSX queda actualizada. Si blocked, restaura POSX.
TryBackoffX:
    LD A, (IX+ENT_POSX)
    LD (.tbxSavePos), A
    LD B, A
    LD A, (CorpseX)
    CP B                            ; A=corpseX, B=posX. CY si corpseX<posX -> push +16
    LD A, (IX+ENT_POSX)
    JR NC, .tbxNeg                  ; corpseX>=posX -> push -16
    ADD A, 16
    JR .tbxApply
.tbxNeg:
    SUB 16
.tbxApply:
    ; Bounds check Y mantenido. Verificar X dentro de pantalla [0..SCREEN_MAX_X]
    LD (IX+ENT_POSX), A
    CP SCREEN_MAX_X
    JR NC, .tbxFail                 ; fuera por la derecha (incluye underflow >= SCREEN_MAX_X)
    CALL CheckEnemyCollision
    JR NZ, .tbxFail
    CALL CheckMonsterOverlap
    JR NZ, .tbxFail
    XOR A                           ; Z = ok
    RET
.tbxFail:
    LD A, (.tbxSavePos)
    LD (IX+ENT_POSX), A
    OR 1                            ; NZ
    RET
.tbxSavePos: DEFB 0

; --- TryBackoffY: intenta retroceder 16px en Y. Z=ok, NZ=blocked ---
TryBackoffY:
    LD A, (IX+ENT_POSY)
    LD (.tbySavePos), A
    LD B, A
    LD A, (CorpseY)
    CP B
    LD A, (IX+ENT_POSY)
    JR NC, .tbyNeg
    ADD A, 16
    JR .tbyApply
.tbyNeg:
    SUB 16
.tbyApply:
    LD (IX+ENT_POSY), A
    CP SCREEN_MIN_Y
    JR C, .tbyFail
    CP SCREEN_MAX_Y
    JR NC, .tbyFail
    CALL CheckEnemyCollision
    JR NZ, .tbyFail
    CALL CheckMonsterOverlap
    JR NZ, .tbyFail
    XOR A
    RET
.tbyFail:
    LD A, (.tbySavePos)
    LD (IX+ENT_POSY), A
    OR 1
    RET
.tbySavePos: DEFB 0

; --- CheckMonsterOverlap: AABB 16x21 vs otros TYPE_MONSTER en EntityTable ---
; IX = monster a testear (su POSX/POSY actual). Returns Z=no overlap, NZ=overlap.
; Itera SLOT_MONSTER0..+5, skipea el slot propio y los no-monster.
CheckMonsterOverlap:
    PUSH BC
    PUSH IY
    LD IY, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, NUM_MONSTERS
.cmoLoop:
    ; Skip self (IY == IX)
    PUSH IX
    POP HL
    PUSH IY
    POP DE
    OR A
    SBC HL, DE
    JR Z, .cmoNext                  ; same slot

    LD A, (IY+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .cmoNext

    ; AABB overlap (rect 16x21 cada uno):
    ;   overlap = (ix.x+16 > iy.x) AND (iy.x+16 > ix.x)
    ;          AND (ix.y+21 > iy.y) AND (iy.y+21 > ix.y)
    LD A, (IX+ENT_POSX)
    ADD A, 16
    LD C, A
    LD A, (IY+ENT_POSX)
    CP C                            ; iy.x cmp ix.x+16
    JR NC, .cmoNext                 ; iy.x >= ix.x+16 -> no overlap X
    LD A, (IY+ENT_POSX)
    ADD A, 16
    LD C, A
    LD A, (IX+ENT_POSX)
    CP C
    JR NC, .cmoNext                 ; ix.x >= iy.x+16 -> no overlap X
    LD A, (IX+ENT_POSY)
    ADD A, 21
    LD C, A
    LD A, (IY+ENT_POSY)
    CP C
    JR NC, .cmoNext
    LD A, (IY+ENT_POSY)
    ADD A, 21
    LD C, A
    LD A, (IX+ENT_POSY)
    CP C
    JR NC, .cmoNext
    ; Overlap en ambos ejes
    POP IY
    POP BC
    OR 1                            ; NZ
    RET
.cmoNext:
    LD DE, ENT_SIZE
    ADD IY, DE
    DJNZ .cmoLoop
    POP IY
    POP BC
    XOR A                           ; Z = no overlap
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
    ; ENT_ATTR conservado: puff hereda color del monster
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
; Fases 2(C2), 3(N1), 4(N2), 5(A1) → CrepuscularTypeTable
;   N2 y A1 originalmente sin spawn, pero cuando los 3 monsters estan
;   atrapados TrySpawnNasty levanta el bloqueo y queremos nocturnos en
;   pantalla, no diurnos.
; ==============================================================================
UpdateNastyTable:
    LD A, (CurrentTimeOfDay)
    CP 2
    JR C, .diurnal              ; 0 (DY), 1 (C1) → diurnos
    CP 6
    JR Z, .diurnal              ; 6 (A2) → diurnos
    LD HL, CrepuscularTypeTable ; 2,3,4,5 → crepusculares
    JR .setTable
.diurnal:
    LD HL, DiurnalTypeTable
.setTable:
    LD (CurrentNastyTable), HL
    RET

; ==============================================================================
; ScareAllMonsters - Monsters huyen al amanecer (como nasties en campanadas)
; ==============================================================================
ScareAllMonsters:
    XOR A
    LD (MonstersActive), A              ; No respawnear mas
    ; Limpiar MAI_FLAG_LEAVING + MAI_FLAG_SHAKE_SAVED en los 3 slots:
    ; LEAVING → UpdateMonsterLeave elegira gap fresco. SHAKE_SAVED → la pausa
    ; del amanecer capturara el orig POSX/POSY del primer frame.
    LD HL, MonsterAiFlags
    LD B, 3
.samClearLoop:
    LD A, (HL)
    AND ~(MAI_FLAG_LEAVING | MAI_FLAG_SHAKE_SAVED) & $FF
    LD (HL), A
    INC HL
    DJNZ .samClearLoop
    LD A, SCARE_TIMER_DAWN
    LD (ScareTimer), A
    ; Transicion eager a STATE_SCARED para los 3 monsters activos. Sin esto el
    ; round-robin de ProcessEnemies (2/frame) tarda hasta ~5 frames en mover
    ; cada monster a STATE_SCARED, y durante ese gap el sprite aun esta en
    ; STATE_RUNNING y haria daño al player aunque ya este temblando.
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, NUM_MONSTERS
.samStateLoop:
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .samStateNext
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    JR Z, .samStateNext                 ; muriendo: no interferir
    CP STATE_SPAWNING
    JR Z, .samStateNext
    LD (IX+ENT_DIR), 0                  ; clear stun (igual que .peDoScare)
    LD (IX+ENT_STATE), STATE_SCARED
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
.samStateNext:
    LD DE, ENT_SIZE
    ADD IX, DE
    DJNZ .samStateLoop
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
MONSTER_ENTRY_BASE  EQU 20          ; Frames antes del primer monster (~0.8s a 25fps)
MONSTER_ENTRY_GAP   EQU 20          ; Frames entre cada monster (~0.8s)

; ==============================================================================
; SpawnMonsters - Primera aparicion tras campanadas
; ==============================================================================
SpawnMonsters:
    IF DEBUG_NO_ENEMIES
    RET
    ENDIF
    LD A, (MonstersActive)
    OR A
    RET NZ
    ; Matar nasties activos antes de poblar slots de monster: liberar el
    ; round-robin de ProcessEnemies (budget 2/frame) para los 3 monsters.
    CALL KillAllActiveNasties
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
    ; Memoria de ubicacion: MonsterRoomId[slot=C] = current screen_id.
    ; El monster "vive" aqui hasta que el player cambie de room (follow) o
    ; lo empuje a un vecino (migracion por knockback).
    CALL MaiGetCurrentScreenId
    LD HL, MonsterRoomId
    LD E, C
    LD D, 0
    ADD HL, DE
    LD (HL), A
.smSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    INC C
    DEC B
    JP NZ, .smLoop
    LD A, MONSTER_ENTRY_BASE
    LD (TryRespawnMonsters.rmTimer), A
    ; MonstersMusic NO arranca aqui — arranca en TryRespawnMonsters cuando
    ; el PRIMER monster aparece visible (tras MONSTER_ENTRY_BASE frames).
    ; Asi el "po-po-popo-po" coincide con la primera aparicion en pantalla.
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
    IF DEBUG_NO_ENEMIES
    RET
    ENDIF
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
    ; Skip si el TIPO de este slot esta atrapado en la iglesia (paso 7).
    ; MonsterTrappedFlags se indexa por type idx (no por slot), porque
    ; ShuffleMonsterTypes baraja la asignacion slot->tipo.
    LD A, (IX+ENT_ANIMBASE)
    OR A
    JR NZ, .rmHasTypeForTrap
    ; ANIMBASE no fijado todavia: leer tipo inicial de MonsterTypeTable[slot]
    LD A, C
    LD HL, MonsterTypeTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
.rmHasTypeForTrap:
    SUB SPRID_MONSTER_0
    SRL A
    SRL A
    SRL A                               ; A = type idx 0..2
    LD HL, .rmTrapBits
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD HL, MonsterTrappedFlags
    AND (HL)
    JP NZ, .rmSkip
    ; Memoria de ubicacion: solo activar si MonsterRoomId[slot] == current.
    ; Monsters migrados a otros rooms (via knockback) quedan TYPE_NONE hasta
    ; que el player visite su room.
    LD A, C
    LD L, A
    LD H, 0
    LD DE, MonsterRoomId
    ADD HL, DE
    LD A, (HL)
    LD E, A                             ; E = room_id del slot
    CALL MaiGetCurrentScreenId          ; A = current screen_id
    CP E
    JP NZ, .rmSkip                      ; distinto room → skip
    ; === Activar SIN tocar POSX/POSY ===
    ; La posicion la fija quien puso TYPE_NONE en este slot:
    ;   - SpawnMonsters: hueco aleatorio via MaiPickRandomGap
    ;   - RepositionMonstersAtEntry: gap en entry side
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
    ; Arrancar MonstersMusic la PRIMERA vez que un monster aparece visible.
    ; Step=$FF (sentinel inactivo) -> aun no ha sonado nunca esta noche.
    ; Tras StartMonstersMusic, Step=0 -> no re-arranca en respawns posteriores.
    ; StopMonstersMusic en sunrise restaura Step=$FF para la siguiente noche.
    LD A, (MonstersMusicStep)
    INC A
    RET NZ                              ; Step != $FF -> ya arranco, salir
    JP StartMonstersMusic               ; tail-call: arranca el secuencer
.rmSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    INC C
    DEC B
    JP NZ, .rmLoop
    RET

.rmTimer: DEFB 0
.rmTrapBits: DEFB $01, $02, $04         ; bit mask por slot 0/1/2 (church trap)

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
    ; MaiPickNearestGapOnSide destruye HL y BC (paginacion bank 6, loops
    ; internos). Preservamos HL (ptr a MonsterReturnTimer[slot]) y B
    ; (contador del outer loop) para que .rmRtNext pueda iterar bien.
    PUSH HL
    PUSH BC
    CALL MaiPickNearestGapOnSide        ; elige gap del side mas cercano al target
    POP BC
    POP HL
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
    ; Memoria de ubicacion: el monster ha vuelto al room actual (Regla 4).
    ; Actualizar MonsterRoomId[slot] = current para que TryRespawnMonsters
    ; lo active en este room. slot = HL - MonsterReturnTimer.
    PUSH HL
    PUSH BC
    LD DE, MonsterReturnTimer
    OR A
    SBC HL, DE                              ; HL = slot (0/1/2)
    LD E, L
    LD D, 0
    CALL MaiGetCurrentScreenId              ; A = current id, preserva DE
    LD HL, MonsterRoomId
    ADD HL, DE
    LD (HL), A
    POP BC
    POP HL
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
    ; Pre-construir CollisionMap del room NEW aqui (DrawScreen lo reconstruira
    ; de nuevo poco despues, pero necesitamos datos frescos para el collision
    ; check de la Fase 8 .reInNewStepBack — sin esto usariamos el map del room
    ; anterior y el migrado acabaria sobre BG sprites).
    CALL BuildCollisionMap
    ; Memoria de ubicacion: solo reposicionar monsters cuyo RoomId == OLD
    ; (siguen al player desde el room anterior) o RoomId == NEW (ya vivian
    ; en este room, migrados por knockback previo). Los que vivan en otro
    ; room quedan intactos (TYPE_NONE en su posicion clampada) y no se
    ; activaran hasta que el player visite su room.
    CALL MaiGetCurrentScreenId
    LD (.reNewId), A
    CALL MaiGetOldScreenId
    LD (.reOldId), A
    ; Cache entry side del player (solo valido para monsters que vienen de OLD)
    CALL MaiGetEntrySide            ; A = MAI_SIDE_N/S/W/E o $FF
    LD (.reFollowSide), A
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
    LD C, 0                         ; C = slot index
.reLoop:
    PUSH BC
    ; --- Pass 1 (solo TYPE_MONSTER): snapshot pre-transition para poder
    ; restaurar si player vuelve antes de que este monster active en NEW. ---
    LD A, (IX+ENT_TYPE)
    CP TYPE_MONSTER
    JR NZ, .reCheckRestore
    ; Guardar LastSeenRoom = OLD, LastSeenX/Y = POSX/POSY actuales
    LD E, C
    LD D, 0
    LD HL, MonsterLastSeenRoom
    ADD HL, DE
    LD A, (.reOldId)
    LD (HL), A
    LD HL, MonsterLastSeenX
    ADD HL, DE
    LD A, (IX+ENT_POSX)
    LD (HL), A
    LD HL, MonsterLastSeenY
    ADD HL, DE
    LD A, (IX+ENT_POSY)
    LD (HL), A
    JR .reCheckReposition
.reCheckRestore:
    ; TYPE_NONE: check si debemos restaurar (player vuelve rapido antes de
    ; que este slot active en el NEW previo). Condicion:
    ;   RoomId[slot] == OLD_actual && LastSeenRoom[slot] == NEW_actual
    ; Significa: este monster estaba tracked como siguiendo al player (RoomId
    ; = OLD = donde el player vino), y su ultima vista visible fue en el
    ; room al que el player vuelve.
    LD E, C
    LD D, 0
    LD HL, MonsterRoomId
    ADD HL, DE
    LD A, (HL)
    LD B, A
    LD A, (.reOldId)
    CP B
    JR NZ, .reCheckReposition       ; RoomId != OLD → no follow-in-transit
    LD HL, MonsterLastSeenRoom
    ADD HL, DE
    LD A, (HL)
    LD B, A
    LD A, (.reNewId)
    CP B
    JR NZ, .reCheckReposition       ; LastSeen != NEW
    JP .reRestore                   ; ambas condiciones OK → restore
.reCheckReposition:
    ; Fetch MonsterRoomId[slot] para comparaciones OLD/NEW (logica original)
    LD E, C
    LD D, 0
    LD HL, MonsterRoomId
    ADD HL, DE
    LD A, (HL)
    LD E, A                         ; E = room_id
    LD A, (.reOldId)
    CP E
    JR Z, .reFromOld
    LD A, (.reNewId)
    CP E
    JR Z, .reInNew
    JP .reSkip                      ; Otro room: no tocar
.reFromOld:
    ; Monster viene con el player: usar entry side actual
    LD A, (.reFollowSide)
    JP .rePickGap
.reInNew:
    ; Monster migrado: estaba aqui esperando. Posicionar en el gap del
    ; entry side (por donde "entro" virtualmente cuando fue empujado) y
    ; ACTIVAR YA MISMO (no esperar al stagger de TryRespawnMonsters) para
    ; que aparezca en el mismo frame en que se dibuja el nuevo room.
    ; Usa MaiPickNearestGapOnSide con target = POSX/POSY al knockback (clamped
    ; al borde, preservado hasta aqui) para que en salidas duales aparezca en
    ; la misma sub-salida (superior/inferior) por donde fue empujado.
    ; Aparecer por el mismo hueco que el player (consistente con .reFromOld).
    ; Antes usaba MonsterEntryBorder[slot] + POSX/POSY del monster (donde fue
    ; empujado en knockback previo); pero el player espera ver al monster
    ; entrar por su mismo gap, no por uno inconsistente.
    LD A, (.reFollowSide)
    CP $FF
    JR Z, .reInNewFallback
    LD (.reInSide), A
    CP 2                                    ; W=2, E=3
    JR C, .reInTargetNS
    LD A, (EntityTable + ENT_POSY)
    SUB SCREEN_MIN_Y
    JR .reInTargetShift
.reInTargetNS:
    LD A, (EntityTable + ENT_POSX)
.reInTargetShift:
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (MaiGapTargetCoord), A
    LD A, (.reInSide)
    CALL MaiPickNearestGapOnSide
    OR A
    JR Z, .reInNewPos
.reInNewFallback:
    LD A, (LastEntryPosX)
    LD (IX+ENT_POSX), A
    LD (.reInGapX), A
    LD A, (LastEntryPosY)
    LD (IX+ENT_POSY), A
    LD (.reInGapY), A
    JR .reInNewStepBack
.reInNewPos:
    LD A, (MaiSpawnX)
    LD (IX+ENT_POSX), A
    LD (.reInGapX), A
    LD A, (MaiSpawnY)
    LD (IX+ENT_POSY), A
    LD (.reInGapY), A
.reInNewStepBack:
    ; Offset collision-aware: probar MAI_WAIT_OFFSET y bajar en pasos de 8
    ; (1 char) hasta encontrar posicion libre, o dejar en el gap (siempre
    ; valido por spec del emitter). CheckEnemyCollision necesita SPRITEID
    ; para leer dims — setear temporalmente a ANIMBASE (activate lo
    ; sobrescribira con el frame de facing).
    LD A, (IX+ENT_ANIMBASE)
    LD (IX+ENT_SPRITEID), A
    LD A, (.reInSide)
    CP $FF
    JP Z, .reInNewActivate              ; sin side valido → sin offset
    LD A, MAI_WAIT_OFFSET
.reInTryLoop:
    LD (.reInTry), A
    ; Reset POSX/POSY a gap, aplicar try offset segun side
    LD A, (.reInGapX)
    LD (IX+ENT_POSX), A
    LD A, (.reInGapY)
    LD (IX+ENT_POSY), A
    LD A, (.reInSide)
    CP MAI_SIDE_N
    JR Z, .reInApplyN
    CP MAI_SIDE_S
    JR Z, .reInApplyS
    CP MAI_SIDE_W
    JR Z, .reInApplyW
    ; side E: POSX -= try
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.reInTry)
    NEG
    ADD A, B
    LD (IX+ENT_POSX), A
    JR .reInCheckColl
.reInApplyN:
    LD A, (IX+ENT_POSY)
    LD B, A
    LD A, (.reInTry)
    ADD A, B
    LD (IX+ENT_POSY), A
    JR .reInCheckColl
.reInApplyS:
    LD A, (IX+ENT_POSY)
    LD B, A
    LD A, (.reInTry)
    NEG
    ADD A, B
    LD (IX+ENT_POSY), A
    JR .reInCheckColl
.reInApplyW:
    LD A, (IX+ENT_POSX)
    LD B, A
    LD A, (.reInTry)
    ADD A, B
    LD (IX+ENT_POSX), A
.reInCheckColl:
    CALL CheckEnemyCollision
    JP Z, .reInNewActivate              ; Z = free → usar esta pos
    ; Blocked: probar offset menor
    LD A, (.reInTry)
    CP 8
    JR C, .reInTryGap                   ; < 8, no podemos restar
    SUB 8
    JR NZ, .reInTryLoop                 ; > 0, retry
.reInTryGap:
    ; Todos los offsets bloqueados → usar gap (offset 0, siempre valido).
    LD A, (.reInGapX)
    LD (IX+ENT_POSX), A
    LD A, (.reInGapY)
    LD (IX+ENT_POSY), A
.reRestore:
    ; Monster "en transito" no activado aun en OLD → player vuelve a NEW ==
    ; LastSeenRoom[slot]. Restaurar POSX/POSY desde el snapshot y activar
    ; directamente (mismo path que .reInNewActivate).
    LD E, C
    LD D, 0
    LD HL, MonsterLastSeenX
    ADD HL, DE
    LD A, (HL)
    LD (IX+ENT_POSX), A
    LD HL, MonsterLastSeenY
    ADD HL, DE
    LD A, (HL)
    LD (IX+ENT_POSY), A
    ; Fall into shared activate code
.reInNewActivate:
    ; Skip si el TIPO esta atrapado (church-trap permanente). Sin esto, un
    ; slot que fue migrado por knockback antes de capturar los 3 sobrevive
    ; al amanecer (TYPE_NONE no lo toca KillAllActiveMonsters) y al visitar
    ; esa sala se reactivaria aqui ignorando MonsterTrappedFlags. Bug
    ; observado: monsters "stuck" en sprites BG tras capturar los 3.
    LD A, (IX+ENT_ANIMBASE)
    SUB SPRID_MONSTER_0
    CP 24                                   ; bound: 3 tipos x 8 stride
    JP NC, .reInActivateProceed             ; fuera de rango (PUFF, etc): no trap check
    SRL A
    SRL A
    SRL A                                   ; A = type idx 0..2
    LD HL, ChurchTrapBitMask
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD HL, MonsterTrappedFlags
    AND (HL)
    JP NZ, .reSkip
.reInActivateProceed:
    ; Activar como TryRespawnMonsters pero sin stagger
    LD A, (IX+ENT_ANIMBASE)
    LD (IX+ENT_TYPE), TYPE_MONSTER
    LD (IX+ENT_STATE), STATE_RUNNING
    ; Facing hacia el player
    LD D, A
    LD A, (EntityTable + ENT_POSX)
    CP (IX+ENT_POSX)
    JR NC, .reInNewFaceR
    LD A, D
    ADD A, MONSTER_FRAMES_LEFT
    JR .reInNewFaceSet
.reInNewFaceR:
    LD A, D
.reInNewFaceSet:
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
    ; Update MonsterRoomId=NEW + cancel timer (via caida a .reSkip)
    POP BC
    PUSH BC
    LD E, C
    LD D, 0
    LD HL, MonsterRoomId
    ADD HL, DE
    LD A, (.reNewId)
    LD (HL), A
    JP .reSkip

.rePickGap:
    CP $FF
    JR Z, .reFallback
    ; Target coord = posicion del player en el eje paralelo al side de entrada.
    ; Para sides N/S (0,1) usamos POSX char; para W/E (2,3) POSY-SCREEN_MIN_Y char.
    ; MaiPickNearestGapOnSide elige el gap del side mas cercano al target → el
    ; monster entra por el MISMO hueco que el player (importante en duales).
    LD B, A                         ; B = side
    CP 2                            ; W=2, E=3
    JR C, .rePickGapNS
    LD A, (EntityTable + ENT_POSY)
    SUB SCREEN_MIN_Y
    JR .rePickGapTargetSet
.rePickGapNS:
    LD A, (EntityTable + ENT_POSX)
.rePickGapTargetSet:
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (MaiGapTargetCoord), A
    LD A, B                         ; restore side
    CALL MaiPickNearestGapOnSide    ; A=0 ok, A=1 sin gaps en ese side
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
    ; MonsterRoomId[slot] = NEW (si venia de OLD, actualiza; si ya era NEW,
    ; queda igual pero no molesta).
    POP BC
    PUSH BC
    LD E, C
    LD D, 0
    LD HL, MonsterRoomId
    ADD HL, DE
    LD A, (.reNewId)
    LD (HL), A
.reSkip:
    ; Cualquier movimiento del player cancela el MonsterReturnTimer del slot:
    ; - Si fue al destino (.reInNew): monster activa alli, timer irrelevante.
    ; - Si siguio (.reFromOld): monster viene con, timer irrelevante.
    ; - Si fue a otro room: monster se queda en destino (memoria), no volver.
    ; Sin cancelar, el timer expiraria y relocaria el monster en player's
    ; current — rompiendo la memoria de ubicacion.
    LD A, C
    LD E, A
    LD D, 0
    LD HL, MonsterReturnTimer
    ADD HL, DE
    XOR A
    LD (HL), A
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    INC C
    DEC B
    JP NZ, .reLoop
    LD A, MONSTER_ENTRY_BASE
    LD (TryRespawnMonsters.rmTimer), A
    RET

.reNewId:      DEFB 0
.reOldId:      DEFB 0
.reFollowSide: DEFB 0
.reInSide:     DEFB 0
.reInGapX:     DEFB 0
.reInGapY:     DEFB 0
.reInTry:      DEFB 0

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

    ; Skip enemigos muriendo o spawneando (no colisionan en absoluto)
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    JP Z, .nextEnemy
    CP STATE_SPAWNING
    JP Z, .nextEnemy
    ; STATE_SCARED (trembling/flee durante campanadas o amanecer): NO se
    ; saltan aqui — se gestiona en .bodyCollision: si player ataca, mueren
    ; (player puede cazarlos); si player no ataca, no le danan al overlap.
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
    ; Player NO atacando + enemigo SCARED (campanadas/amanecer): nasty
    ; pasa de largo sin danarte. Asi puedes verlos huir y, si decides
    ; cazarlos, lo haces tu activamente con la espada.
    ; OJO: saltar a .nextEnemyPop (NO a .nextEnemy directamente) — el
    ; PUSH BC del header del loop sigue en la pila y .nextEnemyPop hace
    ; el POP BC. Sin esto se leakean 2 B/iteracion -> stack overflow ->
    ; crash a BASIC tras varios frames de overlap.
    LD A, (IX+ENT_STATE)
    CP STATE_SCARED
    JP Z, .nextEnemyPop
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
    ; Marcar kb como DIRECTO del player (CheckChurchTrap solo dispara la
    ; trampa para kb directos; un kb heredado por billar limpia este bit).
    SET ENTF_KB_DIRECT, (IX+ENT_FLAGS)
    ; SFX de golpe al monster
    PUSH IX
    PUSH BC
    LD HL, SFX_EnemyDeath
    CALL PlaySFX
    POP BC
    POP IX
    JP .nextEnemyPop

; DEBUG: tabla de colores por golpes recibidos
.kbHitColors:
    DEFB $47                            ; 0 hits: blanco brillante (no deberia usarse)
    DEFB $44                            ; 1 hit:  verde brillante
    DEFB $45                            ; 2 hits: cyan brillante
    DEFB $46                            ; 3 hits: amarillo brillante
    DEFB $42                            ; 4 hits: rojo brillante
    DEFB $43                            ; 5 hits: magenta brillante

.killNasty:

    ; Matar nasty: iniciar animacion puff (ENT_ATTR queda con el color
    ; del nasty para que el puff lo herede via SetEntityAttr en peDying)
    CALL SnapPuffPos                ; ajustar POSX/POSY a hueco 24x24 cercano
    LD (IX+ENT_STATE), STATE_DYING
    LD (IX+ENT_ANIMBASE), SPRID_PUFF
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_PUFF
    LD (IX+ENT_DELTAX), 0          ; Parar movimiento
    LD (IX+ENT_DELTAY), 0
    ; SFX de muerte de enemigo
    PUSH IX
    PUSH BC
    LD HL, SFX_EnemyDeath
    CALL PlaySFX
    POP BC
    POP IX
    JR .nextEnemyPop

.playerHit:
    ; Invulnerable durante respawn phase (prep + grace)
    LD A, (PlayerRespawnPhase)
    OR A
    JP NZ, .nextEnemyPop
    ; Inmunidad temporal tras recibir daño (durante flash rojo)
    LD A, (PlayerHitTimer)
    OR A
    JP NZ, .nextEnemyPop                ; Aun en inmunidad → ignorar
    ; Enemigo toca al player → daño al player (2 puntos por hit; clamp a 0)
    LD A, (PlayerHealth)
    OR A
    JP Z, .nextEnemyPop                 ; Ya muerto, ignorar
    SUB 2
    JR NC, .pHpDmgOk
    XOR A                               ; clamp a 0 si solo quedaba 1 punto
.pHpDmgOk:
    LD (PlayerHealth), A
    OR A
    JR NZ, .pHpDmgNotZero
    ; HP llego a 0: OnPlayerHealthDepleted destruye IX (kill nasties etc).
    ; Tras volver, IX seguia usandose para modificar el nasty atacante; con
    ; HP=0 no necesitamos pegarle, asi que saltamos directo a .nextEnemyPop.
    CALL OnPlayerHealthDepleted
    JP .nextEnemyPop
.pHpDmgNotZero:
    ; Flash rojo (6 frames) + gracia 1s con blink (mismo helper que el respawn).
    ; Convive con PlayerHitTimer: rojo durante 6f, blink durante toda la gracia.
    LD A, RED | $40
    LD (EntityTable + ENT_ATTR), A
    LD A, 6                         ; 6 frames a 25fps ~0.24s (era 12 a 50fps)
    LD (PlayerHitTimer), A
    CALL EnterGracePhase            ; phase=2, timer=RESPAWN_GRACE_FRAMES
    ; Si nasty destructible → muere al tocar al player
    BIT ENTF_DESTRUCT, (IX+ENT_FLAGS)
    JR Z, .playerHitSFX
    CALL SnapPuffPos                ; ajustar POSX/POSY a hueco 24x24 cercano
    LD (IX+ENT_STATE), STATE_DYING
    LD (IX+ENT_ANIMBASE), SPRID_PUFF
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_PUFF
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    ; ENT_ATTR conservado: puff hereda color del nasty
.playerHitSFX:
    ; SFX de golpe al player (no bloqueante via AY hw envelope)
    PUSH IX
    PUSH BC
    CALL AY_PlayPlayerHit
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

; ==============================================================================
; SISTEMA DE LA MUERTE (TYPE_DEATH, slot 11)
; ==============================================================================
; Aparece tras estar DEATH_SPAWN_FRAMES (250 = 10s @ 25fps) en una sala. Persigue
; al player con FlowField a media velocidad (1px cada 2 frames). Al tocar al
; player le quita toda la salud y desaparece. Tambien desaparece al cambiar de
; sala (DrawScreen resetea slot, timer y flag). No avanza durante la cinemática
; de la iglesia (ChurchCutscenePhase ya saltea todo el bloque de gameplay desde
; main.asm; aqui no hace falta guard adicional).
; ==============================================================================

; --- UpdateDeath: wrapper sub-pixel sobre UpdateMonster + stuck detection ---
; IX = EntityTable + SLOT_DEATH * ENT_SIZE. Reusa la AI de monsters (chase
; con wall-escape + persistence + 4-candidate routing). Sub-pixel acc 1/2:
; en frame activo llama a UpdateMonster; en frame skip llama a DeathAnimate.
;
; Stuck detection (option 3 pathfinding): si POSX/Y no cambio durante
; DEATH_STUCK_THRESHOLD frames consecutivos, activar DeathBfsRescue (mini
; BFS depth 3 que elige la mejor direccion para escapar del atasco).
;
; UpdateMonster espera ENT_DIR=0 (sin stun) → SpawnDeath lo inicializa asi
; y nada lo cambia. Con DIR=0 entra siempre por .moNormal.
; .moAnimate redirige TYPE_DEATH a DeathAnimate (animacion R/L con 4 frames
; en vez de 8 + orientacion invertida).
UpdateDeath:
    ; --- Tick contador on-screen (16-bit). Al llegar a DEATH_GHOST_FRAMES
    ; (15s @ 25fps) activa ghost mode independientemente de si Death ha
    ; movido o no. "Atascada" en gameplay incluye dar botes / oscilar sin
    ; progreso real, no solo quedar inmovil. ---
    LD HL, (DeathGhostStuckTimer)
    INC HL
    LD (DeathGhostStuckTimer), HL
    LD A, H
    CP (DEATH_GHOST_FRAMES) >> 8
    JR C, .udGhostCheckDone
    JR NZ, .udGhostOn
    LD A, L
    CP (DEATH_GHOST_FRAMES) & $FF
    JR C, .udGhostCheckDone
.udGhostOn:
    ; Detectar transicion 0->1 (PRIMERA vez entrando ghost mode este episodio).
    ; Solo en ese frame setear tempo doble + restart musica desde primera nota:
    ; asi la primera nota cae sincronizada con el "lanzarse" de la muerte. Los
    ; frames subsecuentes con DeathGhostMode=1 son no-op (idempotente sin
    ; re-disparar restart).
    LD A, (DeathGhostMode)
    OR A
    JR NZ, .udGhostCheckDone
    LD A, 1
    LD (DeathGhostMode), A
    LD (MusicSpeedShift), A         ; tempo doble desde la PRIMERA nota
    LD A, $FE                       ; sentinel restart-current-track
    CALL StartMusic                 ; rearranca DeathMusicTable desde nota 0
.udGhostCheckDone:

    ; --- Ghost mode activo: chase directo ignorando colision con BG ---
    LD A, (DeathGhostMode)
    OR A
    JP NZ, DeathGhostChase

    ; Snapshot de la pos pre-call para detectar stuck (BFS rescue)
    LD A, (IX+ENT_POSX)
    LD (DeathPrevX), A
    LD A, (IX+ENT_POSY)
    LD (DeathPrevY), A
    ; Sub-pixel acc 1/2
    LD A, (DeathSubPixelAcc)
    XOR 1
    LD (DeathSubPixelAcc), A
    JR Z, .udSkip
    CALL UpdateMonster                  ; activo: chase + move + animate
    JR .udPost
.udSkip:
    CALL DeathAnimate                   ; skip: solo animacion
.udPost:
    ; Stuck check para BFS: comparar POS post-call vs pre-call
    LD A, (DeathPrevX)
    CP (IX+ENT_POSX)
    JR NZ, .udMoved
    LD A, (DeathPrevY)
    CP (IX+ENT_POSY)
    JR NZ, .udMoved
    ; No movio: incrementar BFS counter
    LD A, (DeathStuckCounter)
    INC A
    LD (DeathStuckCounter), A
    CP DEATH_STUCK_THRESHOLD
    RET C
    XOR A
    LD (DeathStuckCounter), A
    JP DeathBfsRescue
.udMoved:
    XOR A
    LD (DeathStuckCounter), A
    RET

; --- DeathGhostChase: chase directo al player saltandose colision con BG ---
; Activado cuando DeathGhostMode=1 (15s desde spawn). Velocidad SPEED_RUN
; en un solo eje (greedy primario: el de mayor delta al player). Sin diagonal-
; doble - asi Death no avanza mas rapido que el player en cualquier direccion.
; Atraviesa walls/BG hasta llegar al primer hueco libre (bbox sin overlap).
; Cuando alcanza hueco libre: exit ghost mode + reset timers, AI normal reanuda.
DeathGhostChase:
    ; --- Computar |dx|, |dy| para elegir eje primario ---
    LD A, (EntityTable + ENT_POSX)
    SUB (IX+ENT_POSX)
    JR NC, .udgAbsDxOk
    NEG
.udgAbsDxOk:
    LD B, A                             ; B = |dx|
    LD A, (EntityTable + ENT_POSY)
    SUB (IX+ENT_POSY)
    JR NC, .udgAbsDyOk
    NEG
.udgAbsDyOk:
    ; A = |dy|, B = |dx|
    CP B
    JR NC, .udgVertPrim                 ; |dy| >= |dx| -> mover en Y

    ; --- Eje X primario ---
    XOR A
    LD (IX+ENT_DELTAY), A               ; clear Y
    LD A, (EntityTable + ENT_POSX)
    SUB (IX+ENT_POSX)
    JR Z, .udgAnim                      ; alineado en X (raro si entramos aqui)
    LD A, DEATH_GHOST_SPEED
    JR NC, .udgXSet
    LD A, -DEATH_GHOST_SPEED
.udgXSet:
    LD (IX+ENT_DELTAX), A
    ADD A, (IX+ENT_POSX)
    LD (IX+ENT_POSX), A
    JR .udgAnim

    ; --- Eje Y primario ---
.udgVertPrim:
    XOR A
    LD (IX+ENT_DELTAX), A               ; clear X
    LD A, (EntityTable + ENT_POSY)
    SUB (IX+ENT_POSY)
    JR Z, .udgAnim
    LD A, DEATH_GHOST_SPEED
    JR NC, .udgYSet
    LD A, -DEATH_GHOST_SPEED
.udgYSet:
    LD (IX+ENT_DELTAY), A
    ADD A, (IX+ENT_POSY)
    LD (IX+ENT_POSY), A
.udgAnim:
    ; Ghost mode PERSISTENTE: una vez activo, Death sigue lanzandose hasta
    ; ser despawneada por una de tres condiciones externas:
    ;   1. Caza al player (CheckDeathTouchPlayer.cdtTouched)
    ;   2. Player muere por otra causa (OnPlayerHealthDepleted -> SilentKillDeath)
    ;   3. Player cambia de pantalla (screen_system reset)
    ; En esos hooks se hace DeathSpawned=0 + DeathGhostMode=0 + stop musica,
    ; asi que el flag se limpia ahi. No hay reset por "salir de muro" — el
    ; jugador no puede sacudirse a la muerte cambiando posicion.
    JP DeathAnimate                     ; tail-call para animar (R/L invertido)

; --- DeathAnimate: animacion R/L con orientacion invertida ---
; Llamada por:
;   - .moAnimate (redireccion TYPE_DEATH dentro de UpdateMonster).
;   - UpdateDeath en frame skip (sin movimiento).
; El sprite del aseprite tiene la orientacion fisica invertida vs sign de
; DELTAX → DELTAX > 0 mapea a par "L" (offset 2), DELTAX < 0 a par "R" (0).
DeathAnimate:
    LD A, (IX+ENT_DELTAX)
    OR A
    JR Z, .daKeepDir
    LD C, ENEMY_FRAMES_LEFT             ; DELTAX > 0 → par L (sprite invertido)
    BIT 7, A
    JR Z, .daDir
    LD C, ENEMY_FRAMES_RIGHT            ; DELTAX < 0 → par R
    JR .daDir
.daKeepDir:
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)
    AND 2                               ; bit 1 = par L (offsets 2/3)
    LD C, A
.daDir:
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .daFrameSet
    LD (IX+ENT_ANIMTIMER), ENEMY_ANIM_DELAY
    LD A, (IX+ENT_SPRITEID)
    LD B, A
    SUB (IX+ENT_ANIMBASE)
    AND 1
    JR NZ, .daFrameDec
    INC B
    JR .daFrameStore
.daFrameDec:
    DEC B
.daFrameStore:
    LD (IX+ENT_SPRITEID), B
.daFrameSet:
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)
    AND 1
    ADD A, (IX+ENT_ANIMBASE)
    ADD A, C
    LD (IX+ENT_SPRITEID), A
    RET

; --- SpawnDeath: inicializa slot SLOT_DEATH en la celda mas lejana del player ---
; Si FindFarthestAnyFreeCell no halla candidato, no spawnea (deja DeathSpawned=0
; pero NO resetea DeathScreenTimer; el spawn se reintentara cada frame mientras
; timer >= DEATH_SPAWN_FRAMES).
SpawnDeath:
    ; Picker barato: celda libre mas lejana en Manhattan al player respetando
    ; DEATH_MIN_SPAWN_DIST + footprint 24x24. Sin BFS ni paginar bank 6
    ; (~1M T-states ahorrados vs MaiComputeFlowField+FindFarthestZoneCell).
    ; Si la celda quedase aislada por paredes, ghost mode (15s) cierra el caso
    ; atravesando el mapa.
    CALL FindFarthestAnyFreeCell
    RET Z                               ; sin candidato: reintento siguiente frame
.sdHaveCell:
    ; B = cx, C = cy
    LD IX, EntityTable + (SLOT_DEATH * ENT_SIZE)
    ; POSX = cx * 8
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    LD (IX+ENT_POSX), A
    LD (IX+ENT_OLDX), A                 ; sin valor previo: preinit a pos actual
    ; POSY = cy * 8 + SCREEN_MIN_Y
    LD A, C
    ADD A, A
    ADD A, A
    ADD A, A
    ADD A, SCREEN_MIN_Y
    LD (IX+ENT_POSY), A
    LD (IX+ENT_OLDY), A
    ; Tipo / estado / sprite
    LD (IX+ENT_TYPE), TYPE_DEATH
    LD (IX+ENT_STATE), STATE_RUNNING
    LD (IX+ENT_SPRITEID), SPRID_DEATH
    LD (IX+ENT_OLDSPRID), SPRID_DEATH
    LD (IX+ENT_ANIMBASE), SPRID_DEATH
    LD (IX+ENT_ANIMTIMER), ENEMY_ANIM_DELAY
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_DIR), 0
    ; Color: blanco brillante sobre negro (espectral)
    LD (IX+ENT_ATTR), WHITE | $40
    ; Flags: visible + newspawn (no destructible: la muerte es invulnerable)
    LD (IX+ENT_FLAGS), (1 << ENTF_VISIBLE) | (1 << ENTF_NEWSPAWN)
    ; Sub-pixel acc + ghost mode reset (spawn fresco siempre en chase normal)
    XOR A
    LD (DeathSubPixelAcc), A
    LD (DeathStuckCounter), A
    LD (DeathGhostMode), A
    LD HL, 0
    LD (DeathGhostStuckTimer), HL
    ; Marcar como spawneada
    LD A, 1
    LD (DeathSpawned), A
    ; Arrancar musica de tension de la muerte (track 4, loopable). Suena
    ; mientras Death este en pantalla; se silencia en transiciones de sala
    ; (screen_system) o cuando la muerte caza al player (CheckDeathTouchPlayer).
    LD A, 4
    JP StartMusic                       ; tail-call

; --- UpdateDeathTimer: tick + spawn check (llamado cada frame desde main.asm) ---
UpdateDeathTimer:
    IF DEBUG_NO_ENEMIES
    RET
    ENDIF
    LD A, (DeathSpawned)
    OR A
    RET NZ                              ; ya spawneada: nada que hacer
    ; Inhibida en esta sala (puerta de iglesia abierta -> cinematica de
    ; captura corre sin interferencia). Se limpia al cambiar de sala.
    LD A, (DeathInhibitInRoom)
    OR A
    RET NZ
    ; Bloquear durante la secuencia de muerte del player (yellow + red border)
    ; y el countdown 3-2-1 (PlayerRespawnPhase=1, sin control). El contador
    ; arranca de cero al recuperar el control (urb1LastBeat).
    LD A, (DeathBorderPhase)
    OR A
    RET NZ
    LD A, (PlayerRespawnPhase)
    CP 1
    RET Z
    ; Death aparece normalmente desde medianoche en adelante, en cualquier
    ; sala. NO bloqueamos por MonstersActive — eso era confundir "monsters
    ; activos en general" con "fase del cutscene de trampa de iglesia",
    ; cosas distintas. Si el player esta en cutscene de iglesia su input
    ; ya esta congelado, asi que Death no presiona ahi tampoco.
    LD HL, (DeathScreenTimer)
    LD DE, DEATH_SPAWN_FRAMES
    PUSH HL
    OR A
    SBC HL, DE
    POP HL
    JR NC, .udtTrySpawn                 ; HL >= threshold (caso reintento)
    INC HL
    LD (DeathScreenTimer), HL
    PUSH HL
    LD DE, DEATH_SPAWN_FRAMES
    OR A
    SBC HL, DE
    POP HL
    RET C                               ; HL < threshold
.udtTrySpawn:
    JP SpawnDeath

; --- ProcessDeath: round-robin de la muerte (no-op si no spawneada) ---
; Llamado desde main.asm. Reusa ProcessOneEnemy (que ya tiene branch TYPE_DEATH).
ProcessDeath:
    LD A, (DeathSpawned)
    OR A
    RET Z
    LD IX, EntityTable + (SLOT_DEATH * ENT_SIZE)
    LD A, (IX+ENT_TYPE)
    OR A
    RET Z
    JP ProcessOneEnemy

; --- CheckDeathTouchPlayer: AABB completo 24x24 vs player (no margen) ---
; Si overlap: PlayerHealth=0, erase sprite, despawn.
CheckDeathTouchPlayer:
    LD A, (DeathSpawned)
    OR A
    RET Z
    LD IX, EntityTable + (SLOT_DEATH * ENT_SIZE)
    LD A, (IX+ENT_TYPE)
    OR A
    RET Z
    ; Invulnerable SOLO durante el countdown phase 1 (sin control). NO durante
    ; phase 2 (grace post-respawn O post-nasty-hit) — la phase 2 se setea tambien
    ; al recibir un hit de nasty (EnterGracePhase desde .pHpDmgNotZero), y eso
    ; daba 1s en el que Death te seguia pegada sin matarte. Death es instakill
    ; sin importar inmunidades temporales. En el path post-respawn legitimo,
    ; SilentKillDeath ya la despawneo, asi que no hay riesgo de instakill al
    ; recuperar control.
    LD A, (PlayerRespawnPhase)
    CP 1
    RET Z

    ; Player rect canonico: 16w x 21h (no usar GetSpriteDims — algunos frames
    ; de animacion tienen altura menor y el AABB Y-axis fallaria). Ver
    ; project_player_collision_rect.md.
    LD A, 21
    LD (.cdtPH), A

    ; --- AABB X: deathX..deathX+23 vs playerX..playerX+15 ---
    ; cond1: deathX + 24 > playerX
    LD A, (IX+ENT_POSX)
    ADD A, 24
    JR C, .cdtX2                        ; overflow → asume verdad
    LD D, A
    LD A, (EntityTable + ENT_POSX)
    CP D
    RET NC                              ; playerX >= deathX+24 → no overlap
.cdtX2:
    ; cond2: playerX + 16 > deathX
    LD A, (EntityTable + ENT_POSX)
    ADD A, 16
    JR C, .cdtY1
    LD D, A
    LD A, (IX+ENT_POSX)
    CP D
    RET NC                              ; deathX >= playerX+16 → no overlap

.cdtY1:
    ; cond3: deathY + 24 > playerY
    LD A, (IX+ENT_POSY)
    ADD A, 24
    JR C, .cdtY2
    LD D, A
    LD A, (EntityTable + ENT_POSY)
    CP D
    RET NC

.cdtY2:
    ; cond4: playerY + pH > deathY
    LD A, (EntityTable + ENT_POSY)
    LD B, A
    LD A, (.cdtPH)
    ADD A, B
    JR C, .cdtTouched
    LD D, A
    LD A, (IX+ENT_POSY)
    CP D
    RET NC

.cdtTouched:
    ; Drenar HP completo
    XOR A
    LD (PlayerHealth), A
    ; Erase sprite de la muerte
    CALL EraseDeathSprite
    ; Despawn
    XOR A
    LD (IX+ENT_TYPE), A
    LD (DeathSpawned), A
    ; SFX de muerte lo dispara OnPlayerHealthDepleted, que tambien hace
    ; stop de musica como punto canonico (cubre todos los paths de muerte).
    JP OnPlayerHealthDepleted
.cdtPH: DEFB 0

; --- EraseDeathSprite: redibuja XOR el ultimo sprite y restaura attrs ---
; IX debe ser EntityTable + SLOT_DEATH al entrar.
EraseDeathSprite:
    CALL GetOldSpriteAddr
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    PUSH IX
    LD IX, (OldSprAddr)
    CALL DrawSprite
    POP IX
    LD D, (IX+ENT_OLDY)
    LD E, (IX+ENT_OLDX)
    JP RestoreOldAttr

; ==============================================================================
; DeathBfsRescue - Mini-BFS local cuando UpdateMonster no consigue mover Death
; ==============================================================================
; Activado por UpdateDeath tras DEATH_STUCK_THRESHOLD frames consecutivos sin
; movimiento. Hace BFS de 4-conectividad desde la celda de Death hasta
; profundidad DEATH_BFS_MAX_DEPTH, tracking para cada celda visitada cual fue
; el primer paso (N/S/W/E) desde el inicio.
;
; Pasability: 9 celdas del footprint 3x3 deben ser 0 en CollisionMap (criterio
; consistente con CheckEnemyCollision en cell-aligned positions).
;
; Score: maximizar profundidad alcanzada, tie-break por minima manhattan al
; player. El "max depth" rompe la trampa Manhattan del greedy puro (ej. wall
; al pie + player justo debajo: ir lateral aumenta manhattan en 1 al primer
; paso pero permite llegar a una celda mas profunda con dist menor).
;
; Tras encontrar best dir: setea DELTAX/Y a ±MONSTER_SPEED, intenta UN paso
; con CheckEnemyCollision. Si falla, no-op (siguiente frame retry). Si OK,
; persistencia de UpdateMonster mantendra la direccion en frames sucesivos.
;
; IX = SLOT_DEATH al entrar.
; ==============================================================================
DeathBfsRescue:
    ; --- Celda inicial = celda actual de Death ---
    LD A, (IX+ENT_POSX)
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (DBfsCurCx), A
    LD A, (IX+ENT_POSY)
    SUB SCREEN_MIN_Y
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (DBfsCurCy), A
    ; --- Celda del player ---
    LD A, (EntityTable + ENT_POSX)
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (DBfsPlayerCx), A
    LD A, (EntityTable + ENT_POSY)
    SUB SCREEN_MIN_Y
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (DBfsPlayerCy), A
    ; --- Init queue con celda inicial (depth=0, first_dir=NONE) ---
    LD HL, DBfsQueue
    LD (DBfsQHead), HL
    LD A, (DBfsCurCx)
    LD (HL), A
    INC HL
    LD A, (DBfsCurCy)
    LD (HL), A
    INC HL
    LD (HL), MAI_DIR_NONE
    INC HL
    LD (HL), 0
    INC HL
    LD (DBfsQTail), HL
    ; Best inicial: ningun candidato
    LD A, MAI_DIR_NONE
    LD (DBfsBestDir), A
    XOR A
    LD (DBfsBestDepth), A
    LD A, $FF
    LD (DBfsBestManh), A

.bfsLoop:
    ; Queue empty?
    LD HL, (DBfsQHead)
    LD DE, (DBfsQTail)
    OR A
    SBC HL, DE
    JP Z, .bfsApply
    ; Dequeue
    LD HL, (DBfsQHead)
    LD A, (HL)
    LD (DBfsCurCx), A
    INC HL
    LD A, (HL)
    LD (DBfsCurCy), A
    INC HL
    LD A, (HL)
    LD (DBfsCurFirstDir), A
    INC HL
    LD A, (HL)
    LD (DBfsCurDepth), A
    INC HL
    LD (DBfsQHead), HL
    ; Si depth ya >= max, no expandir vecinos
    LD A, (DBfsCurDepth)
    CP DEATH_BFS_MAX_DEPTH
    JP NC, .bfsLoop

    ; --- Expandir 4 vecinos ---
    ; N: cy-1
    LD A, (DBfsCurCy)
    OR A
    JR Z, .bfsTryS
    DEC A
    LD C, A
    LD A, (DBfsCurCx)
    LD B, A
    LD A, MAI_DIR_N
    CALL .bfsTryNbr
.bfsTryS:
    LD A, (DBfsCurCy)
    CP 21
    JR NC, .bfsTryW
    INC A
    LD C, A
    LD A, (DBfsCurCx)
    LD B, A
    LD A, MAI_DIR_S
    CALL .bfsTryNbr
.bfsTryW:
    LD A, (DBfsCurCx)
    OR A
    JR Z, .bfsTryE
    DEC A
    LD B, A
    LD A, (DBfsCurCy)
    LD C, A
    LD A, MAI_DIR_W
    CALL .bfsTryNbr
.bfsTryE:
    LD A, (DBfsCurCx)
    CP 31
    JP NC, .bfsLoop
    INC A
    LD B, A
    LD A, (DBfsCurCy)
    LD C, A
    LD A, MAI_DIR_E
    CALL .bfsTryNbr
    JP .bfsLoop

.bfsApply:
    ; --- Aplicar best dir si la hay ---
    LD A, (DBfsBestDir)
    CP MAI_DIR_NONE
    RET Z
    ; Setear DELTAX/Y segun dir
    CP MAI_DIR_N
    JR Z, .bfsAppN
    CP MAI_DIR_S
    JR Z, .bfsAppS
    CP MAI_DIR_W
    JR Z, .bfsAppW
    LD (IX+ENT_DELTAX), MONSTER_SPEED
    LD (IX+ENT_DELTAY), 0
    JR .bfsAppMove
.bfsAppN:
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), -MONSTER_SPEED
    JR .bfsAppMove
.bfsAppS:
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), MONSTER_SPEED
    JR .bfsAppMove
.bfsAppW:
    LD (IX+ENT_DELTAX), -MONSTER_SPEED
    LD (IX+ENT_DELTAY), 0
.bfsAppMove:
    ; Intentar 1 paso con collision check
    LD A, (IX+ENT_POSX)
    LD (.bfsSvX), A
    LD A, (IX+ENT_POSY)
    LD (.bfsSvY), A
    LD A, (IX+ENT_POSX)
    ADD A, (IX+ENT_DELTAX)
    LD (IX+ENT_POSX), A
    LD A, (IX+ENT_POSY)
    ADD A, (IX+ENT_DELTAY)
    LD (IX+ENT_POSY), A
    CALL CheckEnemyCollision
    RET Z
    ; Bloqueado: revertir (DELTAX/Y se quedan setteados para que persistence
    ; de UpdateMonster vea la direccion del rescue en el siguiente intento).
    LD A, (.bfsSvX)
    LD (IX+ENT_POSX), A
    LD A, (.bfsSvY)
    LD (IX+ENT_POSY), A
    RET
.bfsSvX: DEFB 0
.bfsSvY: DEFB 0

; --- bfsTryNbr: probar vecino (B=nx, C=ny, A=step_dir). Si valido, encolar
; y actualizar best. ---
.bfsTryNbr:
    LD (DBfsTryDir), A
    LD A, B
    LD (DBfsTryCx), A
    LD A, C
    LD (DBfsTryCy), A
    ; Bounds: nx <= FFZ_MAX_CX, ny <= FFZ_MAX_CY (sprite cabe sin wrap/HUD)
    LD A, (DBfsTryCx)
    CP FFZ_MAX_CX + 1
    RET NC
    LD A, (DBfsTryCy)
    CP FFZ_MAX_CY + 1
    RET NC
    ; Visited?
    CALL .bfsIsVisited
    RET NZ
    ; Footprint 3x3 libre?
    CALL .bfsCanFit
    RET NZ
    ; --- first_dir del nuevo entry: hereda si curFirstDir != NONE, si no usa step ---
    LD A, (DBfsCurFirstDir)
    CP MAI_DIR_NONE
    JR NZ, .nbrInherit
    LD A, (DBfsTryDir)
.nbrInherit:
    LD B, A                             ; B = first_dir para enqueue
    ; Encolar
    LD HL, (DBfsQTail)
    LD A, (DBfsTryCx)
    LD (HL), A
    INC HL
    LD A, (DBfsTryCy)
    LD (HL), A
    INC HL
    LD A, B
    LD (HL), A
    INC HL
    LD A, (DBfsCurDepth)
    INC A
    LD (HL), A
    LD C, A                             ; C = newDepth
    INC HL
    LD (DBfsQTail), HL
    ; --- Score: max depth tie-break min manhattan ---
    ; manhattan = |tryCx - playerCx| + |tryCy - playerCy|
    LD A, (DBfsTryCx)
    LD D, A
    LD A, (DBfsPlayerCx)
    SUB D
    JR NC, .nbrAbsX
    NEG
.nbrAbsX:
    LD D, A
    LD A, (DBfsTryCy)
    LD E, A
    LD A, (DBfsPlayerCy)
    SUB E
    JR NC, .nbrAbsY
    NEG
.nbrAbsY:
    ADD A, D                            ; A = manhattan
    LD D, A
    ; Compare: depth > best ? update : (depth == best && manh < bestManh ? update : skip)
    LD A, C
    LD HL, DBfsBestDepth
    CP (HL)
    JR C, .nbrNoBest
    JR NZ, .nbrUpdate                   ; depth > bestDepth
    LD A, D
    LD HL, DBfsBestManh
    CP (HL)
    JR NC, .nbrNoBest                   ; manh >= best
.nbrUpdate:
    LD A, C
    LD (DBfsBestDepth), A
    LD A, D
    LD (DBfsBestManh), A
    LD A, B
    LD (DBfsBestDir), A
.nbrNoBest:
    RET

; --- bfsIsVisited: scan queue [Queue, QTail). Z=no visited, NZ=visited ---
.bfsIsVisited:
    LD HL, DBfsQueue
    LD DE, (DBfsQTail)
.bivLoop:
    ; HL == DE -> end
    PUSH HL
    OR A
    SBC HL, DE
    POP HL
    JR Z, .bivNotFound
    LD A, (HL)
    LD B, A
    INC HL
    LD A, (HL)
    LD C, A
    DEC HL
    LD A, (DBfsTryCx)
    CP B
    JR NZ, .bivNext
    LD A, (DBfsTryCy)
    CP C
    JR NZ, .bivNext
    ; Match
    LD A, 1
    OR A                                ; NZ
    RET
.bivNext:
    LD A, 4
    ADD A, L
    LD L, A
    JR NC, .bivLoop
    INC H
    JR .bivLoop
.bivNotFound:
    XOR A                               ; Z
    RET

; --- bfsCanFit: footprint 3x3 de Death en CollisionMap libre? ---
; IN: DBfsTryCx, DBfsTryCy. OUT: Z=libre, NZ=bloqueado.
.bfsCanFit:
    LD A, (DBfsTryCy)
    LD H, 0
    LD L, A
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; HL = cy*32
    LD A, (DBfsTryCx)
    ADD A, L
    LD L, A
    JR NC, .cfNoCarry
    INC H
.cfNoCarry:
    LD DE, CollisionMap
    ADD HL, DE                          ; HL = &CollisionMap[cy][cx]
    LD C, 3                             ; filas restantes
.cfRow:
    PUSH HL
    LD B, 3                             ; cols restantes
.cfCol:
    LD A, (HL)
    OR A
    JR NZ, .cfBlocked
    INC HL
    DJNZ .cfCol
    POP HL
    LD DE, 32
    ADD HL, DE
    DEC C
    JR NZ, .cfRow
    XOR A                               ; Z
    RET
.cfBlocked:
    POP HL
    LD A, 1
    OR A                                ; NZ
    RET

; ==============================================================================
; OnPlayerHealthDepleted - PlayerHealth llego a 0
; ==============================================================================
; -1 vida (clamp a 0); refill HP + stamina al maximo. Sin animaciones, sin
; respawn position, sin game over (de momento). El HUD se actualiza solo via
; DrawLivesHUD (caché .dlhLast detecta el cambio).
; ==============================================================================
; ==============================================================================
; InitGameState - Reset explicito de variables de gameplay a "partida nueva"
; ==============================================================================
; Llamado desde Inicio (boot fresco) y desde el reset por SPACE en game over.
; Variables.asm tiene DEFB initializers que solo se aplican al cargar el .tap;
; tras un reset por software los valores actuales persisten en RAM. Esta rutina
; los pone a su default.
; ==============================================================================
InitGameState:
    LD A, PLAYER_LIVES_INIT
    LD (PlayerLives), A
    LD A, HEALTH_MAX
    LD (PlayerHealth), A
    LD A, STAMINA_MAX
    LD (PlayerStamina), A
    XOR A
    LD (GameOver), A
    LD (CurrentObjective), A
    LD (CurrentKey), A
    LD (ChurchEverOpened), A
    LD (ChurchDoorOpen), A
    LD (TimeFrozen), A
    LD (ChurchKeySpawned), A
    LD (TownGateKeySpawned), A
    LD (ArmRevealed), A
    LD (FingerRevealed), A
    LD (MonstersActive), A
    LD (MonsterTrappedFlags), A
    LD (DeathSpawned), A
    LD (TownGatePhase), A
    LD (ChurchCutscenePhase), A
    LD (CurrentTimeOfDay), A            ; fase 0 = DY
    LD (BellsTriggered), A
    LD (NextChurchTrapStep), A
    LD (StatueBlinkCounter), A
    LD (ChurchKeyAltSpawnIdx), A
    LD (PlayerHitTimer), A
    LD (TombstoneCount), A              ; Reset tumbas en game-restart fresh
    LD (TombDrawPending), A
    LD (DeathBorderPhase), A
    LD (DeathBorderTimer), A
    LD (PlayerDeathAnimTimer), A
    LD (PlayerDeathAnimFrame), A
    LD (PlayerRespawnPhase), A
    LD (PlayerRespawnTimer), A
    LD (PlayerRespawnBlinkTimer), A
    LD (PlayerRespawnBeatIdx), A
    LD (GameOverAnimX), A
    LD (GameOverAnimDir), A
    LD (GameOverAnimFrame), A
    LD (GameOverAnimFrameTimer), A
    LD (GameOverAnimLastX), A
    LD HL, 0
    LD (GameOverAnimLastSpr), HL
    LD (DeathScreenTimer), HL           ; 16-bit reset
    LD A, 1
    LD (PlayerRespawnVisible), A
    LD A, BLACK
    LD (CurrentBorderColor), A
    OUT (254), A
    LD A, 1
    LD (DayCycleCount), A
    LD HL, DiurnalTypeTable
    LD (CurrentNastyTable), HL
    ; Reset speed + buff (en caso de restart con buff activo).
    LD A, SPEED_RUN
    LD (PlayerSpeedRun), A
    LD A, SPEED_FIGHT
    LD (PlayerSpeedFight), A
    LD HL, 0
    LD (SpeedBuffTimer), HL                  ; timer + type (16-bit aligned)
    LD (MushroomLockTimer), HL               ; reset mushroom debuff
    XOR A
    LD (SpeedBuffType), A
    ; Activar phase 1 del respawn al boot/game-restart: 4 pitidos (3 cortos +
    ; GO largo) + grace de 1s con control. Durante phase 1: input zero,
    ; nasties bloqueados, Death no aparece. Tras urb1AfterBeep: SpawnTimer
    ; reseteado a SPAWN_INTERVAL -> nasties cuentan desde que el player
    ; recupera el control. Mismo flujo que tras una muerte.
    LD A, 1
    LD (PlayerRespawnPhase), A
    RET

OnPlayerHealthDepleted:
    ; Cancelar magic compass: el power-up se pierde con la muerte (refuerza
    ; coste real). Idempotente si no estaba activo.
    CALL CancelMagicCompass
    ; Silenciar inmediatamente cualquier musica activa (DeathMusic o cualquier
    ; otra). Va ANTES de AY_PlayPlayerDeath: ambos usan canal B, sin este stop
    ; el sweep clobbearia residuos. Es el punto canonico de "player muere"
    ; (combate, Death catch, drain de salud por cualquier via).
    PUSH AF
    LD A, $FF
    CALL StartMusic
    POP AF
    ; Tambien parar el secuencer ad-hoc de MonstersMusic (no va por el driver
    ; tabular; tiene su propia variable de estado MonstersMusicStep).
    CALL StopMonstersMusic
    ; SFX de muerte (sweep largo agudo→muy grave + decay lento ~2s).
    ; No bloqueante, canal B. Va antes que el resto para no perder el ataque.
    CALL AY_PlayPlayerDeath
    ; Congelar tiempo (silencioso, sin parpadeo de la esfera). El feedback
    ; visual ya viene del border yellow/red. Limpiado en urb1LastBeat.
    LD A, 2
    LD (TimeFrozen), A
    ; Guardar tumba en la posicion donde ha muerto (player POSX/POSY actuales)
    CALL TombStore
    ; Despawn de todos los nasties activos con puff (visual de "shockwave")
    CALL KillAllActiveNasties
    ; La muerte (slot 11) tambien desaparece, pero sin puff
    CALL SilentKillDeath
    ; Monsters quedan congelados mirando al cadaver hasta que vuelva el control
    CALL FreezeMonstersFacingCorpse
    ; Trigger del flash del borde: 2s amarillo (anim muerte) + 3s rojo (invisible) o GAME OVER
    CALL TriggerDeathBorder
    ; Override sprite a frame 0 de la anim de muerte. ProcessPlayer en la
    ; siguiente frame hara .plDoErase (erase del sprite anterior + draw del
    ; nuevo) automaticamente porque SPRITEID != OLDSPRID.
    LD IX, EntityTable
    ; Base de la anim segun lastHDir (bits 4-7 de ENT_DIR): DIR_W<<4 = $80
    LD A, (IX+ENT_DIR)
    AND $80
    LD A, SPRID_PLAYER_DEATH            ; default = right base (110)
    JR Z, .ophdRightBase
    LD A, SPRID_PLAYER_DEATH_LEFT       ; lastHDir = W → left base (113)
.ophdRightBase:
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD A, PLAYER_DEATH_ANIM_DELAY
    LD (PlayerDeathAnimTimer), A
    XOR A
    LD (PlayerDeathAnimFrame), A
    ; Decrementar vida (clamp a 0)
    LD A, (PlayerLives)
    OR A
    RET Z
    DEC A
    LD (PlayerLives), A
    RET

; --- ErasePlayerSpriteAtOldPos: XOR-redraw del ultimo sprite + restore attrs ---
; Mismo patron que .plDoErase: GetOldSpriteAddr -> DrawSprite -> RestoreOldAttr.
ErasePlayerSpriteAtOldPos:
    LD IX, EntityTable
    CALL GetOldSpriteAddr
    LD D, (IX+ENT_OLDY)
    LD A, (IX+ENT_OLDX)
    LD E, A
    PUSH IX
    LD IX, (OldSprAddr)
    CALL DrawSprite
    POP IX
    LD D, (IX+ENT_OLDY)
    LD E, (IX+ENT_OLDX)
    JP RestoreOldAttr                   ; tail-call

; --- RespawnPlayerAtEntry: mover a LastEntryPos, refill HP/stamina, NEWSPAWN ---
RespawnPlayerAtEntry:
    LD IX, EntityTable
    LD A, (LastEntryPosX)
    LD (IX+ENT_POSX), A
    LD (IX+ENT_OLDX), A
    LD (IX+ENT_DRAWX), A
    LD A, (LastEntryPosY)
    LD (IX+ENT_POSY), A
    LD (IX+ENT_OLDY), A
    LD A, HEALTH_MAX
    LD (PlayerHealth), A
    LD A, STAMINA_MAX
    LD (PlayerStamina), A
    LD (IX+ENT_SPRITEID), SPRID_IDLE
    LD (IX+ENT_OLDSPRID), SPRID_IDLE
    LD (IX+ENT_ANIMBASE), SPRID_IDLE
    LD (IX+ENT_STATE), STATE_IDLE
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    ; Reset color a blanco + cooldowns: si moriste con AttackCooldown activo
    ; (modo B post-swing), ENT_ATTR estaba en BLUE. Sin esto, el azul stale
    ; persiste tras respawn porque SelectSwordMode ve stamina=MAX -> modo
    ; libre, y .swordModeFree no toca el color.
    LD (IX+ENT_ATTR), WHITE | $40
    XOR A
    LD (AttackCooldown), A
    LD (AttackTimer), A
    SET ENTF_NEWSPAWN, (IX+ENT_FLAGS)
    ; Activar phase 1 del respawn: countdown 3-2-1 con bips.
    ; Timer=0 -> primer beat al siguiente frame. BeatIdx=0.
    LD A, 1
    LD (PlayerRespawnPhase), A
    XOR A
    LD (PlayerRespawnTimer), A
    LD (PlayerRespawnBeatIdx), A
    RET

; ==============================================================================
; TriggerDeathBorder - arranca el flash del borde tras morir
; ==============================================================================
; Phase 1 (yellow) DEATH_BORDER_YELLOW_FRAMES, luego phase 2 (red) DEATH_BORDER_RED_FRAMES,
; luego vuelve a negro y se desactiva.
; ==============================================================================
TriggerDeathBorder:
    LD A, 1
    LD (DeathBorderPhase), A
    LD A, DEATH_BORDER_YELLOW_FRAMES
    LD (DeathBorderTimer), A
    LD A, YELLOW
    LD (CurrentBorderColor), A
    OUT (254), A
    RET

; ==============================================================================
; UpdateRespawnBlink - state machine post-respawn (countdown audio + grace timer)
; ==============================================================================
; Phase 1: countdown "3, 2, 1" con 3 bips bloqueantes (sin control, invulnerable).
; Phase 2: 2s grace (con control, invulnerable). No hay efecto visual de momento.
; ==============================================================================
UpdateRespawnBlink:
    LD A, (PlayerRespawnPhase)
    OR A
    RET Z
    DEC A
    JR Z, .urbPhase1
    ; Phase 2: solo timer (sin parpadeo)
    LD A, (PlayerRespawnTimer)
    DEC A
    LD (PlayerRespawnTimer), A
    RET NZ
    XOR A
    LD (PlayerRespawnPhase), A
    RET

.urbPhase1:
    ; Phase 1: countdown 3-2-1 con bips bloqueantes y silencios entre ellos.
    ; Zero input (sin control)
    XOR A
    LD (InputDirection), A
    LD (InputFire), A
    ; Blink sync con beep audible: BeepDurationFrames != 0 (sonando) → IDLE,
    ; == 0 (silencio) → PLAYER_BLANK. Sin RAM extra (variable ya existente).
    LD A, (BeepDurationFrames)
    SUB 1                               ; CY si era 0 (silencio)
    SBC A, A                            ; $FF si silencio, $00 si sonando
    AND SPRID_PLAYER_BLANK
    LD (EntityTable), A
    ; Si Timer > 0 estamos en silencio entre beats: tickear y volver
    LD A, (PlayerRespawnTimer)
    OR A
    JR Z, .urb1FireBeat
    DEC A
    LD (PlayerRespawnTimer), A
    RET
.urb1FireBeat:
    LD A, (PlayerRespawnBeatIdx)
    INC A
    LD (PlayerRespawnBeatIdx), A
    CP 4
    JR Z, .urb1LastBeat
    CP 5
    JR Z, .urb1AfterBeep        ; beat 5 = "post-GO": grace tras beep largo
    ; Beats 1, 2, 3: pitido corto BASIC-BEEP-style (vol fija + cutoff abrupto)
    LD HL, $00C0                ; ~569 Hz (≈D5, 7 semitonos bajo el A5 original)
    LD B, 4                     ; ~160 ms (4 frames @ 25fps)
    CALL AY_PlayBeep
    ; Intervalo entre beeps: 20 frames @ 25fps = 0.8 s. El blink usa CP 10
    ; (mitad) para mantener ON/OFF ~50/50.
    LD A, 20
    LD (PlayerRespawnTimer), A
    RET
.urb1LastBeat:
    ; Beat 4: pitido octava arriba mas largo (= "GO!"). Vol max sostenida +
    ; cutoff abrupto tras 11 frames (~440 ms). NO entra en grace todavia:
    ; setea timer = 11 (= duracion del beep) → el siguiente fire (idx=5)
    ; entra grace EXACTAMENTE al terminar el beep.
    LD HL, $0060                ; ~1139 Hz (≈D6, octava arriba del corto, 7 semitonos bajo el A6 original)
    LD B, 11                    ; ~440 ms (11 frames @ 25fps)
    CALL AY_PlayBeep
    LD A, 11                    ; espera = duracion del beep
    LD (PlayerRespawnTimer), A
    RET
.urb1AfterBeep:
    ; Beep largo terminado. Phase 2 = control vuelve. Resets ligados al fin
    ; del countdown (igual que la version v3 anterior, solo movidos aqui).
    CALL EnterGracePhase            ; phase 2 + timer = RESPAWN_GRACE_FRAMES
    LD A, SPAWN_INTERVAL
    LD (SpawnTimer), A
    XOR A
    LD (DeathSpawned), A
    LD (MonstersFrozen), A          ; Liberar monsters: AI normal vuelve
    LD (TimeFrozen), A              ; Reanudar reloj
    LD HL, 0
    LD (DeathScreenTimer), HL       ; 16-bit reset
    ; Si los monsters siguen activos (no era game over), reanudar el
    ; secuencer "po-po-popo-po" — fue parado en OnPlayerHealthDepleted.
    LD A, (MonstersActive)
    OR A
    RET Z
    ; No re-arrancar si los 3 monsters estan atrapados en la iglesia
    ; (StopMonstersMusic se llamo en TriggerChurchTrap del 3o; ya no hay
    ; monsters jugables en pantalla aunque MonstersActive siga 1).
    LD A, (MonsterTrappedFlags)
    AND $07
    CP $07
    RET Z
    JP StartMonstersMusic           ; tail-call

; ==============================================================================
; EnterGracePhase - Activa Phase 2 (gracia con blink) por RESPAWN_GRACE_FRAMES
; ==============================================================================
; Llamado desde:
;   - urb1LastBeat: tras los 3 pitidos del countdown del respawn.
;   - CheckPlayerEnemyCollision.pHpDmgNotZero: tras cada hit de nasty/monster.
; Activa invulnerabilidad (.playerHit chequea PlayerRespawnPhase != 0) y blink
; (UpdatePlayer chequea PlayerRespawnTimer != 0).
; ==============================================================================
EnterGracePhase:
    LD A, 2
    LD (PlayerRespawnPhase), A
    LD A, RESPAWN_GRACE_FRAMES
    LD (PlayerRespawnTimer), A
    RET

; ==============================================================================
; UpdateDeathAnim - tick de la anim de muerte del player durante phase 1 (yellow)
; ==============================================================================
; Avanza ENT_SPRITEID +1 cada PLAYER_DEATH_ANIM_DELAY frames. La base (110 right
; o 113 left) se fija en OnPlayerHealthDepleted; aqui solo incrementamos.
; Al llegar al ultimo frame, se queda ahi (resto del yellow en frame final).
; ==============================================================================
UpdateDeathAnim:
    LD A, (DeathBorderPhase)
    CP 1
    RET NZ
    LD A, (PlayerDeathAnimTimer)
    DEC A
    LD (PlayerDeathAnimTimer), A
    RET NZ
    ; Tick consumido: avanzar frame
    LD A, (PlayerDeathAnimFrame)
    INC A
    CP PLAYER_DEATH_ANIM_FRAMES
    RET NC                              ; ya en ultimo frame (clamp)
    LD (PlayerDeathAnimFrame), A
    LD IX, EntityTable
    INC (IX+ENT_SPRITEID)               ; siguiente frame de la anim
    ; Al entrar en el ULTIMO frame (= "desparramado en el suelo") reproducir
    ; el SFX del puff (mismo que la muerte de un nasty). El A actual contiene
    ; el frame recien escrito; comparamos con el ultimo (FRAMES-1).
    CP PLAYER_DEATH_ANIM_FRAMES - 1
    JR NZ, .udaSkipSplatSfx
    LD HL, SFX_EnemyDeath
    CALL PlaySFX
.udaSkipSplatSfx:
    LD A, PLAYER_DEATH_ANIM_DELAY
    LD (PlayerDeathAnimTimer), A
    RET

; ==============================================================================
; UpdateDeathBorder - tick por frame; transiciona fase amarillo -> rojo -> negro
; ==============================================================================
UpdateDeathBorder:
    LD A, (DeathBorderPhase)
    OR A
    RET Z
    LD A, (DeathBorderTimer)
    DEC A
    LD (DeathBorderTimer), A
    RET NZ
    ; Timer expiro: avanzar fase
    LD A, (DeathBorderPhase)
    CP 1
    JR NZ, .udbToBlack
    ; --- Fin fase amarillo ---
    ; Si PlayerLives==0 -> game over directo (sin pasar por rojo).
    ; Si quedan vidas -> fase rojo 3s + sprite a BLANK (player invisible).
    LD A, (PlayerLives)
    OR A
    JR Z, .udbToGameOver
    LD IX, EntityTable
    LD (IX+ENT_SPRITEID), SPRID_PLAYER_BLANK
    LD A, 2
    LD (DeathBorderPhase), A
    LD A, DEATH_BORDER_RED_FRAMES
    LD (DeathBorderTimer), A
    LD A, RED
    LD (CurrentBorderColor), A
    OUT (254), A
    ; Pedir tumba in-place: ProcessPlayer va a borrar el sprite muerte este
    ; mismo frame; DrawPendingTomb (tras ProcessPlayer) la pintara encima.
    LD A, 1
    LD (TombDrawPending), A
    RET
.udbToGameOver:
    ; Pasar borde a negro y disparar pantalla GAME OVER (reemplaza al rojo).
    XOR A
    LD (DeathBorderPhase), A
    LD A, BLACK
    LD (CurrentBorderColor), A
    OUT (254), A
    JP ShowGameOver
.udbToBlack:
    ; Phase 2 (rojo) terminado -> negro + respawn del player en LastEntryPos
    XOR A
    LD (DeathBorderPhase), A
    LD A, BLACK
    LD (CurrentBorderColor), A
    OUT (254), A
    JP RespawnPlayerAtEntry             ; tail-call

; ==============================================================================
; ShowGameOver - solo arma el flag; MainLoop pinta la pantalla en la siguiente iter
; ==============================================================================
; Llamado desde mid-frame en OnPlayerHealthDepleted. NO pinta aqui porque el
; resto del frame (ProcessEnemies, HUD, etc.) sobreescribiria la pantalla.
; MainLoop al ver GameOver=1 hace PaintGameOverScreen y pasa a GameOver=2.
; ==============================================================================
ShowGameOver:
    LD A, 1
    LD (GameOver), A
    RET

; --- PaintGameOverScreen: wipe + init moonwalk anim. Llamado UNA vez por MainLoop. ---
; La animacion en si la dibuja UpdateGameOverAnim cada frame mientras GameOver=2.
PaintGameOverScreen:
    ; Wipe pixels
    LD HL, $4000
    LD DE, $4001
    LD BC, $17FF
    LD (HL), 0
    LDIR
    ; Attrs $47 (white ink, black paper, bright) en toda la pantalla
    LD HL, $5800
    LD DE, $5801
    LD BC, $02FF
    LD (HL), $47
    LDIR
    ; Tumba 2x centrada (sprite ID 144, "little house cemetery") sobre la que
    ; la muerte hará el moonwalk. Cold path: 1 vez por partida.
    CALL DrawTombstone2xCentered
    ; Init anim moonwalk: empieza en X_MAX facing R (slide left).
    LD A, GAMEOVER_ANIM_X_MAX
    LD (GameOverAnimX), A
    XOR A
    LD (GameOverAnimDir), A
    LD (GameOverAnimFrame), A
    LD (GameOverAnimLastX), A
    LD HL, 0
    LD (GameOverAnimLastSpr), HL    ; Sin erase la primera vez
    LD A, GAMEOVER_ANIM_FRAME_TICKS
    LD (GameOverAnimFrameTimer), A
    ; Jingle de game over (track 3). UpdateMusic se llama cada frame en MainLoop
    ; antes del guard de GameOver, asi que la pista sigue avanzando con el juego
    ; congelado en GameOver=2.
    LD A, 3
    JP StartMusic                   ; tail-call

; ==============================================================================
; UpdateGameOverAnim — Death moonwalkea por la pantalla negra
; ==============================================================================
; Llamado cada frame desde MainLoop mientras GameOver=2. Anim ping-pong:
;   dir=0 → slide LEFT  (X: MAX → 0) usando sprites de movimiento DERECHO
;   dir=1 → slide RIGHT (X: 0 → MAX) usando sprites de movimiento IZQUIERDO
; Sprites invertidos vs direccion = efecto moonwalk: el cuerpo desliza al
; contrario de los pies. Aprovecha que en este juego SprDeath_0/1 son el par
; usado para DELTAX<0 (mover izquierda) y SprDeath_L0/L1 para DELTAX>0.
; XOR-erase con el ptr+X guardado del frame anterior. Toggle del frame interno
; cada FRAME_TICKS frames. Init via PaintGameOverScreen.
;
; X bound a [0, 224] para que el sprite 24x24 no overflow VRAM en path
; shifted (que ocupa 4 chars = 32 px).
; ==============================================================================
; Tumba 2x ocupa pixel Y range 80..159 (charY 10..19). La muerte (24x24) baila
; justo encima del techo: Y_top=56 → Y_bottom=79, 1 px de hueco al techo.
; X swing centrado sobre la tumba:
;   X_MIN: 96  = char 12 (2 chars dentro del borde izq de la tumba en char 10)
;   X_MAX: 136 = char 17 (3 chars dentro del borde der de la tumba en char 22)
;   Death sprite 24 px wide → visual cubre chars 12..19 (centrado).
GAMEOVER_ANIM_Y           EQU 56
GAMEOVER_ANIM_X_MIN       EQU 96
GAMEOVER_ANIM_X_MAX       EQU 136
GAMEOVER_ANIM_FRAME_TICKS EQU 6

UpdateGameOverAnim:
    ; --- Erase del sprite previo (si lo hubo) ---
    LD HL, (GameOverAnimLastSpr)
    LD A, H
    OR L
    JR Z, .ugoaNoErase
    PUSH HL
    POP IX
    LD A, (GameOverAnimLastX)
    LD E, A
    LD D, GAMEOVER_ANIM_Y
    CALL DrawSprite
.ugoaNoErase:

    ; --- Tick frame timer (R0 ↔ R1 cada FRAME_TICKS frames) ---
    LD A, (GameOverAnimFrameTimer)
    DEC A
    JR NZ, .ugoaTimerSet
    LD A, (GameOverAnimFrame)
    XOR 1
    LD (GameOverAnimFrame), A
    LD A, GAMEOVER_ANIM_FRAME_TICKS
.ugoaTimerSet:
    LD (GameOverAnimFrameTimer), A

    ; --- Avanzar X segun direccion (ping-pong) ---
    LD A, (GameOverAnimDir)
    OR A
    JR NZ, .ugoaSlideRight
    ; Dir 0: facing R, slide LEFT (X--)
    LD A, (GameOverAnimX)
    CP GAMEOVER_ANIM_X_MIN
    JR Z, .ugoaFlipToL
    DEC A
    LD (GameOverAnimX), A
    JR .ugoaPickSprite
.ugoaFlipToL:
    LD A, 1
    LD (GameOverAnimDir), A
    JR .ugoaPickSprite
.ugoaSlideRight:
    ; Dir 1: facing L, slide RIGHT (X++)
    LD A, (GameOverAnimX)
    CP GAMEOVER_ANIM_X_MAX
    JR Z, .ugoaFlipToR
    INC A
    LD (GameOverAnimX), A
    JR .ugoaPickSprite
.ugoaFlipToR:
    XOR A
    LD (GameOverAnimDir), A

.ugoaPickSprite:
    ; Moonwalk: usar sprites del eje OPUESTO al deslizamiento.
    ;   dir=0 (slide L) → par L (sprites de "mover derecha")
    ;   dir=1 (slide R) → par R (sprites de "mover izquierda")
    LD A, (GameOverAnimDir)
    OR A
    JR NZ, .ugoaPickR
    LD A, (GameOverAnimFrame)
    OR A
    LD HL, SprDeath_L0
    JR Z, .ugoaSprSet
    LD HL, SprDeath_L1
    JR .ugoaSprSet
.ugoaPickR:
    LD A, (GameOverAnimFrame)
    OR A
    LD HL, SprDeath_0
    JR Z, .ugoaSprSet
    LD HL, SprDeath_1
.ugoaSprSet:
    LD (GameOverAnimLastSpr), HL
    LD A, (GameOverAnimX)
    LD (GameOverAnimLastX), A

    ; --- Draw nuevo sprite ---
    PUSH HL
    POP IX
    LD E, A
    LD D, GAMEOVER_ANIM_Y
    JP DrawSprite                   ; tail-call
