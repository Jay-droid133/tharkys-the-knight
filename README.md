# Tharkys the Knight

**A handcrafted (but AI-coded) ZX Spectrum 128K adventure — inspired by Sabre Wulf and Atic Atac.**
**Una aventura artesanal (pero programada por una IA) para ZX Spectrum 128K — inspirada en Sabre Wulf y Atic Atac.**

[🎮 Play in your browser / Juega en el navegador](https://jay-droid133.github.io/tharkys/) · [📥 Download v1.0 / Descargar](https://github.com/Jay-droid133/tharkys-the-knight/releases/latest) · [🎲 itch.io](https://jay-droid133.itch.io/tharkys) · [📖 Devlog (WIP)](devlog/INDEX.md)

---

## About / Acerca de

Tharkys the Knight is a single-screen-per-room adventure on a 16×16 world map, written entirely in Z80 assembly for the ZX Spectrum 128K. It runs on real hardware, on emulators, and in any modern browser via a WebAssembly wrapper — same Z80 binary embedded in all of them.

Tharkys the Knight es una aventura por salas (un screen por sala) sobre un mapa de mundo 16×16, escrita íntegramente en ensamblador Z80 para el ZX Spectrum 128K. Funciona en hardware real, en emuladores, y en cualquier navegador moderno mediante un wrapper WebAssembly — el mismo binario Z80 embebido en todos.

## Story / Historia

Sir Tharkys is a man down on his luck. For too long he has been writing checks his body couldn't cash. His squire has abandoned him. Even his horse has abandoned him. He has no choice but to go wherever a sword is needed, hoping for a few crumbs in exchange for his services. Word reaches him of a town terrorized by monsters of unknown origin — whoever rids them of the creatures has been promised a juicy reward, enough perhaps to pull the knight out of his financial straits. After speaking with the mayor, Tharkys is handed a broken compass that vaguely points to his objectives. The mayor also mentions he used to have a map of the area drawn on a napkin (!?!), but the wind carried it off (!!??!!). He wishes the knight good luck and, as a farewell, informs him that the city gates have been closed so he can't give in to the temptation to flee. Which he very much wants to do, after seeing how the place is crawling with creatures and, above all, after learning how many other knights have fallen before in the attempt...

Sir Tharkys es un tipo con mala suerte. Durante mucho tiempo extendió cheques que su cuerpo no podía pagar. Su escudero le ha abandonado. Le ha abandonado hasta su caballo. No le queda más remedio que ir allá donde se requiera una espada, esperando algunas migajas a cambio de sus servicios. Le llegan noticias de un pueblo que vive atemorizado por unos monstruos de origen desconocido. A quien les librara de ellos, prometían entregar una jugosa recompensa. Esto sacaría al caballero de sus apuros financieros. Tras hablar con el alcalde, éste le entrega una brújula rota que le indicará vagamente la ubicación de sus objetivos. También le dice que tenía un mapa de la zona en una servilleta (!?!), pero que se lo llevó el aire (!!??!!). Le desea buena suerte, y, como despedida, le informa de que han cerrado la puerta de la ciudad para que no pueda ceder a la tentación de huir. Ganas le dan, tras ver cómo está todo lleno de bichos y, sobre todo, tras conocer que muchos otros caballeros han caído antes en el intento...

Although you can wander and get lost, the game is linear — you must reach your objectives in sequence. You have three items to find your way:

Aunque puedes perderte por el mundo, el juego es lineal — debes llegar a los objetivos en secuencia. Para orientarte dispones de tres items:

- **Default compass / Brújula por defecto** — always available. Points to where the next objective is, but not how to get there through the world's layout. / Siempre disponible. Señala hacia dónde se encuentra el próximo objetivo, pero no cómo llegar a él a través del trazado del mundo.
- **Magic compass / Brújula mágica** — actually shows you which path to take. But its effect is short. / Sí te indica qué camino coger para llegar al próximo objetivo. Pero su efecto dura poco.
- **Map / Mapa** — hurry whenever you grab it. The wind will carry it off soon enough! / Date prisa cada vez que lo cojas. ¡El aire se lo lleva enseguida!

## How to play / Cómo jugar

- **Web** — open the [Play link](https://jay-droid133.github.io/tharkys/). Works on phone, tablet, and desktop. Nothing to install.
- **Windows desktop** — grab `tharkys_windows.zip` from the [latest release](https://github.com/Jay-droid133/tharkys-the-knight/releases/latest), unzip, double-click `tharkys.exe`. The emulator core is embedded in the executable.
- **ZX Spectrum 128K** (real hardware or emulator) — load `juego_standalone.tap` or `juego_standalone.sna` in Fuse, Spectaculator, ZEsarUX, etc. The game includes an embedded intro story in English and Spanish.

## Controls / Controles

| | |
|---|---|
| Mover / Move | **QAOP**, flechas (arrow keys), o Kempston / Sinclair joystick |
| Atacar / Attack | **Espacio (Space)** o joystick fire |

(At startup you can choose the story language: English / Español / Skip.)

## Repository layout / Estructura del repo

```
code/        Z80 sources (sjasmplus syntax), level + sprite data, build scripts
port/        C wrapper for desktop (SDL2) and web (Emscripten), based on chips/zx
tools/       Python build & content tools (BG editor, level editor, sprite tools)
docs/        Design notes and technical handoffs
```

The same Z80 source compiles into five distribution targets — a development SNA, a release `.tap` with BASIC loader, a standalone Spectrum variant with embedded intro story, a Windows `.exe` (chips emulator + Z80 binary), and a WebAssembly build hosted on GitHub Pages.

## Build from source / Compilar desde fuente

Requirements: Python 3.10+, [sjasmplus](https://github.com/z00m128/sjasmplus) 1.21+. For the desktop / web wrappers: CMake + a C compiler (MinGW / ucrt64) and / or [Emscripten](https://emscripten.org/).

```bash
cd code
./build_all.bat       # release + standalone Spectrum builds
```

For wrapper builds see [`port/README.md`](port/README.md).

## Devlog

A technical devlog of the project lives at [`devlog/`](devlog/INDEX.md) — **work in progress**. It's written by Claude (the AI assistant Jay-droid133 developed the game with) and covers the 21 March → 23 May 2026 stretch (~64 days, 820 commits): bug hunts told as detective stories, deep-dives into systems like the 128K bank-switching dance, the AY music driver, the level editor pipeline, and the rewrite from the original design. Aimed at programmers, especially Z80 / Spectrum / retro homebrew enthusiasts.

Un devlog técnico del proyecto está en [`devlog/`](devlog/INDEX.md) — **en construcción**. Lo escribe Claude (el asistente AI con el que Jay-droid133 desarrolló el juego) y cubre del 21 marzo al 23 mayo 2026 (~64 días, 820 commits): cacerías de bugs contadas como historias detectivescas, deep-dives en sistemas como el baile de paginado 128K, el driver de música AY, el pipeline del editor de niveles, y la reescritura del diseño original. Escrito para programadores, especialmente gente del mundo Z80 / Spectrum / retrohomebrew.

> ⚠️ **Spoiler warning / Aviso de spoilers**: post 01 describes the full game flow including the ending. If you want to play Tharkys fresh, play it first. / El post 01 describe el flujo completo del juego, incluido el final. Si quieres jugarlo sin saber nada, juégalo primero.

## Credits / Créditos

- **Design, art, music** — [Jay-droid133](https://github.com/Jay-droid133). Pixel art is mostly hand-drawn; a few sprites and the splash screens were started with Gemini and refined by hand. Music tracks are variations of well-known themes, arranged by Jay-droid133 (MIDI sketches converted to AY-3-8912). The Game Over track in particular is a rhythmic homage to "Smooth Criminal" by Michael Jackson — same beat and tempo, different melody. Full game design is his.
- **Code** — written by [Claude](https://claude.com) (Anthropic) under Jay-droid133's direction. All Z80 assembly, build tooling, and C wrapper code in this repository is AI-authored.
- **Reward font** by [DamienG](https://damieng.com/zx-origins) — used in the final credits cutscene. Part of his [ZX Origins](https://damieng.com/zx-origins/) typeface collection.

🤖 Co-developed using [Claude Code](https://claude.com/claude-code).

## License / Licencia

This project is released under **[Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](LICENSE)**. In plain language: you are free to play, share, fork, port, study, and remix it — just credit Jay-droid133 as the original author and don't sell it (or use it as part of something you sell). See [LICENSE](LICENSE) for the full legal text.

Este proyecto se publica bajo **[Creative Commons Atribución-NoComercial 4.0 Internacional (CC BY-NC 4.0)](LICENSE)**. En cristiano: puedes jugarlo, compartirlo, forkearlo, portarlo, estudiarlo y remezclarlo — solo tienes que dar crédito a Jay-droid133 como autor original y no venderlo (ni incluirlo en algo que vendas). El texto legal completo está en [LICENSE](LICENSE).
