cmake_minimum_required(VERSION 3.20)
project(tharkys_desktop
    VERSION 0.1.0
    DESCRIPTION "Tharkys the Knight - desktop wrapper"
    LANGUAGES C
)

# ============================================================================
# Configuration
# ============================================================================
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Output binaries into bin/ at the top of the build tree
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Locate the parent repo (we need juego.sna + juego_release.tap from there)
set(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(SNA_SOURCE "${REPO_ROOT}/juego.sna")
set(TAP_SOURCE "${REPO_ROOT}/code/juego_release.tap")

# Python is required at build time to convert binary blobs to C headers
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# OpenGL: core 1.1 funcs linked through here (Phase 4 CRT shader pipeline).
# Modern entry points are loaded dynamically via SDL_GL_GetProcAddress.
# Emscripten gets SDL2 + WebGL via emcc flags instead -- no host GL needed.
if(NOT EMSCRIPTEN)
    find_package(OpenGL REQUIRED)
endif()

# ============================================================================
# Dependencies (FetchContent)
# ============================================================================
include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

# SDL2 - audio, video, input, gamepad.
# Emscripten ships its own SDL2 via `-s USE_SDL=2`, so we skip the native
# FetchContent in that branch and let emcc inject the headers + libs.
if(NOT EMSCRIPTEN)
    FetchContent_Declare(
        SDL2
        GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
        GIT_TAG        release-2.30.10
        GIT_SHALLOW    TRUE
    )
    set(SDL_SHARED OFF CACHE BOOL "" FORCE)
    set(SDL_STATIC ON  CACHE BOOL "" FORCE)
    set(SDL_TEST   OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(SDL2)
endif()

# chips - header-only Z80/AY/ZX emulator core (no CMake project, just headers)
FetchContent_Declare(
    chips
    GIT_REPOSITORY https://github.com/floooh/chips.git
    GIT_TAG        master
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(chips)

# Historical note: chips/systems/zx.h does not emulate the Spectrum's
# floating data bus during IRQ acknowledge (IORQ + M1 leaves the byte
# undefined). Any game whose IM 2 table overlaps a region of RAM that
# gets corrupted at runtime will crash on chips while running fine on
# real hardware. Tharkys hit this with MagicCompassVisited at $79DC
# overlapping the IM 2 table at $7A00. Fixed game-side in commit 95cc723
# by relocating BFS scratch to $5B00-$5BE0 (low RAM). If a future game
# tickles the same quirk, the floating-bus patch can be reintroduced.

# ============================================================================
# Embedded assets: game SNA + ZX 128 ROMs
# ============================================================================
set(GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")
file(MAKE_DIRECTORY ${GENERATED_DIR})

# --- juego.sna -> juego_sna.h (rebuild whenever the SNA changes) ---
set(SNA_HEADER "${GENERATED_DIR}/juego_sna.h")
add_custom_command(
    OUTPUT  ${SNA_HEADER}
    COMMAND ${Python3_EXECUTABLE}
            ${CMAKE_CURRENT_SOURCE_DIR}/scripts/bin2c.py
            ${SNA_SOURCE}
            ${SNA_HEADER}
            juego_sna
    DEPENDS ${SNA_SOURCE}
            ${CMAKE_CURRENT_SOURCE_DIR}/scripts/bin2c.py
    COMMENT "Embedding juego.sna into juego_sna.h"
    VERBATIM
)

# --- juego_release.tap -> juego_tap.h (default boot path) ---
# The .tap goes through the BASIC LOADER + custom splash before handing
# off to the game, matching what a user inserting the tape would see on
# real hardware. Tape trap in emu.c shortcuts the LD-BYTES audio loop
# so the load is effectively instant.
set(TAP_HEADER "${GENERATED_DIR}/juego_tap.h")
add_custom_command(
    OUTPUT  ${TAP_HEADER}
    COMMAND ${Python3_EXECUTABLE}
            ${CMAKE_CURRENT_SOURCE_DIR}/scripts/bin2c.py
            ${TAP_SOURCE}
            ${TAP_HEADER}
            juego_tap
    DEPENDS ${TAP_SOURCE}
            ${CMAKE_CURRENT_SOURCE_DIR}/scripts/bin2c.py
    COMMENT "Embedding juego_release.tap into juego_tap.h"
    VERBATIM
)

# --- ZX Spectrum 128K ROMs ---
# Amstrad authorised free redistribution of original Sinclair ROMs in 1999.
# Fetched once from chips-test (sister repo to chips) and cached.
set(ZX_ROMS_HEADER "${GENERATED_DIR}/zx_roms.h")
if(NOT EXISTS ${ZX_ROMS_HEADER})
    message(STATUS "Downloading ZX Spectrum ROMs (one-off)...")
    file(DOWNLOAD
        "https://raw.githubusercontent.com/floooh/chips-test/master/examples/roms/zx-roms.h"
        ${ZX_ROMS_HEADER}
        STATUS  _zx_roms_dl_status
        TIMEOUT 30
        TLS_VERIFY ON
    )
    list(GET _zx_roms_dl_status 0 _zx_roms_dl_code)
    if(NOT _zx_roms_dl_code EQUAL 0)
        file(REMOVE ${ZX_ROMS_HEADER})
        message(FATAL_ERROR "Failed to download zx-roms.h: ${_zx_roms_dl_status}")
    endif()
endif()

# --- reward font: reward_font_data.inc (source-of-truth) -> reward.ch8
#     (rebuilt in build/) -> reward_font.h (bin2c output) ---
# The font data lives as DEFB statements in code/reward_font_data.inc
# (Damien Guard's own distribution format). We extract the 768 raw
# bytes into a build-tree-only reward.ch8 so the existing bin2c
# pipeline keeps working unchanged. No .ch8 file is checked into the
# repo -- avoids any "re-hosting the font as a font" concern.
set(REWARD_INC     "${REPO_ROOT}/code/reward_font_data.inc")
set(REWARD_CH8     "${GENERATED_DIR}/reward.ch8")
set(REWARD_HEADER  "${GENERATED_DIR}/reward_font.h")
add_custom_command(
    OUTPUT  ${REWARD_CH8}
    COMMAND ${Python3_EXECUTABLE}
            ${REPO_ROOT}/tools/extract_reward_ch8.py
            ${REWARD_INC}
            ${REWARD_CH8}
    DEPENDS ${REWARD_INC}
            ${REPO_ROOT}/tools/extract_reward_ch8.py
    COMMENT "Extracting reward.ch8 from reward_font_data.inc"
    VERBATIM
)
add_custom_command(
    OUTPUT  ${REWARD_HEADER}
    COMMAND ${Python3_EXECUTABLE}
            ${CMAKE_CURRENT_SOURCE_DIR}/scripts/bin2c.py
            ${REWARD_CH8}
            ${REWARD_HEADER}
            reward_font
    DEPENDS ${REWARD_CH8}
            ${CMAKE_CURRENT_SOURCE_DIR}/scripts/bin2c.py
    COMMENT "Embedding reward.ch8 into reward_font.h"
    VERBATIM
)

# --- Splash sprite (BG sprite id 257 = 256x192 Spectrum-native image) -----
# Extracted from code/bg_sprites.json at build time into a C header that
# main.c includes. Re-runs when the JSON or the extraction script changes.
set(SPLASH_HEADER "${GENERATED_DIR}/splash_sprite.h")
set(SPLASH_SRC    "${REPO_ROOT}/code/bg_sprites.json")
add_custom_command(
    OUTPUT  ${SPLASH_HEADER}
    COMMAND ${Python3_EXECUTABLE}
            ${CMAKE_CURRENT_SOURCE_DIR}/scripts/extract_splash.py
            ${SPLASH_SRC}
            ${SPLASH_HEADER}
            257
    DEPENDS ${SPLASH_SRC}
            ${CMAKE_CURRENT_SOURCE_DIR}/scripts/extract_splash.py
    COMMENT "Extracting splash sprite 257 from bg_sprites.json"
    VERBATIM
)

add_custom_target(generate_assets DEPENDS ${SNA_HEADER} ${TAP_HEADER} ${ZX_ROMS_HEADER} ${SPLASH_HEADER} ${REWARD_HEADER})

# ============================================================================
# Executable
# ============================================================================
# Desktop uses the OpenGL 3.3 + custom CRT shader pipeline (video.c).
# Web (Emscripten) uses a no-shader SDL_Renderer blit (video_web.c) for the
# MVP -- same video.h interface, overlays stubbed out where they would need
# extra shader work.
if(EMSCRIPTEN)
    set(VIDEO_SRC src/video_web.c)
else()
    set(VIDEO_SRC src/video.c)
endif()

add_executable(tharkys
    src/main.c
    src/emu.c
    src/tape.c
    src/input.c
    src/gamepad.c
    ${VIDEO_SRC}
    vendor/ayumi/ayumi.c
)

add_dependencies(tharkys generate_assets)

target_include_directories(tharkys PRIVATE
    src
    ${GENERATED_DIR}
    ${chips_SOURCE_DIR}/chips
    ${chips_SOURCE_DIR}/systems
    vendor/ayumi
)

if(EMSCRIPTEN)
    # SDL2 is bundled into the link line by emcc via USE_SDL=2.
    # USE_WEBGL2 reserved for the future shader port; the MVP only uses
    # SDL_Renderer so plain canvas2D-equivalent is enough.
    target_compile_options(tharkys PRIVATE
        "SHELL:-s USE_SDL=2"
    )
    target_link_options(tharkys PRIVATE
        "SHELL:-s USE_SDL=2"
        "SHELL:-s ALLOW_MEMORY_GROWTH=1"
        "SHELL:-s INITIAL_MEMORY=64MB"
        "SHELL:-s STACK_SIZE=1MB"
        "SHELL:-s EXIT_RUNTIME=0"
    )
    # Output .html (default shell). Custom shell can come later.
    set_target_properties(tharkys PROPERTIES
        SUFFIX ".html"
    )
else()
    target_link_libraries(tharkys PRIVATE
        SDL2::SDL2-static
        SDL2::SDL2main
        OpenGL::GL
    )
endif()

# Treat warnings seriously but don't fail on every nit yet
if(MSVC)
    target_compile_options(tharkys PRIVATE /W3)
else()
    target_compile_options(tharkys PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()

# Windows: GUI subsystem (no console window in Release)
if(WIN32 AND NOT EMSCRIPTEN)
    set_target_properties(tharkys PROPERTIES
        WIN32_EXECUTABLE $<IF:$<CONFIG:Debug>,FALSE,TRUE>
    )
endif()

# macOS: bundle metadata (placeholder for now)
if(APPLE)
    set_target_properties(tharkys PROPERTIES
        MACOSX_BUNDLE FALSE
    )
endif()

# Drop a stable-named copy at the repo root after every build so the user
# can launch tharkys without diving into port/build/bin/. copy_if_different
# is silent on no-op rebuilds. Generator expressions give us tharkys.exe on
# Windows and tharkys on Linux/macOS automatically.
# Emscripten produces a triplet (.html + .js + .wasm), so we skip the
# stamp-at-repo-root step there -- the web target lives in build-web/.
if(NOT EMSCRIPTEN)
    add_custom_command(TARGET tharkys POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                $<TARGET_FILE:tharkys>
                ${REPO_ROOT}/$<TARGET_FILE_NAME:tharkys>
        COMMENT "Stamping $<TARGET_FILE_NAME:tharkys> at repo root"
    )
endif()

# ============================================================================
# Status
# ============================================================================
message(STATUS "")
message(STATUS "Tharkys desktop wrapper configured:")
message(STATUS "  Source SNA   : ${SNA_SOURCE}")
message(STATUS "  Source TAP   : ${TAP_SOURCE}")
message(STATUS "  Build type   : ${CMAKE_BUILD_TYPE}")
message(STATUS "  Output dir   : ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}")
message(STATUS "  Python       : ${Python3_EXECUTABLE}")
message(STATUS "")
