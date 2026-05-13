# Sprite workflow — cómo no perder trabajo entre los editores

Hay **4 fuentes de verdad** que almacenan los sprites. Si divergen, el editor
mostrará algo y el juego compilará otra cosa. Esta guía explica el flujo
correcto para mantenerlas en sync.

## Las 4 capas

```
┌──────────────────────────┐  ┌──────────────────────────┐
│ BG editor (Chrome IDB)   │  │ Level editor (Chrome IDB)│
│ BgEditorDB               │  │ SWLevelEditor            │
│  · Sprites pixeles/attrs │  │  · MISMOS sprites cache  │
│  · Borradores también    │  │  · + placements en salas │
└────────────┬─────────────┘  └────────────┬─────────────┘
             │ Export All BG               │ Export ASM
             ↓                             ↓
┌──────────────────────────┐  ┌──────────────────────────┐
│ code/bg_sprites.json     │  │ code/bg_gfx*.asm         │
│ Snapshot a disco         │  │ Lo que come sjasmplus    │
│  · TODO incluyendo       │  │  · Solo sprites en uso   │
│    borradores            │  │    (placed o CODE_REF)   │
└──────────────────────────┘  └──────────────────────────┘
```

## Reglas para no perder trabajo

### 1. **Después de cualquier sesión en el BG editor → Export All BG**

Por defecto el BG editor solo guarda en su IDB del navegador. Si cierras
la pestaña sin Export, los cambios solo viven ahí. Cualquier cosa
(cache clear, otro navegador, modo incógnito accidental) los pierde.

**Botón Export All BG** escribe `bg_sprites.json` a disco. Es tu único
punto de salvado fuera del navegador.

### 2. **Antes de cualquier sesión en el level editor → Load BG Data**

El level editor tiene SU PROPIA IDB con cache de sprites. Si dibujas en
BG editor y luego abres level editor sin "Load BG Data", el level editor
ve su versión antigua de los sprites — y al colocarlos en salas (o al
Export ASM) propaga esa versión antigua a `bg_gfx*.asm`. **Causa
principal del drift histórico.**

**Botón Load BG Data** en el level editor lee `bg_sprites.json` y
refresca su cache. Hazlo SIEMPRE al abrir el level editor si has
tocado sprites en BG editor desde la última vez.

### 3. **Después de cualquier export del level editor → comprobar JSON**

`Export ASM` reescribe `bg_gfx*.asm` con los sprites en uso. NO toca
`bg_sprites.json`. Si has cambiado sprites desde el BG editor entremedias,
JSON y ASM pueden diferir.

`tools/sync_bg_pickups.py` corre automáticamente en cada build para
sincronizar los **sprites code-referenced** (pickups, llaves, etc) de
JSON hacia ASM. Para sprites placed-only-in-rooms el sync no aplica —
te fías de que Load BG Data se hizo antes.

## Recovery: cuando algo se desincroniza

### Síntoma A: el BG editor muestra sprites viejos

- IDB del navegador quedó desfasada o se vació.
- **Solución**: pulsa **Load BG JSON** en el BG editor para refrescar la IDB desde `bg_sprites.json`.

### Síntoma B: `bg_sprites.json` no tiene los últimos cambios (ASM sí los tiene)

- Pasó porque modificaste sprites vía level editor (que escribe ASM) sin pasar después por BG editor → Export All BG.
- **Solución**: script ad-hoc en Python que parsea bg_gfx*.asm y resync entradas específicas en bg_sprites.json (ver historial del git, commit `e850cfd` como ejemplo: resync forest sprites).

### Síntoma C: pérdida de cualquier estado

- **Backups automáticos**: cada `build_and_*.bat` ejecuta `tools/backup_bg_sprites.py` que crea `code/backups/bg_sprites.YYYYMMDD-HHMMSS.json`. Rota a max 30 snapshots.
- Si pierdes algo, mira en `code/backups/` y restaura el más reciente válido.

## Resumen de comandos / botones

| Acción | Dónde | Cuándo |
|--------|-------|--------|
| **Export All BG** | BG editor (botón) | Al cerrar sesión de dibujo |
| **Load BG JSON** | BG editor (botón) | Si el editor abre con datos viejos |
| **Load BG Data** | Level editor (botón) | ⭐ SIEMPRE al abrir el level editor |
| **Export ASM** | Level editor (botón) | Al terminar de colocar / editar salas |
| `python tools/sync_bg_pickups.py` | CLI | Manual; ya corre en cada build |
| `python tools/backup_bg_sprites.py` | CLI | Manual; ya corre en cada build |
| `code/backups/bg_sprites.*.json` | Filesystem | Recovery último cartucho |
