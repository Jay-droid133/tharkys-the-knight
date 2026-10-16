# Rendimiento y fluidez de Tharkys: revisión medida (16 oct 2026)

Revisión hecha con las herramientas de **Experiment** (`tools/zxrun`, el emulador
sin ventana) adaptadas a Tharkys en `tools/perf/`. Todo lo de aquí está medido
en partidas guionizadas, no estimado a ojo. Cómo repetirlo: `tools/perf/README.md`.

## Resumen

Antes (`956e064`) frente a ahora (`39afdbc`), con las mismas partidas y el
mismo emulador (3 semillas × 6.000 frames, de día y de noche):

| | Antes | Ahora |
|---|---|---|
| Cambio de sala, de día | **36,7 frames congelado (0,73 s)** | **16,1 frames (0,32 s)** |
| Cambio de sala, de noche | 38,8 frames | 17,6 frames |
| Vueltas de juego que no llegan a 25 fps, día / noche | 2,9 % / 2,3 % | **0,2 % / 0,4 %** |
| Tiempo de juego perdido en tirones, día / noche | 1,6 % / 1,7 % | 0,25 % / 0,4 % |
| Interrupciones perdidas (música parada, reloj atrasado), día / noche | **4,5 % / 3,5 % de los frames** | **0,05 % / 0,1 %** |
| Frames con algo visto a medio pintar por el haz, día / noche | 18,8 % / 16,0 % | 12,5 % / 12,0 % |
| Trabajo medio por vuelta de juego (de día) | 82.300 T (58 %) | 72.700 T (51 %) |
| Memoria libre en bank 0 | 670 B | 711 B |

Qué se ha hecho (rama `ccr-0b7542b9-igk045`):

1. **Siete optimizaciones (P1-P7)**, un commit cada una (§3.1). Con P1-P4, la
   pantalla que pinta cada sala, su mapa de colisión y la lista de casillas de
   spawn salen idénticos, byte a byte, a los de antes.
2. **Los SFX de beeper pasan al chip AY** (§3.2): el beeper paraba la CPU
   mientras sonaba (un espadazo costaba un frame entero) y era la causa de casi
   todos los tirones que quedaban. Solo siguen en beeper los pasos (<1 ms) y el
   tic del minimapa.
3. **Mover a los enemigos en cada vuelta**: hecho, pero **apagado** (§3.3).
   Los nasties dejan de avanzar a saltos con la misma velocidad media, pero de
   día el parpadeo sube del 12 % al 20 % de los frames y los tirones se
   multiplican por 4. Se enciende con una línea (`ENEMIES_EVERY_LOOP EQU 1` en
   `code/constants.asm`).
4. **Las mejoras de zxrun están en Experiment**, rama `ccr-0b7542b9-igk045`
   (commit `a1df2fb`, sin fusionar en `main`).
5. **Binarios regenerados**: `juego.sna`, `code/juego_release.tap`,
   `NuevoJuego.sym/.sld` y `code/build_stats.json`. La web de Pages y el zip de
   itch no se han vuelto a publicar.

Falta probarlo jugando (§6): sobre todo cómo suenan los SFX nuevos.

---

## 1. Cómo se ha medido

- **Emulador:** `zxrun` (núcleo *chips*, 128K) compilado en Linux, con el
  mismo `sjasmplus 1.21.1`. Compilando `956e064` sale **el mismo** `juego.sna`
  que estaba commiteado. chips no emula la contienda, así que zxrun la estima
  (patrón 6,5,4,3,2,1,0,0). Las cifras absolutas son aproximadas; las
  comparaciones antes/después, no.
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
  (±20 % frame a frame). Por eso se comparan medias de varias semillas. Ojo
  también con lo que depende del azar del juego (`LD A, R`): una versión con 7
  `NOP` de más, sin ningún otro cambio, da tres veces más ataques de
  depredador en las mismas partidas.

## 2. Dónde se iba el tiempo (antes de los cambios)

### 2.1 El cambio de sala era el gran parón

Cada vez que cruzabas un borde, el juego se congelaba **34-38 frames de día y
~40 de noche**: el 12-13 % del tiempo de juego en las partidas de prueba.
Desglose de `DrawScreen` (media por cambio, 2,5 M T-states):

| Rutina | T por cambio | % | Qué pasaba |
|---|---:|---:|---|
| `DrawBgGfxSprite` | 584.000 | 23 % | Decodificador RLE con el estado en variables de memoria: ~110-126 T por byte |
| `MaiComputeFlowField` | 583.000 | 23 % | BFS con `CALL` + 4 `PUSH/POP` + offset recalculado por vecino, **todo con `DI`** |
| `BuildCollisionMap` | 533.000 | 21 % | **Copiaba cada sprite entero (hasta 830 B) solo para leer 2 bytes**: alto y ancho |
| `LoadBgSpriteToBuffer` | 474.000 | 19 % | Los sprites RLE copiaban siempre 830 B; los literales, byte a byte (42 T/B) |
| `BuildZoneCellList` | 66.000 | 3 % | Con `DI` |
| `CheckIfHouseSprite` | 65.000 | 3 % | Recorría `HouseIdList` (~70 ids) por cada sprite |
| `SaveCleanAttrs` | 17.000 | 1 % | |

### 2.2 Interrupciones perdidas: la música se paraba

El 4,5 % de los frames perdía su interrupción. Dónde estaba la CPU cuando se
perdió el INT (3 partidas):

| Rutina | % de las perdidas |
|---|---:|
| BFS del flow field (`MaiTryCell`, `MaiFlowBfs`, `MaiOffsetFromCy`) + `BuildZoneCellList` | 69 % |
| `PlaySFX` (beeper con `DI`) | 30 % |

Como la música y los SFX AY avanzan en el handler IM 2, cada IRQ perdida es un
tick de música que no suena: la música **se paraba unos 160 ms en cada cambio
de sala** y se encogía con cada espadazo. Además `$5C78` se atrasaba, así que la
vuelta duraba un frame más sin que el bucle se enterase.

### 2.3 En juego normal

97 % de las vueltas a 25 fps; trabajo medio ~82.000 T de los 141.816 de dos
frames. Coste medio por vuelta (semilla 2):

| Rutina | Media T | p99 | Nota |
|---|---:|---:|---|
| `ProcessEnemies` | 30.200 | 57.800 | 2 enemigos por vuelta (round-robin) |
| `ProcessPlayer` | 17.000 | **97.500** | El pico era `PlaySFX(SFX_Attack)`: 75.000 T con `DI` |
| `DrawHealthStaminaHUD` | 7.600 | 8.100 | **Repintaba 64 bytes de barras en cada vuelta** aunque no cambiasen |
| `CheckPickupCollect` | 5.800 | 9.900 | Recorre `PickupTable` entera y **copiaba el sprite del pickup cada vuelta** para el AABB |
| `CheckBumpTriggers` | 2.800 | 7.900 | |
| `CheckPlayerEnemyCollision` | 2.400 | 5.600 | Picos de 90.000+ = `SFX_EnemyDeath` |
| `CheckLockBump` | 2.000 | 3.100 | También copiaba el sprite entero para el AABB |
| `TrySpawnNasty` | 1.400 | **33.500** | `SFX_EnemySpawn` |
| `DrawKeyHUD` | 1.300 | 1.800 | Recarga y redibuja la llave cada vuelta |
| 5 × `Update*Buff` + `UpdatePlayerColorCycler` | ~3.500 | | |

**Los tirones en juego eran casi todos de los SFX de beeper.** Con `PlaySFX`
anulado (solo para medir), las vueltas lentas bajaban del 2,8 % al 0,1 %.
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
| tics de buff y brújula (`BeeperTick`) | 28.000-40.000 | 0,4-0,6 | cada segundo con un buff o la brújula |
| `SFX_Footstep*` | 2.000-3.000 | 0,04 | inocuos |

### 2.4 Parpadeo

El análisis del haz de zxrun estaba pensado para Absurd! (50 fps) y solo
evaluaba los frames que acaban en `HALT`. A 25 fps eso se salta el primer
frame de cada vuelta, que es donde se dibuja casi todo. Lo he adaptado: los
frames de una vuelta se evalúan juntos contra el estado estable anterior y el
final. Resultado: **17-22 % de los frames** mostraban algo a medio pintar. El
principal culpable era `RestoreOldAttr`, que devolvía el color de fondo a un
bloque de 4×4 celdas **antes** de que `SetEntityAttr` volviese a pintar el
color del sprite en las celdas que seguía ocupando. Si el haz pasaba entre
ambas, el sprite salía un frame con el color del fondo. En el jugador la
ventana era mayor: entre las dos escrituras se dibujaba el sprite entero.

---

## 3. Cambios aplicados

### 3.1 P1-P7: optimizaciones sin cambio de comportamiento

Cada commit lleva comentarios `; P1:`… en el código explicando el porqué. Las
ganancias son las medidas al validarlos, acumuladas en orden.

| | Commit | Qué hace | Ganancia medida | Coste |
|---|---|---|---|---|
| **P1** | `e415ea9` | `LoadBgSpriteHeader`: copia solo alto y ancho (2 B, ~200 T) para quien solo necesita dimensiones (`BuildCollisionMap`, `CheckLockBump`, `CheckPickupCollect`, `BuildPickupRectCache`). El sprite entero solo se carga al recoger el pickup. | Cambio de sala 36,7 → 29,5 frames; `CheckPickupCollect` −1.300 T/vuelta | +51 B slot 1, +11 B bank 0 |
| **P2** | `cc1d1cd` | `LoadBgSpriteToBuffer` copia exactamente el sprite con `LDIR`: recorre el stream RLE hasta cubrir alto × ancho, y los literales van en una pasada. Validado sobre los 192 sprites: −60 % de bytes copiados. | 29,5 → 25,8 frames | +18 B slot 1 |
| **P3** | `9431cdc` | BFS del flow field ~4× más rápido. `FlowField` se rellena desde `CollisionMap` (`$FE` bloqueada / `$FF` libre), así que un vecino se mira con una sola lectura. La cola guarda punteros, y hay filas centinela arriba y abajo. **Sin `DI`**: la pila ya era la temporal de bank 2 y el handler no toca slot 3. `BuildZoneCellList` igual, con pila temporal en vez de `DI`. **Mismo BFS, mismas distancias, misma `ZoneCellList`.** | 25,8 → 20,5 frames; IRQ perdidas 4,5 % → 1,6 % (la música ya no se para al cambiar de sala) | +64 B bank 6 (los absorbe el `ALIGN` de `ShiftTables`) |
| **P4** | `ba8be2e` | `DrawBgGfxSprite` con el estado RLE en registros, datos por `DE` en vez de `IX` y tramos del mismo chunk seguidos (37-54 T/byte en vez de 110-126). Atributos sin las dos `CALL` por celda cuando no hay tinte y es de día. `CheckIfHouseSprite` con un mapa de bits de 32 B. | 20,5 → 16,5 frames | +97 B bank 0 |
| **P5** | `2bef180` | `DrawHealthStaminaHUD` solo repinta las barras si cambian salud o estamina. `DrawClockSprite`, que pinta la decoración encima y lo llama `DrawScreen`, invalida la caché. | −7.200 T por vuelta de juego (~9 % del trabajo) | +35 B bank 0 |
| **P6** | `06b388a` | Orden pensado para el haz, en jugador y enemigos: 1) rect nuevo; 2) atributos nuevos; 3) borrar y dibujar píxeles seguidos; 4) fondo **solo** en las celdas que el sprite deja (`RestoreOldAttr` con rect excluido). El estado final es idéntico; cada atributo se escribe una vez por frame. | Frames con algo a medias 17-22 % → 11-14 %; escrituras de `RestoreOldAttr` vistas a medias −90 % | +114 B bank 0; ~+1.500 T por vuelta |
| **P7** | `1e2be4a` | `PlaySFX` sin `DI`: la música y `$5C78` ya no pierden ticks mientras suena el beeper. Desde §3.2 solo quedan en beeper los pasos y el tic del minimapa, así que el posible zumbido a 50 Hz en tonos largos ya no aplica. | IRQ perdidas 1,6 % → 0,05 % | −1 B |

### 3.2 SFX de beeper → AY

Commits `d8ec56a` (audición), `ae8aa5d` (datos al bank 6) y `507ae5a` (la migración).

- **Once SFX y los dos tics** pasan a `code/sfx_library.json`, el motor AY que
  ya existía (canal B y ruido): `AYSFX_ATTACK`, `ENEMY_DEATH`, `ENEMY_SPAWN`,
  `PICKUP`, `BAD_PICKUP`, `NO_SWORD`, `BLOCKED_EXIT`, `KEY_DROP`,
  `DOOR_CLOSE`, `DOOR_OPEN`, `WELL_RECOVER`, `BUFF_TICK` y `COMPASS_BEEP`.
  Cada uno imita el carácter del original (barrido, ruido, arpegio) y tiene
  prioridad: un espadazo nunca corta un pickup ni un golpe. Suenan algo más
  largos que en beeper, porque ya no paran el juego.
- La música del juego usa los canales A y C (el B queda para los SFX), así que
  no se pisan. En las músicas de final (tres voces), un SFX ocupa el canal B
  mientras suena, como ya pasaba con los SFX AY que había.
- Siguen en beeper los pasos (<1 ms) y el tic del minimapa modal (con el AY en
  pausa). Los datos de beeper que ya no se usan se han quitado de `sound.asm`.
- **Memoria:** los programas AY viven en bank 6 (`SFX_DATA_BANK`) y
  `AY_PlaySFX` copia el que va a sonar a un búfer de 112 B en slot 1 (la IRQ no
  puede paginar). Slot 1 libre antes de `$7B7B`: 137 → 485 B.
- **Medido** (frente a P1-P7): vueltas lentas de día 1,37 % → 0,23 %, de noche
  1,40 % → 0,40 %; tiempo perdido 1,00 % → 0,25 % y 1,14 % → 0,42 %. Parpadeo
  e IRQ perdidas, igual.
- **Audición sin jugar:** `python tools/perf/sfx_audition.py` compila con
  `-DSFXTEST`, toca cada SFX y deja un WAV por efecto y sus espectrogramas.
  Para afinar un sonido basta con tocar `sfx_library.json` y volver a oírlo.

### 3.3 Enemigos en cada vuelta (hecho, apagado)

Commit `542504b`. Con 3 enemigos o más, el round-robin
(`MAX_ENEMIES_PER_FRAME 2`) da a cada uno 2 de cada 3 vueltas: los nasties
avanzan paso, paso, parado. Cuando hay enemigos en pantalla, el 85 % del
tiempo hay 3.

`ENEMIES_EVERY_LOOP EQU 1` (en `code/constants.asm`) procesa hasta 3 por vuelta
y, con 3 o más, mueve a los nasties que corren en cada vuelta con 2/3 de su
paso, repartido en 3 vueltas (un paso de 2 px queda en 1, 1, 2). La velocidad
media es la misma. Todo lo demás sigue al ritmo de siempre (cada enemigo
tiene su lógica completa 2 de cada 3 vueltas): monsters, animaciones,
ataques de depredador, aparición, muerte y huida. Con `0`, el binario es
idéntico byte a byte al de antes del cambio.

| Medido (3 semillas) | Apagado | Encendido |
|---|---:|---:|
| Nasties corriendo con 3+ enemigos: avance medio | 2,47 px/vuelta | 2,47 px/vuelta |
| … vueltas en que se quedan parados | 33,2 % | 0,2 % |
| Día: vueltas lentas / tiempo perdido | 0,23 % / 0,25 % | 1,07 % / 0,66 % |
| Día: frames con algo a medio pintar | 12,5 % | **20,3 %** |
| Noche: vueltas lentas / parpadeo | 0,40 % / 12,0 % | 0,47 % / 11,4 % |

Queda **apagado**: de día, el tercer enemigo dibujado en cada vuelta cae en
las filas de arriba justo cuando pasa el haz, y deshace lo que ganó P6. La
estimación anterior (0,3-0,4 % de tiempo perdido) se hizo sin P6 y sin ningún
SFX. Para que salga gratis antes hay que bajar el parpadeo (§4.1).

### 3.4 Unión con la rama del PC (modo 50 Hz)

La rama `pc-50hz` (commits `99de736`, `24c8a95`, `61dd37e`: guardar/reanudar
en la web, sonda de rendimiento del port y jugador a 50 Hz con filtros de
rendimiento) se ha unido a esta. Donde las dos hacían lo mismo se queda la
del PC: la barra de salud que no se repinta si no cambia y la caché de
tamaños de puertas y candados. Se ha arreglado un fallo de esa caché: al
abrir la puerta de la iglesia se borraba un sprite que ya no estaba cargado.
Para caber bajo el límite de bank 0 (`$FE80`), `InitEntities` y
`ShuffleMonsterTypes` pasan a slot 1 (`cold_slot1.asm`) y se quitan dos
rutinas sin uso.

El modo 50 Hz va tras un interruptor, `HYBRID_50HZ` en `code/constants.asm`,
**apagado**: cada vuelta se parte en dos medias que deben caber en un frame
cada una, y con la contienda del 128K de noche no caben a menudo. La sonda
del port no lo veía porque mide sin contienda.

| Medido (3 semillas) | Original | Rama del PC | Unión, 50 Hz encendido | Unión, apagado |
|---|---:|---:|---:|---:|
| Vueltas lentas, día / noche | 2,9 % / 2,3 % | 5,4 % / 5,9 % | 1,8 % / 5,6 % | **0,3 % / 0,3 %** |
| Parpadeo, día / noche | 18,8 % / 16,0 % | 29,3 % / 26,6 % | 16,5 % / 13,2 % | **13,4 % / 10,3 %** |
| IRQ perdidas, día / noche | 4,5 % / 3,5 % | | | 0,07 % / 0,08 % |

Con el interruptor apagado, el HUD vuelve a pintarse al final de la vuelta:
pintarlo al principio retrasaba los sprites y el haz los pillaba a medias.
`ENEMIES_EVERY_LOOP` (§3.3) no es compatible con el modo 50 Hz y queda
bloqueado con un `ASSERT`.

### 3.5 Cómo se validó

- `tools/perf/drawcheck.py`: en cada `DrawScreen` vuelca la pantalla entera
  (fondo + objetos, antes de las tumbas) y la `ZoneCellList`, y compara las
  salas que aparecen en las dos versiones con el mismo estado (fase del día,
  tablas de remap, pozo, llave, posición del jugador y `CollisionMap`).
  P1-P4: **41 pantallas (día y noche) y 27 zonas idénticas**. Experimento de
  control: la versión de antes con un retardo artificial da también 0
  diferencias, así que las diferencias de las primeras pruebas venían del
  estado de la partida (tumbas, ventanas tras las campanadas), no del código.
- `tools/perf/sprites_check.py`: los 192 BG sprites cumplen lo que supone P2
  (el RLE acaba exactamente en alto × ancho; el más largo ocupa 797 B < 832).
- P3 se contrastó además con un BFS de referencia en Python.
- P6: el estado final de cada actualización es el mismo por construcción
  (mismas celdas pintadas y restauradas). Capturas revisadas a mano.
- SFX: los 16 SFX AY que ya había suenan igual tras moverlos al bank 6: 13 WAV
  idénticos byte a byte; en los otros 3 cambia un 2-4 % de las muestras por un
  desfase mínimo, con la misma envolvente y el mismo espectro (correlación
  ≥ 0,997). En 6 partidas sonaron 13 SFX distintos, también los lanzados desde
  bank 4 (brújula) y bank 7 (pickups aleatorios), sin cuelgues; la build
  standalone igual. Los de las cinemáticas usan el mismo camino que los de
  bank 7, pero las partidas de prueba no llegan a ellas.
- Enemigos en cada vuelta: misma distancia media recorrida (tabla de §3.3). Los
  ataques de depredador cambian entre versiones, pero el experimento de
  control con 7 `NOP` muestra la misma dispersión: es el azar de `LD A, R`.
- **Pila:** con zxrun midiendo el SP mínimo en partidas de 5 min, la pila baja
  como mucho a `$FF2C` (antes `$FF2A`). El código de bank 0 acaba ahora en
  `$FD39` (antes `$FD62`): quedan 499 B de margen (antes 456).
- Las builds normal y `-DSTANDALONE=1` compilan y caben, con la fase 3
  apagada y encendida.

---

## 4. Siguientes oportunidades

Por impacto en fluidez:

1. **Parpadeo de píxeles.** El que queda es el clásico de borrar con XOR y
   volver a dibujar. Un `DrawSprite` que borre y dibuje línea a línea (cada
   byte escrito una sola vez) lo reduciría mucho. Otra opción es ordenar la
   actualización de entidades según dónde va el haz. Es lo que haría gratis
   encender `ENEMIES_EVERY_LOOP` (§3.3).
2. **Bucles que recorren tablas globales cada vuelta** (~8.000-10.000 T, otro
   ~12 % del trabajo): `CheckPickupCollect`, `CheckBumpTriggers`,
   `CheckLockBump`, `RefreshPickupAttrs` y `PaintSynthPickupAttrs` recorren
   `PickupTable` entera. Un índice por sala construido en `DrawScreen`, como
   `BuildPickupRectCache`, los dejaría en 0-3 entradas.
   `CheckBankTriggerBg`/`CheckTownGateTriggerBg` paginan bank 7 en cada
   vuelta para mirar si estás en su sala: mejor comprobar la sala antes de
   paginar. `DrawKeyHUD` (caché por llave y parpadeo), los 5 `Update*Buff` y
   `UpdatePlayerColorCycler` (salida rápida si no hay buff activo).
3. **Cambio de sala más corto** (~16 → ~10 frames):
   - limpiar la pantalla con `PUSH` justo tras un `HALT`; hoy el `LDIR` de
     6.912 B cuesta 145.000 T, 2 frames;
   - dibujar los BG sprites directamente desde su banco, moviendo
     `DrawBgGfxSprite` a memoria siempre visible, sin la copia (158.000 T);
   - meter `BuildZoneCellList` en la ventana del BFS (70.000 T).
4. **El *boost* del jugador según el número de enemigos** (`code/MEMORY.md`
   §5) se pensó para compensar caídas de framerate. Medido, el bucle se
   mantiene a 25 fps con 0-3 enemigos; lo que se frenaba era cada enemigo. Hoy
   ese boost hace al jugador más rápido cuando hay enemigos. Es decisión tuya
   si se queda como mecánica de juego.
5. **Memoria.** `tools/memory_map.py --dead` marca código muerto en bank 0:
   `BgGfx_hud_buff_*`, `BgGfx_hud_clock_decay`, `ResetAttrBlock`,
   `ChurchCutsceneDrawStatueAtLast`, `ClearScreen`… Además, la navegación por
   flow field no se usa (`MaiFlowFieldDirection`, `CheckPlayerZoneAtChar`,
   `MaiMaybeRecomputeFlow`: ~300 B en bank 2). Si la quieres reactivar algún
   día, con P3 el BFS ya cuesta ~1,6 frames en vez de ~8.

## 5. Herramientas

- `tools/perf/`: `build.py` (variantes fuera del repo, con parches o
  sustituciones), `bench.py` (perfil por vuelta y por rutina, haz),
  `drawcheck.py` (equivalencia de lo pintado), `irqlost.py` (IRQ perdidas por
  rutina), `sprites_check.py` y `sfx_audition.py` (un WAV por SFX).
- zxrun con `--irq`, `--dump`, `--stable`, `--beam-skip`, `--wav`, haz para
  bucles de 25 fps, SP mínimo y más `--prof`: en Experiment, rama
  `ccr-0b7542b9-igk045` (`a1df2fb`), y como parche en
  `tools/perf/zxrun_tharkys.patch`. Con Absurd! da la misma salida que antes;
  la única diferencia es que el haz cuenta también los frames perdidos.

## 6. Falta probarlo jugando

- **Cómo suenan los SFX nuevos.** zxrun usa la emulación AY de *chips*;
  conviene oírlos en Spectaculator o en un 128K y retocar lo que no guste en
  `sfx_library.json` (`tools/build_sfx.py` lo regenera, `build_all.bat` lo
  llama solo).
- Hardware real y emuladores con haz de verdad (Spectaculator, ZEsarUX):
  que P6 no parpadee.
- Si quieres comparar los enemigos en cada vuelta, compila con
  `ENEMIES_EVERY_LOOP EQU 1` y juega un rato de día.
