# Tharkys the Knight — desktop wrapper

A native multiplatform shell that embeds the Z80 game (`juego.sna`) and runs
it inside a small ZX Spectrum 128K emulator core. Single binary per OS, no
external dependencies for the end user.

## Status

| Phase | Scope                                                                | State |
|-------|----------------------------------------------------------------------|-------|
| 0     | CMake skeleton, SDL2 + chips fetched, SNA embedded, blank window     | done  |
| 1     | Boot SNA, render framebuffer, keyboard mapping                       | next  |
| 2     | Kempston / Sinclair joystick via SDL_GameController                  |       |
| 3     | AY-3-8912 audio piped through SDL_AudioDevice                        |       |
| 4     | CRT shader (crt-mattias / crt-lottes) via OpenGL post-process        |       |
| 5     | GitHub Actions matrix → Windows / Linux / macOS binaries             |       |
| 6     | Icon, fullscreen toggle, config file, optional WASM build            |       |

## Architecture

```
   juego.sna  ─┐
               │  bin2c.py
               ▼
       juego_sna.h  ─┐
                     │
      chips/zx.h  ───┤  (Z80 + AY-3-8912 + bank switching, header-only)
                     │
              main.c ◄── SDL2 (window, input, audio, gamepad)
                     │
                  tharkys(.exe)
```

The game's Z80 source is not touched. We rebuild `juego.sna` with the
existing top-level Makefile, then this CMake project picks it up, converts
it to a `uint8_t[]`, and links it into the executable.

## Requirements

- **CMake** ≥ 3.20
- **Python** ≥ 3.8 (build-time only; converts `juego.sna` → C header)
- **C11 compiler**
  - Windows: MSVC (Visual Studio 2022) or MinGW-w64
  - Linux: gcc or clang
  - macOS: Apple clang (Xcode CLT)
- A working network on the first configure (FetchContent pulls SDL2 + chips)

The game's SNA must exist at the repo root before configure. Build it from
the repo root once with:

```
make
```

## Build

From this directory:

```sh
# Configure (first time only; ~1-3 min while SDL2 sources download)
cmake -B build -DCMAKE_BUILD_TYPE=Release

# Build
cmake --build build --config Release

# Run
./build/bin/tharkys           # Linux / macOS
./build/bin/Release/tharkys.exe  # Windows (MSVC multi-config)
```

On Windows with Ninja installed you can shortcut the config-step generator:

```
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

## Layout

```
port/
├── CMakeLists.txt        # top-level build
├── scripts/
│   └── bin2c.py          # SNA / ROM → C header
├── src/
│   └── main.c            # entry point (Phase 0: SDL bootstrap)
├── roms/                 # gitignored; ZX Spectrum 128 ROMs (Phase 1+)
└── README.md
```

## ROMs (Phase 1+)

chips/zx.h needs the original Sinclair 128K ROMs to boot:

- `128-0.rom` (16 KB) — editor / menu
- `128-1.rom` (16 KB) — 48K BASIC compatibility

Place them at `port/roms/` (gitignored). The build will convert them to
embedded headers automatically. Distribution policy and exact paths are
documented when Phase 1 lands.

## Why this design

- **Single binary, single SNA.** No "open this in your emulator" friction.
- **Zero changes to the game source.** Anything that runs on a real 128K runs here.
- **Real AY chip.** The IRQ-driven music driver, AY beeps, hit SFX all stay
  bit-exact because they execute on an emulated AY-3-8912.
- **Real joystick interfaces.** `ReadInput` in `logic_game.asm` already
  reads Kempston (`$1F`) and Sinclair 1 (`$F7FE`); the wrapper just injects
  state into those ports.
- **CRT shaders for free** in Phase 4 via standard OpenGL post-process.
- **Web distribution later** by re-targeting the same code to Emscripten.
