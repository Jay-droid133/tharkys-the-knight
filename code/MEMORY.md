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

## 5. Sistema de Compensación de Velocidad por Nastis

Cuando hay múltiples nasties en pantalla, la CPU del Spectrum no da abasto y el framerate cae. Para que el jugador perciba la misma velocidad, se aplica un boost dinámico a **movimiento** y **animación**.

### 5.1 Boost de Movimiento (UpdatePlayerMovement, ~línea 1025)
*   **Mecanismo**: tabla fraccionaria `.speedBoostTable` + acumulador 8-bit (`SpeedFracAccum` en variables.asm).
*   Cada entrada de la tabla tiene `[entero, fraccion_256]`. El acumulador suma la fracción cada frame; al desbordar (>= 256) se añade +1px extra ese frame.
*   **Velocidades resultantes (px/frame promedio)**:

| Nastis | Corriendo (base 2) | Atacando (base 1) |
|--------|--------------------:|------------------:|
| 0      | 2.0                | 1.0               |
| 1      | 2.5                | 1.5               |
| 2      | 3.0                | 2.0               |
| 3      | 3.5                | 2.5               |

*   **Ajuste**: modificar los `DEFB` de `.speedBoostTable` en logic_game.asm (~línea 1171).

### 5.2 Boost de Animación (UpdatePlayerAnimation, .applyAnim, ~línea 1468)
*   **Mecanismo**: reduce el `ANIM_DELAY` en -1 por cada nasty a partir del 2do. Mínimo delay = 1 frame.
*   IMPORTANTE: `CountActiveEnemies` destruye B y C — se protegen con PUSH/POP antes de la llamada.
*   **Delays resultantes (frames entre cambio de sprite)**:

| Nastis | Corriendo (base 4) | Atacando (base 2) |
|--------|-----------:|-----------:|
| 0-1    | 4          | 2          |
| 2      | 3          | 1          |
| 3      | 2          | 1          |

### 5.3 Variables Relacionadas
*   `SpeedFracAccum` (variables.asm) — acumulador fraccionario, se resetea a 0 sin nastis.
*   `PlayerCurrentSpeed` (variables.asm) — velocidad final aplicada (debug HUD).
*   `CountActiveEnemies` (logic_game.asm, ~línea 3542) — cuenta monsters + nasties vivos (slots SLOT_MONSTER0..SLOT_NASTY0+NUM_NASTIES-1, excluye DYING y SPAWNING). Machaca B, C, DE, HL.

## 6. Archivos de Referencia
*   `code/MEMORY.md` — Este archivo. Mapa del proyecto y arquitectura.
*   `code/asm_index.md` — Indice de rutinas Z80 con lineas y archivos.
*   `docs/game_design.md` — Game Design Document completo (historia, mecanicas, progresion).
*   `TODO.md` — Lista de bugs, tareas pendientes e ideas.
