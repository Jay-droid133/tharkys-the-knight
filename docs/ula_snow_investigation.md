# Investigación: ULA snow en Sinclair 128K/+2 reales

**Fecha:** 2026-07-01 · **Branch:** `fix/ula-snow-128k` · **Estado:** causa raíz confirmada, fix diseñado (pendiente de implementar)

## Reporte del usuario

> "When I load this game, I see a lot of ULA snow. I am using a Sinclair 128K + to load it"

Snow constante en pantalla desde el arranque, en **hardware real** (Spectrum 128/+2).

## Causa raíz (confirmada)

El setup IM 2 apunta el registro `I` a **RAM contended**:

- [main.asm:116](../code/main.asm#L116) — `LD A, $7A` / `LD I, A` / `IM 2` (único `LD I` de todo el código).
- [music_irq.asm:232](../code/music_irq.asm#L232) — `ORG $7A00` / `Im2Table: DEFS 257, $7B` → tabla en `$7A00-$7B00`, slot 1 = **bank 5 = contended** en toda la familia 128K.

Es el bug de hardware clásico y documentado del Spectrum: con `I` en `$40-$7F` (o apuntando a un bank contended paginado en `$C000`), los refresh cycles M1 del Z80 ponen `I:R` en el bus de direcciones y colisionan con los fetches de vídeo de la ULA → "snow" por toda la pantalla. Afecta a 16K/48K/128K toastrack/+2 gris (en algunos 128K puede llegar a colgar la máquina). El +2A/+3 (gate array Amstrad) no lo exhibe.

### Por qué nunca lo vimos

Ningún entorno de test del proyecto emula el snow:

- **Spectaculator** (loop dev principal): no emula snow.
- **chips/zx.h** (wrappers web + desktop): no emula snow — además esos ports embeben la SNA y siempre corren emulados, así que **no están afectados** y no necesitan cambios.
- El snow solo aparece en hardware real (y en emuladores con snow effect activable, p. ej. ZEsarUX — verificar en ajustes).

El resto del diseño IM 2 es correcto: la tabla de 257×`$7B` hace el vector inmune al valor del floating bus (siempre `$7B7B` → `JP MusicIrqHandler`). El problema es **exclusivamente la página donde vive la tabla**, no el esquema.

## Restricción de diseño

La página del registro `I` debe ser RAM **no-contended Y siempre visible** (el IRQ puede dispararse con cualquier bank en slot 3 — todo el patrón alt_stack existe porque se pagina con EI). En el mapa 128K eso deja exactamente una opción:

| Zona | ¿Sirve? |
|---|---|
| `$40-$7F` (slot 1, bank 5) | ❌ contended → snow (situación actual) |
| `$80-$BF` (slot 2, bank 2) | ✅ **única candidata**: fija en hardware, no-contended en 128K y +2A/+3 |
| `$C0-$FF` (slot 3, pageable) | ❌ banks 1/3/4/6/7 se paginan con EI → vector basura → crash |
| `$00-$3F` (ROM) | ❌ ROM0/ROM1 conmutan y no hay página constante fiable |
| Volver a IM 1 | ❌ reintroduce la latencia de MainLoop que motivó music_irq (notas saltadas) |

## Fix diseñado

**Mover solo la tabla** (257 B) a bank 2; el handler y el vector JP se quedan en slot 1:

1. `Im2Table` → `ORG $BE00` en bank 2 (contenido igual: 257×`$7B`). El último byte de tabla cae en `$BF00`; **no** usar `I=$BF` (el byte 257 caería en `$C000`, slot 3 pageable).
2. [main.asm:116](../code/main.asm#L116): `LD A, $7A` → `LD A, $BE`.
3. `Im2Vector` (`ORG $7B7B: JP MusicIrqHandler`) y `MusicIrqHandler` **no se tocan** (que el handler sea contended es solo un tema menor de velocidad, no de snow).

### Contabilidad de espacio (medida sobre build limpio de hoy, `Errors: 0`)

Bank 2 tiene 27 B libres → hay que desalojar ~230 B. El candidato exacto ya está catalogado como **Opción 2** en `project_ram_optimization_options` / `docs/RAM_OPTIMIZATION_PLAN.md`: el **freeze cluster** (cold tail de logic_game):

- Hoy en `$BC56-$BE2F` (474 B): `SilentKillDeath`, `FreezeMonstersFacingCorpse`, `FreezeOneMonster`, `TryBackoffX/Y`, `CheckMonsterOverlap`, `KillAllActiveMonsters`.
- **Destino: slot 1** — al sacar la tabla de `$7A00` se libera un hueco contiguo de **680 B** (`$78D3-$7B7B` = 301 gap actual + 257 tabla + 122 gap post-tabla). El cluster (474 B) cabe con ~206 B de margen y, al ser slot 1 always-visible, **no necesita thunks** (a diferencia del plan original a bank 7, que costaba 3 thunks + wrapper). Su única dep externa (`EraseDeathSprite`, bank 0) se llama en contextos con bank 0 paginado, igual que hoy.
- Cluster es código frío (muerte de player / day cycle), la contention de slot 1 es irrelevante ahí.
- Tras el shuffle, el tail de bank 2 (`DiurnalTypeTable`...`SpawnMonsters`, hot, 437 B) baja a terminar en ~`$BE0B` — quedan **11 B sobre `$BE00`**: reubicar las type tables (24 B) a `$BF01+` (detrás de la tabla IM 2) o mover una mini-rutina más. Varias palancas fáciles.

### Bonus de mantenibilidad

Desaparece para siempre la zona prohibida `$7A00-$7B00` de slot 1 (memorias `project_slot1_im2_overflow`, `project_org_retrograde_overlap`, colisiones con RoomCompGaps/BFS/magic_compass…). El nuevo invariante es una tabla con ORG fijo en bank 2, lejos de todo código que fluye. Actualizar comentarios que citan `$7A00` (inventariados: main.asm, music_irq.asm, magic_compass.asm, town_gate_exit_thunk.asm, bank_cutscene_thunks.asm, tools/generate_tech_manual.js). `tools/check_slot_overlap.py` no referencia la tabla — sin cambios.

## Validación propuesta

1. Build dev + standalone (`Errors: 0`) + `python tools/check_slot_overlap.py` + diff de `memory_map.py`.
2. Smoke tests canario (orden de `project_ram_optimization_options`): compass mágica → game over (tumba 2x) → cinemática iglesia → town gate. La música (tick IRQ 25 Hz) debe sonar idéntica desde el splash.
3. Muerte de player completa (el freeze cluster movido es exactamente ese flujo): monstruos congelados mirando al cadáver + backoff 16px + KillAllActiveMonsters en day cycle.
4. Confirmación del snow: emulador con snow effect (ZEsarUX) si lo soporta, y en última instancia el usuario reportante con la TAP nueva en su 128K.
