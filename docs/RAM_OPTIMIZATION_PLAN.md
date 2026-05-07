# Plan maestro de optimización RAM — slot 1 + bank 2

> **Branch**: `ram/optimize-slot1` (HEAD: `e5eec9a` al crear el plan)
> **Estado**: design phase. Sin código aún.
> **Objetivo principal**: corregir overflow latente de slot 1 y crear ≥ 2 KB de
> headroom en cada zona always-visible para sostener los próximos hitos.

---

## 1. Goals (en orden de prioridad)

1. **Corregir overflow de slot 1** (bug latente; 331 B de room_routes.asm desbordan
   a $80XX, zona MainLoop).
2. **Reclamar ≥ 2 KB en slot 1** (headroom para nuevas cinemáticas, helpers,
   thunks).
3. **Reclamar ≥ 1 KB en bank 2** (slot 2 always-visible está al 99,99 %; el
   próximo include grande no cabe).
4. **Mantener bank 0 ≤ 92 %** y bank 6 ≤ 86 % (no empeorar).
5. **Cero regresiones runtime** (validación gateada por fase).

---

## 2. Estado actual (al inicio del plan)

### 2.1 Bancos

| Bank      | Tipo                  | Usado / Cap        | Pct      | Libres  | Contenido                                               |
| --------- | --------------------- | ------------------ | -------- | ------- | ------------------------------------------------------- |
| **Slot 1**| Always-visible (b5)   | **8523** / 8192    | **104 %**| **−331**| Cutscenes + paging + tombstones + ... + room_routes     |
| **Bank 2**| Always-visible        | 16383 / 16384      | 99,99 %  | 1       | MainLoop + variables + monster_ai + logic_game + ...    |
| Bank 0    | Paged slot 3 (default)| 15156 / 16384      | 92,5 %   | 1228    | main code (upper portion)                               |
| Bank 1    | Paged slot 3          | 10970 / 16384      | 67,0 %   | 5414    | screen_rooms                                            |
| Bank 3    | Paged slot 3          | 11990 / 16384      | 73,2 %   | 4394    | bg_gfx (baseline + neutrals + town + filler)            |
| Bank 4    | Paged slot 3          | 9982 / 16384       | 60,9 %   | 6402    | bg_gfx_b (ruins + cemetery) + ay_sound                  |
| Bank 6    | Paged slot 3          | 14080 / 16384      | 85,9 %   | 2304    | screen_gaps + monster_ai_bank6 + sprite_data + shift    |
| Bank 7    | Paged slot 3          | 5198 / 16384       | 31,7 %   |**11186**| bg_gfx_c (forest) + game_over_tomb body                 |
| LOW-RAM   | Slot 1 contended      | 468 / 768          | 60,9 %   | 300     | variables_lo.asm (vars cold/raras)                      |

### 2.2 Layout real de slot 1

| Rango           | Bytes | Módulo                              | Tipo     |
| --------------- | ----- | ----------------------------------- | -------- |
| $6000–$60C5     | 198   | Inicio (boot)                       | one-shot |
| $60C6–$6A8E     | 2505  | town_gate_cutscene + church_cutscene| one-shot |
| $6A8F–$6B50     | 194   | paging.asm (LoadBgSpriteToBuffer)   | hot      |
| $6B51–$6D15     | 453   | tombstones.asm                      | cold     |
| $6D16–$6DCC     | 183   | sfx_player_hit_ay.asm               | warm     |
| $6DCD–$720B     | 1087  | random_pickups.asm                  | mixto    |
| $720C–$771E     | 1299  | magic_compass.asm                   | hot      |
| $771F–$774D     | 47    | game_over_tomb_thunk.asm            | one-shot |
| $774E–$814B     | 2558  | room_routes.asm (RoomCompGapsTable) | cold     |
| **TOTAL**       |**8523**| (cap 8192 → desbordamiento 331 B) |          |

### 2.3 Layout aproximado de bank 2 (slot 2 always-visible)

| Módulo                | Tamaño aprox | Tipo  | Mover? |
| --------------------- | ------------ | ----- | ------ |
| MainLoop + vars hot   | ~600 B       | hot   | NO     |
| variables.asm         | ~272 B       | hot   | NO     |
| monster_ai.asm        | ~1300 B      | hot   | NO     |
| ay_sound_thunks.asm   | ~215 B       | hot   | NO     |
| engine_graphics.asm   | ~506 B       | hot   | parcial|
| logic_game.asm        | **~6160 B**  | mixto | parcial|
| screen_system.asm     | ~2556 B      | mixto | parcial|
| screen_data.asm       | ~626 B       | hot   | NO     |
| day_cycle.asm         | ~747 B       | hot   | NO     |
| hud_clock.asm         | ~636 B       | hot   | NO     |
| **milestones.asm**    | **~1589 B**  | cold  | **SÍ** |
| sound.asm             | ~409 B       | hot   | NO     |

### 2.4 Bank 7 free space

```
$C000-$D44E    bg_gfx_c (forest sprites) + game_over_tomb body  →  5198 B usados
$D44E-$E000    LIBRE                                            →  2994 B
$E000-$EXXX    Tombstone storage (200 entradas × 4 B)           →  ~800 B
$EXXX-$FFFF    LIBRE                                            →  ~7000 B
TOTAL libre en bank 7: 11186 B
```

---

## 3. Restricciones / invariantes (no negociables)

1. **HOT** (llamado cada frame en MainLoop) debe vivir en slot 1, slot 2 o bank 0.
2. **paging.asm** vive en slot 1 always-visible — sus rutinas hacen el OUT de
   page switch; si vivieran en un bank paginado, el OUT las haría desaparecer.
3. **VRAM** ($4000–$5AFF), **system area 128K** ($5B00–$5CCB), **stack** (parte
   alta de slot 2) — intocables.
4. **LoadBgSpriteToBuffer restaura bank 0 al final** (hardcoded). Cualquier
   caller en bank ≠ 0 desaparece tras el RET → solo bank 0 puede llamarla
   directamente; el resto necesita un thunk en slot 1 (ver Fase 0).
5. **Cross-bank CALL**: si bank A llama a bank B, durante la ejecución de B
   el código de A NO está visible. Los datos se acceden vía buffers en slot
   2 (always-visible) — p. ej. BgSpriteBuffer.
6. Cualquier nuevo INCLUDE en slot 1 va **ANTES** de `INCLUDE "room_routes.asm"`
   (hasta que la Fase 3 elimine el desbordamiento).

---

## 4. Patrones de movimiento

### 4.1 Patrón A — "Cinemática one-shot a bank 7"

Aplicable a: `town_gate_cutscene.asm`, `church_cutscene.asm`,
`game_over_tomb.asm` (ya hecho).

Estructura:
```
code/<feature>_thunk.asm    # 30–50 B, vive en slot 1
code/<feature>.asm           # body, vive en bank 7
```

Thunk:
```asm
<EntryPoint>:
    ; Si necesita cargar sprite, hacerlo PRIMERO (LoadBgSpriteToBuffer
    ; restaura bank 0, no podemos hacerlo después de paginar bank 7).
    LD HL, <BgGfx_label>
    LD A, <bank>
    CALL LoadBgSpriteToBuffer

    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 7
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    CALL <BodyEntryPoint>

    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    OUT (C), A          ; BC sigue $7FFD
    LD A, (StartupComplete)
    OR A
    RET Z
    EI
    RET
```

Body (en bank 7) restricciones:
- NO llama `LoadBgSpriteToBuffer` (esa rutina restaura bank 0 → body
  desaparece).
- Lee `BgSpriteBuffer` (slot 2 always-visible).
- Lee/escribe sus propios buffers (en bank 7).
- Puede llamar a helpers en slot 1 (paging.asm) o slot 2 (CalcPixelAddr,
  NextPixelLine, etc.) sin problema.

### 4.2 Patrón B — "Tabla de datos a bank holgado"

Aplicable a: `room_routes.asm` (RoomCompGapsTable + per-room data).

Estructura:
- Datos viven en bank 6 o 7.
- Helper en slot 1 lee de la tabla con paging in/out.
- Si el patrón de acceso es "leer N bytes para una sala", se copian a un
  buffer en slot 2 (BgSpriteBuffer reutilizable o un nuevo scratch).

Ejemplo helper:
```asm
ReadRoomCompGap:
    ; IN:  A = sid, HL = dst buffer (en slot 2)
    ; OUT: dst buffer rellenado, paging restaurado
    DI
    LD B, A                     ; B = sid
    LD A, (CurrentPaging)
    LD C, A                     ; C = paging original
    AND $F8
    OR <bank>
    OUT ($FD), A                ; conmutar slot 3
    LD (CurrentPaging), A
    ; ... leer RoomCompGapsTable[B] desde slot 3, copiar a (HL) ...
    LD A, C
    LD (CurrentPaging), A
    OUT ($FD), A
    LD A, (StartupComplete)
    OR A
    RET Z
    EI
    RET
```

### 4.3 Patrón C — "Función fría aislada a bank 7"

Aplicable a: funciones específicas de `milestones.asm`,
`logic_game.asm`, `screen_system.asm` que se invocan ocasionalmente.

Estructura: pequeño thunk en bank 0 (siempre paginado por defecto) llama a
helper en bank 7. Para llamadas desde bank 2, el thunk vive en slot 1 o
slot 2.

---

## 5. Fases del plan

> **Convención**: cada fase es **un commit atómico** en `ram/optimize-slot1`.
> Si una fase falla en validación, `git revert` y debug.

### Fase 0 — Generalizar `LoadBgSpriteToBuffer` (PRE-REQUISITO)

**Por qué primero**: las fases 1, 2 dependen de poder llamar
`LoadBgSpriteToBuffer` desde código que vive en bank 7 sin perderlo.

**Cambio**: en `code/paging.asm`, en lugar de hardcodear "page bank 0 back"
al final, guardar al inicio el bank del caller y restaurar ese al final.

**Diff esperado** (~5 B extra en slot 1):
```asm
; AL ENTRAR:
LoadBgSpriteToBuffer:
    LD (.lbsBankSave), A            ; ya existe
    PUSH BC
    DI
    ; NUEVO: guardar bank del caller
    LD A, (CurrentPaging)
    AND $07
    LD (.lbsCallerBank), A
    ; ... resto igual ...

; AL SALIR (.lbsLoadDone):
    LD A, (CurrentPaging)
    AND $F8
    LD B, A
    LD A, (.lbsCallerBank)
    OR B                            ; restaurar bank del caller (no fija 0)
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    ; ... resto igual ...

.lbsCallerBank: DEFB 0               ; nueva var en slot 1
```

**Validación**:
- Build clean.
- Todos los callers de `LoadBgSpriteToBuffer` están en bank 0 (verificar con
  `grep -B 30 "CALL LoadBgSpriteToBuffer" code/*.asm | grep "ORG\|PAGE"`).
- Smoke test: cualquier sprite BG carga (cualquier transición de pantalla).

**Riesgo**: bajo. Para los callers en bank 0, el bank guardado es 0 y el
restore es a 0 → comportamiento idéntico.

**Coste neto**: +6 B en slot 1.

### Fase 1 — `town_gate_cutscene.asm` → bank 7 (libera ~2 KB en slot 1)

**Tamaño del move**: ~1500 B (la mitad de los 2505 B compartidos con church).

**Pasos**:
1. Identificar entry points (callers en bank 2 / bank 0):
   ```bash
   grep -E "town_gate|TownGate|StartTownGate|UpdateTownGate" code/*.asm
   ```
2. Crear `code/town_gate_cutscene_thunk.asm` con un thunk por entry point.
3. Mover el INCLUDE de `town_gate_cutscene.asm` al bloque `PAGE 7 / ORG $C000`
   en `main.asm` (después de bg_gfx_c y antes de game_over_tomb).
4. Reemplazar el INCLUDE original (en slot 1) por el del thunk
   (`town_gate_cutscene_thunk.asm`).
5. Si el cuerpo llama `LoadBgSpriteToBuffer` y ya pasó la Fase 0, las llamadas
   funcionan directamente. Si no, mover esas llamadas al thunk.

**Validación**:
- Build clean. Verificar `grep -E "Bank7End:" NuevoJuego.sym` para el nuevo
  fin de bank 7.
- `tools/check_slot_overlap.py` (Fase −1, ver §7) → 0 overlaps.
- Smoke test: jugar hasta el hito final, ver la cinemática town_gate completa.

**Coste neto**: −1500 B en slot 1, +1530 B en bank 7.

### Fase 2 — `church_cutscene.asm` → bank 7 (libera ~1 KB en slot 1)

Análogo a Fase 1.

**Pasos**:
1. Entry points: `grep -E "church_cutscene|StartChurchTrap|UpdateChurchCut" code/*.asm`.
2. Thunk: `code/church_cutscene_thunk.asm`.
3. Mover INCLUDE al bloque PAGE 7.
4. Validar.

**Smoke test**: M7 — atrapar 3 monstruos en la iglesia.

**Coste neto**: −1000 B en slot 1, +1030 B en bank 7.

### Fase 3 — `room_routes.asm` → bank 6 (libera ~2.5 KB en slot 1)

**Cuidado**: esta es la fase con más superficie de cambio. magic_compass usa
RoomCompGapsTable en su BFS reverse (cold-ish, 1 BFS por activación de
compass).

**Análisis del patrón de acceso** (medir antes):
```bash
grep -nE "RoomCompGapsTable|RoomCompGaps_" code/magic_compass.asm
```

**Plan**:
3.1. Mover `INCLUDE "room_routes.asm"` al bloque PAGE 6 (2304 B libres antes
     del move; tras el move, bank 6 estará al 99 % o desbordando).
     **Alternativa preferida: bank 7** (11 KB libres, no sufre tras Fase 1+2).
3.2. Crear helper `ReadRoomCompGapsForRoom` en slot 1 (vive con magic_compass).
     - IN: A = sid (Y*16+X)
     - OUT: copia los gaps de esa sala a un buffer en slot 2 (~30 B).
3.3. Modificar `magic_compass.asm` para usar el helper en vez de leer la
     tabla directamente.

**Coste runtime**: cada llamada al helper ~50 T (DI + paging + leer < 30 B
+ paging back). BFS hace ~100 lookups → 5000 T amortizados sobre 12+ frames.
Invisible.

**Validación**:
- Build clean.
- `grep -E "RoomCompGaps.*EQU 0x000080" NuevoJuego.sym` → debe estar VACÍO
  (no más overflow).
- Smoke test: activar compass, ir a sala lejos, verificar que la flecha
  apunta correcto.

**Coste neto**: −2558 B en slot 1, +2570 B en bank 7 (incluye helper).

**Estado al final de Fase 3**:

| Bank      | Antes      | Después F1+F2+F3   |
| --------- | ---------- | ------------------ |
| Slot 1    | 8523 B     | **3580 B** (44 %)  |
| Bank 7    | 5198 B     | **10100 B** (62 %) |

→ slot 1 con **4612 B libres** después de fase 3.

### Fase 4 — `milestones.asm` → bank 7 (libera ~1500 B en bank 2)

**Cuidado**: milestones tiene tablas de datos (MilestoneTable) y handlers
de eventos (CheckMilestoneTrigger, AdvanceMilestone, etc.).

**Pasos**:
1. Identificar callers hot (de MainLoop o per-frame). Probablemente
   `CheckMilestoneTrigger` se llama solo en eventos (cold).
2. Crear thunk `milestones_thunk.asm` en slot 1 o slot 2.
3. Mover body a bank 7.

**Validación**:
- Build clean.
- Smoke test: completar 2-3 hitos consecutivos.

**Coste neto**: −1589 B en bank 2, +1620 B en bank 7.

**Estado al final de Fase 4**:

| Bank      | Antes (post F3) | Después F4         |
| --------- | --------------- | ------------------ |
| Bank 2    | 16383 B         | **14794 B** (90 %) |
| Bank 7    | 10100 B         | 11720 B (72 %)     |

→ bank 2 con **1590 B libres** post-F4.

### Fase 5 (opcional) — Pulir: `tombstones.asm` core a bank 7

Solo si tras F1-F4 sobra trabajo. tombstones es 453 B en slot 1, cold path.
Mover a bank 7 libera ~400 B más en slot 1.

### Fase 6 (opcional) — Funciones cold de `logic_game.asm` a bank 7

logic_game es 6160 B en bank 2. Identificar funciones cold (one-shot, eventos
raros) y moverlas. Candidatos típicos:
- Inicializadores (InitGameState, InitEntities) — solo se llaman en boot.
- Game over / victory handlers.

---

## 6. Estado objetivo (post Fase 4)

| Bank      | Pre-plan          | Post-F4              | Δ          |
| --------- | ----------------- | -------------------- | ---------- |
| Slot 1    | 8523 / 8192 (104%)| **3580 / 8192 (44%)**| **−4943 B**|
| Bank 2    | 16383 / 16384     | **14794 / 16384 (90%)** | **−1589 B**|
| Bank 0    | 15156 / 16384 (92%)| 15156 / 16384 (92%)| 0          |
| Bank 7    | 5198 / 16384 (32%)| **11720 / 16384 (72%)** | +6522 B    |

**Resultado**: slot 1 con 4612 B libres, bank 2 con 1590 B libres, bank 7
con 4664 B libres. Headroom suficiente para 2-3 cinemáticas más, varios
power-ups, sistemas de menú/pause, etc.

---

## 7. Tooling de soporte (a implementar antes de Fase 1)

### 7.1 `tools/check_slot_overlap.py`

Validador automático ejecutable tras cada build:

```python
"""
Verifica que el binario no tenga overlaps de slot 1 / slot 2 / banks paginados.
Lee NuevoJuego.sym + main.asm (PAGE directives) y reporta:
  - Símbolos en $80XX que también son target de room_routes overflow.
  - Códigos always-visible (slot 1) que pasan de $7FFF.
  - Símbolos cuya dirección está fuera del rango del bank donde fueron
    incluidos.
Exit code 0 si todo OK, 1 si hay overlaps.

Uso: python tools/check_slot_overlap.py NuevoJuego.sym
"""
```

**A integrar** en `build_and_zesarux.bat` y `build_and_spectaculator.bat`
después del sjasmplus.

### 7.2 `tools/print_bank_layout.py`

Reporta el layout actual de cada bank con módulos identificados (entry
symbols → tamaños). Útil para revisitar el plan o decidir nuevas
movidas.

---

## 8. Protocolo de validación por fase

Después de cada commit de fase:

1. **Build clean**:
   ```
   sjasmplus code/main.asm --sym=NuevoJuego.sym ...
   ```
   Exit 0, sin warnings nuevos.

2. **Overlap check**:
   ```
   python tools/check_slot_overlap.py
   ```
   Exit 0.

3. **Diff de stats**:
   ```
   python tools/parse_build_stats.py /tmp/sjasm_out.tmp code/build_stats.json
   git diff code/build_stats.json
   ```
   Cambios coherentes con el plan.

4. **Smoke test runtime** (mínimo, en emulador):
   - Boot OK.
   - 3 transiciones de sala.
   - Recoger 1 pickup random (cualquier tipo).
   - Activar compass; verificar flecha.
   - Si la fase tocó cinemática: trigger esa cinemática.
   - Game over (al menos una vez por sesión de validación).

5. **Memoria actualizada**: si la fase descubre un patrón nuevo o corrige
   un invariante, actualizar `~/.claude/projects/C--NUEVO-JUEGO/memory/`.

---

## 9. Rollback

Cada fase es un commit limpio. Si una fase rompe el juego:

```bash
git revert <commit>     # revert atómico
# o, si es la última:
git reset --hard HEAD~1
```

`ram/optimize-slot1` se mergea a `main` solo cuando todas las fases
deseadas han pasado validación.

---

## 10. Métricas de éxito

- [ ] Slot 1 ≤ 70 % usado (≥ 2400 B libres).
- [ ] Bank 2 ≤ 92 % usado (≥ 1300 B libres).
- [ ] Cero overlap entre slot 1 y bank 2 (verificado por tooling).
- [ ] Smoke tests pasan en cada fase.
- [ ] Documentación actualizada (`docs/RAM_OPTIMIZATION_PLAN.md` con
      checkboxes marcados, memoria actualizada).

---

## 11. Pulido avanzado (post-plan, opcional)

Si tras las 4 fases sobra interés:

### 11.1 Compresión

- Aplicar RLE a sprites BG sin compresión (auditar `bg_gfx*.asm` con
  `grep -c "DEFB.*RLE" code/bg_gfx*.asm`).
- Compresión de `screen_rooms.asm` (10970 B en bank 1; los placements
  podrían comprimirse si hay repeticiones).

### 11.2 Datos compartidos

- Detectar tablas/strings duplicados entre módulos (algunos sprites
  pueden compartir attrs si se generalizan).

### 11.3 RAM expansion plan B/C/D (memoria preexistente)

La memoria del proyecto menciona "Fase A done (libera 653 B). B/C/D
pending si bank 0/2 vuelven a llenarse". Activar B/C/D si se acerca
al límite tras este plan.

### 11.4 Stack reduction

Auditar profundidad de stack. El stack vive en slot 2; reducirlo
podría liberar bytes (improbable que valga la pena).

---

## 12. Cronograma estimado

Este plan es **secuencial** (cada fase depende de la anterior por
disponibilidad de bank 7).

| Fase | Duración estimada | Riesgo |
| ---- | ----------------- | ------ |
| 0    | 30 min            | bajo   |
| 1    | 1–2 h             | medio  |
| 2    | 1 h               | medio  |
| 3    | 2–3 h             | alto   |
| 4    | 1–2 h             | medio  |

Total: ~6–9 h de trabajo dirigido.

---

## 13. Notas para el siguiente agente / sesión

- **HEAD del plan**: branch `ram/optimize-slot1`, commit que añade este
  doc.
- **Contexto extra**: ver `~/.claude/projects/C--NUEVO-JUEGO/memory/` —
  específicamente `project_ram_placement.md`, `project_ram_expansion_plan.md`,
  `project_sprite_2x_upscale.md`.
- **Hand-off al iniciar trabajo**: leer §3 (invariantes) y §5 (la fase
  exacta a abordar). No empezar por una fase posterior sin validar las
  anteriores.
- **Si el usuario quiere rapidez**: Fases 0 + 1 + 3 son el camino crítico
  (corrige overflow + libera 4 KB en slot 1). Fases 2 y 4 son optimización.
