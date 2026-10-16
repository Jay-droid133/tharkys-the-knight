;==============================================================================
; cold_slot1.asm - Codigo frio movido desde bank 0 (slot 1, siempre visible)
;==============================================================================
; Solo corre al empezar partida o al sacar monsters: la contienda de slot 1 no
; importa. Movido para que el bank 0 quepa bajo $FE80 al juntar la rama de
; rendimiento con el modo 50 Hz (ASSERT Bank0End <= $FE80 en main.asm).
;==============================================================================

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

