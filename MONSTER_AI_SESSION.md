# Monster AI v2 — session log (2026-04-22)

Rama: `feature/monster-ai-v2`. Branch-from `main` (`beb6682`). No merged.

## Estado jugable actual

Los tres monsters aparecen por huecos al anochecer, te siguen al cambiar de
room, rodean obstáculos sencillos, y al empujarlos con la espada salen por
el lateral y vuelven por el mismo hueco tras ~2 s.

## Fases completadas

### Fase 1 — ScreenGaps precalculados (commit `0376343`)
- Script `tools/build_screen_gaps.py` lee `code/screen_data.asm` (MapTable
  exportada), `code/screen_rooms.asm` (placements) y `code/bg_gfx.asm` +
  `code/bg_gfx_b.asm` (dimensiones de sprite, incluye autoFills IDs 200+
  siguiendo aliases EQU).
- Emite `code/screen_gaps.asm` a bank 6: `ScreenGapsTable` (256 DEFW ptrs por
  screen_id = Y*16+X) + por-room `DEFB count, {side, coord}×count`.
- Filtro valida huella 2×3 del monster + pertenencia a la región conexa
  principal con `MIN_POCKET_SIZE=20`. Sin esto, spawn podía caer sobre BG
  sprites o en bolsillos inalcanzables.
- Coord emitida = char top-left del monster (alineado a char), no el borde
  crudo.

### Fase 2 — Estructuras runtime (commit `d567893`)
- RAM baja +15 B: `MonsterRoomId[3]`, `MonsterLingerTimer[3]`,
  `MonsterEntryBorder[3]`, `MonsterAiFlags[3]`, `RoomHistory[3]`.
  (Varias de estas aún no se usan — reservadas para fases pendientes.)
- Bank 6 +~900 B: `FlowField` (704 B), `BfsQueue` (128 → 1408 B más tarde).

### Fase 3 — Flow field BFS (commit `6b99559`, desactivado en `a8fdf65`)
- `MaiComputeFlowField` con stack temporal de 128 B en bank 2 para los CALLs
  internos del BFS (no se puede usar el stack real porque vive en slot 3
  paginado).
- Desactivado: coste real ~1 M T-states = 7 frames de stutter. La
  infraestructura queda pero NO se llama desde el main loop.
- Reactivación futura: refactor a BFS amortizado (K iteraciones/frame,
  estado persistente entre frames, reinicio en cambio de celda del player).

### Fase 4 — Regla 1 (commit `fa8e276`)
- `MaiPickRandomGap` + hook en `SpawnMonsters`: cada monster en su primera
  aparición de la noche pilla hueco aleatorio del screen actual (no
  `LastEntryPos`).
- Crash fix inicial (`9c42d51`): `monster_ai.asm` tenía que vivir en bank 2
  fijo (`INCLUDE` después de `paging.asm`) porque al paginar bank 6 el
  propio código se iba a tomar por saco si estaba en bank 0. Además toda
  paginación es **inline** — nada de `CALL PageBankSlot3` durante la ventana
  paginada (el stack vive en slot 3).
- Fix (`584a6af`): `TryRespawnMonsters` sobrescribía POSX/POSY al activar.
  Ahora respeta lo que puso `SpawnMonsters`/`RepositionMonstersAtEntry`.

### Fase 5 — Regla 2 amplia (commit `6f9978e`, fix `41aa748`)
- Al cambiar de room, cada monster entra por un hueco **aleatorio del
  mismo borde** que cruzó el player — no apilados en `LastEntryPos`.
- `MaiPickRandomGapOnSide(side)` + `MaiGetEntrySide`.
- Fix importante (`41aa748`): `POP BC` destruía el idx objetivo cargado
  en `C`. Antes: los 3 monsters cogían siempre el mismo gap.

### AI híbrido reactivo (commits `f30f5b1`, `74e8cc7`, `ed0124c`, `3ee6614`)
Capas en `UpdateMonster.moDoMove`:
1. **Greedy primary**: intenta dirección primaria hacia player. Si pasa → go.
2. **Persistence**: si greedy bloqueada, continúa dirección anterior
   (commitment al rodeo).
3. **Random en alineamiento**: cuando player está en línea recta (hDx=0 o
   vDy=0), randomiza el eje 0 para romper trampa de oscilación.
4. **Recalc completo**: 4 candidatos (primary, secondary, rev, backtrack).

Sin la capa 3, el monster oscilaba 2 celdas frente a un muro alineado.
Sin la 2, no rodeaba obstáculos en L/U. Sin la 1, no snapeaba de vuelta a
greedy tras rodear.

Animación: sprite mira hacia la dirección de `DELTAX`, no al player. Excepto
durante stun/knockback (`ENT_DIR != 0`) donde sí mira al player.

### Fase 6 — Regla 4 (commits `6ce8f5f`, `7dae950`, `f9479c1`, `4ff84dd`, `5c83451`, `c3a0aa1`)
- Al salir por knockback, `.moKbOffscreen` registra el borde en `ENT_DIR`
  (DIR_N/S/E/W) — sobrecargado con el stun counter pero no hay conflicto
  porque TYPE_NONE durante el timer.
- Timer por monster `MAI_LINGER_PUSHED=50f` (~2s).
- `.rmUpdateReturnTimers` al expirar: llama `MaiPickNearestGapOnSide` con
  target coord = char-position del crossing point, elige el gap cuya
  coord sea la más próxima. Así al empujar por el gap superior de un
  pasaje dual, vuelve por el superior.
- Elección de eje de salida por **magnitud del knockback**, no por borde
  cruzado primero: si `|DELTAX| >= |DELTAY|`, fuerza salida por X (más
  coherente con la intención del player).
- Knockback diagonal preservado (esencial para dinámica del billar).
- Multi-monster fix (`5c83451`): `.rmCheckSlots` ahora respeta
  `MonsterReturnTimer` individual por slot. Antes: si M1 expiraba y M2
  seguía con timer, M2 se activaba en su posición clampada offscreen en
  vez de Regla 4.

## Layout memoria

- **RAM baja** (+15 B en bank 0 / bank 2 fijo): estado monster + RoomHistory.
- **Bank 2 fijo** ($8000-$BFFF): todo `monster_ai.asm` (rutinas que paginan
  bank 6 deben vivir aquí para no evaporarse al cambiar slot 3).
- **Bank 6** ($C000-$FFFF paginable): `ScreenGaps` (~2.5 KB), `FlowField`
  (704 B reservados, sin uso), `BfsQueue` (1408 B reservados, sin uso).

## Constantes tuneables (`constants.asm`)

```
MAI_LINGER_NORMAL   EQU 45      ; ~1.8s migrar tras abandono sin push (no usado aún)
MAI_LINGER_PUSHED   EQU 50      ; ~2s vuelta tras knockback
MAI_ENTRY_OFFSET    EQU 0       ; spawn inicial al borde
MAI_REENTRY_OFFSET  EQU 16      ; reentry tras push: 2 chars dentro
MAI_FLOW_INTERVAL   EQU 10      ; frames entre BFS (no usado; flow field desactivado)
```

## Trade-offs conocidos

- **Flow field desactivado**. Monsters usan AI reactiva híbrida. Rodean
  obstáculos simples bien, pero no hacen pathfinding real en laberintos
  complejos. Reactivar exige BFS amortizado (no trivial — el actual cuesta
  ~7 frames de stutter por invocación).
- **Residuo de color post-knockback**. Al morir el monster por knockback
  offscreen, los atributos de sus ~2×3 celdas quedan con su `ENT_ATTR`
  hasta que algo los repinta. El intento de `RestoreOldAttr` en
  `.peScaredDespawn` corrompía la pantalla masivamente (probablemente por
  invadir attrs del player/HUD con la huella 3×3 genérica); revertido en
  `c3a0aa1`. Fix limpio futuro: `RestoreOldAttr` con huella 2×3 exacta.
- **Exit side cuando empuje diagonal cerca de esquina**: si el player empuja
  con `|DX| ≈ |DY|` y el monster está muy cerca de la esquina, puede salir
  por el eje "equivocado" según la intuición del player. Mitigado (tie
  decide X), pero no perfecto.
- **Primer fresh-draw en reentry**: XOR sin erase previo. Matemáticamente
  balanceado por el `.peScaredDespawn` inicial, pero si el player se ha
  movido entre medias, overlap puede flickerear 1-2 frames hasta que el
  monster se mueve.

## Bugs/features pendientes

De la lista original de 7 reglas, quedan:
- **Regla 7 / STATE_LEAVING**: al amanecer, los monsters buscan un gap,
  caminan y cruzan → despawn visual limpio. Ahora mismo desaparecen de golpe.
- **RoomHistory[3]**: si dejas un monster más de 2 rooms atrás, debería
  teletransportarse a tu room actual. `MonsterRoomId` está reservado pero
  no se usa.
- **Debug key `K`**: kill all monsters en room actual (útil para tuning).

Ajustes opcionales:
- BFS amortizado para reactivar flow field.
- `RestoreOldAttr` con huella exacta 2×3 para eliminar residuo de color sin
  corromper nada.
- Detección de knockback saliente cuando el monster ya estaba en el borde
  (edge case: lo golpeas pegado a la pared, no hay recorrido de knockback).

## Gotchas aprendidas (para no repetir errores)

1. **Paging + stack**: cualquier rutina que pagine `bank 6` a slot 3 debe
   vivir en bank 2 fijo ($8000-$BFFF) y no hacer NINGÚN stack op durante
   la ventana paginada (PUSH/POP/CALL/RET). Si necesita CALLs internos,
   swap de SP a un stack temporal en bank 2.
2. **JR fuera de rango**: cuando un bloque crece, `JR`/`DJNZ` de más de
   127 bytes fallan. Cambiar a `JP`/`DEC B + JP NZ`.
3. **Sprite height ceil vs floor**: `(h_px + 7) // 8` (Python) vs `h_px >> 3`
   (Z80 runtime). Coinciden solo si `h_px` es múltiplo de 8. Todos los
   sprites actuales lo son, pero worth tener en mente.
4. **`CALL` preserva IX implícitamente** si la rutina llamada no lo toca.
   `DrawSprite` SÍ lo toca (usa como source pointer). `PUSH IX`/`POP IX`
   obligatorio si el caller lo necesita después.
5. **`POP BC` destruye C**: si guardas un valor en C antes de un `POP BC`,
   se pierde. Hacer los POPs antes de asignar o reordenar.
6. **Level editor autoFills**: `level_data.json` NO contiene los auto-fill
   sprites de bordes. El script debe parsear la ASM exportada para ver la
   verdad que ve el juego.
7. **`ScreenTransition` vs `LastScreenTransition`**: el primero se
   resetea cada frame en `CheckScreenTransition`; el segundo persiste.
   Para `MaiGetEntrySide` durante `RepositionMonstersAtEntry` basta con
   `ScreenTransition` porque ahí aún está set.

## Archivos clave

- `code/monster_ai.asm` — rutinas AI/pick-gap/flow-field (bank 2 fijo).
- `code/monster_ai_bank6.asm` — buffers `FlowField` + `BfsQueue` en bank 6.
- `code/screen_gaps.asm` — generado. Regenerar con `python tools/build_screen_gaps.py`.
- `code/screen_gaps.report.txt` — reporte por room de qué openings se emiten.
- `tools/build_screen_gaps.py` — filtro ScreenGaps.
- `code/logic_game.asm` — cambios en `SpawnMonsters`, `UpdateMonster`,
  `TryRespawnMonsters`, `.rmUpdateReturnTimers`, `RepositionMonstersAtEntry`,
  `.moKbOffscreen`, `.peScaredDespawn`, `.moAnimate`.
- `code/constants.asm` — constantes `MAI_*`.
- `code/variables.asm` — vars de estado monster.

## Próximos pasos sugeridos

1. Merge a `main` o seguir iterando en la rama.
2. Elegir entre Regla 7 (STATE_LEAVING), RoomHistory, o Debug K.
3. Si el flow field se reactiva en el futuro, hacerlo con BFS amortizado.
