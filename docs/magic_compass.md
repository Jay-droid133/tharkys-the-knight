# 🧭 Brújula mágica — sistema de routing sala-a-sala

Power-up que muestra al jugador **la próxima salida correcta** desde la sala
donde está hacia el `CurrentObjective`, evitando cul-de-sacs internos. La
ruta calculada coincide con la que produciría el char-level BFS del editor.

---

## 1. Funcionalidad visible

| Cuándo | Qué pasa |
|---|---|
| Recoge sprite ID 34 (`BgGfx_pickup_compass`) | Activa power-up por **30 s** (refresh-on-pickup). |
| Sala destino del hito ≠ sala actual | El HUD compass se sustituye por el sprite **ID 36** (`Sprite_Compass_Magic`) — o por **ID 37** (`Sprite_Compass_MagicLasting`) si la brújula es la permanente (`MagicCompassPermanent != 0`, post-cinemática iglesia). 4 chars con el color base que diga el editor; uno (el correspondiente a la dirección) destella en blanco bright `$47` cada vez que suena un tick AY (sincronía exacta con el oído). |
| Player cruza borde a una sala nueva | BFS sincrónico antes de `DrawScreen` actualiza `PathDir`, y se dispara un **tick inmediato** (AY beep + flash al char activo) en el mismo frame del cruce. Sin esperas: feedback al instante con la flecha correcta. |
| Player **llega** a la sala destino del hito | **Cancela inmediatamente** (cleanup exhaustivo: tick AY off, jingle off, HUD vuelve al compass clásico). Si recoges el power-up estando ya en la sala destino, se cancela al frame siguiente. |
| Timer **expira** (timeout natural a los 30 s) | Cancela. El HUD vuelve al compass clásico (8 flechas + X) en el frame siguiente, sin necesidad de cambiar de sala. Internamente: `_DoCancelMagicCompass` setea `PreviousObjectiveDistance=$FF` para forzar `DrawCompass` a re-renderizar. Además dispara el **wobble** (9 frames de oscilación) como señal visual de que el power-up se acabó. |
| Últimos 5 s | Tick AY pasa de 1/s a 2/s; el destello sigue acoplado, así que parpadea al doble de frecuencia automáticamente. |
| Player muere | Cancela. |
| Player cumple `CurrentObjective` (avanza hito) | Cancela (suele ser redundante: ya canceló al entrar en la sala). |
| AY canal B | Jingle 3 notas al recoger + tick heartbeat. |

**Mapping diagonal del char activo (mismo layout 2×2 para ID 36 e ID 37):**

```
       col 1   col 2
row 1   W       N    ← top-left = W, top-right = N
row 2   S       E    ← bottom-left = S, bottom-right = E
```

PathDir 0 (N) → char (2,1); 1 (S) → (1,2); 2 (W) → (1,1); 3 (E) → (2,2).

Convive ortogonalmente con rayo / caracol / mushroom (sólo afecta HUD + canal B).

---

## 2. Arquitectura — pipeline build → runtime

```
level_data.json
       │
       ▼  (Editor → Export ASM)
screen_data.asm + screen_rooms.asm + bg_gfx*.asm
       │
       ▼  (build_screen_gaps.py)
screen_gaps.asm (consumido por monster spawn)
room_routes.asm (consumido por brújula mágica)
       │
       ▼  (sjasmplus)
juego.tap / juego.sna
```

`build_screen_gaps.py` ejecuta una sola pasada y emite **dos** outputs paralelos
desde la misma fuente: el formato simple `(side, coord) × count` para los
nasties, y el formato extendido `(side_comp, coord) × count` para la brújula.
Esto garantiza que ambas tablas comparten *single source of truth*.

---

## 3. Conceptos clave

### 3.1 Componentes walkable internas

Una sala puede tener varias zonas walkables **disconnected internamente** por
muros internos. Ejemplo real: sala (5,12) tiene un pasillo superior y otro
inferior separados por una pared horizontal. Aunque ambas zonas tengan gaps
hacia salas vecinas, **no se puede ir de un pasillo al otro sin salir de la
sala**.

`build_screen_gaps.py` detecta estas componentes con `connected_components()`
y las re-indexa por tamaño descendente (comp 0 = la zona walkable más grande).
Soportamos hasta 3 componentes por sala (cap del filtro MIN_POCKET_SIZE).

### 3.2 Estado del BFS: `(sid, comp)`

El BFS sala-a-sala no opera con sólo `sid` (id de sala = `Y*16 + X`), sino
con el par `(sid, comp_local)`. Eso evita "atajos fantasma" que cruzarían
una sala saltando entre componentes desconectadas.

### 3.3 Tracking del player

Para iniciar el BFS necesitamos saber en qué componente está el player ahora
mismo. Como no tenemos walkability char-level en runtime (vive sólo en el
editor), inferimos la componente a partir de **por qué borde y a qué char**
entró a la sala actual:

- `LastEntrySide` (1 byte): N=0, S=1, W=2, E=3 — opuesto del borde cruzado.
- `LastEntryCoord` (1 byte): charX (si cruzó N/S) o charY top-left (si W/E).
  Necesario para desambiguar cuando una sala tiene **dos gaps en el mismo
  side pero en componentes distintas** (caso (5,12): E@3 en comp 1 superior
  vs E@11 en comp 0 inferior).

`CheckScreenTransition` (en `screen_system.asm`) actualiza ambos campos en
cada cruce de borde. Boot/respawn → `LastEntrySide = $FF` → fallback `comp 0`.

### 3.4 Heurística del target

El BFS reverse arranca desde `(target_sid, 0)`. Asumimos que el pickup del
hito vive en la **componente principal** (comp 0 = la mayor). Esta hipótesis
cubre el 99 % de casos en niveles bien diseñados; sólo falla si el level
designer pone deliberadamente un pickup tras una pared interna sin gap.

---

## 4. Estructuras de datos

### 4.1 `RoomCompGapsTable` (slot 1, ~3 KB)

Auto-generada por `build_screen_gaps.py`. Formato paralelo al de
`ScreenGapsTable` pero con info de componente.

```asm
RoomCompGapsTable:        ; 256 DEFW ptrs (sid = Y*16+X)
RoomCompGaps_YX:          ; record per-sala
    DEFB count
    DEFB side_comp_0, coord_0
    DEFB side_comp_1, coord_1
    ...
RoomCompGapsNone:         ; DEFB 0 (sentinel)
```

**Encoding `side_comp` (1 byte):**
- bits 0-1 = `side` (0=N, 1=S, 2=W, 3=E) — coincide con `SIDE_*` de Python.
- bits 2-3 = `local comp idx` (0..2).
- bits 4-7 = unused (0).

`coord` es el mismo char-coord que usa `ScreenGapsTable` (charX para N/S,
charY top-left para W/E). Esto permite **resolver la correspondencia
gap-físico** cuando dos gaps del mismo side existen en distintas comps:
sus `coord` son diferentes y eso identifica unívocamente cada gap.

### 4.2 Estado runtime

| Variable | Loc | Bytes | Función |
|---|---|---|---|
| `MagicCompassTimer` | variables_lo | 2 | Frames restantes (16-bit, 0 = inactivo) |
| `MagicCompassPathDir` | variables_lo | 1 | Dir actual (0/1/2/3 = N/S/W/E, $FF = no path) |
| `MagicCompassPathDirty` | variables_lo | 1 | Flag para recomputar BFS |
| `MagicCompassTickActiveFrames` | variables_lo | 1 | Frames restantes del beep audible. >0 = char activo en bright; 0 = silencio |
| `MagicCompassTickCounter` | variables_lo | 1 | Frames hasta el próximo tick AY |
| `MagicCompassJingleIdx` | variables_lo | 1 | Índice de la nota actual ($FF = idle) |
| `MagicCompassJingleFrames` | variables_lo | 1 | Frames hasta avanzar de nota |
| `MagicCompassBfsHead/Tail` | variables_lo | 2 | Punteros cola FIFO |
| `MagicCompassBfsState` | variables_lo | 1 | 0 = idle, 1 = BFS amortizado en progreso |
| `LastMagicCompassDrawn` | variables_lo | 1 | Cache: último PathDir con sprite ya volcado a VRAM ($FF = invalid) |
| `LastEntrySide` | variables_lo | 1 | Side por el que entró el player |
| `LastEntryCoord` | variables_lo | 1 | Coord aproximado del char entry |
| `MagicCompassBfsQueue` | $5B00 (bank 5) | 128 | 64 entries × 2 bytes (sid, comp) |
| `MagicCompassVisited` | $5B80 (bank 5) | 96 | Bitmap 768 bits (256 sids × 3 comps) |

Total RAM permanente: 12 B en variables_lo. Scratch: 224 B en el printer-buffer
area `$5B00..$5BDF` (declarados como `EQU` dentro de `magic_compass.asm`).

**Por qué $5B00 y no slot 1**: estos arrays vivían originalmente al final de
`magic_compass.asm` como `DEFS 128`/`DEFS 96`, lo que los colocaba en
`$795C..$7A3B`. Los últimos 60 bytes de `Visited` solapaban la tabla IM 2 de
`music_irq.asm` (`$7A00..$7B00`, todos los bytes a `$7B`). Cuando el BFS
inicializaba `Visited` con `LDIR`, machacaba `$7A00..$7A3B` con basura. En
hardware real funcionaba por accidente: durante IRQ ack el bus flotante pone
`$FF`, así que la CPU leía siempre `$FF` como vector low → `$7AFF/$7B00`
(zona intacta) → `$7B7B` → handler ok. Pero en emuladores cuyo data bus
puede tomar valores en `$00..$3B` durante IORQ+M1 (chips/zx.h sin parche,
posiblemente otros) saltaba a un vector basura y colgaba.

Reubicar al printer-buffer (`$5B00`, bank 5 always-on) elimina la mina: la
tabla IM 2 queda intacta post-LDIR. SAVETAP excluye `$5B00..$5DFF` así que
no añade peso al `.tap`/`.sna` (la región se inicializa por el BFS antes de
cada uso, no necesita preservar contenido entre cargas).

---

## 5. Algoritmo BFS reverse con componentes

```pseudo
// Inicialización
target_sid  = ResolveObjectiveScreen()
current_sid = current_screen
player_comp = comp_of_gap(current_sid, LastEntrySide, LastEntryCoord)
                                       (gap más cercano en coord, o 0 fallback)

queue.push((target_sid, 0))      // heurística: target_comp = 0
visited[(target_sid, 0)] = true

// Loop
while queue not empty:
    (R, R_comp) = queue.pop()
    for each gap (side, coord, gap_comp) in RoomCompGaps[R]:
        if gap_comp != R_comp: skip
        V = neighbor(R, side)
        if V out of bounds: skip
        // Resolver gap correspondiente en V
        opp_side = side XOR 1
        V_gap = find_gap(V, opp_side, coord)   // matching por coord
        if V_gap not found: skip
        V_comp = V_gap.comp
        if V == current_sid AND V_comp == player_comp:
            // ENCONTRADO. dir player = opposite(side).
            PathDir = side XOR 1
            return
        if visited[(V, V_comp)]: skip
        visited[(V, V_comp)] = true
        queue.push((V, V_comp))

// Sin path
PathDir = $FF
```

Coste runtime: ~3 ms peor caso (~10000 T-states). El BFS se ejecuta en dos
modos según el contexto:

- **Sincrónico** (`ForceComputeMagicCompassPath`): al cruzar un borde con
  magic activa, `CheckScreenTransition.doTransition` corre el BFS COMPLETO
  antes de que `DrawScreen` pinte la nueva sala. Garantiza que `PathDir`
  refleja la sala nueva antes de que pueda dispararse el primer tick AY de
  la nueva sala — sin esto, los primeros ticks parpadeaban apuntando a la
  dirección vieja durante 3-4 frames.
- **Amortizado** (chunks de `MAGIC_COMPASS_BFS_ITERS_PER_FRAME` = 8 iter
  por frame): cuando el player **recoge el pickup** estando ya en una
  sala, `ApplyMagicCompassBuff` setea `PathDirty=1` y `UpdateMagicCompass`
  arranca el BFS chunked. Aquí no hay urgencia (el primer tick suena 1 s
  después por el `TickCounter=TICK_NORMAL`), así que repartir los ~10K T-
  states en chunks de ~2500 evita un spike puntual.

`MagicCompassBfsState` (1 byte) marca si el BFS amortizado está en
progreso. El sync no necesita estado persistente — corre hasta el final
en una sola llamada via loop interno.

---

## 5b. HUD visual (sprite ID 36 / ID 37)

Mientras la brújula está activa **y** el target no es la sala actual, el
HUD compass se sustituye por uno de dos sprites según `MagicCompassPermanent`:

- `Sprite_Compass_Magic` (id **36**, "magic compass HUD") cuando la brújula
  viene del random pickup temporal (timer 30 s).
- `Sprite_Compass_MagicLasting` (id **37**, "compass lasting") cuando es la
  brújula mágica permanente que se obtiene al final de la cinemática de la
  iglesia (no expira).

Ambos son 16×16 px = 2×2 chars con la siguiente convención de **iluminación
diagonal**:

```
       col 1   col 2
row 1   W       N    ← top-left = W, top-right = N
row 2   S       E    ← bottom-left = S, bottom-right = E
```

PathDir → char activo:
- 0 (N) → (col 2, row 1) — esquina arriba-derecha
- 1 (S) → (col 1, row 2) — abajo-izquierda
- 2 (W) → (col 1, row 1) — arriba-izquierda
- 3 (E) → (col 2, row 2) — abajo-derecha

**Color base** del HUD: lo decide el editor (los `attrBytes` de cada sprite
en `bg_sprites.json`). El script `tools/import_magic_compass_hud.py` extrae
los 4 bytes de attrs de cada variante limpiando el bit 6 (BRIGHT) y los emite
en `MagicCompassBaseAttrs` (ID 36) y `MagicCompassLastingBaseAttrs` (ID 37).
`PaintMagicCompassAttrs` selecciona la tabla según `MagicCompassPermanent`.
Mientras el tick AY no suena, los 4 chars se pintan con esos attrs sin más.

**Flash sincronizado al tick auditivo:** mientras suena el tick (durante
`MAGIC_COMPASS_TICK_DURATION` = 2 frames), el char activo se sobreescribe a
`$47` (ink white + paper black + bright). Cuando el tick deja de sonar,
vuelve al attr base. Sincronía perfecta normal (1/s) y warning (2/s).

**Importante para el sprite design:** dado que el flash forza
`paper black + ink white`, los pixels del sprite se interpretan invertidos
si en el editor pintas paper distinto de black. Para que la silueta no se
"invierta" al activarse el flash, el char correspondiente a cada dirección
debe diseñarse en el editor con paper black. Si no quieres preocuparte de
esto, pinta los 4 chars con paper black + ink del color que prefieras.

### Optimizaciones contra flicker del reloj HUD

Investigación: el reloj HUD se redibuja entero cada frame
(`DrawClockHUD` → `DrawClockFaceOnly` + `DrawHandLine` × 2). Si el frame se
sale de presupuesto (más de 70 000 T-states), el raster del Spectrum puede
pasar por la zona del reloj entre la limpieza de la cara y el repintado de
las agujas, causando el efecto visible de "agujas parpadeando". Sin la
brújula mágica el budget tiene margen; con magic activa, el redibujo del
HUD compass + tick AY + BFS empujaba el frame por encima en transiciones
y, sobre todo, cuando el player choca verticalmente contra un BG sprite
(la lógica de step-up consume tiempo extra ese frame).

Optimizaciones aplicadas en `DrawCompass` y `magic_compass.asm`:

1. **Cache de sprite drawn** (`LastMagicCompassDrawn`). El sprite
   `Sprite_Compass_Magic` siempre es el mismo; sólo se re-vuelca a VRAM
   cuando `PathDir` cambia. El resto de frames basta con repintar 4 attrs.
   Ahorro: ~470 T-states/frame.
2. **Skip del wobble en magic mode.** El wobble (oscilación de 9 frames
   post-transición del HUD compass clásico) es invisible en magic
   (siempre se dibuja el mismo sprite). Se fuerza `CompassWobbleCounter=0`
   en cuanto se detecta magic activa. Ahorro: ~150 T-states/frame durante
   los 9 frames post-transición.
3. **Invalidación de cache al cambiar de sala.** En `.dcRedrawNewScreen`,
   `LastMagicCompassDrawn = $FF`. Si por casualidad el nuevo `PathDir`
   coincide con el anterior, igualmente forzamos un re-vuelco — `DrawScreen`
   pudo haber pisado los pixels del HUD durante la carga de la nueva sala.
   Sin esto, el sprite a veces no se mostraba al entrar en sala.
4. **BFS amortizado para pickups** (`MagicCompassBfsState` +
   `.cmcpItersLeft`). Cuando recoges el pickup compass estando ya en una
   sala (no cruzando borde), el BFS arranca via `PathDirty=1` y se reparte
   en chunks de 8 iter/frame ~2500 T-states cada uno, distribuidos en
   3-4 frames. Evita un spike puntual en el frame del pickup. **Para
   cruces de sala no aplica** — esos usan el sync de `.doTransition`
   (ver §5), que paga ~10K T-states de golpe pero garantiza que el primer
   tick visible de la nueva sala muestre la flecha correcta.
5. **Abort del BFS pickup en cambio de sala**
   (`ForceComputeMagicCompassPath` setea `BfsState=0` antes de su loop).
   Si recoges el pickup en una sala y cruzas borde antes de que el BFS
   amortizado termine, sus datos (current_sid, comps, queue) serían stale.
   El sync que arranca en `.doTransition` los descarta y reinicia desde
   cero con el nuevo `current_sid`.

Resultado: el flicker ya no es reproducible en juego.

---

## 6. Archivos del feature

| Archivo | Rol |
|---|---|
| `tools/build_screen_gaps.py` | Genera `room_routes.asm` con info per-gap+comp. |
| `tools/import_magic_compass_hud.py` | Sincroniza sprites ID 36 (temporal) e ID 37 (permanente) desde `bg_sprites.json` a `code/sprite_magic_compass_hud.inc`. Idempotente. Llamado desde los `.bat` de build. |
| `tools/inject_pickup_sprites.py` | Inyecta `BgGfx_pickup_compass` (id 34) en `bg_gfx.asm` si falta. |
| `code/magic_compass.asm` | Apply/Cancel/Update + jingle + tick AY + BFS (sync via `ForceComputeMagicCompassPath`, amortizado para pickups) + `PaintMagicCompassAttrs` + `INCLUDE` del .inc. Vive en slot 1. |
| `code/room_routes.asm` | Auto-generado. `RoomCompGapsTable` + records. Slot 1. |
| `code/sprite_magic_compass_hud.inc` | Auto-generado. `Sprite_Compass_Magic` + `MagicCompassBaseAttrs` (ID 36, temporal) y `Sprite_Compass_MagicLasting` + `MagicCompassLastingBaseAttrs` (ID 37, permanente), 32 + 4 bytes cada variante. Incluido desde `magic_compass.asm`. |
| `code/variables_lo.asm` | Estado runtime + alias scratch. |
| `code/main.asm` | Init defaults en `Inicio`, `CALL UpdateMagicCompass` en MainLoop. |
| `code/milestones.asm` | `DrawCompass` con dispatch a Sprite_Compass_Magic + `PaintMagicCompassAttrs` cuando magic activa, cache de sprite, skip wobble. Hooks `CancelMagicCompass` en avance de hito. |
| `code/screen_system.asm` | Tracking de `LastEntrySide` + `LastEntryCoord` en `CheckScreenTransition`. `CALL ForceComputeMagicCompassPath` en `.doTransition` para sync del BFS antes de `DrawScreen`. Dispatch de `ApplyMagicCompassBuff` en `CheckPickupCollect`. |
| `code/random_pickups.asm` | `ROUL_COMPASS = 7`, ruleta + roll directo + dispatch en `CheckRandomSyntheticPickup`. |
| `code/logic_game.asm` | Hook `CancelMagicCompass` al inicio de `OnPlayerHealthDepleted`. |
| `code/constants.asm` | `MAGIC_COMPASS_*` constantes (timer, tick, BFS chunks, active attr). |
| `code/bg_gfx.asm` | Sprite `BgGfx_pickup_compass` (id 34, inyectado por `inject_pickup_sprites.py`). |
| `code/build_and_*.bat` | Invocan `import_magic_compass_hud.py` antes del compilado, junto a los demás scripts de pipeline. |

---

## 7. Lo que es completamente dinámico

Una vez modificado el nivel desde el editor (Export ASM + rebuild):

- ✅ Mover un pickup de hito a otra sala — `ResolveObjectiveScreen` lo detecta y el BFS arranca con el target nuevo.
- ✅ Cambiar paredes internas o añadir obstáculos — `connected_components` recalcula y `RoomCompGapsTable` se regenera.
- ✅ Añadir/quitar/conectar salas (cambios en `MapTable`) — el grafo se reconstruye automáticamente.
- ✅ Mover el sprite del pickup compass — auto-detectado por el dispatch en pickup collect (busca por ptr).

**No automático** (edición manual en código):

- ⚠️ Cadena de hitos — `MilestoneTable` + `MilestoneResolveTable` en `milestones.asm`.
- ⚠️ Si el pickup de un hito vive en una comp que **no es la principal** de su sala, el BFS asume `target_comp = 0` y el path lo lleva a la zona equivocada de la sala destino. Solución: poner el pickup en suelo abierto (lo normal).

---

## 8. Decisiones de diseño no obvias

1. **¿Por qué BFS reverse y no forward?** Reverse desde target permite no
   tener que tracker "first-direction-from-current" en cada nodo expandido —
   la dir se deriva del último step antes de tocar `current`.

2. **¿Por qué scratch en slot 1 y no en bank 2?** Bank 2 estaba al límite
   (~10 B libres) cuando empezamos. Slot 1 ($6000-$7FFF) tenía ~5 KB libres.
   Las helpers del BFS no tienen problema de paginación porque
   `RoomCompGapsTable` también vive en slot 1.

3. **¿Por qué no usar el char-level BFS del editor en runtime?** Sería
   demasiado caro (Z80 a 3.5 MHz no procesa 32×22 grid en tiempo razonable).
   Aproximamos con BFS sala-a-sala + componentes, que da el mismo resultado
   en el 100 % de casos prácticos del nivel actual.

4. **¿Por qué no exportar una tabla precomputada `next_dir[milestone][sala]`?**
   Sería 9 × 256 = 2304 B de tabla, comparado con los ~3 KB actuales.
   Diferencia mínima, pero requeriría cada-rebuild rerun el BFS para todos
   los pares y cargar la lógica de targets en Python. Más frágil ante
   cambios futuros.

5. **`LastEntryCoord` distancia, no exacta** — usamos "gap más cercano al
   coord del player" en vez de matching exacto, porque el player no entra
   exactamente en el midpoint del gap. Es una heurística de tolerancia que
   funciona porque los gaps están bien separados.

---

## 9. Cómo verificar / debuggear

### Activar modo dev rápido

En `constants.asm`:

```asm
DEBUG_NO_ENEMIES    EQU 1   ; sin nasties molestando
DEBUG_FORCE_COMPASS EQU 1   ; cualquier random pickup → compass
```

Cualquier pickup en la ruleta saldrá compass. Recógelo en cualquier sala y
verifica la dir.

### Inspeccionar la tabla generada

```bash
grep -A 6 "RoomCompGaps_C5" code/room_routes.asm
```

Para sala (5,12) (sid 197 = $C5 en hex Y=12, X=5):

```
RoomCompGaps_C5:
    DEFB 4
    DEFB $04, 15    ; N @ 15 comp 1
    DEFB $01, 15    ; S @ 15 comp 0
    DEFB $07, 3     ; E @ 3  comp 1
    DEFB $03, 11    ; E @ 11 comp 0
```

Lectura: la sala tiene 4 gaps, en 2 componentes desconectadas internamente.
El BFS sólo cruzará un gap si comparte comp con el side por el que entraste.
