# Índice de Rutinas Z80

Aquí listamos todas las rutinas importantes del código con sus ubicaciones para fácil navegación (Actualizar tras cada sesión según las reglas).

| Línea | Rutina | Archivo | Funcionalidad |
|-------|--------|---------|---------------|
| 13 | `Inicio` | `main.asm` | Inicio del juego, desactiva interrupciones, fija pila |
| 23 | `MainLoop` | `main.asm` | Bucle principal a 50Hz (sincronizado con Halt) |
| 7 | `ClearScreen` | `engine_graphics.asm` | Limpia la pantalla usando rutina de la ROM |
| 7 | `ReadInput` | `logic_game.asm` | Plantilla para leer los controles |
| 10 | `UpdateLogic` | `logic_game.asm` | Plantilla para la lógica temporal del juego |
| 13 | `DrawGame` | `logic_game.asm` | Plantilla para renderizado del frame |
| 1004 | `UpdatePlayerMovement` | `logic_game.asm` | Movimiento del player con boost fraccionario por nastis |
| 1407 | `UpdatePlayerAnimation` | `logic_game.asm` | Animación del player con boost de delay por nastis |
| 3542 | `CountActiveEnemies` | `logic_game.asm` | Cuenta monsters + nastis vivos (excluye DYING/SPAWNING). Machaca B,C,DE,HL |
