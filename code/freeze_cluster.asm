; ==============================================================================
; FREEZE_CLUSTER - Rutinas frias de muerte de player / day cycle (slot 1)
; ==============================================================================
; MOVIDO desde bank 2 (logic_game.asm) al hueco que libero la tabla IM 2 al
; mudarse a bank 2 (fix ULA snow en hardware real, ver im2_table.asm +
; docs/ula_snow_investigation.md).
;
; Por que slot 1 y no otro bank: slot 1 es always-visible -> los CALL
; absolutos de los callers (day_cycle.asm KillAllActiveMonsters,
; milestones.asm + logic_game.asm SilentKillDeath/FreezeMonstersFacingCorpse,
; logic_game.asm CheckMonsterOverlap) funcionan sin thunks ni paginacion.
; Codigo frio (solo corre al morir el player o en cambio de ciclo): la
; contention de slot 1 es irrelevante.
;
; Deps: EraseDeathSprite (bank 0) -- todos los callers entran con bank 0 en
; slot 3 (gameplay), igual que cuando esto vivia en bank 2. CheckEnemyCollision
; y las vars (EntityTable, CorpseX/Y, MonstersFrozen...) viven en bank 2,
; siempre visibles.
;
; OJO: el flujo de slot 1 posterior (music_irq.asm) termina en un ASSERT
; $ <= $7B7B antes del ORG de Im2Vector. Si este cluster crece, el build
; falla ahi en vez de solapar silenciosamente.
; ==============================================================================

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
    SET ENTF_DYING_FRESH, (IX+ENT_FLAGS)  ; peDying restaura attrs pre-puff
    ; ENT_ATTR conservado: puff hereda color del monster
.kamSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    POP BC
    DJNZ .kamLoop
    RET
