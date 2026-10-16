# Rendimiento y fluidez de Tharkys: revisión medida (16 oct 2026)

Revisión hecha con las herramientas de **Experiment** (`tools/zxrun`, el emulador
sin ventana) adaptadas a Tharkys en `tools/perf/`. Todo lo de aquí está medido
en partidas guionizadas, no estimado a ojo. Cómo repetirlo: `tools/perf/README.md`.

## Resumen

| | Hoy | Con los parches P1-P7 |
|---|---|---|
| Cambio de sala (de día) | **~37 frames congelado (0,73 s)** | **~16 frames (0,33 s)** |
| Cambio de sala (de noche) | ~43 frames | ~18 frames |
| Vueltas de juego que no llegan a 25 fps | ≈3 % (de noche ≈2 %) | ≈1,3 % (1,0-2,0 %) |
| Interrupciones perdidas (música parada, reloj atrasado) | **4,5 % de los frames** | **0,05 %** |
| Frames con sprites vistos a medio pintar por el haz | 17-22 % | 11-14 % |
| Trabajo medio por vuelta de juego | ~82.000 T (58 %) | ~76.000 T (54 %) |
| Memoria | — | +256 B en bank 0, +69 B en slot 1 |

Los siete parches están en `parches/`, validados uno a uno (§3). Con P1-P4,
la pantalla que pinta cada sala, su mapa de colisión y la lista de casillas de
spawn salen **idénticos, byte a byte**, a los de hoy. Siguen sin aplicar:
decides tú cuáles entran.

Lo que más fluidez daría a continuación **no es código sino sonido**:
**los SFX de beeper paran la CPU**. Causan ~90 % de los tirones que quedan en
juego, porque un espadazo cuesta un frame entero. Pasarlos al motor AY que ya
existe (`sfx_library.json`) deja el juego a 25 fps el 99,5 % del tiempo,
incluso moviendo a los tres enemigos en cada vuelta (§4).

---

## 1. Cómo se ha medido

- **Emulador:** `zxrun` (núcleo *chips*, 128K) compilado en Linux, con el
  mismo `sjasmplus 1.21.1`. El `juego.sna` que sale es **idéntico** al
  commiteado. chips no emula la contienda, así que zxrun la estima (patrón
  6,5,4,3,2,1,0,0). Las cifras absolutas son aproximadas; las comparaciones
  antes/después, no.
- **Partidas:** se arranca con SPACE y luego un "explorador" con joystick
  Kempston recorre el mapa con tramos largos en una dirección y espadazos al
  azar (semilla fija = misma entrada). Escenarios: día, y noche (se pone el
  reloj a las 23:59 para que suenen las campanas y salgan los monsters).
  Partidas de 6.000 frames (2 min) y una prueba de resistencia de 15.000
  frames (5 min) × 3 semillas × día/noche.
- **Qué se mide:**
  - Cada **vuelta de `MainLoop`**. El juego va a 25 fps, así que una vuelta
    debe durar 2 ticks; 3 o más es un tirón.
  - El coste de **cada `CALL` del bucle**, y de lo que hay dentro de
    `DrawScreen`, `ProcessPlayer`…
  - Las **IRQ perdidas**: frames cuyo INT llega con `DI` y el handler no corre.
  - El **parpadeo**: bytes que el haz lee a medio pintar.
- **Partidas caóticas:** cualquier cambio de código cambia las trayectorias
  (±20 % frame a frame). Por eso se comparan medias de varias semillas.

## 2. Dónde se va el tiempo hoy

### 2.1 El cambio de sala es el gran parón

Cada vez que cruzas un borde, el juego se congela **34-38 frames de día y ~43
de noche**. En las partidas de prueba eso suma **el 12-13 % del tiempo de
juego**. Desglose de `DrawScreen` (media por cambio, 2,5 M T-states):

| Rutina | T por cambio | % | Qué pasa |
|---|---:|---:|---|
| `DrawBgGfxSprite` | 584.000 | 23 % | Decodificador RLE con el estado en variables de memoria: ~110-126 T por byte |
| `MaiComputeFlowField` | 583.000 | 23 % | BFS con `CALL` + 4 `PUSH/POP` + offset recalculado por vecino, **todo con `DI`** |
| `BuildCollisionMap` | 533.000 | 21 % | **Copia cada sprite entero (hasta 830 B) solo para leer 2 bytes**: alto y ancho |
| `LoadBgSpriteToBuffer` | 474.000 | 19 % | Los sprites RLE copian siempre 830 B; los literales, byte a byte (42 T/B) |
| `BuildZoneCellList` | 66.000 | 3 % | Con `DI` |
| `CheckIfHouseSprite` | 65.000 | 3 % | Recorre `HouseIdList` (~70 ids) por cada sprite |
| `SaveCleanAttrs` | 17.000 | 1 % | |

### 2.2 Interrupciones perdidas: la música se para

El 4,5 % de los frames pierde su interrupción. Dónde estaba la CPU cuando se
perdió el INT (3 partidas):

| Rutina | % de las perdidas |
|---|---:|
| BFS del flow field (`MaiTryCell`, `MaiFlowBfs`, `MaiOffsetFromCy`) + `BuildZoneCellList` | 69 % |
| `PlaySFX` (beeper con `DI`) | 30 % |

Como la música y los SFX AY avanzan en el handler IM 2, cada IRQ perdida es un
tick de música que no suena: la música **se para unos 160 ms en cada cambio de
sala** y se encoge con cada espadazo. Además, `$5C78` se atrasa, así que la
vuelta dura un frame más sin que el bucle se entere.

### 2.3 En juego normal

97 % de las vueltas a 25 fps; trabajo medio ~82.000 T de los 141.816 de dos
frames. Coste medio por vuelta (semilla 2):

| Rutina | Media T | p99 | Nota |
|---|---:|---:|---|
| `ProcessEnemies` | 30.200 | 57.800 | 2 enemigos por vuelta (round-robin) |
| `ProcessPlayer` | 17.000 | **97.500** | El pico es `PlaySFX(SFX_Attack)`: 75.000 T con `DI` |
| `DrawHealthStaminaHUD` | 7.600 | 8.100 | **Repinta 64 bytes de barras en cada vuelta** aunque no cambien |
| `CheckPickupCollect` | 5.800 | 9.900 | Recorre `PickupTable` entera y **copia el sprite del pickup cada vuelta** para el AABB |
| `CheckBumpTriggers` | 2.800 | 7.900 | |
| `CheckPlayerEnemyCollision` | 2.400 | 5.600 | Picos de 90.000+ = `SFX_EnemyDeath` |
| `CheckLockBump` | 2.000 | 3.100 | También copia el sprite entero para el AABB |
| `TrySpawnNasty` | 1.400 | **33.500** | `SFX_EnemySpawn` |
| `DrawKeyHUD` | 1.300 | 1.800 | Recarga y redibuja la llave cada vuelta |
| 5 × `Update*Buff` + `UpdatePlayerColorCycler` | ~3.500 | | |

**Los tirones en juego son casi todos de los SFX de beeper.** Con `PlaySFX`
anulado (solo para medir), las vueltas lentas bajan del 2,8 % al 0,1 %.

Coste de cada SFX de beeper, con `DI` (calculado desde `sound.asm`; el del
espadazo coincide con el medido):

| SFX | T | frames | Cuándo |
|---|---:|---:|---|
| `SFX_Attack` | 75.000 | 1,1 | cada espadazo |
| `SFX_EnemyDeath` | 87.000 | 1,2 | cada enemigo muerto |
| `SFX_EnemySpawn` | 26.000 | 0,4 | cada nasty que aparece |
| `SFX_NoSwordError` | 90.000 | 1,3 | |
| `SFX_Pickup` / `SFX_BadPickup` | 184.000 / 251.000 | 2,6 / 3,5 | pickups |
| `SFX_KeyDrop` / `SFX_DoorClose` | 195.000 / 215.000 | 2,8 / 3,0 | |
| `SFX_WellRecover` | 334.000 | 4,7 | pozo |
| `SFX_ChurchDoorOpen` | 703.000 | 9,9 | candados, cinemáticas |
| `SFX_Footstep*` | 2.000-3.000 | 0,04 | inocuos |

### 2.4 Parpadeo

El análisis del haz de zxrun estaba pensado para Absurd! (50 fps) y solo
evaluaba los frames que acaban en `HALT`. A 25 fps eso se salta el primer
frame de cada vuelta, que es donde se dibuja casi todo. Lo he adaptado: los
frames de una vuelta se evalúan juntos contra el estado estable anterior y el
final. Resultado: **17-22 % de los frames** muestran algo a medio pintar. El
principal culpable es `RestoreOldAttr`, que devuelve el color de fondo a un
bloque de 4×4 celdas **antes** de que `SetEntityAttr` vuelva a pintar el color
del sprite en las celdas que sigue ocupando. Si el haz pasa entre ambas, el
sprite sale un frame con el color del fondo. En el jugador la ventana es mayor:
entre las dos escrituras se dibuja el sprite entero.

---

## 3. Parches (validados, sin aplicar)

Están en `parches/`, en orden (cada uno se aplica sobre el anterior;
`todos.patch` es la suma):

```
git apply docs/rendimiento/parches/P1-cabeceras-sin-copia.patch   (y así hasta P7)
git apply docs/rendimiento/parches/todos.patch                      (o todos de golpe)
```

Cada uno lleva comentarios `; P1:`… en el código explicando el porqué.

| | Qué hace | Ganancia medida | Coste |
|---|---|---|---|
| **P1** | `LoadBgSpriteHeader`: copia solo alto y ancho (2 B, ~200 T) para quien solo necesita dimensiones (`BuildCollisionMap`, `CheckLockBump`, `CheckPickupCollect`, `BuildPickupRectCache`). El sprite entero solo se carga al recoger el pickup. | Cambio de sala 36,7 → 29,5 frames; `CheckPickupCollect` −1.300 T/vuelta | +51 B slot 1, +11 B bank 0 |
| **P2** | `LoadBgSpriteToBuffer` copia exactamente el sprite con `LDIR`: recorre el stream RLE hasta cubrir alto × ancho, y los literales van en una pasada. Validado sobre los 192 sprites: −60 % de bytes copiados. | 29,5 → 25,8 frames | +18 B slot 1 |
| **P3** | BFS del flow field ~4× más rápido. `FlowField` se rellena desde `CollisionMap` (`$FE` bloqueada / `$FF` libre), así que un vecino se mira con una sola lectura. La cola guarda punteros, y hay filas centinela arriba y abajo. **Sin `DI`**: la pila ya era la temporal de bank 2 y el handler no toca slot 3. `BuildZoneCellList` igual, con pila temporal en vez de `DI`. **Mismo BFS, mismas distancias, misma `ZoneCellList`.** | 25,8 → 20,5 frames; IRQ perdidas 4,5 % → 1,6 % (la música ya no se para al cambiar de sala) | +64 B bank 6 (los absorbe el `ALIGN` de `ShiftTables`) |
| **P4** | `DrawBgGfxSprite` con el estado RLE en registros, datos por `DE` en vez de `IX` y tramos del mismo chunk seguidos (37-54 T/byte en vez de 110-126). Atributos sin las dos `CALL` por celda cuando no hay tinte y es de día. `CheckIfHouseSprite` con un mapa de bits de 32 B. | 20,5 → 16,5 frames | +97 B bank 0 |
| **P5** | `DrawHealthStaminaHUD` solo repinta las barras si cambian salud o estamina. `DrawClockSprite`, que pinta la decoración encima y lo llama `DrawScreen`, invalida la caché. | −7.200 T por vuelta de juego (~9 % del trabajo) | +35 B bank 0 |
| **P6** | Orden pensado para el haz, en jugador y enemigos: 1) rect nuevo; 2) atributos nuevos; 3) borrar y dibujar píxeles seguidos; 4) fondo **solo** en las celdas que el sprite deja (`RestoreOldAttr` con rect excluido). El estado final es idéntico; cada atributo se escribe una vez por frame. | Frames con algo a medias 17-22 % → 11-14 %; escrituras de `RestoreOldAttr` vistas a medias −90 % | +114 B bank 0; ~+1.500 T por vuelta |
| **P7** | `PlaySFX` sin `DI`. El handler IM 2 (~250-900 T) corta el tono un instante cada 20 ms, pero la música y `$5C78` ya no pierden ticks. **Hay que escucharlo**: puede añadir un leve zumbido a 50 Hz en los tonos largos. | IRQ perdidas 1,6 % → 0,05 %; vueltas lentas en juego ~−50 % (el bucle ya no pierde ticks durante el SFX) | −1 B |

**Con los siete** (prueba de resistencia, 15.000 frames × 3 semillas × día/noche):
cambios de sala de 16-18 frames (hoy 34-37), vueltas lentas en juego 1,0-1,5 %
(hoy 1,9-3,2 %), sin cuelgues, y un 6-10 % más de vueltas de juego en el mismo tiempo.

### Cómo se validaron

- `tools/perf/drawcheck.py`: en cada `DrawScreen` vuelca la pantalla entera
  (fondo + objetos, antes de las tumbas) y la `ZoneCellList`, y compara las
  salas que aparecen en las dos versiones con el mismo estado (fase del día,
  tablas de remap, pozo, llave, posición del jugador y `CollisionMap`).
  P1-P4: **41 pantallas (día y noche) y 27 zonas idénticas**. Experimento de
  control: la versión de hoy con un retardo artificial da también 0
  diferencias. Así queda probado que las diferencias de las primeras pruebas
  venían del estado de la partida (tumbas, ventanas tras las campanadas),
  no de los parches.
- `tools/perf/sprites_check.py`: los 192 BG sprites cumplen lo que supone P2
  (el RLE acaba exactamente en alto × ancho; el más largo ocupa 797 B < 832).
- P3 se contrastó además con un BFS de referencia en Python.
- P6: el estado final de cada actualización es el mismo por construcción
  (mismas celdas pintadas y restauradas). Capturas revisadas a mano.
- Los parches se aplican limpios sobre `main` y el `.sna` resultante es el
  validado. La build `-DSTANDALONE=1` también compila y cabe.
- **Pila:** con zxrun midiendo el SP mínimo en partidas de 5 min, la pila baja
  como mucho a `$FF2A`. El código de bank 0 pasa de acabar en `$FD62` a `$FE62`:
  quedan 200 B de margen (hoy 456).
- **No probado:** hardware real ni emuladores con haz de verdad (Spectaculator,
  ZEsarUX). Toca jugar con los parches, sobre todo P6 (que no parpadee) y P7
  (cómo suena).

---

## 4. Siguientes oportunidades (sin parche)

Por impacto en fluidez:

1. **SFX de beeper → AY.** `sfx_interp.asm` + `sfx_library.json` ya existen
   y el plan del proyecto es migrar ("LEGACY: será reemplazado por
   sfx_interp.asm"). Prioridad por frecuencia: `SFX_Attack`,
   `SFX_EnemyDeath`, `SFX_EnemySpawn`, pickups, `SFX_NoSwordError`, llaves y
   puertas, y los tics de `UpdateBeeperTicks` (picos de 50.000 T). Es diseño
   de sonido tuyo. Medido: sin SFX bloqueantes, 99,5 % de vueltas a 25 fps.
2. **Mover a todos los enemigos en cada vuelta** (`MAX_ENEMIES_PER_FRAME`
   3 en vez de 2). Hoy, con 3 enemigos, cada uno se mueve 2 de cada 3
   vueltas: avanza a saltos. Con P1-P5 cuesta casi lo mismo en tirones que
   hoy con 2 (1,6-2,3 % de frames de más, hoy 1,5-1,7 %); con P1-P5 y sin SFX bloqueantes, **0,3-0,4 %**.
   Pero es decisión de diseño: los enemigos irían 1,5× más rápido y habría que
   reajustar `EnemySpeedTable`, `MONSTER_SPEED` y los retardos de animación.
   Relacionado: el *boost* del jugador según el número de enemigos
   (`code/MEMORY.md` §5) se pensó para compensar caídas de framerate. Medido,
   el bucle se mantiene a 25 fps con 0-3 enemigos; lo que se frena es cada
   enemigo. Hoy ese boost hace al jugador más rápido cuando hay enemigos.
   Conviene revisarlo junto con esto.
3. **Bucles que recorren tablas globales cada vuelta** (~8.000-10.000 T, otro
   ~12 % del trabajo): `CheckPickupCollect`, `CheckBumpTriggers`,
   `CheckLockBump`, `RefreshPickupAttrs` y `PaintSynthPickupAttrs` recorren
   `PickupTable` entera. Un índice por sala construido en `DrawScreen`, como
   `BuildPickupRectCache`, los dejaría en 0-3 entradas.
   `CheckBankTriggerBg`/`CheckTownGateTriggerBg` paginan bank 7 en cada
   vuelta para mirar si estás en su sala: mejor comprobar la sala antes de
   paginar. `DrawKeyHUD` (caché por llave y parpadeo), los 5 `Update*Buff` y
   `UpdatePlayerColorCycler` (salida rápida si no hay buff activo).
4. **Parpadeo de píxeles.** El que queda es el clásico de borrar con XOR y
   volver a dibujar. Un `DrawSprite` que borre y dibuje línea a línea (cada
   byte escrito una sola vez) lo reduciría mucho. Otra opción es ordenar la
   actualización de entidades según dónde va el haz.
5. **Cambio de sala más corto** (~16 → ~10 frames):
   - limpiar la pantalla con `PUSH` justo tras un `HALT`; hoy el `LDIR` de
     6.912 B cuesta 145.000 T, 2 frames;
   - dibujar los BG sprites directamente desde su banco, moviendo
     `DrawBgGfxSprite` a memoria siempre visible, sin la copia (158.000 T);
   - meter `BuildZoneCellList` en la ventana del BFS (70.000 T).
6. **Memoria para compensar los parches.** `tools/memory_map.py --dead` marca
   código muerto en bank 0: `BgGfx_hud_buff_*`, `BgGfx_hud_clock_decay`,
   `ResetAttrBlock`, `ChurchCutsceneDrawStatueAtLast`, `ClearScreen`… Además,
   la navegación por flow field no se usa (`MaiFlowFieldDirection`,
   `CheckPlayerZoneAtChar`, `MaiMaybeRecomputeFlow`: ~300 B en bank 2). Si la
   quieres reactivar algún día, con P3 el BFS ya cuesta ~1,6 frames en vez de ~8.

## 5. Herramientas

- `tools/perf/`: `build.py` (variantes fuera del repo, con parches), `bench.py`
  (perfil por vuelta y por rutina, haz), `drawcheck.py` (equivalencia de lo
  pintado), `irqlost.py` (IRQ perdidas por rutina), `sprites_check.py`.
- `tools/perf/zxrun_tharkys.patch`: mejoras al `zxrun` de Experiment
  (`--irq`, `--dump`, `--stable`, `--beam-skip`, haz para bucles de 25 fps,
  SP mínimo, más `--prof`). Son compatibles con Absurd!; la única diferencia
  allí es que el haz evalúa también los frames perdidos, que antes se saltaba.
