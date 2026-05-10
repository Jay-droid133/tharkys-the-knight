# Bank Cutscene — diseño (draft, M9 propuesto)

> **Estado**: DRAFT — el archivo `code/bank_cutscene.asm` existe pero **NO está
> INCLUDE'd en `main.asm`**. Cero impacto en RAM hasta wire-up.
>
> **Propósito**: cinemática intermedia entre la trampa de la iglesia (M7
> actual) y la cinemática final town_gate (M9 actual). El jugador, con el
> cheque que dejó el cura tras la trampa, va al banco a "cobrarlo" y
> recibe la llave de la ciudad.

## ⚠️ DIAGNÓSTICO REVISADO con `tools/memory_map.py`

Estado real de bancos hoy (verificado, no estimado):

| Bank | Used | Free | Notas |
|---|---|---|---|
| 0 | 14980 | **1404** | main code slot 3 default — donde irá bank_cutscene |
| 1 | 11064 | 5320 | screen_rooms |
| 2 | 16382 | **2** | always-vis full (KeyLockTable, MainLoop, vars) |
| 3 | 12509 | 3875 | bg_gfx baseline |
| 4 | 9773 | 6611 | bg_gfx_b + ay_sound |
| 5 | 16090 | **294** | slot 1 (incluye VRAM + sys + vars_lo + cold code) |
| 6 | 14080 | 2304 | gaps + AI |
| 7 | 7199 | **9185** | bg_gfx_c + room_routes_b7 + tombs |

**Slot 1 NO es viable** (294 B libres, draft pesa ~1.0-1.3 KB).

**Bank 7 NO es óptimo**: aunque tiene 9 KB libres, todos los helpers que llama
el cutscene están en bank 0, slot 1, o slot 2 — meterlo en bank 7 obligaría
a thunks/paging por cada CALL. Heat overlay confirma que random_pickups,
tombstones, magic_compass son LAVA (depth 1-2 desde MainLoop) → no se
pueden mover sin penalty per-frame.

**Bank 0 es óptimo**: cabe (1404 B - ~1200 B = ~200 B margen), CERO thunks
porque DrawBgGfxSprite, RestoreOldAttr, RedrawPickupByPtr, PlaySFX,
CheckMilestoneTrigger viven en bank 0; KillAllActiveNasties, DrawSprite,
EntityTable, MainLoop están en slot 2 (always-vis); LoadBgSpriteToBuffer,
KillDeathIfActive, AY_PlayBeep están en slot 1 (always-vis).

**INCLUDE va entre `sound.asm` y `PAGE 1`** en main.asm (línea 412 aprox),
zona bank 0 default.

## 1. Resumen narrativo

Tras la cinemática de la iglesia, en vez de soltarse la llave de la puerta de
la ciudad, se suelta un **cheque** (sprite `BankCheck`, id 44).

Próximo hito: ir a la **puerta del banco**, que está en la pantalla **norte
del ayuntamiento** (room (8, 8), justo encima de town hall en (8, 9)).
Allí, al contactar la puerta con el cheque encima, arranca la cinemática:

1. Player se ancla frente a la puerta, mirando arriba.
2. **3 toques** → espera silenciosa.
3. **3 toques** → espera silenciosa.
4. Player gira y mira al usuario un instante.
5. Player se vuelve hacia la puerta.
6. **6 toques**.
7. Pausa breve.
8. La puerta se abre.
9. Asoma una **mano abierta** (palma) — pide el cheque.
10. Tras un instante el **cheque desaparece del inventario** (HUD).
11. La mano abierta se retira.
12. Pausa breve con la rendija vacía.
13. Aparece la **mano "no no"** y dice "No no" 4 veces (anim 2 frames).
14. La mano se retrae.
15. Aparece la **llave de la ciudad** en el suelo.
16. Player gira un instante a cámara.
17. Recupera el control y puede recoger la llave.

Próximo hito: bajar al sur, abrir la puerta de la ciudad, arranca el
town_gate cutscene (cinemática final actual, sin cambios).

## 2. Cadena de hitos — propuesta

Hoy: 9 hitos. Tras este cambio: **11 hitos** (insertamos 2 entre M7 y el
actual M8).

| # antes | # después | Tipo | Ref | Descripción |
|---------|-----------|------|-----|-------------|
| 1-7     | 1-7       | sin cambios | | forest/ruins/cemetery/clock keys + townhall trigger + church key + church trap |
| —       | **8**     | **PICKUP 7** | BankCheck | recoger el cheque (NUEVO) |
| —       | **9**     | **TRIGGER 4** | BankDoor | tocar puerta del banco con cheque (NUEVO) |
| 8       | 10        | PICKUP 6 | BankKey (ex TownGateKey) | recoger llave de ciudad |
| 9       | 11        | TRIGGER 3 | TownGate | puerta sur, cinemática final |

**Coste de RAM del cambio en cadena:** +4 B en `MilestoneTable` + +4 B en
`MilestoneResolveTable` (ambas en bank 0, 1.2 KB libres → cabe). Más cambios
de `CP 9` → `CP 11` en CheckMilestonePickup/Trigger/DebugKey (3 sitios, 0 B
neto).

**HUD del dígito milestone (col 23, 8x8):** hoy muestra 1..9. Con 11
milestones la solución más barata es seguir mostrando hex (A=10, B=11) o
extender a 2 dígitos. Decisión postponible — funciona correctamente en
gameplay aunque el HUD muestre un dígito raro durante M10/M11.

## 3. Sprites necesarios

| ID | Nombre | Estado | Uso |
|----|--------|--------|-----|
| 39 | Bank | ✅ existe (BgGfx_bank), placement en (8,8) char (12,0) | facade — la mano se dibuja sobre esto, queda CERRADA toda la cinemática |
| 44 | BankCheck | ✅ en editor + en CODE_REF_IDS, falta export | cheque (PICKUP M8). Placement: sala (15,6) char (26,9) |
| 186 | town_gate_key | ✅ existente, placement movido a sala (8,8) | la llave de la ciudad. La revela bank_cutscene via `TownGateKeySpawned` (mismo flag que ya existia) |
| —  | BankHandFrame0 | ✅ inline en bank_cutscene.asm | mano "no" frame 0 (16x16) |
| —  | BankHandFrame1 | ✅ inline en bank_cutscene.asm | mano "no" frame 1 (16x16) |
| ~~41~~ | ~~BankKey~~ | ❌ **eliminada de la ecuación** — el usuario decidió reusar town_gate_key como llave de la ciudad. BankKey queda en el editor solo como sprite no-referenciado | — |
| ~~43~~ | ~~BankDoorOpen~~ | ❌ **NO necesaria** — la puerta no se abre, la mano sale por la rendija | — |

**Decisiones del usuario para simplificar**:

1. **La puerta del banco NO se abre** durante la cinemática. La mano se
   dibuja con XOR sobre la puerta cerrada (sugiriendo que sale por una
   rendija/ventanilla del banco). Implicaciones:
   - No se llama `DrawBgGfxSprite(BankDoorOpen)`.
   - No se necesita `LoadBgSpriteToBuffer` para la puerta.
   - Rutina `BankCutsceneOpenBankDoor` eliminada (~30 B menos).
   - La mano hereda attrs de la facade → XOR self-cancel limpio sin
     `RestoreOldAttr`.

2. **No hay BankKey separada — reuso de town_gate_key**. La llave de la
   ciudad sigue siendo `BgGfx_town_gate_key` (id 186) con su flag dormant
   `TownGateKeySpawned` (variable preexistente). El usuario movió el
   placement del sprite de la iglesia a la sala (8, 8) del banco. La
   cinematica del banco activa el flag igual que antes lo hacía la de la
   iglesia. Ahorro: 1 variable (BankKeySpawned eliminada) + 1 sprite + 1
   entrada en CODE_REF_IDS + 1 entrada en DormantPickupTable + 1 entrada
   en KeyLockTable. La cinemática de la iglesia ahora suelta el cheque
   (BankCheck) usando el mismo patrón pero con su nuevo flag
   `BankCheckSpawned`.

> Nota: el usuario añadió "nono hand left/right" al editor con IDs 43 y 50,
> pero el draft NO los referencia (sigue inline). Esos IDs quedan reservados
> en el editor por si más adelante se decide migrarlo al patrón
> `DrawBgGfxSprite`. Hoy son no-op (no afectan al binario porque el editor
> no exporta nada que no esté en `CODE_REF_IDS`).
>
> Lo mismo vale para BankKey (id 41) tras la decisión de eliminarla de la
> ecuación: queda en `bg_sprites.json` como sprite editable pero no aparece
> en `CODE_REF_IDS`, así que no entra en el binario.

**Pasos para wirear los sprites del editor:**

1. En `tools/level_editor.html` → `CODE_REF_IDS` añadir:
   ```js
   41,  // BgGfx_BankKey      — bank cutscene drop, KeyLockTable slot 6
   43,  // BgGfx_BankDoorOpen — bank cutscene phase DOOR_OPEN
   44,  // BgGfx_BankCheck    — pickup intermedio M8, KeyLockTable slot 7
   ```
2. En el editor: "Export All BG" → re-genera `bg_gfx.asm` con los nuevos labels.
3. Crear los 2 sprites de la mano (importar desde aseprite, o dibujarlos en
   el sprite editor del nivel).

**Sprite de la mano**: importado de `References/nono01.aseprite` (16×16 px,
2 frames) via Aseprite CLI → PNG → DEFB. Inserto inline al final de
`bank_cutscene.asm` siguiendo el mismo patrón que `SmokeFrame0/1/2` en
`milestones.asm`. Formato compatible con `DrawBgSprite16XorAtPixel`:
header 2B + 32 B de pixel data CPL'd. Total 68 B (los 2 frames). NO requiere
ID en el editor porque es sprite interno de cutscene, no placeable en el
mapa.

## 4. KeyLockTable — cambios

```diff
 KeyLockTable:
     DEFW BgGfx_forestkey            ; 1
     DEFW BgGfx_ruinskey             ; 2
     DEFW BgGfx_cemeterykey          ; 3
     DEFW BgGfx_clock_tower_key      ; 4
     DEFW BgGfx_church_key           ; 5
-    DEFW BgGfx_town_gate_key        ; 6: TownGate Key (id 186)
+    DEFW BgGfx_BankKey              ; 6: BankKey visual (funciona como TownGateKey)
+    DEFW BgGfx_BankCheck            ; 7: BankCheck (cheque, intermedio)
     DEFW BgGfx_forestlock           ; 7→8
     ...
```

**Nota crítica** ([KeyLockTable sprite-id trap](../memory/...) — ya
documentado en memoria): la tabla identifica keys por puntero exacto. El
editor debe placear el SPRITE BASE (`BgGfx_BankKey`, `BgGfx_BankCheck`) y
no una variante derivada, o no se reconocerá.

## 5. PickupTable + DormantPickupTable

```diff
 DormantPickupTable:
     DEFW BgGfx_church_key, ChurchKeySpawned
-    DEFW BgGfx_town_gate_key, TownGateKeySpawned
+    DEFW BgGfx_BankCheck, BankCheckSpawned     ; church drop → cheque
+    DEFW BgGfx_BankKey, BankKeySpawned         ; bank cutscene drop → llave
     DEFW BgGfx_arm, ArmRevealed
     DEFW BgGfx_finger, FingerRevealed
     DEFW 0
```

**Posiciones de placement** (a colocar en el editor, dormant inicialmente):

- `BgGfx_BankCheck` en la sala de la iglesia (donde hoy aparece TownGateKey
  tras la trampa). Probablemente room (X, Y) = el lugar exacto que ya tiene
  hoy `town_gate_key` placeado y que se revela vía RedrawPickupByPtr.
- `BgGfx_BankKey` en la sala del banco (X=8, Y=8), centrado en el suelo
  delante de la puerta. **Placeholder propuesto**: char (15, 8). Ajustar al
  ver visualmente.

## 6. Trigger del banco

Patrón clonado de `CheckTownGateTriggerBg` ([town_gate_cutscene.asm:128](../code/town_gate_cutscene.asm#L128)):

- Sala: (CurrentScreenX, CurrentScreenY) == (8, 8).
- CurrentKey == 7 (BankCheck).
- Phase == 0 (no en cutscene).
- AABB del player vs rect de la puerta del banco con tolerancia ±4.

**Rect de la puerta del banco** — placeholder a tunear viendo el sprite real:

- Bank facade en char (12, 0), 64×48 px → ocupa pixels (96-159, 16-63) (con
  BG_Y_OFFSET=2).
- Asumo puerta en mitad inferior: chars relativos (3-4, 4-5), absolutos
  (15-16, 4-5).
- Door rect placeholder: pixels (120-135, 48-63).

**Wiring del trigger** (NO se llama hoy, hay que añadir CALL en MainLoop):

```asm
; En MainLoop, junto a CheckTownGateTriggerBg (logic_game.asm o screen_system):
    CALL CheckBankTriggerBg
```

## 7. Phase machine (16 fases)

```
BCP_IDLE                 0    no en cutscene
BCP_LOCK                 1    snap player a anchor, facing N, pausa
BCP_KNOCKS_1             2    3 toques (sub-state HIT/GAP)
BCP_WAIT_1               3    espera silenciosa tras grupo 1
BCP_KNOCKS_2             4    3 toques más
BCP_WAIT_2               5    espera tras grupo 2
BCP_TURN_TO_CAM          6    player gira a S (cara cámara)
BCP_TURN_TO_DOOR         7    player vuelve a N
BCP_KNOCKS_3             8    6 toques
BCP_WAIT_3               9    pausa antes de abrir
BCP_PRE_HAND            10    erase puerta + draw mano abierta (NO la "no no")
BCP_HAND_IN             11    [skipped] reservado por compat (dispatcher inalcanzable)
BCP_HAND_NO_NO          12    anim 4× (frame 0/1 swap)
BCP_HAND_OUT            13    erase mano "no no" + cierra puerta
BCP_KEY_DROP            14    pausa con la llave + giro a camara
BCP_PLAYER_TURN_CAM     15    player gira a S un instante
BCP_DONE                16    sentinel; phase = BCP_IDLE para devolver control
BCP_WAIT_NASTIES        17    pre-LOCK: nasties + death animan puff antes de LOCK
BCP_DOOR_CLOSED         18    pausa con puerta cerrada antes del key drop
BCP_HAND_OPEN_IN        19    mano abierta visible — pide el cheque
BCP_HAND_OPEN_TAKE      20    cheque desaparece del HUD, mano abierta sigue visible
BCP_HAND_OPEN_OUT       21    rendija vacia, pausa antes del "no no"
```

Flujo nuevo entre PRE_HAND (10) y HAND_NO_NO (12):

```
PRE_HAND -> [draw OPEN hand] -> HAND_OPEN_IN (timer)
HAND_OPEN_IN -> [CurrentKey=0; HUD clears] -> HAND_OPEN_TAKE (timer)
HAND_OPEN_TAKE -> [erase OPEN hand] -> HAND_OPEN_OUT (timer)
HAND_OPEN_OUT -> [draw NO-NO frame 0] -> HAND_NO_NO (existing swap loop)
```

Sub-states usados:

- `BankCutsceneKnockIdx` DEFB — knocks emitidos en grupo actual.
- `BankCutsceneSubState` DEFB — 0=HIT, 1=GAP dentro de grupo de toques.
- `BankCutsceneNoIdx` DEFB — swaps de "no no" emitidos.
- `BankCutsceneHandFrame` DEFB — 0/1, frame actual de la mano.

## 8. Timings (frames a 50 Hz, ajustables)

```
BCS_T_LOCK              30   1.2 s lock inicial
BCS_T_KNOCK_HIT         6    cada hit de toque (door shake + SFX)
BCS_T_KNOCK_GAP         8    gap entre toques de un grupo
BCS_T_GROUP_WAIT        50   2 s espera silenciosa tras cada grupo
BCS_T_TURN_CAM          40   1.6 s mirando cámara (mid-cutscene)
BCS_T_TURN_BACK         10   transición rápida de vuelta
BCS_T_PRE_DOOR_OPEN     30   pausa tras los 6 toques
BCS_T_DOOR_OPEN_HOLD    20   hold tras abrir
BCS_T_HAND_IN           20   hand spawn pause
BCS_T_NO_FRAME          12   cada swap de "no no"
BCS_NO_SWAPS_TOTAL      8    4 × 2 swaps por "no" = 8 transiciones
BCS_T_HAND_HOLD         15   pausa tras último swap
BCS_T_HAND_OUT          10   tras erase
BCS_T_KEY_HOLD          30   pausa tras drop antes de turn-cam
BCS_T_PLAYER_TURN_FINAL 30   1.2 s mirando cámara antes de devolver control
```

## 9. Anchor positions

**Confirmadas por el usuario** (editor screenshot Cell:8,8 T:15,4):

```
BCS_BANK_ROOM_X         8     ✅ confirmado
BCS_BANK_ROOM_Y         8     ✅ confirmado
BCS_DOOR_CHARX         15     ✅ confirmado (puerta del banco)
BCS_DOOR_CHARY          4     ✅ confirmado
```

**Asumidas** (ajustar tras ver sprite real / play test):

```
BCS_DOOR_CHAR_W         2     asumido — door 2x2 chars (= 16x16 px)
BCS_DOOR_CHAR_H         2     asumido. Si real es 3x3 / 4x4 / 4x5, ajustar.
BCS_PLAYER_ANCHOR_X   120     centrado bajo puerta (= door X)
BCS_PLAYER_ANCHOR_Y    80     16 px bajo borde inferior puerta
BCS_HAND_PX_X         120     centrado en hueco puerta abierta
BCS_HAND_PX_Y          48     en mitad de la puerta
BCS_KEY_DROP_CHARX     15     char donde aparece la BankKey
BCS_KEY_DROP_CHARY      7     1 char bajo el borde inferior de la puerta
```

## 10. Cambios fuera del bank_cutscene.asm

Cuando wireemos (no hoy):

1. `church_cutscene.asm` línea 151-153: cambiar `TownGateKeySpawned` →
   `BankCheckSpawned`, `BgGfx_town_gate_key` → `BgGfx_BankCheck`. ~5 B.
2. `milestones.asm`: insertar 2 entradas nuevas en MilestoneTable +
   MilestoneResolveTable, cambiar `CP 9` → `CP 11` en 3 sitios. ~10 B.
3. `screen_system.asm`: KeyLockTable slot 6 cambia de
   `BgGfx_town_gate_key` → `BgGfx_BankKey`. Slot 7 nuevo (`BgGfx_BankCheck`).
   DormantPickupTable: añadir BankCheck + BankKey. ~16 B en bank 2 ⚠️
   (bank 2 tiene 1 B libre — esto rompería el build).
4. `variables.asm`: `BankCheckSpawned: DEFB 0`, `BankKeySpawned: DEFB 0`.
   ~2 B en bank 2 ⚠️.
5. `MainLoop`: `CALL CheckBankTriggerBg`. ~3 B en bank 2 ⚠️.
6. `bump_trigger`: añadir action 4 = BankDoor handler. ~10-20 B en bank 0.

**Bank 2 está al 100% (2 B libres)**. Cualquier byte añadido a includes que
caen ANTES del fin de bank 2 hace spillover automático a bank 0 (sjasmplus
linear assembler — no error, simplemente desplaza). El efecto real:

- 6 B de CALL en MainLoop → 6 B desplazan de fin-de-bank-2 a inicio-de-bank-0.
- 14 B en tablas (KeyLockTable / DormantPickupTable / BumpTriggerTable, en
  screen_system.asm late-bank-2) → mismo desplazamiento.
- 8 B en milestone tables → milestones.asm vive en bank 0, suma directo.
- 10 B de vars (BankCutscenePhase + 9 más) → variables.asm vive en bank 2,
  spillover a bank 0.

**Total bank 0 cost (wiring + body): ~1.2-1.4 KB**. Bank 0 tiene 1404 B
libres → margen 0-200 B. **Apretado pero teóricamente cabe**.

Si tras compilar el draft real medimos > 1300 B, opciones de aliviar:
1. **Dead code purge** — `--dead` reportó 16 labels muertos en banks 0/2/4/5/6.
   Borrar libera bytes sin riesgo.
2. **Reducir el draft**: factorizar inicialización de knock-groups (3 sitios
   con código repetido), quitar SFX stubs hasta que se necesiten (~7 B).

## 11. Tamaño esperado del cuerpo

Comparando con town_gate (16 fases ≈ 1.5 KB) y church (más simple ≈ 1 KB):

- 16 fases similares al town_gate.
- Sin credits/black-screen/wipe (−200 B vs town_gate).
- Sub-state machinery extra para knock-loops (+100 B).
- **Estimado: 1.0-1.3 KB.** Verificable con compile-check (ver §12).

## 12. Compile-check para medir tamaño real

Para medir bytes exactos sin commitear:

1. Añadir temporalmente `INCLUDE "bank_cutscene.asm"` en main.asm entre
   `sound.asm` (línea 412) y la siguiente directive de `PAGE`.
2. Antes de compilar, añadir stubs DEFW 0 para los labels pendientes
   de export (`BgGfx_BankCheck`, `BgGfx_BankKey`, `BgGfx_BankDoorOpen`,
   `BgGfx_BankHandFrame0`, `BgGfx_BankHandFrame1`) en cualquier sitio
   compatible — solo para que el linker resuelva.
3. F6 build. Leer .sld para ver direcciones de `BankCutscenePhase`
   (final del módulo) y `CheckBankTriggerBg` (inicio). Diferencia = bytes.
4. Comparar con `(Bank0End_actual - Bank0End_pre)` en build_stats.json.
5. **Revertir el INCLUDE temporal.** El draft vuelve a estar fuera del build.

## 13. Plan de wire-up (cuando decidamos darle el OK)

1. **Crear sprites pendientes** (mano `BgGfx_BankHandFrame0/1`) o reusar
   2 sprites BG existentes como placeholder visual.
2. **Editor**: placear `BankCheck` en pantalla iglesia (donde hoy
   `town_gate_key`); placear `BankKey` en pantalla banco char (15, 8).
   Marcar ambos dormant + añadir IDs 41, 43, 44 a `CODE_REF_IDS`.
   Re-export bg_gfx.
3. **Ediciones del wire-up** (todas en bank 0 o spillover a bank 0):
   - church_cutscene.asm: drop cheque en vez de key (~5 B).
   - milestones.asm: +2 entradas en MilestoneTable + ResolveTable, CP 9 → CP 11.
   - screen_system.asm: KeyLockTable slot 6 cambia + slot 7 nuevo,
     DormantPickupTable +2 entries, BumpTriggerTable +1 entry (action 4).
   - variables.asm: BankCheckSpawned, BankKeySpawned, etc.
   - main.asm: CALL CheckBankTriggerBg + CALL UpdateBankCutscene en MainLoop.
4. **INCLUDE `bank_cutscene.asm`** entre sound.asm y PAGE 1 en main.asm.
5. **Build clean + check_slot_overlap.py + parse_build_stats.py** para
   confirmar bank 0 dentro de presupuesto.
6. **Smoke test**: completar M7 (church trap) → cheque aparece → coger →
   compass apunta al banco → ir y tocar puerta → cinemática completa →
   key aparece → coger → compass apunta a town gate → final cutscene OK.
   Validar también que compass HUD sigue dibujándose (canario de overflow).

## 13. Riesgos / TODOs

- [x] Hand sprite: 2 frames importados de `References/nono01.aseprite` ✅
- [ ] Door rect AABB: tunear viendo el sprite real del banco.
- [ ] Key drop position: tunear viendo qué deja vacío la puerta abierta.
- [ ] HUD dígito milestone: 1..11 vs hex. Cosmético; postponible.
- [ ] Bank 2 saturado: bloquea wire-up. Pre-fase obligatoria.
- [ ] SFX: knocks, door open, hand "no", key drop — todos stub `RET`
      por ahora; rellenar después.
- [ ] Cheque visual al recoger: ¿debería el HUD mostrar algún indicador
      "tienes el cheque"? Hoy CurrentKey muestra el sprite de la key —
      con BankCheck como key id 7 funcionaría automáticamente si está
      en KeyLockTable.

## 14. Referencias cruzadas

- Patrón maestro: [code/town_gate_cutscene.asm](../code/town_gate_cutscene.asm)
- Drop-key actual de la iglesia: [code/church_cutscene.asm:137](../code/church_cutscene.asm#L137) (UpdatePostTrapPause)
- KeyLockTable / BumpTriggerTable / DormantPickupTable: [code/screen_system.asm:1976](../code/screen_system.asm#L1976)
- Milestone chain: [code/milestones.asm:33](../code/milestones.asm#L33)
- CODE_REF_IDS: [tools/level_editor.html:8281](../tools/level_editor.html#L8281)
- RAM master plan: [docs/RAM_OPTIMIZATION_PLAN.md](RAM_OPTIMIZATION_PLAN.md)
