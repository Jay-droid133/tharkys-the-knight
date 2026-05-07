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
| 3565 | `CountActiveNasties` | `logic_game.asm` | Cuenta nastis vivos (excluye DYING/SPAWNING). Machaca B,C,DE,HL |
| 3569 | `CountActiveMonsters` | `logic_game.asm` | Cuenta monsters vivos (excluye DYING/SPAWNING). Machaca B,C,DE,HL |

## Magic compass (power-up "ruta exacta sala-a-sala")

Ver [docs/magic_compass.md](../docs/magic_compass.md) para la documentación completa del sistema (BFS multi-componente, pipeline build, datos, decisiones de diseño).

| Rutina | Archivo | Funcionalidad |
|--------|---------|---------------|
| `ApplyMagicCompassBuff` | `magic_compass.asm` | Activa el power-up (refresh-on-pickup). Llamada desde `CheckRandomSyntheticPickup` y `CheckPickupCollect`. |
| `CancelMagicCompass` | `magic_compass.asm` | Cancela el efecto. Hooks: muerte (`OnPlayerHealthDepleted`), avance de hito (3 puntos en `milestones.asm`). |
| `UpdateMagicCompass` | `magic_compass.asm` | Tick por frame: timer 16-bit + blink phase + AY tick heartbeat + jingle sequencer + dispatch BFS si `PathDirty`. |
| `GetMagicCompassAttr` | `magic_compass.asm` | Devuelve `$70`/`$30` según fase del blink (3 Hz normal, 6 Hz warning últimos 5 s). |
| `ComputeMagicCompassPath` | `magic_compass.asm` | BFS reverse desde target hasta current con state `(sid, comp_local)`. Lee `RoomCompGapsTable`. Escribe `MagicCompassPathDir`. |
| `RoomCompGapsTable` | `room_routes.asm` | 256 ptrs DEFW (auto-generados). Records `(side_comp, coord) × count` por sala. side_comp = bits 0-1 side + bits 2-3 comp. |
| Override en `DrawCompass` | `milestones.asm` | Si `MagicCompassTimer > 0` y no estás en sala destino: sobrescribe sprite idx (1=N, 7=S, 3=W, 5=E) y attr (paper amarillo blink). |
| Tracking en `CheckScreenTransition` | `screen_system.asm` | Setea `LastEntrySide` (side opuesto al cruzado) + `LastEntryCoord` (POSX/8 o (POSY-16)/8 según side). Necesario para arrancar el BFS con el comp correcto. |
