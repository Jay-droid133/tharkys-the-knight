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

## 5. Archivos de Referencia
*   `code/MEMORY.md` — Este archivo. Mapa del proyecto y arquitectura.
*   `code/asm_index.md` — Indice de rutinas Z80 con lineas y archivos.
*   `docs/game_design.md` — Game Design Document completo (historia, mecanicas, progresion).
*   `TODO.md` — Lista de bugs, tareas pendientes e ideas.
