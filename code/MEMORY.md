# Mapa del Proyecto y Arquitectura

Este archivo sirve como referencia principal para la estructura del proyecto y su estado organizativo.

## 1. Estructura de Archivos
*   `code/main.asm` - Punto de entrada, configuración de hardware.
*   `code/constants.asm` - Constantes, memoria y variables locales.
*   `code/variables.asm` - Variables gestionadas en la RAM.
*   `code/macros.asm` - Macros Z80.
*   `code/engine_graphics.asm` - Motor de renderizado.
*   `code/logic_game.asm` - Reglas físicas y de jugabilidad.

## 2. Mapa de Memoria
*   `$4000 - $57FF`: Video RAM (Píxeles)
*   `$5800 - $5AFF`: Video RAM (Atributos)
*   `$8000`: Inicio del código (`ORIGIN_ADDRESS`)
*   `$FF58`: Pila / Stack Pointer

## 3. Build & Run

*   **Script**: `code/build_and_spectaculator.bat` — compila y lanza el emulador
*   **Compilador**: `I:\PROGRAMACION\COMPILADORES\sjasmplus-1.21.1.win\sjasmplus.exe`
*   **Emulador**: `C:\Program Files (x86)\Spectaculator\Spectaculator.exe`
*   **Ejecutar desde CLI**: `cmd.exe /c "pushd <raiz_proyecto>\code && .\build_and_spectaculator.bat"`
*   El bat sincroniza bg_gfx.asm y screen_data.asm desde el repo principal si detecta worktree.
*   Output: `code/juego.tap` y `code/juego.sna`

## 4. Notas Arquitectónicas
*   Clon de Sabre Wulf. Round-robin de enemigos (MAX_ENEMIES_PER_FRAME=2). Entidades en EntityTable (17 slots x 12 bytes). Ciclo dia/noche con 7 fases.

## 5. Framerate: híbrido 50/25 Hz (player a 50, mundo a 25)

**OBSOLETO desde 5468db7 (abr 2026):** el antiguo boost dinámico por número de
enemigos (tablas fraccionarias + `SpeedFracAccum` + boost de anim) **ya no
existe**. Se sustituyó por framerate fijo de 25 fps, y desde jul 2026 por el
**híbrido 50 Hz**: el MainLoop divide el par de 40 ms en dos sub-frames con un
HALT intermedio (el frameSync sigue cerrando el par a 2 ticks = timers y
lógica a 25 fps intactos):

*   **Tick A** (`TickA`/`TickAGameplay` en music_irq.asm, slot 1): ReadInput
    (input a 50 Hz), player a `floor(S/2)` + redraw (`ProcessPlayer.plDraw`),
    1 enemigo del round-robin (`EnemyBudget`), `ProcessDeath` y el HUD
    (`DrawHudBlock`). Gateado en pausa/cutscenes (solo HUD).
*   **Tick B**: el frame de siempre — estado/ataque/animación del player
    (25 Hz), la otra mitad del movimiento (`S - floor(S/2)`, flag
    `HalfPassPhase`), el otro enemigo, pickups/colisiones/sistemas.
*   La suma por par es exactamente S → misma velocidad (`SPEED_RUN = 4`
    px/par = 100 px/s; fight 2; rayo 6/3; caracol 2/1), posición muestreada
    al doble. `SnapPlayerOnStop` alinea a mod 4 al parar (offsets {2,6} mod 8
    rompen el attr-paint bajo los pies — mismo fail-safe que el fin del
    CARACOL).

`CountActiveNasties`/`CountActiveMonsters` siguen en logic_game.asm pero sin
callers (candidatas a dead-code).

### 5.1 Perfil de CPU medido (jul 2026, perf probe del port)

Instrumentación en `port/src/emu.c` (activar con `?perf=1` web / `--perf`
desktop): T-states de trabajo por frame via pin HALT + histograma de PC.
Presupuesto por frame de juego (2 ticks) = 141.816 T; medido tras los perf
gates: salas normales ~45-80k, salas cargadas (3 entidades + Muerte) pico
~90-120k. Dominante: `_DrawSpriteImpl` (render XOR entidades, 50-64% del
trabajo). chips no emula contention: sumar ~8-12% para hardware real.

### 5.2 Perf gates (jul 2026)

MainLoop ya no paga trabajo per-frame cuando no hay nada que hacer:
*   `DrawHealthStaminaHUD` / `DrawKeyHUD`: dirty-flags (redibujan solo al
    cambiar nivel/llave; invalidación en DrawScreen/DrawClockSprite).
*   `CheckBumpAndLocks` (screen_system.asm): wrapper de CheckBumpTriggers +
    CheckLockBump — skip total en salas sin locks/puertas y dims de sprites
    desde `BumpLockCache` (rellenado por BuildPickupRectCache) en vez de
    `LoadBgSpriteToBuffer` por frame.
*   `UpdateBuffTicks` / `UpdateSynthAndRoulette` + gate de `UpdateRandomPickup`:
    replican el early-out de los bodies de bank 7 ANTES del thunk (SP swap +
    doble page switch), leyendo las mismas variables always-visible.

## 6. Escalado de Velocidad y Animación de Nasties por Ciclo

La velocidad de los nasties sube con `DayCycleCount` (`EnemySpeedTable`). La animación ahora también escala con `EnemyAnimDelayTable` para que las patas acompañen al movimiento.

*   `UpdateEnemySpeed` (logic_game.asm) — cada frame, lee ambas tablas y actualiza `CurrentEnemySpeed` y `CurrentEnemyAnimDelay`.
*   La rata (`SPRID_ENEMY_5`) usa siempre la mitad del delay (mínimo 1).
*   **Tablas (ajustables)**:

| Ciclo | Velocidad | Anim Delay | Rata Delay |
|-------|-----------|------------|------------|
| 1     | 1px       | 8          | 4          |
| 2     | 1.5px     | 7          | 3          |
| 3     | 2px       | 6          | 3          |
| 4     | 2.5px     | 5          | 2          |
| 5     | 3px       | 4          | 2          |
| 6     | 3.5px     | 4          | 2          |
| 7     | 4px       | 3          | 1          |
| 8     | 4.5px     | 3          | 1          |
| 9     | 5px       | 2          | 1          |
| 10    | 6px       | 2          | 1          |

### Pendiente: Aplicar sistema similar a los Monsters

Los monsters **no** tienen aún escalado de velocidad ni animación por ciclo. Para implementarlo:

*   Velocidad actual fija: `MONSTER_SPEED EQU 1` (constants.asm ~línea 165).
*   Animación actual fija: `ENEMY_ANIM_DELAY` en sus rutinas de update.
*   Necesario crear: `MonsterSpeedTable`, `MonsterAnimDelayTable`, `CurrentMonsterSpeed`, `CurrentMonsterAnimDelay`.
*   Las rutinas de monster están en `ProcessOneEnemy` (logic_game.asm ~línea 356), separadas de `UpdateEnemy` (nasties).
*   Los monsters son sprites 2×2 (más grandes), sus valores de velocidad necesitarán ajuste independiente.
*   Debug: teclas S/D (`CheckDebugKeys`, day_cycle.asm) cambian `DayCycleCount` y servirán para probar el escalado.

## 7. Archivos de Referencia
*   `code/MEMORY.md` — Este archivo. Mapa del proyecto y arquitectura.
*   `code/asm_index.md` — Indice de rutinas Z80 con lineas y archivos.
*   `docs/game_design.md` — Game Design Document completo (historia, mecanicas, progresion).
