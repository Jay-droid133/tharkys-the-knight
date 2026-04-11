#!/usr/bin/env python3
import os

asm_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'code', 'logic_game.asm')
lines = open(asm_path, encoding='utf-8').readlines()

start = None
end = None
for i, line in enumerate(lines):
    if line.startswith('SpawnMonsters:') and start is None:
        start = i
    if line.startswith('ResetAttrBlock:') and start is not None:
        end = i
        break

# Go back to include the header comment
while start > 0 and not lines[start-1].strip().startswith('; ==='):
    start -= 1
if start > 0 and lines[start-1].strip().startswith('; ==='):
    start -= 1

new_block = """\
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
    ; Posicion = LastEntryPos
    LD A, (LastEntryPosX)
    LD (IX+ENT_POSX), A
    LD A, (LastEntryPosY)
    LD (IX+ENT_POSY), A
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
    ; === Activar en LastEntryPos ===
    LD A, (LastEntryPosX)
    LD (IX+ENT_POSX), A
    LD A, (LastEntryPosY)
    LD (IX+ENT_POSY), A
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

; --- Timers de regreso: knockback -> 3s -> reaparece ---
.rmUpdateReturnTimers:
    LD HL, MonsterReturnTimer
    LD IX, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    LD B, MONSTERS_TO_SPAWN
.rmRtLoop:
    LD A, (HL)
    OR A
    JR Z, .rmRtNext
    DEC A
    LD (HL), A
    JR NZ, .rmRtNext
    ; Timer expiro: dejar TYPE_NONE + DIR!=0 en LastEntryPos
    LD A, (LastEntryPosX)
    LD (IX+ENT_POSX), A
    LD A, (LastEntryPosY)
    LD (IX+ENT_POSY), A
    LD (IX+ENT_DIR), DIR_N
    XOR A
    LD (.rmTimer), A
.rmRtNext:
    LD DE, ENT_SIZE
    ADD IX, DE
    INC HL
    DJNZ .rmRtLoop
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
    LD A, (LastEntryPosX)
    LD (IX+ENT_POSX), A
    LD A, (LastEntryPosY)
    LD (IX+ENT_POSY), A
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

"""

print(f'Replacing lines {start+1}-{end} ({end-start} lines)')
lines[start:end] = [new_block]
open(asm_path, 'w', encoding='utf-8').writelines(lines)
print('Done')
