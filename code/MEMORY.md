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

## 3. Notas Arquitectónicas
_(Añadir notas cuando se decida el género del juego: Scroll, Isométrico, Pantallas fijas, etc.)_
