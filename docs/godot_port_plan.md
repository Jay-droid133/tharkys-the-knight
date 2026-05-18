# Contexto — port de "Tharkys the Knight" a Godot

Este documento es un contexto autocontenido pensado para iniciar una sesión
local de Claude Code (o cualquier asistente) en la carpeta del proyecto Godot.
Resume las decisiones cerradas en la sesión de discusión previa (rama
`claude/godot-port-discussion-Hn9b2`).

## El juego original

- Nombre: **Tharkys the Knight**
- Plataforma original: ZX Spectrum 128K
- Lenguaje original: Z80 assembly (sjasmplus)
- Estado: **prácticamente terminado**, sólo quedan bugs de pulido
- Repo: `github.com/Jay-droid133/nuevo-juego`
- Hay un emulador wrapper en `port/` (SDL2 + chips Z80 + shader CRT) que ejecuta
  `juego.sna`. **Esa es la spec ejecutable.** Ante cualquier duda de
  comportamiento, se ejecuta y se observa.

## Objetivo

"Lo más fiel posible al Spectrum, pero programado en Godot."

- NO es "estética Spectrum-inspired".
- NO es un envoltorio del emulador (eso ya lo hace `port/`).
- ES reimplementar en Godot 4 + GDScript con restricciones Spectrum reales.

## Mecánicas (resumen)

- Pantallas tipo Speccy: **flip de pantalla, no scroll**. Cada pantalla = `(sx, sy)`.
- **Player**: caballero con espada, stamina, anims idle/walk/attack/death.
- **Ciclo día/noche** con campanadas en HUD (reloj central) y ventanas que se
  encienden/apagan.
- **Nasties** (enemigos comunes): águila, araña, cabra, serpiente, rata,
  murciélago, escorpión, gato rabioso. Aparecen por franja horaria, mueren al
  cambiar de franja.
- **Monsters** (3 persistentes, sólo de noche): siguen al player entre rooms,
  aparecen escalonadamente al entrar a una room nueva.
- **Objetivo final** (pendiente confirmar con el autor): empujar los 3 monsters
  a la iglesia → mueren → fin.

## Restricciones de fidelidad (NO negociables)

- Viewport **256×192** + strip HUD.
- **50 Hz** lógico y de render (no 60). `Engine.physics_ticks_per_second = 50`.
- **Paleta de 15 colores Spectrum**, hardcoded. Cero excepciones en juego, HUD,
  menús.
- **Posiciones siempre enteras**. Nada de subpíxel, nada de Tweens con easing.
- Input **digital de 8 direcciones** (gamepad con dead zone que discretiza).
- **Attribute clash emulado** por shader post-proceso: para cada celda 8×8 del
  frame final, snap a los 2 colores dominantes.
- **Música AY**: idealmente embeber un player AY (libayemu o equivalente, vía
  GDExtension). Fallback: pre-renderizar a OGG si SFX y música no comparten
  canales.
- Prohibido: Light2D, normal maps, partículas masivas, AA en texto, scroll
  suave, rumble.

## Estructura técnica acordada

### Cadena de render

```
SubViewport(256×N)
  → shader attribute_clash
  → shader CRT (opcional)
  → TextureRect integer-scaled a la ventana
```

Todo el resto del juego ignora shaders y escalado.

### Autoloads (5 máximo)

- **GameState** — HP, score, `(sx,sy)`, inventario, flags de monsters muertos,
  pantallas visitadas.
- **SaveManager** — serializa GameState a JSON en `user://`.
- **Audio** — único punto de mezcla.
- **Palette** — los 15 colores como constantes + helpers.
- **Bus** — nodo con señales (`enemy_killed`, `screen_entered`…) para desacoplar
  HUD/world/player.

Resistir la tentación de poner Player o RoomManager como autoload. Esos viven
en el árbol.

### Mundo

- **Una sola room cargada a la vez.**
- **UNA sola `room.tscn` genérica** parametrizada por un `RoomData` Resource.
  NO una escena por pantalla.
- `level_data.json` original → portar a `.tres` con un script de una sola
  ejecución.

### Datos vs escenas

- Contenido del juego = Resource o JSON (`RoomData`, `MonsterData`, `DoorData`).
- Escenas = sólo prefabs de actores y maquinaria.

### Actores

- `CharacterBody2D` con helper `move_pixel(dx, dy)` que redondea a entero.
  Todos los actores pasan por ahí.
- Lógica en `_physics_process` a 50 Hz. **No usar `_process` para lógica.**
- `AnimatedSprite2D` con avance por frame (no por tiempo).

### Pipeline de assets

- Scripts en `tools/` que convierten `.inc` y JSON del Z80 a PNG indexados +
  manifiestos.
- Se ejecutan **una vez**, se commitea el output. **No son parte del build de
  Godot.**
- El `.inc` queda como referencia histórica; el PNG es el nuevo origen.

### Lenguaje

- **GDScript**. C# sólo si hay razón fuerte (no la hay a esta escala).

## Decisiones todavía abiertas

1. **Bugs del `TODO.md` del Z80** — opciones:
   - (a) arreglar primero en Z80, luego portar
   - (b) portar tal cual, arreglar sólo en Godot
   - (c) mixto: baratos en ambos lados, caros sólo en Godot

   Inclinación: **(b) o (c)**. NO (a): Bank 0 está al 96.58% y no caben cambios
   grandes.

2. **Música AY**: player embebido vs OGG pre-rendered. Decidir mirando si SFX
   dinámicos roban canales a la música.

3. **Algoritmo exacto del attribute clash shader** (los 2 colores más
   frecuentes por celda 8×8 — falta cuajar bordes y prioridad ink/paper).

## AVISOS — no caer en estas trampas

- **`DESIGN_NOTES.md`** del repo original es de hace ~1 año y tiene planes
  **abandonados**: sistema de respawn con tumbas, score BCD 24-bit, brújula
  HUD, cadena de objetivos al ayuntamiento. **No usarlo como referencia de
  diseño actual.**
- **`TODO.md`** SÍ es actual (bugs pendientes, no features nuevas).
- **El código Z80 en `code/`** es la spec canónica. Cualquier duda de
  comportamiento → ejecutar `port/` y observar.

## Setup local

1. Clonar `Jay-droid133/nuevo-juego` en algún sitio aparte como **referencia
   de lectura**, no tocar.
2. Proyecto Godot en `C:\THARKYS TO GODOT\` (carpeta hoy vacía).
3. Godot 4.x (estable más reciente).

## Rama de discusión previa

La conversación de la que sale este contexto vive en la rama
`claude/godot-port-discussion-Hn9b2` del repo original.
