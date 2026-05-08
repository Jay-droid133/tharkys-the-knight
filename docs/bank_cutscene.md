# Bank Cutscene — diseño (draft, M9 propuesto)

> **Estado**: DRAFT — el archivo `code/bank_cutscene.asm` existe pero **NO está
> INCLUDE'd en `main.asm`**. Cero impacto en RAM hasta que decidamos placement.
>
> **Propósito**: cinemática intermedia entre la trampa de la iglesia (M7
> actual) y la cinemática final town_gate (M9 actual). El jugador, con el
> cheque que dejó el cura tras la trampa, va al banco a "cobrarlo" y
> recibe la llave de la ciudad.

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
9. Una **mano asoma**, dice "No no" 4 veces (anim 2 frames).
10. La mano se retrae.
11. Aparece la **llave de la ciudad** en el suelo.
12. Player gira un instante a cámara.
13. Recupera el control y puede recoger la llave.

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
| 39 | Bank | ✅ existe (BgGfx_bank), placement en (8,8) char (12,0) | facade closed |
| 41 | BankKey | ✅ en editor, **falta export a bg_gfx** | la llave que aparece |
| 43 | BankDoorOpen | ✅ en editor, **falta export a bg_gfx** | puerta abierta |
| 44 | BankCheck | ✅ en editor, **falta export a bg_gfx** | cheque (PICKUP M8) |
| ? | BankHandFrame0 | ❌ por crear | mano "no" izq (2x2 chars = 16x16 px) |
| ? | BankHandFrame1 | ❌ por crear | mano "no" der (2x2 chars = 16x16 px) |

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

**Placeholder de la mano**: durante el draft uso labels
`BgGfx_BankHandFrame0` / `BgGfx_BankHandFrame1` que aún no existen. El draft
no compila hasta que estos labels existan, pero como el draft NO está
INCLUDE'd, no afecta el build actual.

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
BCP_DOOR_OPEN           10    erase facade door area, draw BankDoorOpen
BCP_HAND_IN             11    aparece mano (frame 0)
BCP_HAND_NO_NO          12    anim 4× (frame 0/1 swap)
BCP_HAND_OUT            13    erase mano
BCP_KEY_DROP            14    BankKeySpawned=1 + RedrawPickupByPtr
BCP_PLAYER_TURN_CAM     15    player gira a S un instante
BCP_DONE                16    sentinel; phase = BCP_IDLE para devolver control
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

## 9. Anchor positions (todas placeholder, ajustar in-game)

```
BCS_BANK_ROOM_X         8
BCS_BANK_ROOM_Y         8
BCS_PLAYER_ANCHOR_X    120    centrado bajo puerta
BCS_PLAYER_ANCHOR_Y     80    16 px bajo borde inferior puerta
BCS_DOOR_PX_LEFT       116
BCS_DOOR_PX_RIGHT      139
BCS_DOOR_PX_TOP         40
BCS_DOOR_PX_BOTTOM      63
BCS_HAND_PX_X          120    centrado en hueco puerta abierta
BCS_HAND_PX_Y           48    en mitad de la puerta
BCS_KEY_DROP_CHARX      15    char donde aparece la BankKey
BCS_KEY_DROP_CHARY       8    suelo, frente a puerta
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

**Bank 2 está al 99.99% — los puntos 3-5 (~21 B) NO caben sin liberar antes.**
Esto es el verdadero bottleneck del wiring, no el slot 1 del cuerpo de la
cinemática. Pre-fase requerida: mover **freeze cluster** (~470 B) o equivalente
de bank 2 a bank 7 antes del wire-up.

## 11. Tamaño esperado del cuerpo

Comparando con town_gate (16 fases ≈ 1.5 KB) y church (más simple ≈ 1 KB):

- 16 fases similares al town_gate.
- Sin credits/black-screen/wipe (-200 B vs town_gate).
- Sub-state machinery extra para knock-loops (+100 B).
- **Estimado: 1.2-1.4 KB.**

Cabe en slot 1 (1.6 KB libres) **sin** pre-fase de descarga, **pero con
margen estrecho**. Decisión final tras compilar el draft con INCLUDE
temporal en bank 7 para medir bytes reales.

## 12. Plan de wire-up (cuando decidamos)

1. **Antes de tocar bank 2** (puntos 3, 4, 5 de §10): hacer pre-fase de
   liberación en bank 2. Candidato más barato: freeze cluster (~470 B) →
   bank 7 con thunk. Ganamos ~470 B de margen.
2. Resolver placement del cuerpo `bank_cutscene.asm`:
   - Si tras paso 1 slot 1 sigue cómodo: INCLUDE en slot 1, mismo patrón
     que town_gate / church.
   - Si apretado: hacer también pre-fase tombstones → bank 7 (~400 B más).
3. Crear sprites pendientes (mano `BgGfx_BankHandFrame0/1`) o reusar 2
   sprites BG existentes como placeholder visual.
4. Editor: placear `BankCheck` en pantalla iglesia (donde hoy
   `town_gate_key`); placear `BankKey` en pantalla banco (15, 8) char.
   Marcar ambos dormant + añadir IDs a `CODE_REF_IDS`. Re-export bg_gfx.
5. Ediciones de §10 puntos 1-6.
6. INCLUDE bank_cutscene.asm en su sitio + CALL CheckBankTriggerBg en MainLoop.
7. Smoke test: completar M7 (church trap) → cheque aparece → coger →
   compass apunta al banco → ir y tocar puerta → cinemática completa →
   key aparece → coger → compass apunta a town gate → final cutscene OK.

## 13. Riesgos / TODOs

- [ ] Hand sprite: 2 frames placeholder. Diseñar definitivo.
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
