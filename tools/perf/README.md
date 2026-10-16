# tools/perf: medir rendimiento y fluidez de Tharkys sin mirar la pantalla

Partidas guionizadas en **zxrun** (el Spectrum 128K sin ventana del repo
Experiment) y su análisis. Es lo que se usó para `docs/rendimiento/INFORME.md`.

## Preparar (una vez)

1. **zxrun con el parche de Tharkys.** En el repo Experiment:

   ```bat
   cd C:\Experiment
   git apply C:\NUEVO_JUEGO\tools\perf\zxrun_tharkys.patch
   tools\zxrun\build.bat
   ```

   El parche añade `--irq`, `--dump`, `--stable`, `--beam-skip`, el haz para
   bucles de 25 fps, el SP mínimo y más `--prof`. No cambia nada de lo que ya
   usa Absurd!.
2. **Rutas** (variables de entorno; si no están, se prueban las de siempre):
   - `ZXRUN`: por defecto `C:\Experiment\tools\zxrun\zxrun.exe`
   - `SJASMPLUS`: por defecto `I:\PROGRAMACION\COMPILADORES\sjasmplus-1.21.1.win\sjasmplus.exe`
   - `THARKYS_PERF_WORK`: carpeta de las variantes (por defecto `%TEMP%\tharkys_perf`)
3. Python 3; no hace falta nada más.

## Uso

```bat
:: compilar variantes (fuera del repo: no toca code\ ni los .sna commiteados)
python tools\perf\build.py base
python tools\perf\build.py todos --patch docs\rendimiento\parches\todos.patch
python tools\perf\build.py me3 --sed "constants.asm|MAX_ENEMIES_PER_FRAME EQU 2|MAX_ENEMIES_PER_FRAME EQU 3"

:: perfil de una partida (2 min de juego explorando; --scenario night = a medianoche)
python tools\perf\bench.py %TEMP%\tharkys_perf\base --seed 2
python tools\perf\bench.py %TEMP%\tharkys_perf\base --seed 2 --inside DrawScreen
python tools\perf\bench.py %TEMP%\tharkys_perf\base --seed 2 --beam 128k

:: IRQ perdidas y donde
python tools\perf\irqlost.py %TEMP%\tharkys_perf\base

:: ¿pintan lo mismo las dos variantes al entrar en cada sala?
python tools\perf\drawcheck.py %TEMP%\tharkys_perf\base %TEMP%\tharkys_perf\todos
python tools\perf\drawcheck.py %TEMP%\tharkys_perf\base %TEMP%\tharkys_perf\todos --night --seeds 6 7 8

:: formato de los BG sprites (sin emulador)
python tools\perf\sprites_check.py %TEMP%\tharkys_perf\base
```

## Qué sale

`bench.py`:

- **ticks por vuelta**: el juego va a 25 fps, así que una vuelta de
  `MainLoop` debe durar 2 ticks; 3 o más es un tirón.
- **frames de más en juego**: tiempo perdido en tirones.
- **trabajo por vuelta**: T-states hasta `.frameSync`, con la contienda
  estimada. Presupuesto: 141.816 (2 frames).
- **cambios de sala**: frames que dura cada vuelta con `DrawScreen`.
- **tabla por rutina**: coste medio, p99 y máximo de cada `CALL` del bucle.
  Incluye lo que llama y las IRQ que caigan dentro. `lentas` = su media en
  las vueltas de 3 o más ticks.
- `--beam 128k`: % de frames en los que el haz lee bytes a medio pintar
  (parpadeo), con las celdas y las instrucciones que más.

## Cuidado al leer los números

- Las partidas son caóticas: un cambio de código cambia trayectorias. Compara
  medias de 3 o más semillas, no partida a partida.
- chips no emula la contienda; zxrun la estima. Las cifras absolutas son
  aproximadas; las comparaciones antes/después, no.
- La entrada es un joystick Kempston al azar con espadazos. Quieto o en
  cinemáticas se mide poco.
- Las vueltas del minimapa modal (`ShowMinimap*`) se excluyen.
