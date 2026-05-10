# Bank Cutscene — Handoff doc para próxima sesión

**Fecha**: 2026-05-09. Sesión anterior se quedó sin contexto.

**Branch**: `feat/bank-cutscene` (37 commits desde main).

**Estado del build**: limpio (0 errors). `tools/check_slot_overlap.py` OK.
Bank 0 free: `0x0119` (281 B). Slot 1 sin overflow.

**Estado runtime**: pendiente smoke test final por el usuario. Todas las
fases del cutscene implementadas y verificadas individualmente. Falta
correr la secuencia entera M7→M11 y confirmar que no hay regresiones.

---

## ¿Qué es el bank cutscene?

Cinemática intermedia entre la trampa de la iglesia (M7) y el town_gate
final (ahora M11). El jugador, con un **cheque** que dejó la iglesia tras
trampear los 3 monstruos, va al **banco** (sala 8, 8 = norte del
ayuntamiento) y al chocar con la puerta del banco arranca la cinemática:

1. Player se posiciona pegado a la puerta (centrado + 1 px debajo).
2. **3 toques** soft → retreat a posición original → espera silenciosa.
3. **3 toques** soft → retreat → espera.
4. Player **gira a cámara** (frustración) → vuelve a girarse.
5. **6 toques loud** (tone+noise mix, más sonoros).
6. Pausa → **puerta se abre** (XOR-cancel + invert attrs).
7. **Mano abierta** (palma) asoma — pide el cheque.
8. Tras un instante el **cheque desaparece del HUD** (CurrentKey=0).
9. Mano abierta se retira → pausa breve con rendija vacía.
10. **Mano "no no" 4 veces** (animación 2 frames con swap).
11. Mano se retira → **puerta se cierra** + restore attrs.
12. Pausa con puerta cerrada → **llave de la ciudad aparece** en (8, 8) char (25, 5).
13. Pausa → player gira a cámara → control devuelto.

> Nota: el cheque ya **no** se consume al disparar el trigger (StartBankCutscene
> ya no hace `LD (CurrentKey), 0`). Se consume cuando la mano abierta lo "coge"
> en la transición HAND_OPEN_IN → HAND_OPEN_TAKE. El re-trigger queda bloqueado
> por `BankCutscenePhase != 0` en CheckBankTriggerBg igual que antes.

El player coge la llave, va al sur, abre la puerta de la ciudad → cinemática final town_gate.

---

## Cadena de hitos extendida (9 → 11)

`code/milestones.asm` MilestoneTable + ResolveTable:

| # | Tipo | Ref | Descripción |
|---|---|---|---|
| 1 | PICKUP | 1 | forest key |
| 2 | PICKUP | 2 | ruins key |
| 3 | PICKUP | 3 | cemetery key |
| 4 | PICKUP | 4 | clock tower key |
| 5 | TRIGGER | 1 | town hall door |
| 6 | PICKUP | 5 | church key |
| 7 | SPECIAL | 0 | encerrar monsters (church trap) |
| **8** | **PICKUP** | **7** | **bank check (cheque)** ← NUEVO |
| **9** | **TRIGGER** | **4** | **bank cutscene** ← NUEVO |
| 10 | PICKUP | 6 | town gate key (era #8) |
| 11 | TRIGGER | 3 | south door / town_gate cutscene (era #9) |

Cambio mecánico: 4× `CP 9 → CP 11` en `CheckMilestonePickup`,
`CheckMilestoneTrigger`, `CheckMilestoneDebugKey`, `ResolveObjectiveScreen`.

---

## KeyLockTable extendida (12 → 13 slots)

`code/screen_system.asm` KeyLockTable: insertado `BgGfx_BankCheck` en slot 7.
Locks shifted: ForestLock 7→8, RuinsLock 8→9, CemeteryLock 9→10. Boundary
checks actualizados:

- `screen_system.asm:1574, 1763, 1887`: `CP 7 → CP 8` (3 sites).
- `screen_system.asm:1576, 1765`: `SUB 6 → SUB 7` (2 sites, formula slot→key id).
- `screen_system.asm:2568`: `LD B, 12 → LD B, 13` (GetPickupKeyBehavior loop count).
- `variables.asm:37`: comment update `1-7 keys, 8-13 locks`.

K debug cycle: `milestones.asm:191` `CP 7 → CP 8` para incluir BankCheck (id 7) en
el ciclo de debug.

DormantPickupTable: añadida entrada `BgGfx_BankCheck, BankCheckSpawned` antes
de `BgGfx_arm`.

---

## Sprites del banco

| ID | Nombre | Estado | Uso |
|----|--------|--------|-----|
| 39 | Bank | placement en sala (8, 8) char (12, 0). Fachada con hueco donde antes estaba la puerta cerrada. | render del room |
| 44 | BankCheck | placement church (15, 6) char (26, 9), cat=pickup. dormant. | drop tras church trap |
| 54 | bank_door_closed | placement bank (8, 8) char (15, 4), bgPlacements (solid). | XOR-cancel/restore en cinemática |
| 186 | town_gate_key | placement bank (8, 8) char (25, 5). dormant. | drop tras bank cinemática |
| — | BgGfx_BankHandFrame0/1 | inline en bank_cutscene.asm | mano "no no", drawn via DrawBgSprite16XorAtPixel |
| 41 | BankKey | en editor pero NO en CODE_REF_IDS | reservado, no usado (decisión: reusar town_gate_key como llave de la ciudad) |
| 43, 50 | nono hand left/right | en editor pero NO referenciado | reservado, hand sprites finalmente inline |

Hand sprites de `References/nono01.aseprite` (importados via Aseprite CLI →
PNG → DEFB CPL'd). Re-importados 3 veces durante esta sesión (user fue
ajustando el dibujo).

---

## Posiciones del player durante la cinemática

| Fase | POSX | POSY | Helper |
|---|---|---|---|
| StartBankCutscene | guarda OrigX/Y, no teleport, set facing N | | `BankCutsceneFacingNRedraw` |
| WAIT_NASTIES | bump pos (= OrigX/Y) | mantiene | — |
| LOCK + KNOCKS_1 | **120** (centrado) | **64** (1 px debajo door) | `BankCutsceneSnapToDoor` |
| WAIT_1 | OrigX | OrigY | `BankCutsceneSnapToRetreat` |
| KNOCKS_2 | 120 | 64 | `SnapToDoor` |
| WAIT_2, TURN_TO_CAM, TURN_TO_DOOR | OrigX | OrigY | `SnapToRetreat` (en KNOCKS_2 done) |
| KNOCKS_3 | 120 | 64 | `SnapToDoor` |
| HAND_*, DOOR_CLOSED, KEY_DROP, PLAYER_TURN_CAM | 120 | 64 | mantiene desde KNOCKS_3 |

**Constantes** (`bank_cutscene.asm`):
- `BCS_PLAYER_ANCHOR_X = 120` (door center 128 = 120 + 8 player half-width).
- `BCS_PLAYER_ANCHOR_Y = 64` (door bottom 63 + 1).
- `BankCutsceneOrigX/Y` (variables.asm): guardado al StartBankCutscene.

---

## Phase machine (22 fases)

`bank_cutscene.asm`. Phase EQU values:

```
BCP_IDLE             0
BCP_LOCK             1
BCP_KNOCKS_1         2
BCP_WAIT_1           3
BCP_KNOCKS_2         4
BCP_WAIT_2           5
BCP_TURN_TO_CAM      6
BCP_TURN_TO_DOOR     7
BCP_KNOCKS_3         8
BCP_WAIT_3           9
BCP_PRE_HAND        10  (era BCP_DOOR_OPEN, renombrado; ahora dibuja la mano ABIERTA, no la "no no")
BCP_HAND_IN         11  (skipped; dispatcher inalcanzable)
BCP_HAND_NO_NO      12
BCP_HAND_OUT        13
BCP_KEY_DROP        14
BCP_PLAYER_TURN_CAM 15
BCP_DONE            16
BCP_WAIT_NASTIES    17  (sentinel high, dispatch CP en MainLoop + UpdateBankCutscene)
BCP_DOOR_CLOSED     18  (sentinel high, post-HAND beat antes del key drop)
BCP_HAND_OPEN_IN    19  (sentinel high, mano abierta visible -> consume cheque al expirar)
BCP_HAND_OPEN_TAKE  20  (sentinel high, cheque consumido -> erase mano abierta)
BCP_HAND_OPEN_OUT   21  (sentinel high, rendija vacia -> arranca "no no")
```

`UpdateBankCutscene` dispatcher: 2 sentinels al top con `CP`,
luego DEC A chain para fases 1..15.

`MainLoop` ramifica especial para `BankCutscenePhase == 17`
(`WAIT_NASTIES`) que ejecuta `ProcessEnemies + ProcessDeath` para que
los puffs animen.

---

## Timings (frames a 25 fps)

```
BCS_T_LOCK              30   1.2s lock inicial
BCS_T_KNOCK_HIT          4   por hit (era 6, reducido por user feedback)
BCS_T_KNOCK_GAP          5   gap entre toques (era 8)
BCS_T_GROUP_WAIT        50   2s espera silenciosa entre grupos
BCS_T_TURN_CAM          40   1.6s mid-cutscene mirando camara
BCS_T_TURN_BACK         10   transicion rapida volver
BCS_T_PRE_HAND          30   pausa tras 6 toques
BCS_T_PRE_HAND_HOLD     20   hold corto antes de la mano
BCS_T_HAND_IN           20   pausa tras aparecer mano
BCS_T_NO_FRAME          12   cada swap "no no"
BCS_T_HAND_HOLD         15   pausa tras último swap
BCS_T_DOOR_CLOSED_HOLD  30   pausa con puerta cerrada (NUEVO beat)
BCS_T_KEY_HOLD          30   pausa tras drop antes de turn-cam
BCS_T_PLAYER_TURN_FINAL 30   1.2s mirando camara antes de devolver control
BCS_T_PUFF_WAIT        100   safety timeout WAIT_NASTIES
```

3 toques rápidos: `4 + 5 = 9 frames/knock × 3 = 27 frames = 1.08s`. Total cutscene
~10-12 segundos (estimado).

---

## SFX

| Evento | SFX | Implementación |
|---|---|---|
| Knocks grupos 1, 2 (3 cada uno) | soft noise B | `AY_PlayKnockSoft` (sfx_player_hit_ay.asm). R7=$2A, R6=$05, env $0200 |
| Knocks grupo 3 (6) | loud tone+noise B | `AY_PlayKnockLoud`. R2=$00, R3=$02 (~217 Hz tone), R7=$28, R6=$05, env $0400 |
| Puerta abre (PRE_HAND entry) | `SFX_ChurchDoorOpen` | reuso de la iglesia |
| Puerta cierra (HAND_OUT) | `SFX_ChurchDoorOpen` | mismo SFX para abrir/cerrar (igual que iglesia) |
| Llave dropea (DOOR_CLOSED → KEY_DROP) | `SFX_KeyDrop` | clink existente |

`BankCutsceneKnockType` (variables.asm) dispatch entre soft/loud según
fase de entrada del grupo. `_uphMuteR9` extendido para restaurar R7=$38
al cutoff (era solo mute R9; ahora también restore mixer para que los
knocks no dejen tone B disabled).

Ticker IRQ existente (`AY_UpdatePlayerHit`) maneja el cutoff de los knocks
via `BeepDurationFrames` (compartido con beep/hit).

---

## Wiring desde el editor

**Sprites en bg_sprites.json** (editor canonical state):
- 39: Bank (modificado: hueco donde estaba la puerta cerrada).
- 44: BankCheck (24×16, pickup).
- 54: Bank door closed (16×16, sólido).
- 41: BankKey (no usado pero presente).
- 43: nono hand right (no usado, hand inline).
- 50: nono hand left (no usado, hand inline).

**CODE_REF_IDS** en `tools/level_editor.html:8281`: añadidos 44 y 54.

**HUD_LABEL_MAP** en `tools/level_editor.html:8819`: cambiado
`44: 'BgGfx_hud_clock'` → `44: 'BgGfx_BankCheck'` (id 44 fue reusado).

⚠️ **Caveat editor**: tras añadir/cambiar IDs en CODE_REF_IDS, hacer
**hard-refresh del editor (Ctrl+Shift+R)** antes del próximo Export ASM,
o la sesión cargada en el browser usa la lista vieja en memoria.

---

## Bugs encontrados y soluciones (lecciones)

### 1. `DrawBgGfxSprite` ≠ XOR

Línea 808 de `screen_system.asm`: `LD (HL), A` (write destructivo, no XOR).
Para XOR usar `DrawBgSpriteXOR` (línea 2948). Llamar `DrawBgGfxSprite`
dos veces NO cancela el sprite — solo re-pinta.

Síntoma: cinematica "abria" la puerta sin abrirla realmente, mano XOR'd
contra los pixels de la puerta cerrada → corrupto.

Fix: `BankCutsceneOpenDoorWithHandAttrs` usa `DrawBgSpriteXOR` para cancel.
`BankCutsceneCloseDoorRestoreAttrs` usa `DrawBgGfxSprite` para set + paint
attrs originales (apunto a 0s tras erase hand, así set = visible).

### 2. `DrawBgSprite16XorAtPixel` lee de `BgSpriteBuffer`, NO de HL

Línea 519 de `church_cutscene.asm`. El parámetro HL del comentario es
engañoso — la función carga IX = BgSpriteBuffer y lee desde ahí.

Fix: antes del JP, hacer `LDIR` 34 bytes (header 2 + pixel 32) desde
el sprite ptr a `BgSpriteBuffer`. Mismo patrón que `DrawSmokeFrameXor`
en `church_cutscene.asm:259`.

Síntoma específico: como `BankCutsceneRedrawClosedDoor` dejaba el sprite
de la puerta en BgSpriteBuffer, la llamada a `BankCutsceneDrawHand`
inmediata después dibujaba la PUERTA (no la mano) en coords de la mano.

### 3. `CurrentTintVar` con tintPaper match → todo negro

`ApplyTintSwap` (screen_system.asm:983): si `CurrentTintVar != $FF` y
`attr.paper == sprite.tintPaper`, swap paper to CurrentTintVar.

Cuando `BankCutsceneCloseDoorRestoreAttrs` seteaba CurrentTintVar=0 +
sprite tintPaper=7 + attr $78 (paper bits=7) → match → swap → paper=0
→ todo negro al cerrar la puerta.

Fix: `LD A, $FF; LD (CurrentTintVar), A` antes del `JP DrawBgGfxSprite`.
ApplyTintSwap hace early-return en CP $FF y preserva attrs originales.

### 4. sjasmplus local label scope (`.foo`)

Las local labels (`.foo`) se scopan al ÚLTIMO global label antes, no al
contenedor lógico. Si tengo `Func1: ... .data: ...` y entre `Func1` y
`.data` hay un `_helper:` (treated as global por underscore), el `.data`
se scopa a `_helper`, no a `Func1`.

Síntoma: `error: Label not found: AY_PlayKnockSoft.knockSoftRegs`.

Fix: usar nombres globales (`_knockSoftRegs`, `_knockLoudRegs`) en vez de
locales con dots.

### 5. HUD_LABEL_MAP hardcoded conflicto con id reuse

`tools/level_editor.html` tenía hardcoded `44: 'BgGfx_hud_clock'` en
HUD_LABEL_MAP. Esto OVERRIDE el sanitizer del editor. Cuando el user
reusó id 44 para BankCheck, el editor seguia exportando label
`BgGfx_hud_clock` en `screen_data.asm` PickupTable y BgGfxPtrById.

Síntoma: cinematica entrada a iglesia → game crash (pantalla de basura)
porque pickup table tenía ptr a hud_clock sprite (48×16) tratado como
pickup en char (26, 9) → render corrupto + crash.

Fix: `HUD_LABEL_MAP[44] = 'BgGfx_BankCheck'`. User debe hard-refresh
del editor antes de re-export.

### 6. Editor categoriza placements stale

Editor's `bgSpriteData` cache stale tras reusar id 44 → emite placement
en `ObjectTable` (solid) en vez de `PickupTable` (pickup) aunque el
cellOverlay lo marca cat=pickup. User cambió manualmente en editor
durante la sesión.

### 7. `inject_pickup_sprites.py` bug — re-run elimina labels previos

Si re-ejecutaba el script tras añadir un nuevo TARGET, los sprites ya
inyectados se perdían. Causa: detectar "missing" antes de strippear el
SENTINEL block existente — labels ya inyectados aparecían como
"presentes", no se re-emitían, y el strip los borraba.

Fix: detectar "missing" DESPUÉS de strippear el SENTINEL. Garantiza
emisión completa cada vez. Ya commiteado.

### 8. R13 retrigger envelope debe ir ÚLTIMO

Cualquier write a R13 retriggers el envelope desde el principio. En
`.knockRegs`, R13 es el último DEFB pair antes del sentinel $FF — si
fuera el primero, el envelope retriggerearía cada vez que se setea otro
registro despues, invalidando la configuración.

---

## Archivos modificados (high-level)

**Código del juego:**
- `code/bank_cutscene.asm` — feature file completo (838 líneas, ~1.2 KB compilado).
- `code/main.asm` — INCLUDE bank_cutscene.asm + 6 CALLs en MainLoop dispatch.
- `code/variables.asm` — vars cutscene state (~10 B en bank 2).
- `code/screen_system.asm` — KeyLockTable +slot 7, DormantPickupTable +entry, boundary updates.
- `code/milestones.asm` — chain extendida 9→11, K cycle 6→7, comments.
- `code/church_cutscene.asm` — drop cheque (BankCheck) en vez de TownGateKey.
- `code/sfx_player_hit_ay.asm` — `AY_PlayKnockSoft/Loud` + extended `_uphMuteR9` para restore R7.
- `code/screen_data.asm` — auto-gen del editor (BankCheck en PickupTable, BgGfxPtrById[44] = BgGfx_BankCheck, etc.).
- `code/screen_rooms.asm` — auto-gen del editor (placements del banco con bank_door_closed).
- `code/bg_gfx.asm` — re-export del editor + inject de BgGfx_BankCheck (id 44 manual label).
- `code/bg_gfx_b.asm` — re-export.

**Editor / tools:**
- `tools/level_editor.html` — CODE_REF_IDS += 44, 54. HUD_LABEL_MAP[44] fix.
- `tools/inject_pickup_sprites.py` — bug fix + 44 added to TARGETS.

**Datos:**
- `code/bg_sprites.json` — sprites nuevos en editor.
- `code/level_data.json` — placements en sala (8, 8) y (15, 6).
- `References/nono01.aseprite` — fuente de sprites mano (3 versiones durante sesión).

**Docs:**
- `docs/bank_cutscene.md` — diseño completo.
- `docs/bank_cutscene_handoff.md` — este doc.

---

## Lo que falta (para próxima sesión)

### 1. Smoke test runtime completo (USER)

Ejecutar el juego (`build_and_*.bat` → F6) y validar:

1. Empezar partida normalmente. Compass apunta a 1ª llave (forest).
2. Recoger las 4 llaves de zonas (forest, ruins, cemetery, clock tower).
3. Tocar la puerta del ayuntamiento → spawn church_key.
4. Coger church_key → compass apunta a iglesia (15, 6).
5. Ir a iglesia → entrar (bump-trigger con church_key) — **NO debe crashear**.
6. Atrapar 3 monstruos en estatuas (M7).
7. Tras cinematica de iglesia: **el cheque debe aparecer** en char (26, 9).
8. Coger cheque → CurrentKey = 7. Compass apunta al banco (8, 8).
9. Ir al banco → tocar puerta del banco con cheque.
10. **Cinemática del banco entera**: 3+3+giro+6 toques + mano "no no" 4× + drop llave.
11. Coger town_gate_key → compass apunta al sur (7, 15).
12. Tocar arco del sur → cinemática final.

### 2. Tunings menores que pueden surgir

- Si SFX knock loud sigue muy bajo: subir env period a `$0400` o más, o
  añadir más tone freq.
- Si pos del player en knock no esta exactamente como user quiere:
  ajustar `BCS_PLAYER_ANCHOR_X/Y`.
- Si timing de los toques se siente mal: ajustar `BCS_T_KNOCK_HIT`,
  `BCS_T_KNOCK_GAP`.
- Si la mano "no no" parpadea raro: ajustar `BCS_T_NO_FRAME` o
  `BCS_NO_SWAPS_TOTAL`.

### 3. Limpiezas / TODOs documentados

- `screen_data.asm` tiene fixes manuales (BgGfx_BankCheck, BgGfxPtrById[44]).
  Tras hard-refresh editor + re-export, esto se auto-genera correctamente
  y no necesita patch manual.
- HUD del dígito milestone (col 23) no soporta números >9 (M10, M11
  saldrán raros). Cosmético.
- BankKey (id 41) y nono hand left/right (43, 50) en editor pero no
  usados en el binario. Decisión consciente del user. Pueden quedarse
  como sprites editables sin afectar build.

### 4. Merge a main

Cuando smoke test pase: merge `feat/bank-cutscene` → `main`. 37 commits
atomicos, fácil de revisar.

---

## Comandos útiles para próxima sesión

```bash
# Build + verify
cd code && "/c/Users/JJ/Downloads/sjasmplus-extracted/sjasmplus-1.21.1.win/sjasmplus.exe" --syntax=abfF main.asm
python tools/check_slot_overlap.py
python tools/memory_map.py --pretty | python -c "import json,sys; d=json.load(sys.stdin); [print(f\"Bank {b['bank']}: used={b['used_bytes']} free={b['free_bytes']}\") for b in d['banks']]"

# Si el editor re-exporta y rompe BankCheck label:
python tools/inject_pickup_sprites.py

# Status branch
git log --oneline feat/bank-cutscene ^main
git diff --stat main feat/bank-cutscene
```

## Memorias persistentes a leer

Las siguientes memorias del proyecto son relevantes:

- `project_bank_cutscene_session.md` (este handoff resumido)
- `project_ram_master_plan.md`
- `project_ram_optimization_options.md`
- `project_ram_placement.md`
- `project_128k_build.md`
- `project_slot1_overflow_canary.md`
- `project_milestone_chain.md`
- `project_church_trap.md`
- `project_town_gate_cutscene.md`
- `project_key_lock_system.md`
- `project_keylock_sprite_id_trap.md` (relevante: sprite-id reuse gotcha)
