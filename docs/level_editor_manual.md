# Manual del Level Editor

Editor visual del juego (`tools/level_editor.html`). Se abre con doble-click en
el .html — usa **File System Access API**, así que pide elegir la carpeta
`code/` del juego una vez por sesión y luego trabaja directamente sobre disco.

---

## 1. Quick start

1. Doble-click en `tools/level_editor.html` (abre en el navegador).
2. Aparece un modal pidiéndote la carpeta del juego → **Seleccionar directorio
   `code/`**. Concede permiso de lectura/escritura.
3. Si los sprites se ven en blanco: pulsa **Load BG Data** (carga
   `code/bg_sprites.json`). Solo necesario la primera vez o tras pegar otro
   `bg_sprites.json` por encima.
4. Click en cualquier room del mapa para empezar a editar.
5. Cuando hayas hecho cambios, **Save** (guarda `level_data.json`) y
   **Export ASM** (genera `screen_data.asm` y `bg_gfx.asm` que el juego compila).
6. Para verlo en marcha: **🚀 MAGIC PLAY** (Spectaculator) o
   **🎯 MAGIC TRACK** (ZEsarUX + tracker en vivo).

---

## 2. Mapa mental (conceptos)

```
Map (16x16 rooms)
   └─ cada celda apunta a un Template (índice 1..255, 0 = vacío)

Template
   ├─ placements: lista de sprites BG colocados (id, x, y, tint)
   ├─ autoFillPlacements: sprites generados automáticamente (bordes biome)
   └─ ligado opcionalmente a una entrada del Library
        (autoLibraryIdx + autoLibrarySig)

Library (template_library.json)
   └─ entradas reusables. Si editas un template ligado a la library,
      todos sus "siblings" (mismo idx en otras rooms) se actualizan.

Variantes
   └─ varias library entries con misma signature de conexiones; permiten
      tener N versiones intercambiables de un room (Forest v1, v2, v3…).
      V key = ciclar variante en el placement seleccionado.

Biome
   └─ propiedad de cada room. Determina qué sprites de auto-fill se usan
      en los bordes y cómo se grupea visualmente.

Saved Routes
   └─ rutas nombradas (origen → destino) sobre el char-level walk grid.
      Usa BFS para validar conectividad y avisa si rompes una ruta.

Placement vs Object
   └─ Por defecto, los sprites están en el TEMPLATE (todas las rooms con
      ese template los heredan). En modo OBJECTS, se colocan por celda
      individual (cellOverlays).
```

---

## 3. Toolbar (botones del header)

### Persistencia / disco
| Botón | Qué hace |
|---|---|
| **Set Game Dir** | Elige carpeta `code/`. Necesario antes de Save / Load / Export / Import. |
| **Save** | Guarda a `level_data.json` (auto-backup en `level_backup.json`). |
| **Load** | Carga `level_data.json` desde disco. |
| **Restore Backup** | Restaura `level_backup.json` (versión previa al último Save). |
| **Export ASM** | Genera `screen_data.asm` + `bg_gfx.asm`. Esto es lo que el juego compila. |
| **Import ASM** | Reconstruye el estado del editor leyendo los `.asm`. Útil tras `git restore`. |
| **Clear Cell** | Borra la room actualmente seleccionada. |

### Build & play
| Botón | Qué hace |
|---|---|
| **🚀 MAGIC PLAY** | Export ASM + señal a `magic_watcher.ps1` → compila y lanza Spectaculator. |
| **🎯 MAGIC TRACK** | Export ASM + lanza ZEsarUX con tracker live (marcador rojo del player en el mapa) + ShaderGlass encima. **Toggle**: 2º click escribe stop trigger y mata todo. Botón se vuelve verde con datos frescos. |

### BG sprites
| Botón | Qué hace |
|---|---|
| **Export PNG** | Descarga PNG con todos los BG sprites en uso, etiquetados. Solo referencia. |
| **Load BG Data** | Carga `code/bg_sprites.json` (DB del BG editor). Necesario al inicio. |
| **Reset BG handle** | Olvida el handle. Próximo Load BG Data te pedirá el fichero. |

### Modos de edición
| Botón | Qué hace |
|---|---|
| **Player Start** | Activa modo "colocar spawn del jugador". Siguiente click en mapa lo coloca. |
| **Design Mode** | Click=crear room nueva con template auto-id, Ctrl+click=borrar. |
| **🌅 Day Cycle** | Cicla preview día/noche/amanecer (DY → C1 → C2 → N1 → N2 → A1 → A2). Solo visual. |

### Toggles de visualización (header derecha)
| Toggle | Qué hace |
|---|---|
| **GRID** | Líneas de la grid de tiles. |
| **SCANLINES** | Efecto CRT scanlines en el editor. |
| **MASK** | Efecto CRT shadow mask. |
| **BLUR** | Suavizado CRT (default ON). |
| **LAYOUT** | Cicla 4 modos: normal → silueta → silueta+outline → paths (BFS visual). |
| **ROOMS** | Muestra grid de rooms del mapa. |
| **SOLO** | Solo dibuja la room seleccionada (resto en negro). |
| **SHARED** | Marcos de colores: amarillo=siblings, paleta=variantes alternativas. |
| **OBJECTS** | Modo objetos por celda (no por template). Selector "Solid/Pickup". |
| **TRACK** | Activa polling de `_player_pos.json` y dibuja marcador rojo del player. |

---

## 4. Atajos de teclado y ratón

### Edición
| Atajo | Qué hace |
|---|---|
| **Click izq** sobre room | Selecciona room. |
| **Click izq** con sprite seleccionado | Coloca placement. |
| **Click derecho** sobre placement | Menú contextual (delete, send to back, etc.). |
| **Drag** sobre placement | Mueve el placement (mismo room o entre rooms). |
| **Ctrl+Z** | Undo (incluye toggle de passages). |
| **Ctrl+S** | Save. |
| **Ctrl+C / X / V** | Copiar / cortar / pegar room entera. |

### Variantes (con placement seleccionado)
| Atajo | Qué hace |
|---|---|
| **V** | Ciclar tint del placement (white → yellow → green → ...). |
| **Shift+V** | Ciclar variante de la library (alterna entre v1, v2, v3 con misma signature). |

### Debug
| Atajo | Qué hace |
|---|---|
| **N** | Toggle Noclip (en el juego). El editor solo lo expone vía export — el flag se mantiene en RAM. |
| **Esc** | Cierra menús / cancela selección. |

### Navegación / cámara
| Atajo | Qué hace |
|---|---|
| **Rueda ratón** | Zoom (alrededor del cursor). |
| **Ctrl + rueda** | También zoom. |
| **Drag con espacio** o **botón medio** | Pan de cámara. |

> **Tip:** la cámara, modo y room seleccionada se persisten en localStorage,
> así que F5 te deja exactamente donde estabas.

---

## 5. Flujos diarios

### Añadir una room nueva
1. Activa **Design Mode**.
2. Click en una celda vacía del mapa → crea template nuevo con id auto.
3. Desactiva Design Mode.
4. Selecciona la room → coloca sprites del palette izquierdo.
5. Si quieres reusarla: **Save current to Library** (le da nombre y signature).

### Marcar un passage entre rooms
1. Selecciona la room.
2. En el panel derecho, marca las direcciones (Top/Bottom/Left/Right) que tienen passage.
3. Save.

### Crear una variante de un room existente
1. Selecciona el room cuyo template está en library.
2. Pulsa **Create Variant** en el panel derecho.
3. Edita la copia: añade/quita/mueve sprites manteniendo las mismas conexiones.
4. Save to Library con nombre nuevo (ej. "Forest v2").
5. En cualquier room con esa misma signature, Shift+V cicla entre variantes.

### Lanzar tracker live (ver al player en el mapa)
1. **🎯 MAGIC TRACK** (lanza ZEsarUX + watcher Python).
2. El botón **TRACK** se activa solo y empieza a mostrar la posición.
3. Marker rojo aparece sobre la room donde está el player.
4. Indicador a la derecha del botón: `R(x,y) px(X,Y) gs=N` con valores en vivo.
5. 2º click en MAGIC TRACK = STOP (mata ZEsarUX + watcher + ShaderGlass).

### Crear una saved route (ruta nombrada)
1. En el panel derecho, panel de Routes → click **Pick origin** + click en mapa.
2. Click **Pick target** + click en mapa.
3. **Save current** con nombre.
4. Si en el futuro rompes la conectividad de esa ruta (cierras un passage,
   borras un room), te avisa con un modal antes de aplicar el cambio.

### Recuperar tras "la cagué guardando"
1. Si fue el último Save: **Restore Backup** (restaura `level_backup.json`).
2. Si los `.asm` están bien y el editor no: **Import ASM** reconstruye el editor
   leyendo `screen_data.asm` + `bg_gfx.asm`.

---

## 6. Troubleshooting

### El marker del tracker no aparece
- ¿Está **TRACK** verde? Si no, click.
- ¿Indicador a la derecha del botón dice `_player_pos.json no existe…`? El
  watcher Python no está corriendo. Lanza MAGIC TRACK otra vez.
- ¿Indicador en verde con `R(x,y) px(X,Y) gs=144` y nada cambia? Los addresses
  están desincronizados. Recompila (cualquier MAGIC) — el watcher relee
  `juego.map` al arrancar.

### El marker está desplazado
- Si está 16px abajo: revisa que `PLAYER_HUD_OFFSET_Y = 16` no se haya tocado
  (compensa el HUD del juego que el editor no renderiza).

### "F5 no respeta mi zoom/modo"
- localStorage debería persistirlo. Si no lo hace, abre DevTools → Application
  → Local Storage y borra `swLevelEditor_uiState` para empezar de cero.

### MAGIC TRACK no hace nada
1. ¿`magic_watcher.ps1` está corriendo? Es la pieza que detecta el trigger.
2. Si lo cambiaste recientemente, reinícialo (mátalo y vuélvelo a abrir — los
   cambios al .ps1 no se recogen en caliente).
3. Cambios al `.bat` o a `track_player.py` SÍ se recogen al siguiente click, no
   hace falta reiniciar nada.

### Los sprites del palette aparecen en blanco
- Pulsa **Load BG Data** y selecciona `code/bg_sprites.json`.

### "Cannot read directory" tras cambiar de carpeta
- F5 al editor. La FS API a veces invalida el handle al renombrar carpetas
  padre.

### El botón TRACK se queda rojo cuando ZEsarUX está cerrado
- El botón se autoevalúa cada segundo. Si pasan >5s sin JSON nuevo vuelve a
  teal automáticamente. Si no, mata el `python.exe` huérfano que sigue
  reintentando conectar.

### "Auto-library: rojo desync"
- Indica que el placement local no coincide con la entrada del library
  (alguien editó uno y no propagó). Click derecho sobre el room → "Resync
  from library" (o edita la library entry para que tome esto como referencia).

---

## Archivos relacionados

| Archivo | Descripción |
|---|---|
| `tools/level_editor.html` | El editor (single-file). |
| `code/level_data.json` | Estado del mapa serializado. |
| `code/level_backup.json` | Backup automático antes de cada Save. |
| `code/template_library.json` | Library de templates reusables. |
| `code/bg_sprites.json` | DB de BG sprites (compartido con BG editor). |
| `code/screen_data.asm` | Output: rooms compiladas para sjasmplus. |
| `code/bg_gfx.asm` | Output: gráficos BG en banks 3+4. |
| `code/_player_pos.json` | Output del tracker (gitignored). |
| `code/_magic_run.json` / `_magic_zesarux.json` / `_magic_zesarux_stop.json` | Triggers (gitignored). |
| `tools/track_player.py` | Watcher ZRCP → JSON. |
| `tools/launch_zesarux.ps1` | Launcher con foreground + cursor + ShaderGlass. |
| `tools/zesarux.sgp` | Profile de ShaderGlass para el shader CRT. |
| `code/magic_watcher.ps1` | Detecta triggers y dispara los .bat. |
| `code/build_and_spectaculator.bat` | Build → Spectaculator. |
| `code/build_and_zesarux.bat` | Build → ZEsarUX (con ZRCP + tracker + ShaderGlass). |
