# Notas de diseño — sesión cloud 26/04/2026

Conversación de diseño (sin código, solo decisiones) trasladada
desde una sesión de Claude Code on the web. Siguiente paso: continuar
afinando los puntos pendientes y empezar implementación.

## Estado del repo al cerrar la sesión cloud

- Rama `claude/download-juego-sna-343TR` (en remoto): contiene un
  commit `637c5d7` que recompila `juego.sna`/`juego.tap`/`juego.map`
  con sjasmplus 1.23.0 desde el HEAD de `main` de aquel momento.
  Mergear o descartar a discreción.
- `main`: sin cambios de código míos (solo este documento).

## 1. Sistema de muerte y respawn

**Decisiones cerradas:**

- Implementar muerte real: ahora `PlayerHealth=0` no hace nada
  (`code/logic_game.asm:5626`). Hay que disparar el respawn ahí.
- Sin vidas finitas (respawn infinito). La penalización es la caminata
  de vuelta + las "tumbas".
- Al respawn:
  - HP a tope, posición al ayuntamiento.
  - **Se conservan**: puertas abiertas, llaves consumidas, items
    recogidos, objetivo actual de la cadena.
  - **Se resetean**: HP, posición del player, enemigos (los nasties
    ya se respawnean por pantalla; los monsters reaparecen).
- "Tumbas": un sprite decorativo persiste en el sitio donde moriste.
  - **1 tumba por pantalla** (sobrescribe la anterior). Estructura por
    pantalla: 4 bytes (px_x, px_y) en una tabla indexada por
    `(sx, sy)` o sólo en pantallas visitadas. Pendiente afinar.
- El ayuntamiento como respawn: misma `(sx, sy)` que el hito #5 de la
  cadena (coherencia narrativa). Una sola coordenada sirve para
  ambas cosas.

**Pendiente:**

- ¿Diseño visual de la tumba? (lápida / esqueleto / calavera).
- Sonido de muerte y de respawn.

## 2. Sistema de puntuación

**Filosofía elegida: B + guiño de C (exploración con penalización
suave por muerte).**

| Acción                               | Puntos     |
| ------------------------------------ | ---------- |
| Pantalla nueva visitada              | +25        |
| Enemigo eliminado                    | +10        |
| Item / llave recogida                | +250       |
| Puerta importante abierta            | +500       |
| Secreto / jefe                       | +1000–2500 |
| Bonus "no death" al final            | +5000      |
| Morir                                | no resta — pero rompe el bonus |

- Score 24-bit BCD (3 bytes), hasta 999.999.
- Las tumbas pasan a tener significado mecánico: cada tumba = bonus
  de "perfect run" perdido.

**Pendiente decidir:**

- ¿HUD permanente o solo al pausar?
- ¿Multiplicadores por encadenar acciones rápido?
- ¿High score persistente entre sesiones (no triv. en Spectrum sin
  medio de guardado) o solo dura la sesión?
- ¿Objetivo final ganador concreto? (la puerta sur ya cubre esto).

## 3. Brújula / indicador de objetivo en HUD

**Cerrado:**

- Métrica: **distancia Manhattan en pantallas** (`|Δsx| + |Δsy|`).
- Tipo: **brújula a vuelo de pájaro** (opción 1) — ignora paredes
  del laberinto. A veces apuntará a un muro; convención asumida.
- Indicador visual = **flecha de 8 direcciones**:
  - dirección por signo de `dx` / `dy` (9 combinaciones, una de
    ellas es "estás aquí").
  - color: **verde** si la distancia bajó respecto a la pantalla
    anterior, **rojo** si subió.
- En la pantalla del objetivo (Manhattan = 0): sprite **"X medieval"**
  en lugar de flecha; sin variantes de color.
- Sprites totales: 8 flechas × 2 colores + 1 X = **17 sprites**
  (o color vía atributos para reducir, ver pendiente).
- Tamaño: **16×16**, en las **dos primeras filas** del HUD.

**Pendiente:**

- ¿16 sprites de flecha distintos (8 verdes + 8 rojos) o 8 sprites
  con cambio de atributo de color? Lo segundo ahorra ROM/RAM gfx.
- ¿Color del primer cruce tras cambiar de hito (no hay distancia
  anterior para comparar)? Sugerencia: por convención **verde**.
- ¿La X medieval también vale como sprite "estás aquí" cuando estás
  encima del objetivo durante el paso 7 (encerrar monsters), o ahí
  va otro sprite? (En el #4 acordamos: sí, X medieval).

## 4. Cadena de 9 hitos (orden estricto)

| # | Hito                                | Cómo se completa |
|---|-------------------------------------|------------------|
| 1 | Llave del bosque                    | Recogerla |
| 2 | Llave de las ruinas                 | Recogerla |
| 3 | Llave del cementerio                | Recogerla |
| 4 | Llave del reloj (al pie de iglesia) | Recogerla |
| 5 | Puerta del ayuntamiento             | Tocarla con llave del reloj → spawnea llave de la iglesia ahí mismo |
| 6 | Llave de la iglesia (en ayuntamiento)| Recogerla |
| 7 | Iglesia                             | Encerrar a los 3 monsters → spawnea llave de la puerta sur |
| 8 | Llave de la puerta sur (en iglesia) | Recogerla |
| 9 | Puerta sur de la ciudad             | Tocarla con la llave → final |

- Iglesia en hitos 4 y 6 = misma pantalla.
- **Orden estricto** vía gating físico del laberinto: las paredes
  impiden saltarse pasos.
- Llaves físicas (1–4): colocadas en el level editor.
- Llaves dinámicas (6, 8): las spawnea el ASM al disparar el trigger
  correspondiente, en la posición del propio trigger.

**Variable nueva**: `CurrentObjective` (byte 0..8). Se incrementa al
completar cada hito. Casos particulares de los flags ya existentes
`ChurchKeySpawned` y `ChurchDoorOpen` quedan absorbidos por este
sistema más general.

## 5. Configuración de hitos en el Level Editor

**Estado actual del editor (`tools/level_editor.html`):**

- Cada objeto colocado: `{id, x, y, cat}` en `cellOverlays`. Sin
  nombre legible. `id` = sprite gráfico (correlaciona con `BgGfx_*`
  en ASM).
- Editor genera ASM directo (`generateScreenDataAsm()` ~línea 8065).
- **Player Start** ya implementado; se exporta a `START_SCREEN_X/Y`
  y `START_PLAYER_X/Y`.
- `BumpTriggerTable` y `DormantPickupTable`: hardcoded en ASM, no las
  toca el editor.

**Decisión: opción C (híbrido) — pendiente confirmar definitivamente**.

- **Hitos 1–4** (llaves físicas): cada una con **sprite único** y
  posición resuelta escaneando `PickupTable` por su `BgGfx_*` en
  build time. Cero cambios al editor.
- **Hitos 5/7/9** (puerta ayuntamiento / iglesia / puerta sur):
  triggers únicos. Los dos primeros ya existen en `BumpTriggerTable`;
  falta añadir el de la puerta sur.
- **Hitos 6/8** (llaves dinámicas): no se colocan en el editor;
  coordenadas heredadas del trigger que las suelta.
- **Respawn point**: por simplicidad, **el Player Start = el
  ayuntamiento**. El editor ya cubre esto.

**Lo que hay que hacer en código (estimación):**

| Cambio | Dónde | Esfuerzo |
|---|---|---|
| 4 sprites únicos para llaves | aseprite + `bg_gfx.asm` | pixelart |
| 1 sprite único para puerta sur | igual | pixelart |
| 17 sprites para brújula (8 flechas ×2 colores + X) | igual | pixelart |
| Sprite de tumba | igual | pixelart |
| `MilestoneTable` con 9 entradas | nuevo o `screen_data.asm` | ~30 líneas |
| Resolver coordenada de hito (escan. `PickupTable`) | `logic_game.asm` o nuevo | ~50 líneas |
| `CurrentObjective` + integraciones en triggers | `variables.asm` + triggers | ~40 líneas |
| Render flecha-brújula en HUD | nuevo módulo | ~80 líneas |
| Sistema de muerte (HP=0 → respawn) | `logic_game.asm` | ~50 líneas |
| Tabla de tumbas + render | nuevo | ~80 líneas |
| Mecánica "encerrar 3 monsters" (paso 7) | depende de monster AI actual | ? |
| Score 24-bit BCD + HUD | nuevo | ~120 líneas |

## 6. Preguntas abiertas (orden recomendado para retomar)

1. **Confirmar opción C para los hitos en editor** (vs B con UI nueva).
2. **Mecánica de "encerrar a los 3 monsters"** del paso 7: ¿existe
   ya algo en el sistema de monsters (`MONSTER_AI_SESSION.md`) o hay
   que diseñarla desde cero? ¿Qué significa "encerrar"
   técnicamente — están dentro de una zona delimitada, una puerta se
   cierra detrás, otra cosa?
3. **Sonido al cambiar de objetivo**: beep distintivo cuando completes
   un hito. ¿Sí/no?
4. **Feedback narrativo** del paso 4→5: cuando el jugador toca la
   puerta de la iglesia con las llaves y "no abre, te falta algo",
   ¿basta con que la flecha cambie de dirección, o quieres una pista
   adicional (mensaje, sprite que aparece, sonido)?
5. **Color en el primer cruce tras cambio de hito** (no hay distancia
   anterior). Sugerencia: verde por convención.
6. **¿Sprites de flecha en 16 variantes o 8 + cambio de atributo?**
7. **Pendientes de score** (ver sección 2).

## 7. Orden de implementación sugerido

Cuando estés listo para tirar código, este orden minimiza dependencias:

1. **Variable `CurrentObjective` + tabla `MilestoneTable`** (estática
   por ahora, con coordenadas hardcoded a tu spawn actual). Pruebas
   de que "el byte avanza al recoger llaves".
2. **Resolución de coordenadas** desde `PickupTable` (sustituye los
   hardcodeos del paso 1).
3. **Sistema de muerte** (HP=0 → respawn al ayuntamiento). Prueba que
   conserva las llaves y puertas.
4. **Brújula en HUD** (placeholder con cuadrados de colores; los
   sprites finales después). Prueba que la flecha cambia al cruzar
   pantalla.
5. **Tumbas persistentes** (1 por pantalla).
6. **Mecánica del paso 7** (encerrar monsters).
7. **Score y HUD** completo.
8. **Sprites finales** (pixelart).
