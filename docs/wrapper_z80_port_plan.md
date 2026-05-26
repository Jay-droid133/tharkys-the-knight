# Plan — wrapper-on-Z80 (port nativo del flujo desktop)

Fecha: 2026-05-26.
Sesión previa: ver `docs/wrapper_z80_port_handoff.md` (contexto + opciones evaluadas).
Rama de trabajo: `claude/fervent-mccarthy-QWKeC`.
Commit base: `f372e03`.

Este doc fija las **decisiones tomadas** sobre el handoff anterior y desglosa el
**plan incremental** por fases. Cada fase es testeable independientemente en
Spectaculator/ZEsarUX antes de pasar a la siguiente.

---

## Decisiones cerradas

### 1. Nombres de splash

- **`art`** = sprite id **185** ("Splash alternative"). Pintado por la BASIC del
  TAP via `LOAD ""SCREEN$`. Sin cambios — sigue como hoy.
- **`title`** = sprite id **257** ("image"). Nuevo. Embebido en ASM
  comprimido. Es el fondo del flow wrapper-on-Z80.

### 2. Compresión de `title`

- Algoritmo: **ZX0 estándar** (Einar Saukas, BSD-3, ~70 B de decompressor en Z80).
- Datos comprimidos: **4242 B** (raw SCREEN$ 6912 B → 61.4 %).
- Δ runtime: 65 B (efímero, decomp in-place a VRAM `$4000`).
- Toolchain: `tools/build_title_zx0.py` (a crear) extrae sprite 257 de
  `code/bg_sprites.json` y produce `code/title.zx0` para INCBIN.
- ZX0 Python disponible vía `pip install zx0` (mismo formato que decompressor Z80).

### 3. Ubicación en RAM

- **`code/title.zx0` → bank 1** (hueco `$EE2D-$10000`, 4563 B libres → 321 B
  restantes tras el INCBIN).
- **Decompressor ZX0** → ubicación TBD entre bank 5 residente (slot 1) o
  bank 2 (AY thunks). Se decide en Fase 1.
- **Razonamiento:** el número de plantillas `Room_TXX` no va a crecer
  (confirmado), así que los 4563 B libres de bank 1 son capacidad muerta. El
  crecimiento futuro esperado (un sprite grande tipo iglesia, ~3.7 KB
  contiguos partido en trozos) **necesita los 4533 B de bank 4 intactos** —
  bank 4 es el único bank que aguanta un sprite así sin split. Por eso title
  va a bank 1, no a bank 4.

### 4. Build flag — dos artefactos desde el mismo source

- **Default build** (`build_and_tharkys.bat` actual, sin flag): sin
  wrapper-on-Z80. Sigue alimentando `tharkys.exe`. **Cero diff visible.**
- **`-DWRAPPER_ONZ80`** (nuevo `build_and_native.bat`): incluye cards/menu/
  story/title-ZX0/decompressor/glyphs extra. Produce `juego_native.tap` para
  real hardware / ZEsarUX / Spectaculator standalone.
- Gating en ASM con `IFDEF WRAPPER_ONZ80 / ... / ENDIF` alrededor del único
  módulo nuevo (`wrapper_on_z80.asm`), sin contaminar el resto.
- `dist/` shipea ambos: `tharkys.exe` (desktop) + `juego_native.tap` (real hw).

### 5. Flujo target en Z80 nativo

```
1. BASIC del TAP carga          → art (185) pintado por SCREEN$ en VRAM
2. Z80 arranca, blanquea VRAM   → fondo negro
3. Pinta iconos estáticos       → key/btn frame A, sin animar
4. Card 0 "JayDroid Presents"   → texto centrado sobre negro, iconos visibles, 3 s
5. Card 1 "A Sinclair ZX..."    → ídem, 3 s
6. ZX0-decomp title a VRAM      → fondo nuevo
   + repaint iconos             → siguen visibles (overlay sobre title)
   + arranca EndGame music      → iconos empiezan a animarse con beat
7. Menú idioma                  → sobre title + iconos animados
                                   3 opciones: English / Español / Skip story
8. Story (6 páginas)            → sobre title con preserve_rect
                                   iconos visibles bajo texto, animan con beat
9. Arranque del juego           → return de WrapperOnZ80Flow → main.asm
                                   sigue con el boot habitual (saltando
                                   SplashWait, ya hicimos splash+music)
```

Skip por cualquier input (kbd + Kempston) con release-gate: una pulsación =
una transición. Idéntico al wrapper desktop.

### 6. preserve_rect en story

- **Sí** — iconos animados visibles bajo el overlay narrativo (mismo trick que
  `help_preserve_rect` del wrapper desktop).
- Implementación: re-blittear el rect del title bajo el texto cada N frames,
  + repintar iconos encima. Buffer del rect ~64-128 B (según geometría) en
  RAM baja.

### 7. Dependencia externa ZX0

- **OK**. Integrar `code/zx0_decompress_standard.asm` (BSD-3). Variante
  "standard" (forward, ~70 B). Mantenimiento cero.

---

## Snapshot de RAM (2026-05-26, post-decisión)

Libre actual por bank (verificado con `python tools/memory_map.py`):

| Bank | Label | Libre | Tras wrapper-on-Z80 |
|---|---|---:|---:|
| 0 | main code | 379 + 355 = 734 B | sin cambios |
| 1 | screen_rooms | 4563 B | **321 B** (− title.zx0 4242 B) |
| 2 | variables + AY thunks | 2 B | sin cambios (o − ~70 B si decomp va aquí) |
| 3 | bg_gfx baseline | 2301 B | sin cambios |
| 4 | bg_gfx_b (ruins + cemetery) | 4533 B | **intacto** (reservado para sprite tipo iglesia futuro) |
| 5 | screen + vars_lo + slot 1 code | 135 B | − ~70 B si decomp va aquí |
| 6 | screen_gaps + monster_ai_b6 + sprites | 2304 B | sin cambios |
| 7 | bg_gfx_c + room_routes_b7 + tombs | 1217 + 1448 = 2665 B | − ~1.4 KB (cards/menu/story code + glyphs + strings ES/EN) |

Estimado código wrapper-on-Z80 sin contar title: ~1.5 KB (cards/menu/story
SM + strings ES+EN + 12 glyphs custom + render multi-line). Cabe en bank 7
(2665 B) sin tocar otros bancos.

---

## Plan incremental por fases

| Fase | Descripción | Estimado | Riesgo |
|---|---|---:|---|
| 0 | Andamio del build flag | 30-60 min | bajo |
| 1 | Toolchain ZX0 + decomp a VRAM | 1-2 h | medio |
| 2 | Iconos estáticos + animados | 1 h | bajo |
| 3 | Cards 0/1 sobre negro con iconos | 2-3 h | bajo |
| 4 | Splash title + música EndGame | 1 h | bajo |
| 5 | Font extendido (acentos) | 1 h | bajo |
| 6 | Menú idioma | 1-2 h | bajo |
| 7 | Story 6 páginas con preserve_rect | 3-4 h | medio |
| 8 | Wire final + verificación E2E | 1 h | bajo |
| **Total** | | **~12-16 h** | |

### Fase 0 — Andamio del build flag

- Crear `code/build_and_native.bat` (clon de `build_and_spectaculator.bat`
  + flag `-DWRAPPER_ONZ80`, output `juego_native.sna` / `.tap`).
- Crear `code/wrapper_on_z80.asm` con stub:
  ```asm
  WrapperOnZ80Flow:
      RET
  ```
- En `code/main.asm:143` envolver `CALL SplashWait`:
  ```asm
  IFDEF WRAPPER_ONZ80
      INCLUDE "wrapper_on_z80.asm"
      CALL WrapperOnZ80Flow
  ELSE
      CALL SplashWait
  ENDIF
  ```

**Test:** `build_and_tharkys.bat` produce SNA idéntico a hoy (diff binario
== 0); `build_and_native.bat` produce SNA con +N bytes en bank donde viva el
INCLUDE. `python tools/memory_map.py` confirma diff.

### Fase 1 — Toolchain ZX0 + decomp a VRAM

- `tools/build_title_zx0.py`:
  ```python
  # Carga bg_sprites.json id 257, convierte a SCREEN$ Spectrum-native
  # (linear_to_spectrum_native ya existe en build_tap_with_splash.py),
  # ZX0-comprime, escribe code/title.zx0
  ```
- Wire en `build_and_native.bat` antes de sjasmplus.
- Añadir `code/zx0_decompress_standard.asm` (copiar de github.com/einar-saukas/ZX0, variante "standard").
- En `wrapper_on_z80.asm`:
  ```asm
  TitleZX0:
      INCBIN "title.zx0"
  TitleZX0End:

  DecompressTitleToVRAM:
      DI
      LD HL, TitleZX0
      LD DE, $4000
      CALL dzx0_standard
      EI
      RET
  ```
- **Hook temporal:** `WrapperOnZ80Flow: CALL DecompressTitleToVRAM : HALT_LOOP: JR HALT_LOOP`.
- Decidir ubicación final del decompressor (bank 5 residente vs bank 2).

**Test:** Spectaculator muestra title correctamente tras carga del TAP.
Verificar pixels (256×192) y attrs (8×24 chars).

### Fase 2 — Iconos estáticos + animados

- Reutilizar `code/splash_prompt.bin` (136 B, ya en repo) y sub-rutinas de
  `code/splash_wait.asm`.
- Extraer/aislar:
  - `DrawIconsStatic` — pinta key frame A + btn frame A + attrs.
  - `DrawIconsBeatAnim` — alterna A/B según contador de música (tickado por
    el music IRQ, no por loop manual).

**Test:** sobre title de Fase 1, pintar iconos estáticos. Verificar
posición. Luego activar animación y verificar beat.

### Fase 3 — Cards 0/1 sobre negro con iconos estáticos

- `BlankVRAM` — `LD HL,$4000 / LD (HL),0 / LD DE,$4001 / LD BC,6911 / LDIR`
  (o LDIRR optimizado).
- `DrawCenteredText` — multi-line con `\n` separator, codepoints custom.
  Reutiliza renderer de `PrintStringFontAt` (en `town_gate_cutscene_bank7.asm`).
- Strings cards 0/1 (~70 B): `"JayDroid Presents"`,
  `"A Sinclair ZX Spectrum 128K computer game"`.
- State machine: 150 frames (3 s) por card a 50 Hz, release-gate por input.
- Flow:
  ```
  BlankVRAM → DrawIconsStatic → DrawCenteredText(card0) → WaitFrames(150 | skip)
  BlankVRAM → DrawIconsStatic → DrawCenteredText(card1) → WaitFrames(150 | skip)
  ```

**Test:** dos cards centradas con iconos estáticos visibles, skip por
input, una pulsación = una transición (no cascada).

### Fase 4 — Splash title + música EndGame

- Hook a music system existente: `LD HL, EndGameMusicTable_Bank7 : CALL StartMusic`.
- `DecompressTitleToVRAM` (Fase 1) + `DrawIconsStatic` superpuestos.
  Los pixels de title bajo iconos se pierden — intencional (los iconos
  ocupan zona fija reservada en el diseño del title).
- Activar `DrawIconsBeatAnim` tickado por IRQ del music engine.
- Loop ~4 s (200 frames) o hasta input (release-gate).

**Test:** tras cards 0/1, fade-in title + música arranca + iconos animan
con beat. Skip funciona limpio.

### Fase 5 — Font extendido (acentos)

- 12 glyphs custom (96 B = 12 × 8 B/glyph) para
  `á é í ó ú Á É Í Ó Ú ñ Ñ` en codepoints `0x80-0x8B`.
- Tabla `ExtendedFontGlyphs:` con los 96 B.
- Extender lookup en renderer: `if codepoint >= 0x80 → ExtendedFontGlyphs[(codepoint - 0x80) * 8] else font_normal`.
- Strings ES pre-codificados con `DEFB` directos (no conversión runtime):
  ```asm
  StoryES_P1: DEFB "Sir Tharkys es un tipo", 13
              DEFB "con mala suerte.", 13
              DEFB "Durante mucho tiempo", 13
              DEFB "extendi", $83, " cheques que su", 13     ; ó = $83
              ...
  ```
- Script Python opcional para pre-codificar UTF-8 → DEFB con codepoints
  custom desde el source actual del wrapper desktop
  (`port/src/main.c:140-256`), guardando en `code/story_es.inc` / `_en.inc`.

**Test:** imprimir cadena ES con acentos sobre title y verificar pixels.

### Fase 6 — Menú idioma

- Strings: `"ENGLISH"`, `"ESPA", $8B, "OL"`, `"SKIP STORY"` (~50 B).
- State machine: cursor index 0..2, UP/DOWN no-cíclico, ENTER/FIRE
  confirma, release-gate por input.
- Render con highlight (attrs invertidos en la fila activa).
- Variable global `LangIsES` (1 bit) en RAM baja para que la story sepa
  qué tabla de strings usar.

**Test:** navegación visual correcta, confirmación de cada opción,
release-gate evita doble-confirm.

### Fase 7 — Story 6 páginas con preserve_rect

- Strings ES (~570 B) + EN (~545 B), pre-codificados en `code/story_es.inc`
  y `code/story_en.inc`.
- State machine: page index 0..5, ENTER/FIRE avanza, release-gate.
- `DrawCenteredText` reutilizada de Fase 3.
- **preserve_rect:**
  - Identificar rect bajo iconos en el title (probable: 4 chars × 4 chars
    en zona central baja).
  - Al renderizar texto que invade ese rect, re-blittear el rect del title
    (no se puede ZX0-decomp parcial; usar buffer pre-extraído en RAM baja,
    ~64-128 B según geometría).
  - Cada N frames: re-blit rect title + repaint iconos animados encima.
- Refresh iconos animados sincronizado con beat de música (sigue tocando
  EndGame).

**Test:** las 6 páginas en ambos idiomas (toggle por menu), acentos
correctos, iconos animados visibles bajo texto sin glitches.

### Fase 8 — Wire final + verificación E2E

- Tras story → return de `WrapperOnZ80Flow` → `main.asm` sigue con boot
  habitual saltando `SplashWait` (en build `-DWRAPPER_ONZ80`).
- Verificar `juego_native.tap` end-to-end en Spectaculator + ZEsarUX:
  BASIC load art → Z80 → blanco → iconos estáticos → cards 0/1 →
  title + música + iconos animando → menú → story → juego.
- `python tools/memory_map.py` confirma layout final:
  - title.zx0 (~4242 B) en bank 1
  - decompressor (~70 B) en bank 5 o 2
  - cards/menu/story code (~1.4 KB) repartido en bank 7
- Build `dist/`: copia `tharkys.exe` (sin cambios) + `juego_native.tap`
  + `LICENSES.txt` (añadir mención BSD-3 de ZX0).

---

## Comandos de build / verificación

```bash
# Build wrapper desktop (sin cambios, igual que hoy)
cd code && build_and_tharkys.bat

# Build native con wrapper-on-Z80 (nuevo)
cd code && build_and_native.bat

# Memory map del último build (depende de qué .bat ejecutaste)
python tools/memory_map.py

# Inspección de huecos por bank
python tools/memory_map.py | jq '.banks[1].regions'
python tools/memory_map.py | jq '.banks[4].regions'
python tools/memory_map.py | jq '.banks[7].regions'

# Verificación rápida del title comprimido
python tools/build_title_zx0.py --report   # imprime tamaño raw/ZX0
```

---

## Notas y riesgos

- **Bank 5 vs bank 2 para decompressor:** decidir en Fase 1. Bank 5 sólo
  tiene 135 B libres → meter ~70 B deja 65 B (apretado). Bank 2 tiene 2 B
  libres → no entra ahí; habría que reubicar algún thunk AY menor.
  Alternativa: bank 0 (main code) con 734 B en dos holes, pero requiere que
  el decompressor sea callable desde slot principal sin paginar.
- **preserve_rect (Fase 7):** la pieza más delicada. Depende de la
  geometría exacta del title bajo los iconos. Posible plan B: text overlay
  opaco temporal mientras se diseña el rect, refinar en pasada posterior.
- **ZX0 Python dep:** `pip install zx0` requerido en el entorno de build.
  Añadir a `requirements.txt` si existe, o documentar en README.
- **`code/title.zx0`:** generado por tool, NO debe entrar al repo
  (regenerable desde `bg_sprites.json` + `tools/build_title_zx0.py`).
  Añadir a `.gitignore`.

---

## Para retomar (próxima sesión)

1. Leer este doc + `docs/wrapper_z80_port_handoff.md` para contexto completo.
2. Verificar memoria fresca: `python tools/memory_map.py`.
3. Arrancar por **Fase 0** (andamio build flag). Diff binario garantiza que
   el wrapper desktop sigue intacto.
4. Avanzar fase a fase, testeando en Spectaculator/ZEsarUX antes de cada
   commit. Cada fase debería caber en un commit autocontenido.
5. Si bloqueo en alguna fase (especialmente Fase 7 preserve_rect), volver
   a este doc y proponer plan B antes de seguir.
