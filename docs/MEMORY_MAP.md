# Memory Map — visualización de RAM/ROM en vivo

Mapa interactivo de la memoria del Spectrum 128 que muestra, después de cada
build, qué hay en cada bank físico y cómo encajan los slots lógicos de la CPU.
Pensado para razonar sobre el plan de optimización RAM (Phase B/C/D), detectar
overflows, ver de un vistazo cuánto sitio queda libre por bank y dónde vive cada
sistema.

## Arquitectura

```
┌────────────────────────────────────────────────────────────┐
│ tools/memory_map.py             (parser .sld → modelo)     │
│ tools/memory_map_serve.py       (mini servidor stdlib)     │
│ tools/memory_map_template.html  (UI autocontenida)         │
│ tools/memory_map.bat            (lanzador idempotente)     │
└────────────────────────────────────────────────────────────┘
        │
        ▼
http://localhost:8765/        ← Chrome abre aquí
        │
        │  GET /data           ← reparseado en cada petición
        ▼
NuevoJuego.sld + code/build_stats.json
```

* **`memory_map.py`** parsea `NuevoJuego.sld` (formato Source Level Debugging
  de sjasmplus, con `bank` explícito por símbolo) y combina con
  `code/build_stats.json` (used/free por bank desde DISPLAY). Agrupa labels
  consecutivos del mismo `.asm` en "regiones" coloreadas.
* **`memory_map_serve.py`** expone `/data` que reparsea on-demand. El botón
  *Refrescar* del HTML lo llama y re-renderiza sin recargar la página
  (preserva scroll, sistema seleccionado, búsqueda).
* **`memory_map.bat`** chequea con un TCP probe si el server ya está vivo en
  `127.0.0.1:8765`. Si responde, sólo abre Chrome. Si no, lanza
  `pythonw.exe memory_map_serve.py` en background y abre Chrome cuando el
  puerto responde. Es **idempotente**: pulsa Ctrl+F7 las veces que quieras.

## Usar

### Doble-click

`tools/memory_map.bat` → arranca server + abre Chrome. La pestaña de Chrome
se queda abierta indefinidamente; cualquier pulsación posterior del .bat sólo
trae la pestaña al frente.

### Desde VS Code (Ctrl+F7)

La task **"Abrir Mapa de Memoria"** ya está en `.vscode/tasks.json`. Para
bindarla a `Ctrl+F7`, edita tu `keybindings.json` user-level
(`Ctrl+Shift+P` → *Preferences: Open Keyboard Shortcuts (JSON)*) y añade:

```json
{
  "key": "ctrl+f7",
  "command": "workbench.action.tasks.runTask",
  "args": "Abrir Mapa de Memoria"
}
```

> **Nota:** la combinación más obvia, `Shift+F7`, **colisiona** con un binding
> por defecto de VS Code (navegación de markers/cambios) y aunque tu binding
> custom debería tener precedencia, en la práctica el default gana en algunos
> contextos. `Ctrl+F7` está libre y funciona limpio. Si en tu setup también
> colisionara, prueba `Ctrl+Alt+M`, `Alt+F7` o `Ctrl+Alt+Shift+M`.

Si tienes ya un binding para `F7` que abre los editores, este vive aparte.

### Refrescar tras un build

Después de cada `Compilar y Jugar` (F7 actual), pulsa el botón **↻ Refrescar**
en la página. Lee el `.sld` y `build_stats.json` recién generados y actualiza
las regiones in-place. El sistema seleccionado, la búsqueda y el scroll se
preservan.

## Interfaz

* **Banner superior**: los 4 slots lógicos de la CPU. Slot 0 = ROM,
  slots 1-2 = banks fijos (5 y 2), slot 3 = paginable entre 0/1/3/4/6/7.
* **Cuerpo**: 8 columnas verticales = los 8 banks físicos de 16 KB. Altura
  proporcional a bytes. Cada región coloreada por sistema.
* **Tooltip al pasar**: nombre del sistema, rango `$XXXX-$YYYY`, tamaño,
  ficheros origen, lista completa de labels (top-level).
* **Click en una región o en la leyenda** → resalta ese sistema across todos
  los banks (lo demás se atenúa). Doble-click en cualquier sitio o
  *Quitar filtro* lo limpia.
* **"Sólo libre"** → resalta huecos `_FREE_` en todos los banks. Útil para
  ver de un vistazo dónde queda sitio.
* **Búsqueda** en la leyenda filtra por nombre de sistema.
* **% por bank** en cabecera: verde <75%, ámbar 75-90%, rojo >=90%.

## Sistemas

La agrupación es **automática por nombre del fichero `.asm`**, con algunas
fusiones explícitas en `EXPLICIT_SYSTEMS` (memory_map.py):

| sistema           | ficheros                                                    |
|-------------------|-------------------------------------------------------------|
| `audio`           | `ay_sound`, `ay_sound_thunks`, `sfx_player_hit_ay`, `sound`, `music_irq` |
| `bg_gfx`          | `bg_gfx`, `bg_gfx_b`, `bg_gfx_c`                           |
| `monster_ai`      | `monster_ai`, `monster_ai_bank6`                            |
| `room_routes`     | `room_routes`, `room_routes_bank7`                          |
| `screen_layout`   | `screen_data`, `screen_gaps`, `screen_rooms`, `screen_system` |
| `cutscenes`       | `town_gate_cutscene`, `church_cutscene`                     |
| `game_over`       | `game_over_tomb`, `game_over_tomb_thunk`                    |
| `variables`       | `variables`, `variables_lo`                                 |
| (resto)           | nombre del .asm tal cual                                    |

Sistemas sintéticos (zonas hardcoded del Spectrum o del juego que no aparecen
como labels colocados en `.sld`):

* `_screen_` — VRAM ($4000-$57FF) + attrs ($5800-$5AFF) en bank 5.
* `_sys128_` — Área del sistema 128K ($5B00-$5CFF) en bank 5.
* `_reserved_` — Tombstones runtime ($E000-$E7FF) en bank 7.
* `_FREE_` — Huecos de RAM no usada (rayado diagonal).

Para refinar agrupaciones, editar `EXPLICIT_SYSTEMS` en
`tools/memory_map.py`. Para añadir/cambiar zonas hardcoded, editar
`HARDCODED_ZONES` en el mismo fichero.

## v2 — funcionalidades añadidas

### Marcadores especiales

Líneas críticas dibujadas sobre las columnas de bank, en tres severidades:

| severidad | aspecto | usos                                                       |
|-----------|---------|------------------------------------------------------------|
| **danger** | rojo dashed con glow | Canary slot 1 a `$7FFF` en bank 5 — si una etiqueta esperada en bank 5 cae más allá, ha desbordado al slot 2. |
| **warn**   | ámbar dashed | Boundary blanda. Bank 7 a `$E000` y `$E7FF` (zona reservada para tombstones runtime). |
| **info / landmark** | blanco punteado | Entry points conocidos (`Inicio`, `MainLoop`, `LoadBgSpriteToBuffer`, `AY_PlayPlayerHit`, `RoomCompGapsTable`, `DrawTombstone2xCentered`, ...). Lista canónica en `LANDMARK_LABELS` (memory_map.py). Sincroniza con `SLOT1_ENTRY_POINTS` de `check_slot_overlap.py`. |

Toggle **📌 Landmarks** en la leyenda esconde los info markers cuando estorben.

### Diff entre snapshots

Botón **📸 Snapshot** congela un baseline (resumen por sistema y bank,
guardado en `tools/.memory_map_snapshot.json`, gitignored). A partir de ahí:

* Cada bank header muestra Δ used vs baseline (`+180 B`, `−45 B`).
* Cada item de la leyenda muestra Δ por sistema.
* Banner ámbar superior con el snapshot ts y el Δ total.
* Sistemas que **desaparecieron** desde el snapshot aparecen tachados con
  Δ negativo, etiquetados "eliminado".

Botón **🗑 Descartar** elimina el baseline y vuelve al modo sin diff.

### Zoom por bank

**Click en cualquier bank header** (o en el row de label) abre un modal con:

* Columna del bank ampliada con address ruler `$200` (512 B por tick).
* Cada región muestra **labels inline** (no sólo en hover tooltip).
* Panel derecho con tres bloques:
  * Lista ordenada de regiones con direcciones.
  * Lista de marcadores con descripción larga y dirección.
  * Stats agregadas: cuánto ocupa cada sistema en este bank, ordenado.

Cerrar con `ESC`, click fuera del modal, o el botón × Cerrar.

### Auto-refresh (Server-Sent Events)

Botón **🟢 Auto / ⚪ Auto** en el header. Cuando está activo (estado por
defecto, persistido en `localStorage`):

* La página abre un canal SSE permanente al endpoint `/events`.
* El server tiene un thread watcher que mira `mtime` de `NuevoJuego.sld` y
  `code/build_stats.json` cada 1.5 s.
* Cuando alguno cambia (porque sjasmplus terminó un build), emite un evento
  `refresh` a todos los suscriptores. La página llama a `/data` y
  re-renderiza in-place — preserva scroll, sistema seleccionado, baseline,
  estado del modal.
* Heartbeat `: ping` cada 15 s para mantener viva la conexión.
* El botón Refrescar pulsa con un anillo verde cuando el refresh fue
  auto-disparado, para feedback visual.

Toggle a "off" si quieres congelar la vista durante una inspección sin que
te interrumpa el siguiente build.

## v3 — call graph, heat, dead code, move cost

Análisis estático del código que convierte el mapa en herramienta de
planificación accionable para Phase B/C/D del plan RAM.

### Heat overlay 🔥

Toggle **🔥 Heat** en la leyenda. Cada región se recolorea según el nivel
de calor del label más caliente que contenga:

| Color | Nivel | Significado |
|-------|-------|-------------|
| 🔴 rojo brillante | **lava** | Reachable desde `MainLoop` o `MusicIrqHandler` con depth ≤ 2 — ejecuta a 50 Hz, NO meterle thunks. |
| 🟧 naranja        | **warm** | Reachable con depth 3-5 — frecuencia media. |
| 🔵 azul           | **cool** | Reachable con depth ≥ 6 — raramente. |
| 🟪 violeta        | **init** | Sólo reachable desde `Inicio` — una vez por partida. Mover es virtually free. |
| ⬛ rayado rojo    | **dead** | NO reachable de ningún entry point — candidato a borrar. |
| 🔘 atenuado       | **none** | Zona sintética (screen, sys128, free) o sin info de calor. |

El cálculo es BFS estático sobre el grafo de llamadas `CALL/JP/JR` parseado
de los .asm + el .sld. Sin profiling runtime — los entry points conocidos
del juego (`MainLoop`, `MusicIrqHandler`, `Inicio`) sirven de raíces.

### Dead code highlight 💀

Toggle **💀 Dead**. Resalta las regiones con código muerto detectado y
atenúa el resto. Bordes rojos + chip "💀 dead". El dead code aparece cuando
un label:

1. Existe en el .sld con bank real (no es EQU constante).
2. NO es reachable desde ningún entry point por el call graph.
3. NO aparece en NINGÚN otro sitio en los .asm fuera de su línea de
   definición (filtro conservador para evitar falsos positivos por
   referencias-como-dato `LD HL, table` o `DEFW table`).

Bytes liberables sin riesgo. Ideal para arrancar Phase B con quick wins
antes de mudanzas complicadas.

### Move analyzer (en el modal de zoom)

Click en un bank header → abre modal con el bank ampliado. Al final del
panel derecho aparece la sección **🚚 Move analyzer**:

1. Selecciona un sistema del bank (dropdown).
2. Selecciona un bank destino.
3. Click "Calcular".
4. Resultado: nuevos thunks necesarios, call sites afectados, thunks que
   dejan de hacer falta (al mover hacia slot 1/2 desaparecen overheads),
   thunks persistentes (que ya cruzaban antes), bytes Δ estimados.
5. Desglose por target label: cuántas call sites tendría cada thunk
   nuevo. Guía qué labels son "el cuello de botella" del coste del move.

La regla del thunk usada por el simulador: **se necesita thunk para target T
si T está en slot 3 (banks 0/1/3/4/6/7) Y el caller no está en el mismo
bank que T**. Targets en slot 1 (B5) o slot 2 (B2) son siempre visibles
desde cualquier sitio y NO requieren thunk. Cada thunk se cuenta una vez
por target label (no por call site).

### CLI v3 (para Claude / análisis programático)

Toda la información del análisis es accesible vía CLI sin abrir el HTML:

```bash
python tools/memory_map.py --callgraph              # grafo completo (JSON)
python tools/memory_map.py --callers MainLoop       # quién llama a X
python tools/memory_map.py --callees MainLoop       # a quién llama X
python tools/memory_map.py --heat                   # heat por label
python tools/memory_map.py --dead                   # dead code list
python tools/memory_map.py --cohesion               # tabla cohesión
python tools/memory_map.py --movecost magic_compass --from 5 --to 7
```

Y como librería:

```python
import sys; sys.path.insert(0, "tools")
from memory_map import (build_call_graph, propagate_heat,
                         find_dead_code, cohesion_per_system, simulate_move)

g = build_call_graph()
heat = propagate_heat(g)
dead = find_dead_code(g)
move = simulate_move(g, "screen_layout", from_bank=0, to_bank=7)
```

### Endpoints HTTP del server

```
GET  /callgraph     → grafo completo
GET  /heat          → {label: {level, runtime_depth, ...}}
GET  /dead          → {count, dead: [{label, bank, file, line, addr}]}
GET  /cohesion      → {system: {internal, incoming, outgoing, cohesion_pct}}
POST /movecost      → body {system, from_bank, to_bank}
```

El call graph se parsea una vez al primer fetch y se cachea hasta que el
mtime del .sld cambia. Subsiguientes peticiones devuelven en ms.

### Limitación honesta del análisis

El parser detecta CALL/JP/JR estáticos a labels nombrados. Lo que NO ve:

* **Indirectos** (`JP (HL)`, `CALL (IX+0)`, jump tables). En la práctica ~99%
  de las llamadas en este juego son estáticas, pero las jump tables del
  monster_ai dispatcher u otras pueden hacer que ciertas funciones aparezcan
  como "dead" cuando en realidad sí se llaman.
* **Macros que expanden a CALL**. En este juego `macros.asm` sólo tiene
  aritmética sin CALLs, así que no es problema. Si en el futuro añades
  macros con CALL embebido, marcarán como unresolved (visibles en
  `unresolved_count` del callgraph).

La tasa de resolución actual está en el `--callgraph` (~99.87% en este
proyecto). Si baja por algún cambio, conviene investigar.

## Pendientes para v4 (cuando aparezcan necesidades)

* **Diff visual sobre regiones**: overlay rojo/verde encima de las regiones
  cambiadas (no sólo deltas numéricos en headers).
* **Anotaciones manuales** persistidas a JSON local ("candidato Phase C").
* **Histórico de snapshots** (no sólo 1 baseline).
* **Auto-ejecutar `--dead` tras cada build** y notificar al usuario por SSE
  si aparece código muerto nuevo (regresión de refactor).

## Troubleshooting

* **"Error cargando /data"** en el HTML → el servidor no está arrancado.
  Lanza `tools/memory_map.bat`.
* **Puerto 8765 ocupado por otro proceso** → cambia `set PORT=8765` al inicio
  del .bat y `--port` en cualquier integración.
* **Ventana de consola Python visible** → asegurarse de que `pythonw.exe`
  está en PATH (no `python.exe`). El .bat hace fallback automático.
* **Símbolos faltantes** ("no veo X.asm en ningún bank") → comprobar que el
  fichero se ensambla (busca `+used` en el `.sld`). Constantes EQU sin uso
  no aparecen en el `.sld` con bank explícito por diseño.
