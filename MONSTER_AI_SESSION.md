# Monster AI v2 — session log (2026-04-22 → 2026-04-23)

Rama: `feature/monster-ai-v2`. Branch-from `main` (`beb6682`). No merged.

## Estado jugable actual

Tres monsters aparecen por gaps al anochecer (Regla 1), te siguen por el
borde de entrada al cambiar de room (Regla 2), rodean obstáculos simples
(hybrid AI), se van por un gap al amanecer (Regla 7), y al empujarlos con
la espada migran al room vecino (Fase 8). La memoria de ubicación es
exacta: si un monster "en tránsito" no ha activado aún en el room nuevo
y el player vuelve rápido, aparece en la posición exacta que tenía antes
(Fase 9).

---

# Ubicación y comportamiento (referencia consolidada)

## Estado per-slot (3 slots: 0, 1, 2 relativos a SLOT_MONSTER0)

Cada monster tiene:

**En EntityTable[SLOT_MONSTER0 + slot]:**
- `ENT_TYPE`: 0 (TYPE_NONE = invisible) o TYPE_MONSTER (visible).
- `ENT_STATE`: STATE_RUNNING (AI normal), STATE_SCARED (amanecer/bells),
  STATE_DYING (puff), STATE_IDLE.
- `ENT_POSX/POSY`: pixel position.
- `ENT_DIR`: stun counter (0=normal). Al knockback se sobrecarga con
  DIR_N/S/E/W para indicar side de salida durante el timer de regreso.
- `ENT_ANIMBASE`, `ENT_ATTR`, `ENT_SPRITEID`, etc.

**En RAM baja (variables.asm, bank 2 fijo):**
- `MonsterRoomId[3]`: screen_id (Y*16+X) donde el monster "vive".
- `MonsterEntryBorder[3]`: MAI_SIDE por donde entró al room actual. Usado
  para waiting position (Fase 8) y para el gap de salida en LEAVING.
- `MonsterExitCoord[3]`: coord char del gap elegido durante STATE_LEAVING
  (amanecer).
- `MonsterAiFlags[3]`: bits. Bit 0 = PUSHED (no usado), bit 1 = LEAVING,
  bit 2 = REMOTE (no usado).
- `MonsterReturnTimer[3]`: countdown frames para Regla 4 (0 = inactivo).
- `MonsterLastSeenRoom[3]`: último room donde estuvo TYPE_MONSTER ($FF
  inicial = nunca visto).
- `MonsterLastSeenX[3]`, `MonsterLastSeenY[3]`: POSX/POSY en ese room.
- `MonsterLingerTimer[3]`, `RoomHistory[3]`: reservados, no usados.

## Invariantes

- `TYPE_MONSTER` ⇒ visible, en `MonsterRoomId[slot] == CurrentScreenId`.
- `TYPE_NONE` ⇒ invisible; el monster "está" en `MonsterRoomId[slot]`
  (puede ser distinto del current del player).
- `MonsterRoomId[slot]` solo cambia en:
  1. `SpawnMonsters` (init a current).
  2. `.moKbOffscreen` (knockback → neighbor).
  3. `RepositionMonstersAtEntry` (follow/migrate/skip → actualiza a NEW si
     reposiciona, deja igual si skip).
  4. `.rmUpdateReturnTimers` (expiración → current, el monster vuelve).
- `MonsterLastSeen*` solo se escribe en transiciones (Pass 1 para
  TYPE_MONSTER slots).

## Flujo 1 — Spawn inicial (N1, tras campanadas)

`SpawnMonsters` se llama vía cadena bells → BellsDoneTimer → SpawnAfterWinTimer.

Por cada slot 0-2:
- `MonsterRoomId[slot] = CurrentScreenId`.
- Position vía `MaiPickRandomGap` (gap random cualquier side).
- `TYPE_NONE`, `DIR_N` (sentinel), `DELTAS=0`.

`TryRespawnMonsters.rmTimer = MONSTER_ENTRY_BASE` (50f = 2s @ 25fps).

Frames posteriores: `TryRespawnMonsters` activa staggered (slot 0 a los 50f,
slot 1 a los +40f, slot 2 a los +40f). Activar = TYPE_MONSTER, STATE_RUNNING,
ENTF_NEWSPAWN → `.peFresh` dibuja sin erase.

## Flujo 2 — Transición normal (player cambia de room)

`CheckScreenTransition` detecta cruce → actualiza `CurrentScreenX/Y`,
`ScreenTransition`, `LastScreenTransition` → `.doTransition` →
`RepositionMonstersAtEntry`.

**Paso preparatorio:**
1. `BuildCollisionMap` explícito (DrawScreen lo reconstruiría después,
   pero el collision check del .reInNew necesita datos frescos del NEW).
2. `.reNewId = MaiGetCurrentScreenId()`, `.reOldId = MaiGetOldScreenId()`,
   `.reFollowSide = MaiGetEntrySide(ScreenTransition)`.

**Loop (pass combinado sobre los 3 slots):**

Para cada slot C = 0, 1, 2:

- **Si TYPE_MONSTER** (estaba visible en OLD): snapshot Pass 1 →
  `LastSeen[slot] = (OLD, POSX, POSY)`. Luego cae a `.reCheckReposition`.

- **Si TYPE_NONE**: check restore →
  ```
  if RoomId[slot] == OLD && LastSeen[slot] == NEW:
      .reRestore → POSX/POSY desde LastSeen → .reInNewActivate
  ```
  Si no matchea, cae a `.reCheckReposition`.

- **`.reCheckReposition`**: comparar `MonsterRoomId[slot]` con OLD/NEW:
  - `== OLD` → `.reFromOld`: gap random en `.reFollowSide` →
    `.rePickGap` → set POSX/POSY → `.rePosDone` → TYPE_NONE, DIR=
    ScreenTransition, DELTAS=0, update RoomId=NEW, cancel timer en
    `.reSkip`.
  - `== NEW` → `.reInNew` (migration arrival; ver Flujo 3 rama B).
  - Otro → `.reSkip`: no toca POSX/POSY, no toca RoomId. Cancel timer.

Al final, `.rmTimer = MONSTER_ENTRY_BASE` para stagger activación.

## Flujo 3 — Knockback con espada

`UpdateMonster` detecta golpe → stun counter (`ENT_DIR`) → `.moKbApply` mueve
según deltas invertidos. Si el move cruza borde → `.moKbOffscreen`:

1. POSX/POSY clamp al borde según eje primario del knockback
   (`|DELTAX| vs |DELTAY|`, tie decide horizontal).
2. `ENT_DIR = DIR_N/S/E/W` (exit direction — sentinel, no stun).
3. `MonsterKbDespawn = 1` → `.peScaredDespawn` hace XOR erase y set TYPE_NONE.
4. Slot index = `(IX - EntityTable) / ENT_SIZE - SLOT_MONSTER0`.
5. Clear `MAI_FLAG_LEAVING` del slot (por si estaba amaneciendo).
6. `MonsterRoomId[slot] = MaiGetNeighborScreenId(exitDIR)` (destino).
7. `MonsterEntryBorder[slot] = MaiDirToEntrySide(exitDIR)` (MAI_SIDE opuesto).
8. `MonsterReturnTimer[slot] = MAI_LINGER_PUSHED` (50f).

A partir de ahí hay 3 ramas:

### Rama A — Player se queda en el room original

`TryRespawnMonsters → .rmUpdateReturnTimers` cada frame:
- Decrementa `MonsterReturnTimer[slot]`.
- Al llegar a 0 (expiración):
  1. Compute `MaiGapTargetCoord` = POSX/8 (N/S) o (POSY-MIN_Y)/8 (W/E) —
     el char-position del cruce.
  2. `MaiPickNearestGapOnSide(ENT_DIR)` → gap más cercano al target
     (PUSH HL/BC wrapping para no corromper el outer loop).
  3. Apply `MAI_REENTRY_OFFSET` inward según side.
  4. Set POSX/POSY.
  5. **Update `MonsterRoomId[slot] = current`** (el monster ha vuelto).
  6. `ENT_DIR = DIR_N` sentinel. Clear timer y `rmTimer`.

`TryRespawnMonsters.rmCheckSlots` activa el slot cuando su RoomId coincide.

### Rama B — Player cruza al room destino antes de expirar

Durante la transición, `RepositionMonstersAtEntry` → `.reInNew` (porque
`RoomId == NEW`):

1. Leer `MonsterEntryBorder[slot]` → A = side.
2. Compute `MaiGapTargetCoord` según side (preserva sub-salida en gaps duales).
3. `MaiPickNearestGapOnSide(side)` → MaiSpawnX/Y (gap del entry border).
4. Save gap pos en `.reInGapX/Y`.
5. Set `SPRITEID = ANIMBASE` temp (para `CheckEnemyCollision` con dims
   correctos; la activación lo sobrescribe).
6. **Collision-aware step-back**:
   ```
   try = MAI_WAIT_OFFSET (40)
   while try > 0:
     POSX/POSY = gap
     aplicar try inward según side
     si CheckEnemyCollision == free: break
     try -= 8
   si todos bloqueados: POSX/POSY = gap (offset 0, siempre válido)
   ```
7. **Activación inmediata** (`.reInNewActivate`): TYPE_MONSTER, STATE_RUNNING,
   NEWSPAWN flag, facing hacia player, ENT_DIR=0, DELTAS=0, set OLDX/OLDY/
   OLDSPRID para el primer draw.
8. Cancel timer. Update RoomId = NEW (redundant).

El monster aparece dibujado en el mismo frame que el nuevo room, 2-5 chars
dentro desde el entry gap, en la misma sub-salida por la que fue empujado.

### Rama C — Player cruza a un tercer room

`RepositionMonstersAtEntry` → slot RoomId (neighbor de KB) != OLD, != NEW
→ `.reSkip`. Cancel timer. Monster queda TYPE_NONE con `RoomId = destino`.

Memoria persistente: si el player visita ese destino más tarde,
`.reInNew` lo encuentra con su EntryBorder memoria.

## Flujo 4 — Monster in-transit, player vuelve rápido (Fase 9)

Player A→B → los slots se reposicionan TYPE_NONE al gap del S de B →
TryRespawn empieza el stagger (50+40+40 frames).

Player B→A antes de que todos activen:

- Slots ya activados en B (TYPE_MONSTER): Pass 1 guarda LastSeen=B.
  Pass 2 → `.reCheckReposition` → RoomId=B=OLD → `.reFromOld` (follow
  normal a A por el gap S).
- Slots aún TYPE_NONE (no activados en B): Pass 2 restore check →
  `RoomId=B=OLD && LastSeen=A=NEW` match → `.reRestore` → POSX/POSY
  desde LastSeenX/Y (sus posiciones exactas en A al momento de leave) →
  activación inmediata.

Net: los que ya te seguían entran por el gap; los que aún estaban en
tránsito están en sus posiciones originales. Sin interrupción visual.

## Flujo 5 — Amanecer (Regla 7, STATE_LEAVING)

`ScareAllMonsters` (fase 5 del day cycle):
- `MonstersActive = 0` (bloquea respawn).
- Clear `MAI_FLAG_LEAVING` de los 3 slots (fresh dawn).
- `ScareTimer = SCARE_TIMER_DAWN` (125f ≈ 5s).

Cada frame, `ProcessOneEnemy` para monsters RUNNING + `ScareTimer > 0`
auto-transiciona a STATE_SCARED.

Primeros 75f (pause): `.peScaredFlee` es bypass; monsters oscilan mirando L/R.

Frames siguientes 50-0 (flee): `.peScaredFlee` → `UpdateMonsterLeave`:

1. Si `MAI_FLAG_LEAVING` clear (primera llamada por monster):
   - `MaiPickRandomGap` → guardar side+coord en
     `MonsterEntryBorder[slot]` + `MonsterExitCoord[slot]`.
   - Set `MAI_FLAG_LEAVING`.

2. AI híbrida hacia pixel del gap:
   - Escape-wall (via `CheckEnemyCollision` del bbox entero + push 2px).
   - Greedy primary.
   - Persistence (prev DELTAX/DELTAY).
   - 4 candidatos axis-aligned (primary, secondary, revs).
   - 4 diagonales.

3. Reach char-align (`POSX & $F8 == MaiSpawnX & $F8` y POSY análogo) →
   `NastyFleeDespawn = 1` → `.peScaredDespawn` hace XOR erase limpio
   (sin puff).

Clamp X suave (POSX hasta 239, no 231 estricto) — imprescindible para
alcanzar el E-side target (POSX = SCREEN_MAX_X = 232).

`.mulApply` también clampa Y suave (POSY < 200) para evitar wrap-around.

Si screen sin gaps emitidos → fallback a `UpdateNastyFlee` (comportamiento
reactivo antiguo).

## Tabla resumen de escenarios

| Acción player | Monster estado | Código que actúa | Pos monster final |
|---|---|---|---|
| Spawn inicial | TYPE_NONE | `SpawnMonsters` | random gap + stagger |
| Cambio de room (normal) | TYPE_MONSTER | `.reFromOld` | gap del entry side + stagger |
| Cambio + volver rápido (slot no activó) | TYPE_NONE | `.reRestore` | **posición exacta original** (LastSeen) |
| Cambio + volver tarde (slot ya activó) | TYPE_MONSTER | `.reFromOld` | gap del entry side + stagger |
| Knockback + stay 2s | TYPE_NONE → TYPE_MONSTER | `.rmUpdateReturnTimers` | gap nearest en exit side + REENTRY_OFFSET |
| Knockback + cruzar al destino | TYPE_NONE → TYPE_MONSTER | `.reInNew` | gap en entry border + WAIT_OFFSET (collision-aware) |
| Knockback + cruzar a otro room | TYPE_NONE | `.reSkip` | sin mover, espera memoria |
| Amanecer | TYPE_MONSTER → STATE_SCARED → TYPE_NONE | `UpdateMonsterLeave` | cruza por gap + despawn XOR |

## Constantes tuneables (`constants.asm`)

```
MAI_LINGER_NORMAL   EQU 45      ; reservado, no usado
MAI_LINGER_PUSHED   EQU 50      ; 2s — Rama A regreso knockback
MAI_ENTRY_OFFSET    EQU 0       ; spawn inicial al borde
MAI_REENTRY_OFFSET  EQU 16      ; 2 chars — Rama A return position
MAI_WAIT_OFFSET     EQU 40      ; 5 chars — Rama B migrated waiting
MAI_FLOW_INTERVAL   EQU 10      ; flow field (desactivado)
SCARE_TIMER_DAWN    EQU 125     ; 5s amanecer total
SCARE_FLEE_THRESHOLD EQU 50     ; ventana de flee (50f tras 75f pause)
```

## Helpers (monster_ai.asm)

| Helper | Entrada | Salida | Uso |
|---|---|---|---|
| `MaiGetCurrentScreenId` | - | A = Y*16+X | RoomId check/update |
| `MaiGetNeighborScreenId(DIR)` | A=DIR | A = neighbor | Knockback migration |
| `MaiGetOldScreenId` | ScreenTransition | A = OLD | Reposition OLD/NEW detect |
| `MaiDirToEntrySide(DIR)` | A=DIR | A = MAI_SIDE opuesto | EntryBorder at knockback |
| `MaiGetEntrySide` | ScreenTransition | A = MAI_SIDE entrada | FollowSide per transition |
| `MaiPickRandomGap` | - | MaiSpawnX/Y | SpawnMonsters |
| `MaiPickRandomGapOnSide(side)` | A=side | MaiSpawnX/Y o A=1 | Regla 2 follow |
| `MaiPickNearestGapOnSide(side)` | A=side, MaiGapTargetCoord | MaiSpawnX/Y o A=1 | Regla 4, `.reInNew` |
| `UpdateMonsterLeave` | IX=monster | Movimiento o despawn | Fase 7 LEAVING |

## Gotchas críticos

1. **Paging + stack**: rutinas que paginan bank 6 deben vivir en bank 2
   fijo y hacer paginación inline sin stack ops (o swapear a stack temp).
2. **`MaiPickNearestGapOnSide` destruye HL/BC**: envolver en PUSH/POP si
   el caller los necesita después (bug latente en `.rmRtLoop`).
3. **CollisionMap stale**: DrawScreen reconstruye, pero corre DESPUÉS de
   Reposition. Llamar `BuildCollisionMap` explícito al inicio de Reposition.
4. **SPRITEID antes del collision check**: `CheckEnemyCollision` usa
   SPRITEID para dims. Antes de activar, set SPRITEID = ANIMBASE temp.
5. **Clamp suave X**: `POSX < 240 → clamp a 0` (wraparound), no
   `POSX >= SCREEN_MAX_X → clamp a MAX-1`. El estricto impedía alcanzar
   el E-side target.
6. **Reach char-align**: `AND $F8` (snap a char boundary) + compare.
   Pixel-exact falla por drift sub-char del greedy AI.
7. **JR fuera de rango**: con código creciendo, cambiar `JR`/`DJNZ` a
   `JP`/`DEC B + JP NZ`.
8. **POP BC destruye C**: si hay valor útil en C antes de POP, salvarlo
   en stack o scratch.
9. **LastSeen timing**: Pass 1 (save) y Pass 2 (check restore) son
   mutuamente exclusivos por slot (TYPE_MONSTER vs TYPE_NONE), por eso
   caben en un single pass sin interferir.
10. **`ScreenTransition` vs `LastScreenTransition`**: el primero se
    resetea cada frame; el segundo persiste. Reposition usa el primero
    (aún válido durante .doTransition).

---

## Fases completadas

### Fase 1 — ScreenGaps precalculados (commit `0376343`)
- Script `tools/build_screen_gaps.py` lee `code/screen_data.asm` (MapTable
  exportada), `code/screen_rooms.asm` (placements) y `code/bg_gfx.asm` +
  `code/bg_gfx_b.asm` (dimensiones de sprite, incluye autoFills IDs 200+
  siguiendo aliases EQU).
- Emite `code/screen_gaps.asm` a bank 6: `ScreenGapsTable` (256 DEFW ptrs por
  screen_id = Y*16+X) + por-room `DEFB count, {side, coord}×count`.
- Filtro valida huella 2×3 del monster + pertenencia a la región conexa
  principal con `MIN_POCKET_SIZE=20`. Sin esto, spawn podía caer sobre BG
  sprites o en bolsillos inalcanzables.
- Coord emitida = char top-left del monster (alineado a char), no el borde
  crudo.

### Fase 2 — Estructuras runtime (commit `d567893`)
- RAM baja +15 B: `MonsterRoomId[3]`, `MonsterLingerTimer[3]`,
  `MonsterEntryBorder[3]`, `MonsterAiFlags[3]`, `RoomHistory[3]`.
  (Varias de estas aún no se usan — reservadas para fases pendientes.)
- Bank 6 +~900 B: `FlowField` (704 B), `BfsQueue` (128 → 1408 B más tarde).

### Fase 3 — Flow field BFS (commit `6b99559`, desactivado en `a8fdf65`)
- `MaiComputeFlowField` con stack temporal de 128 B en bank 2 para los CALLs
  internos del BFS (no se puede usar el stack real porque vive en slot 3
  paginado).
- Desactivado: coste real ~1 M T-states = 7 frames de stutter. La
  infraestructura queda pero NO se llama desde el main loop.
- Reactivación futura: refactor a BFS amortizado (K iteraciones/frame,
  estado persistente entre frames, reinicio en cambio de celda del player).

### Fase 4 — Regla 1 (commit `fa8e276`)
- `MaiPickRandomGap` + hook en `SpawnMonsters`: cada monster en su primera
  aparición de la noche pilla hueco aleatorio del screen actual (no
  `LastEntryPos`).
- Crash fix inicial (`9c42d51`): `monster_ai.asm` tenía que vivir en bank 2
  fijo (`INCLUDE` después de `paging.asm`) porque al paginar bank 6 el
  propio código se iba a tomar por saco si estaba en bank 0. Además toda
  paginación es **inline** — nada de `CALL PageBankSlot3` durante la ventana
  paginada (el stack vive en slot 3).
- Fix (`584a6af`): `TryRespawnMonsters` sobrescribía POSX/POSY al activar.
  Ahora respeta lo que puso `SpawnMonsters`/`RepositionMonstersAtEntry`.

### Fase 5 — Regla 2 amplia (commit `6f9978e`, fix `41aa748`)
- Al cambiar de room, cada monster entra por un hueco **aleatorio del
  mismo borde** que cruzó el player — no apilados en `LastEntryPos`.
- `MaiPickRandomGapOnSide(side)` + `MaiGetEntrySide`.
- Fix importante (`41aa748`): `POP BC` destruía el idx objetivo cargado
  en `C`. Antes: los 3 monsters cogían siempre el mismo gap.

### AI híbrido reactivo (commits `f30f5b1`, `74e8cc7`, `ed0124c`, `3ee6614`)
Capas en `UpdateMonster.moDoMove`:
1. **Greedy primary**: intenta dirección primaria hacia player. Si pasa → go.
2. **Persistence**: si greedy bloqueada, continúa dirección anterior
   (commitment al rodeo).
3. **Random en alineamiento**: cuando player está en línea recta (hDx=0 o
   vDy=0), randomiza el eje 0 para romper trampa de oscilación.
4. **Recalc completo**: 4 candidatos (primary, secondary, rev, backtrack).

Sin la capa 3, el monster oscilaba 2 celdas frente a un muro alineado.
Sin la 2, no rodeaba obstáculos en L/U. Sin la 1, no snapeaba de vuelta a
greedy tras rodear.

Animación: sprite mira hacia la dirección de `DELTAX`, no al player. Excepto
durante stun/knockback (`ENT_DIR != 0`) donde sí mira al player.

### Fase 7 — Regla 7 / STATE_LEAVING
- Al amanecer (`ScareTimer > 0`), los monsters entran en STATE_SCARED (igual
  que antes) pero en la fase de flee ya no usan `UpdateNastyFlee` — despacha a
  `UpdateMonsterLeave` (nuevo, en `monster_ai.asm`).
- Primera llamada por monster: `MaiPickRandomGap` → guarda side+coord en
  `MonsterEntryBorder[slot]` + `MonsterExitCoord[slot]` y marca
  `MAI_FLAG_LEAVING` en `MonsterAiFlags[slot]`.
- Llamadas siguientes: AI híbrida (escape-wall + greedy primary + persistence +
  4 candidatos + 4 diagonales) hacia el pixel del gap. Reach **char-align**
  (`POSX & $F8 == MaiSpawnX & $F8` y análogo Y) → `NastyFleeDespawn=1` →
  reutiliza `.peScaredDespawn` existente para erase XOR limpio (sin puff).
- `ScareAllMonsters` limpia `MAI_FLAG_LEAVING` de los 3 slots para que cada
  amanecer pille un gap fresco.
- Fallback: si el screen no tiene gaps emitidos, tail-call a `UpdateNastyFlee`
  (comportamiento anterior).
- `MulTryPassable` solo chequea `CheckEnemyCollision` (sin overlap monster/player)
  — durante la fuga es aceptable que se solapen.

Gotchas resueltos durante iteración:
- **Reach pixel-exacto fallaba**: drift del greedy dejaba POSX sub-char del
  target. Fix: comparación char-align (`& $F8`) con tolerancia de 8 px por eje.
- **Stuck side-to-side del gap**: monster desalineado cubre 3 chars de ancho,
  rozando walls adyacentes al gap aunque el top-left esté libre.
  `IsPointBlocked` no lo detectaba (solo top-left). Fix: usar
  `CheckEnemyCollision` (todo el bbox) como escape-wall trigger, empujar 2 px
  hacia (MaiSpawnX, MaiSpawnY).
- **E-side inalcanzable**: target `POSX = SCREEN_MAX_X = 232` pero
  `.mulApply` clampaba estricto a 231 → `231 & $F8 = 224 != 232 & $F8 = 232`
  → reach nunca disparaba. Fix: clamp suave (POSX >= 240 → 0, permite 232-239).

### Fase 8 — Memoria de ubicación (MonsterRoomId)
Extensión de Regla 4: el monster empujado sigue siendo candidato a **volver**
al room actual si el player se queda (comportamiento original), PERO si el
player cruza al room destino, el monster le **espera allí** dibujado en el
mismo frame en que se renderiza el room.

- `SpawnMonsters`: `MonsterRoomId[slot] = CurrentScreenId` al spawn.
- `.moKbOffscreen` (commit actual):
  - `MonsterRoomId[slot] = neighbor_id` (destino via `MaiGetNeighborScreenId`).
  - `MonsterEntryBorder[slot] = MAI_SIDE` opuesto (via `MaiDirToEntrySide`).
  - `MonsterReturnTimer[slot] = MAI_LINGER_PUSHED` (50f, para regreso si stay).
  - Clear `MAI_FLAG_LEAVING`.
- `.rmUpdateReturnTimers` expiración (player staying):
  - Reposiciona en gap del exit side del room actual (Regla 4 clásica).
  - **Actualiza `MonsterRoomId[slot] = current`** (para que TryRespawnMonsters
    lo active en este room).
- `RepositionMonstersAtEntry`:
  - `.reFromOld` (RoomId == OLD, seguidor): gap en entry side. TYPE_NONE
    (stagger vía TryRespawn). Timer cancel.
  - `.reInNew` (RoomId == NEW, migrado): gap en entry side + **MAI_WAIT_OFFSET
    (40 px) hacia dentro** + **activación INMEDIATA** (TYPE_MONSTER,
    STATE_RUNNING, NEWSPAWN) — aparece en el mismo frame que el draw del
    room. Timer cancel.
  - `.reSkip` (otro room): monster queda TYPE_NONE en destino. **Timer cancel**
    — sin cancelar, la expiración movería el monster al room actual rompiendo
    la memoria.
- `TryRespawnMonsters.rmLoop`: solo activa slots TYPE_NONE con
  `MonsterRoomId[slot] == current`. Seguidores staggered normal.

Helpers nuevos (`monster_ai.asm`):
- `MaiGetCurrentScreenId` → A = Y*16+X.
- `MaiGetNeighborScreenId(DIR)` → A = neighbor screen.
- `MaiGetOldScreenId` → leyendo ScreenTransition.
- `MaiDirToEntrySide(DIR)` → A = MAI_SIDE opuesto.

Constante nueva: `MAI_WAIT_OFFSET EQU 40` (`constants.asm`).

Bug latente arreglado de paso: `.rmUpdateReturnTimers` llamaba
`MaiPickNearestGapOnSide` (destruye HL/BC) sin proteger los registros
usados por el outer loop. Con una única expiración simultánea era tolerable;
con writes adicionales de MonsterRoomId usando HL pos-call, corrompía
memoria y crasheaba. Fix: `PUSH HL/BC ... POP BC/HL` envolviendo el CALL.

Escenarios cubiertos:
1. Push + stay → monster vuelve por el mismo borde tras 2s (Regla 4 original).
2. Push + cruzar al destino antes de 2s → monster espera dibujado 40px dentro
   desde el entry gap, al instante del draw del nuevo room.
3. Push + cruzar a un room distinto → monster queda TYPE_NONE en destino
   hasta que el player lo visite (memoria persistente).

Refinamientos .reInNew:
- **Collision-aware offset**: prueba MAI_WAIT_OFFSET (40 px), si bloquea baja
  en pasos de 8 hasta encontrar celda libre (via CheckEnemyCollision con
  SPRITEID temp = ANIMBASE). Si todos bloquean, fallback al gap (0 offset,
  siempre valido por spec del emitter).
- **Pre-build CollisionMap**: `RepositionMonstersAtEntry` llama
  `BuildCollisionMap` al inicio. Sin esto, el collision check usaba el map
  del room anterior (stale) y el migrado caia sobre BG sprites del nuevo.
  DrawScreen reconstruye de nuevo despues — coste minimo en transition frame.
- **Gap nearest-coord**: usa `MaiPickNearestGapOnSide` con target coord =
  POSX/8 (N/S) o (POSY-MIN_Y)/8 (W/E). Preserva la sub-salida en gaps
  duales — el migrado aparece en la misma "rama" (superior/inferior) por
  donde fue empujado, no random.

### Fase 11 — Pulido flee AI (fantasmas atascados)
Usuarios reportaron que algunos monsters ("fantasmas") se quedaban rebotando
al huir: al chocar contra una pared cerca del gap, retrocedían, reintentaban,
y volvían a chocar indefinidamente.

Cambios en `UpdateMonsterLeave`:
- **Diagonal primario insertado** entre greedy y recalc candidates: tras
  greedy axis-aligned, prueba `(MulHDx, MulVDy)` (ambos ejes hacia target).
  Evita oscilación cuando hay que ajustar Y mientras se avanza en X (ej.
  aproximación a salida dual W).
- **Persistencia eliminada**: en chase normal (UpdateMonster) persistence
  commite a un rodeo, pero en flee con target fijo re-aplicaba backtracks
  previos → oscilación. Los 4 candidatos + 4 diagonales cubren sin ella.

Flujo actualizado: greedy → diagonal primario → 4 candidatos → 4 diagonales.

### Fase 10 — Shake pre-fuga al amanecer
Los monsters se agitan ±1 px random durante la fase pausa del amanecer
(ScareTimer 125→51, ~3s), antes de huir. Visualmente muestra el "nervio"
del monster ante el dia.

- Nuevo flag `MAI_FLAG_SHAKE_SAVED` (bit 3 de `MonsterAiFlags`).
- Nuevo `MonsterShakeOrigX[3]`, `MonsterShakeOrigY[3]` (6 bytes RAM).
- Nuevo helper `MaiGetMonsterSlot(IX) → A` en monster_ai.asm.
- `ScareAllMonsters` limpia `MAI_FLAG_SHAKE_SAVED` (fresh cada amanecer).
- `.peScared` pause branch: primer frame por monster guarda POSX/POSY como
  orig + set flag; frames siguientes eligen dirección cardinal random (N/S/
  W/E via `R & 3`), offset ±1 px desde orig, `CheckEnemyCollision`. Si
  bloquea → revert a orig (no shake este frame).
- Monster-only; nasties durante bells no se agitan.

### Fase 9 — Restaurar posicion in-transit (LastSeen)
Si el player cambia de room y vuelve ANTES de que un slot active en el
nuevo (~130f de stagger por TryRespawnMonsters), ese slot reaparece en su
posicion exacta del room anterior (no en el entry gap). "Mientras el
monster no me haya seguido, recuerdo donde estaba."

Per-slot: `MonsterLastSeenRoom[3]` ($FF inicial), `MonsterLastSeenX[3]`,
`MonsterLastSeenY[3]`. 9 bytes de RAM.

En `RepositionMonstersAtEntry.reLoop`, single pass:
- Si TYPE_MONSTER: Pass 1 snapshot → LastSeen[slot] = (OLD, POSX, POSY).
- Si TYPE_NONE: Pass 2 check → si `RoomId == OLD && LastSeen == NEW`,
  JP `.reRestore` → POSX/POSY desde LastSeen → fall-through a
  `.reInNewActivate` (mismo codigo que migration, sin step-back).
- Resto: logica existente (OLD → follow, NEW → .reInNew migration,
  otros → .reSkip).

Como TYPE_MONSTER y TYPE_NONE son mutuamente exclusivos por slot,
una sola iteracion cubre ambos passes. El LastSeen se sobreescribe
naturalmente en la siguiente transicion (monster activado en NEW pasa a
TYPE_MONSTER → Pass 1 guarda LastSeen=NEW antes del proximo leave).

### Fase 6 — Regla 4 (commits `6ce8f5f`, `7dae950`, `f9479c1`, `4ff84dd`, `5c83451`, `c3a0aa1`)
- Al salir por knockback, `.moKbOffscreen` registra el borde en `ENT_DIR`
  (DIR_N/S/E/W) — sobrecargado con el stun counter pero no hay conflicto
  porque TYPE_NONE durante el timer.
- Timer por monster `MAI_LINGER_PUSHED=50f` (~2s).
- `.rmUpdateReturnTimers` al expirar: llama `MaiPickNearestGapOnSide` con
  target coord = char-position del crossing point, elige el gap cuya
  coord sea la más próxima. Así al empujar por el gap superior de un
  pasaje dual, vuelve por el superior.
- Elección de eje de salida por **magnitud del knockback**, no por borde
  cruzado primero: si `|DELTAX| >= |DELTAY|`, fuerza salida por X (más
  coherente con la intención del player).
- Knockback diagonal preservado (esencial para dinámica del billar).
- Multi-monster fix (`5c83451`): `.rmCheckSlots` ahora respeta
  `MonsterReturnTimer` individual por slot. Antes: si M1 expiraba y M2
  seguía con timer, M2 se activaba en su posición clampada offscreen en
  vez de Regla 4.

## Layout memoria

- **RAM baja** (+27 B en bank 2 fijo): estado monster completo — RoomId (3),
  LingerTimer (3, reservado), EntryBorder (3), ExitCoord (3), AiFlags (3),
  LastSeenRoom (3), LastSeenX (3), LastSeenY (3), RoomHistory (3, reservado).
  Más `MonsterReturnTimer[3]` en logic_game.asm.
- **Bank 2 fijo** ($8000-$BFFF): todo `monster_ai.asm` (rutinas que paginan
  bank 6 deben vivir aquí para no evaporarse al cambiar slot 3).
- **Bank 6** ($C000-$FFFF paginable): `ScreenGaps` (~2.5 KB), `FlowField`
  (704 B reservados, sin uso), `BfsQueue` (1408 B reservados, sin uso).

## Trade-offs conocidos

- **Flow field desactivado**. Monsters usan AI reactiva híbrida. Rodean
  obstáculos simples bien, pero no hacen pathfinding real en laberintos
  complejos. Reactivar exige BFS amortizado (no trivial — el actual cuesta
  ~7 frames de stutter por invocación).
- **Residuo de color post-knockback**. Al morir el monster por knockback
  offscreen, los atributos de sus ~2×3 celdas quedan con su `ENT_ATTR`
  hasta que algo los repinta. El intento de `RestoreOldAttr` en
  `.peScaredDespawn` corrompía la pantalla masivamente (probablemente por
  invadir attrs del player/HUD con la huella 3×3 genérica); revertido en
  `c3a0aa1`. Fix limpio futuro: `RestoreOldAttr` con huella 2×3 exacta.
- **Exit side cuando empuje diagonal cerca de esquina**: si el player empuja
  con `|DX| ≈ |DY|` y el monster está muy cerca de la esquina, puede salir
  por el eje "equivocado" según la intuición del player. Mitigado (tie
  decide X), pero no perfecto.
- **Primer fresh-draw en reentry**: XOR sin erase previo. Matemáticamente
  balanceado por el `.peScaredDespawn` inicial, pero si el player se ha
  movido entre medias, overlap puede flickerear 1-2 frames hasta que el
  monster se mueve.

## Bugs/features pendientes

De la lista original de 7 reglas, quedan:
- **RoomHistory[3] (anti-lost)**: si un monster migrado lleva mucho tiempo
  "huérfano" (varias transiciones sin que el player lo visite), podría
  auto-teletransportarse a la room actual. Opcional — con MonsterRoomId ya
  hay memoria de ubicación; RoomHistory solo sería un safety net para
  evitar que un monster se pierda indefinidamente en un room lejano.
- **Debug key `K`**: kill all monsters en room actual (útil para tuning).

Ajustes opcionales:
- BFS amortizado para reactivar flow field.
- `RestoreOldAttr` con huella exacta 2×3 para eliminar residuo de color sin
  corromper nada.
- Detección de knockback saliente cuando el monster ya estaba en el borde
  (edge case: lo golpeas pegado a la pared, no hay recorrido de knockback).

## Gotchas aprendidas (para no repetir errores)

1. **Paging + stack**: cualquier rutina que pagine `bank 6` a slot 3 debe
   vivir en bank 2 fijo ($8000-$BFFF) y no hacer NINGÚN stack op durante
   la ventana paginada (PUSH/POP/CALL/RET). Si necesita CALLs internos,
   swap de SP a un stack temporal en bank 2.
2. **JR fuera de rango**: cuando un bloque crece, `JR`/`DJNZ` de más de
   127 bytes fallan. Cambiar a `JP`/`DEC B + JP NZ`.
3. **Sprite height ceil vs floor**: `(h_px + 7) // 8` (Python) vs `h_px >> 3`
   (Z80 runtime). Coinciden solo si `h_px` es múltiplo de 8. Todos los
   sprites actuales lo son, pero worth tener en mente.
4. **`CALL` preserva IX implícitamente** si la rutina llamada no lo toca.
   `DrawSprite` SÍ lo toca (usa como source pointer). `PUSH IX`/`POP IX`
   obligatorio si el caller lo necesita después.
5. **`POP BC` destruye C**: si guardas un valor en C antes de un `POP BC`,
   se pierde. Hacer los POPs antes de asignar o reordenar.
6. **Level editor autoFills**: `level_data.json` NO contiene los auto-fill
   sprites de bordes. El script debe parsear la ASM exportada para ver la
   verdad que ve el juego.
7. **`ScreenTransition` vs `LastScreenTransition`**: el primero se
   resetea cada frame en `CheckScreenTransition`; el segundo persiste.
   Para `MaiGetEntrySide` durante `RepositionMonstersAtEntry` basta con
   `ScreenTransition` porque ahí aún está set.

## Archivos clave

- `code/monster_ai.asm` — rutinas AI/pick-gap/flow-field (bank 2 fijo).
- `code/monster_ai_bank6.asm` — buffers `FlowField` + `BfsQueue` en bank 6.
- `code/screen_gaps.asm` — generado. Regenerar con `python tools/build_screen_gaps.py`.
- `code/screen_gaps.report.txt` — reporte por room de qué openings se emiten.
- `tools/build_screen_gaps.py` — filtro ScreenGaps.
- `code/logic_game.asm` — cambios en `SpawnMonsters`, `UpdateMonster`,
  `TryRespawnMonsters`, `.rmUpdateReturnTimers`, `RepositionMonstersAtEntry`,
  `.moKbOffscreen`, `.peScaredDespawn`, `.moAnimate`.
- `code/constants.asm` — constantes `MAI_*`.
- `code/variables.asm` — vars de estado monster.

## Próximos pasos sugeridos

1. Merge a `main` o seguir iterando en la rama.
2. Features restantes: RoomHistory anti-lost (safety net), Debug key K.
3. Polish: residuo de color post-knockback, fresh-draw flicker, BFS amortizado.
4. Si todo OK en playtest, merge a `main`.

## Commits de la rama (monster-ai-v2)

| Commit | Fase | Descripción |
|---|---|---|
| `0376343` | 1 | ScreenGaps precalculados |
| `d567893` | 2 | Estructuras runtime |
| `6b99559` | 3 | Flow field BFS (después desactivado en `a8fdf65`) |
| `fa8e276` | 4 | Regla 1 — spawn en gap random |
| `6f9978e` | 5 | Regla 2 — follow por entry border |
| `6ce8f5f`..`c3a0aa1` | 6 | Regla 4 — return post-knockback |
| `f8048a9` | 7 | Regla 7 — STATE_LEAVING al amanecer |
| `f4b33fd` | 8 | Memoria de ubicación (MonsterRoomId) |
| `f025950` | 8b | Refinar posición migrado (collision + nearest gap) |
| `2c55adb` | 9 | LastSeen restore (in-transit) |
| `b6b04b1` | docs | Seccion consolidada ubicacion/comportamiento |
| (pending) | 10+11 | Shake pre-fuga + pulido flee AI |
