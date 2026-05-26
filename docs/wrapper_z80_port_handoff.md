# Handoff — desktop wrapper + propuesta de port a Z80

Fecha: 2026-05-26.
Para: próxima sesión que retome el wrapper o el port a Z80.

## Estado actual del desktop wrapper (commit `fb6fc73` en `main`)

Ubicación: `port/` (CMake + SDL2 + chips/zx + ayumi).
Binario: `tharkys.exe` (raíz + `dist/`). Embebe `juego_release.tap` y arranca por defecto vía LD-BYTES trap.

### Pipeline de boot (post-este último merge)

1. **Card 0 "JayDroid Presents"** (3 s). Pantalla negra + texto centrado multi-line.
2. **Card 1 "A Sinclair ZX Spectrum 128 K computer game"** (3 s). Igual layout.
3. **Card 2 bg-257 wrapper splash** (4.5 s). Calibrado para que EndGame suene hasta ~bar 3 antes del menu.
4. **Menú idioma** (3 opciones: English / Español / Skip story, navegación no-cíclica).
5. **Historia bilingüe** (6 páginas, manual advance, indicador con iconos animados del juego visibles bajo el texto vía `help_preserve_rect`).
6. **Game splash** (icons animados, SplashWait del juego).

### Características clave

- **Audio mute durante cards 0/1**, emu pausado tras TURBO precharge. Unmute + ayumi reset al entrar card 2 → primera nota EndGame audible justo cuando aparece bg-257.
- **Skip por cualquier control** (kbd / botones / stick / triggers) con release-gate por card: una pulsación = una transición. Imposible cascada.
- **Tape trap** en `rom[1][$0556]` (LD-BYTES) que vuelca bloques directamente a memoria.
- **Font reward** (Damien Guard, ZX Origins) + 12 glyphs custom para acentos españoles (á é í ó ú Á É Í Ó Ú ñ Ñ), codepoints 0x80-0x8B. UTF-8 en source se convierte a codepoints compactos al cargar páginas ES.
- **Distribución**: `dist/tharkys.exe` + `dist/LICENSES.txt` + `dist/README.txt`. Font reward inlinead como `DEFB` statements en `code/reward_font_data.inc` (NO se redistribuye el `.ch8` raw como font file).

### Archivos relevantes del wrapper

- `port/src/main.c` — orquesta todo. State machine de los 3-card splash, language menu, story, input handling, audio mute/unmute lifecycle.
- `port/src/emu.c` — chips/zx wrapper, ayumi integration, tape trap, `emu_set_audio_processing`, `emu_audio_warmup_reset`, `emu_ay_regs`.
- `port/src/video.c` — OpenGL CRT shader, font overlays (`video_upload_centered_text`, `video_set_help`, `video_set_help_preserve_rect`).
- `port/src/gamepad.c` — `gamepad_poll`, `gamepad_poll_stick_only`, `gamepad_any_input`.
- `port/src/tape.c` — TAP block parser usado por el trap.
- `tools/extract_reward_ch8.py` — regenera el `.ch8` en build dir desde `code/reward_font_data.inc` (script de build, NO en repo el `.ch8`).

## Propuesta abierta: port wrapper-on-Z80

El user planteó replicar el flujo del wrapper (cards splash + menú idioma + historia bilingüe + iconos animados) **dentro del propio juego en Z80**. Discusión hasta el momento:

### Coste estimado (~1.8 KB en Z80)

| Componente | Tamaño |
|---|---|
| Texto historia ES (6 páginas con codepoints custom) | ~550 B |
| Texto historia EN (6 páginas) | ~500 B |
| Cards splash strings | ~70 B |
| Strings menu idioma | ~50 B |
| 12 glyphs custom acentos (á é í ó ú Á É Í Ó Ú ñ Ñ) | 96 B |
| State machine 3-card splash | ~80 B |
| Render multi-line centered | ~80 B |
| Lookup font extendido (codepoints ≥ 0x80) | ~40 B |
| State machine menú idioma (3 opciones, no-cycle, release-gate) | ~120 B |
| State machine story (6 pages, manual advance, release-gate) | ~80 B |
| Input handling (kbd + Kempston + release-gate) | ~80 B |
| Thunks slot 1 ↔ bank 4 | ~80 B |
| **TOTAL** | **~1826 B** |

### Lo que NO se replica (features inherentes del wrapper)

CRT shader F2, border crop F3, ayumi audio reset, primera-nota mute trick, tape trap. Son features del host emulator, no contenido del game.

### Snapshot de RAM disponible (memory_map.py, 2026-05-26)

```
Bank  Label                                  Used    Free    Pct
0     main code                             16029     355  97.8%
1     screen_rooms                          11821    4563  72.1%
2     variables + AY thunks                 16382       2 100.0%
3     bg_gfx baseline                       14083    2301  86.0%
4     bg_gfx_b (ruins + cemetery)           11851    4533  72.3%
5     screen + vars_lo + código slot 1      16249     135  99.2%
6     screen_gaps + monster_ai_b6 + spri    14080    2304  85.9%
7     bg_gfx_c + room_routes_b7 + tombs     14936    1448  91.2%
TOTAL FREE: 15641 B
```

**Aviso**: el resumen reporta 1448 B en bank 7 pero hay **dos holes**: 1217 B en $E050-$E511 (entre `_reserved_` y `magic_compass`) + 1448 B al final ($FA58-$10000). Total real bank 7: **2665 B**. Usar `python tools/memory_map.py | jq .banks[7].regions` para ver todos los `_FREE_` regions.

### Decisión pendiente — cómo preservar bg-257 (6912 B) detrás del overlay narrativo

Si quieres replicar el wrapper con el efecto visual completo (iconos animados de SplashWait visibles bajo el texto narrativo, como hace el wrapper con `help_preserve_rect`), necesitas bg-257 en RAM accesible. Opciones evaluadas:

| Opción | Tamaño | Bank 1 free | Bank 4 free | Otros | Notas |
|---|---|---|---|---|---|
| **A** Split 3 bancos (bank 1+4+6) sin compresión | 6912 B repartido | 563 B | 1733 B (post-wrapper) | bank 6: 392 B | 3 paginations al pintar. Apretado |
| **B** Split bank 1+4 50/50 | 3456+3456 B | 1107 B | 1077 B (no cabe wrapper) | -- | Solo si NO añades wrapper-on-Z80 en Z80 |
| **C** ZX0 comprimido | ~3500 B + 70 B decompressor | 993 B | 2733 B (post-wrapper) | -- | Más limpio, requiere integrar ZX0 |
| **E** Split bank 1+4 + ambos holes de bank 7 | 6912 B repartido | 1563 B | 1233 B (post-wrapper) | bank 7: 253 B | 4 paginations al pintar. Más balanceado que A |

**Sin** preservar bg-257 detrás del texto (overlay sobre fondo negro): 0 B extra, pero la UX cambia bastante.

### Bug pendiente conocido del wrapper

**Primera nota EndGame distorsionada** cuando hay gamepad conectado. Investigación parcial:
- Spectaculator suena bien con el mismo SNA → wrapper-specific.
- Pause de eventos `SDL_CONTROLLERAXISMOTION` durante precharge ayuda pero no soluciona del todo.
- Con cards 3-card splash + emu paused durante cards 0/1, mejoró pero el user dijo "regular" (audible pero algo distorted).
- Hipótesis no descartada: el polling continuo del gamepad introduce jitter en el SDL event pump al cruzar el boundary del unmute.
- El user dijo "déjalo así" — el current state es el mejor compromise encontrado.

## Uso de `tools/memory_map.py`

```bash
# JSON completo (defaults a stdout)
python tools/memory_map.py

# Solo summary por banks
python tools/memory_map.py | jq -r '.banks[] | "\(.bank) \(.label[:30]) \(.used_bytes) used \(.free_bytes) free"'

# Lista de regions de un bank específico (ver los gaps internos)
python tools/memory_map.py | jq '.banks[7].regions'

# Heatmap, call graph, move cost (ver tools/memory_map.py --help)
python tools/memory_map.py --movecost SYS --from N --to M
python tools/memory_map.py --dead
python tools/memory_map.py --heat
```

Doc canónica del tool: `docs/MEMORY_MAP.md`.

## Para retomar

1. Revisar tape `dist/tharkys.exe` para verificar estado actual del wrapper.
2. Si vas a por el port Z80: empezar leyendo este doc + `project_desktop_wrapper.md` + decidir opción A/C/E para bg-257.
3. Branch sugerida: `feat/wrapper-on-z80` desde `main`. Implementación incremental por componente (texto + render → menú → story → cards splash → bg-257 paginado).
4. Test rápido por componente con Spectaculator o ZEsarUX antes de integrar al pipeline `build_and_*.bat`.
