# Tharkys the Knight

**A handcrafted ZX Spectrum 128K adventure — inspired by Sabre Wulf and Atic Atac.**
**Un videojuego de aventura artesanal para ZX Spectrum 128K — inspirado en Sabre Wulf y Atic Atac.**

[🎮 Play in your browser / Juega en el navegador](https://jay-droid133.github.io/tharkys/) · [📥 Download v1.0 / Descargar](https://github.com/Jay-droid133/tharkys-the-knight/releases/latest) · [🎲 itch.io](https://jay-droid133.itch.io/tharkys)

---

## About / Acerca de

Tharkys the Knight is a single-screen-per-room adventure on a 16×16 world map, written entirely in Z80 assembly for the ZX Spectrum 128K. It runs on real hardware, on emulators, and in any modern browser via a WebAssembly wrapper — same Z80 binary embedded in all of them.

Tharkys the Knight es una aventura por salas (un screen por sala) sobre un mapa de mundo 16×16, escrita íntegramente en ensamblador Z80 para el ZX Spectrum 128K. Funciona en hardware real, en emuladores, y en cualquier navegador moderno mediante un wrapper WebAssembly — el mismo binario Z80 embebido en todos.

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

## Credits / Créditos

- **Design, art, music** — [Jay-droid133](https://github.com/Jay-droid133). Pixel art is mostly hand-drawn; a few sprites were started with Gemini and refined by hand. Music is original (MIDI sketches converted to AY-3-8912). Full game design is his.
- **Code** — written by [Claude](https://claude.com) (Anthropic) under Jay-droid133's direction. All Z80 assembly, build tooling, and C wrapper code in this repository is AI-authored.
- **Reward font** by [DamienG](https://damieng.com/zx-origins) — used in the final credits cutscene. Part of his [ZX Origins](https://damieng.com/zx-origins/) typeface collection.

🤖 Co-developed using [Claude Code](https://claude.com/claude-code).

## License / Licencia

This project is released under **[Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](LICENSE)**. In plain language: you are free to play, share, fork, port, study, and remix it — just credit Jay-droid133 as the original author and don't sell it (or use it as part of something you sell). See [LICENSE](LICENSE) for the full legal text.

Este proyecto se publica bajo **[Creative Commons Atribución-NoComercial 4.0 Internacional (CC BY-NC 4.0)](LICENSE)**. En cristiano: puedes jugarlo, compartirlo, forkearlo, portarlo, estudiarlo y remezclarlo — solo tienes que dar crédito a Jay-droid133 como autor original y no venderlo (ni incluirlo en algo que vendas). El texto legal completo está en [LICENSE](LICENSE).
