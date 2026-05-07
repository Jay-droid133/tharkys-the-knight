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
| `UpdateMagicCompass` | `magic_compass.asm` | Tick por frame: timer 16-bit + AY tick heartbeat + jingle sequencer + dispatch del BFS amortizado si `PathDirty` o `BfsState=1`. |
| `PaintMagicCompassAttrs` | `magic_compass.asm` | Pinta los 4 chars del HUD compass con `MagicCompassBaseAttrs` (decididos por el editor); si el tick está sonando override del char activo a `$47` (white bright). |
| `ComputeMagicCompassPath` | `magic_compass.asm` | BFS reverse amortizado en chunks (8 iter/frame). State `(sid, comp_local)` con resume entre frames. Lee `RoomCompGapsTable`, escribe `MagicCompassPathDir`. |
| `RoomCompGapsTable` | `room_routes.asm` | 256 ptrs DEFW (auto-generados). Records `(side_comp, coord) × count` por sala. side_comp = bits 0-1 side + bits 2-3 comp. |
| `Sprite_Compass_Magic` + `MagicCompassBaseAttrs` | `sprite_magic_compass_hud.inc` | Auto-generado por `tools/import_magic_compass_hud.py` desde sprite ID 36 (`bg_sprites.json`). 32 bytes pixel raw + 4 bytes attrs (bit BRIGHT clearado). Incluido desde `magic_compass.asm`. |
| Override en `DrawCompass` | `milestones.asm` | Si `MagicCompassTimer > 0` y no estás en sala destino: dibuja `Sprite_Compass_Magic` (con cache `LastMagicCompassDrawn`, redraw solo en cambio de PathDir) + llama a `PaintMagicCompassAttrs`. Skip del wobble en magic mode + invalidación de cache + abort del BFS al cambiar de sala. |
| Tracking en `CheckScreenTransition` | `screen_system.asm` | Setea `LastEntrySide` (side opuesto al cruzado) + `LastEntryCoord` (POSX/8 o (POSY-16)/8 según side). Necesario para arrancar el BFS con el comp correcto. |
