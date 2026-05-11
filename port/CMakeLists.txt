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

# Locate the parent repo (we need juego.sna from there)
set(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(SNA_SOURCE "${REPO_ROOT}/juego.sna")

# Python is required at build time to convert binary blobs to C headers
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# ============================================================================
# Dependencies (FetchContent)
# ============================================================================
include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

# SDL2 - audio, video, input, gamepad
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

# chips - header-only Z80/AY/ZX emulator core (no CMake project, just headers)
FetchContent_Declare(
    chips
    GIT_REPOSITORY https://github.com/floooh/chips.git
    GIT_TAG        master
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(chips)

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

add_custom_target(generate_assets DEPENDS ${SNA_HEADER} ${ZX_ROMS_HEADER})

# ============================================================================
# Executable
# ============================================================================
add_executable(tharkys
    src/main.c
    src/emu.c
    src/input.c
)

add_dependencies(tharkys generate_assets)

target_include_directories(tharkys PRIVATE
    src
    ${GENERATED_DIR}
    ${chips_SOURCE_DIR}/chips
    ${chips_SOURCE_DIR}/systems
)

target_link_libraries(tharkys PRIVATE
    SDL2::SDL2-static
    SDL2::SDL2main
)

# Treat warnings seriously but don't fail on every nit yet
if(MSVC)
    target_compile_options(tharkys PRIVATE /W3)
else()
    target_compile_options(tharkys PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()

# Windows: GUI subsystem (no console window in Release)
if(WIN32)
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

# ============================================================================
# Status
# ============================================================================
message(STATUS "")
message(STATUS "Tharkys desktop wrapper configured:")
message(STATUS "  Source SNA   : ${SNA_SOURCE}")
message(STATUS "  Build type   : ${CMAKE_BUILD_TYPE}")
message(STATUS "  Output dir   : ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}")
message(STATUS "  Python       : ${Python3_EXECUTABLE}")
message(STATUS "")
