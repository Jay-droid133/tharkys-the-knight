@echo off
:: build_and_tharkys.bat - mirror of build_and_spectaculator.bat but with
:: an extra step that rebuilds the desktop wrapper (chips/zx + GL CRT) and
:: launches the resulting tharkys.exe instead of Spectaculator.
::
::   1. Same pre-tools python pipeline (HUD sprites, BG pickups, RLE,
::      pickup injection, compass HUD, screen-buffer caps check).
::   2. sjasmplus to regenerate juego.sna in code/.
::   3. Copy code\juego.sna -> repo root so CMake's DEPENDS picks it up.
::   4. cmake --build (incremental: bin2c + main.c + relink, ~5-10 s).
::   5. tharkys.exe is post-build-copied to the repo root by CMakeLists,
::      so we just launch from there.

setlocal
cd /d "%~dp0"

:: --- Pre-tools (mirror of build_and_spectaculator.bat) -----------
echo Backup snapshot de bg_sprites.json...
python "%~dp0..\tools\backup_bg_sprites.py"
echo Exportando HUD sprites desde JSON...
python "%~dp0..\tools\export_hud_sprites.py"
echo Sincronizando code-ref sprites desde bg_sprites.json (raw, RLE despues)...
python "%~dp0..\tools\sync_bg_pickups.py" --no-rle
echo Comprimiendo BG sprites (RLE in-place, idempotente)...
python "%~dp0..\tools\compress_bg_rle.py"
echo Inyectando pickup sprites si faltan (idempotente, no-op tras editor re-export)...
python "%~dp0..\tools\inject_pickup_sprites.py"
echo Sincronizando sprites del magic compass HUD (id 36 temporal + id 37 permanente)...
python "%~dp0..\tools\import_magic_compass_hud.py"
echo Compilando libreria SFX (sfx_library.json a sfx_data.asm)...
python "%~dp0..\tools\build_sfx.py"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: build_sfx fallido
    pause
    exit /b 1
)
echo Verificando CurrentScreenBuffer caps...
python "%~dp0..\tools\check_screen_buffer.py"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Algun room excede CurrentScreenBuffer cap. Build abortado.
    pause
    exit /b 1
)

:: --- sjasmplus ----------------------------------------------------
echo Compilando juego.sna...
:: --sld + --lst regeneran los artefactos que consume tools/memory_map.py
:: (NuevoJuego.sld para simbolos por bank, code/tmp.lst para deteccion de
:: gaps reales por bytes emitidos). Sin esto, memory_map muestra datos
:: stale del ultimo build manual.
"I:\PROGRAMACION\COMPILADORES\sjasmplus-1.21.1.win\sjasmplus.exe" --fullpath --syntax=abfF --sld="%~dp0..\NuevoJuego.sld" --lst="%~dp0tmp.lst" main.asm > "%TEMP%\sjasmplus_out.tmp" 2>&1
set BUILD_ERR=%ERRORLEVEL%
type "%TEMP%\sjasmplus_out.tmp"
for /f "delims=" %%L in ('findstr /i "RAM Libre" "%TEMP%\sjasmplus_out.tmp"') do set FREE_BYTES=%%L
python "%~dp0..\tools\parse_build_stats.py" "%TEMP%\sjasmplus_out.tmp" "%~dp0build_stats.json"
del "%TEMP%\sjasmplus_out.tmp" 2>NUL
if %BUILD_ERR% NEQ 0 (
    echo ERROR: Compilacion sjasmplus fallida
    pause
    exit /b 1
)

:: --- Sync SNA to repo root (where CMake's DEPENDS lives) ----------
copy /Y "juego.sna" "..\juego.sna" >NUL

:: --- Wrapper build ------------------------------------------------
echo.
echo Compilando wrapper desktop...
cd /d "%~dp0..\port"
if not exist "build\build.ninja" (
    echo Primera vez: configurando CMake con Ninja...
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
    if %ERRORLEVEL% NEQ 0 (
        echo ERROR: cmake configure fallido
        pause
        exit /b 1
    )
)
cmake --build build --config Release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: compilacion wrapper fallida
    pause
    exit /b 1
)

:: --- Banner + launch ----------------------------------------------
echo.
for /f "tokens=7" %%H in ("%FREE_BYTES%") do set /a FREE_DEC=%%H
echo ==============================
echo  Bytes libres SNA: %FREE_DEC%
echo ==============================

:: Generar juego_release.tap (BASIC custom + SCREEN$ bg257 + bloques originales).
:: Idempotente: solo reescribe si cambian inputs.
python "%~dp0..\tools\build_tap_with_splash.py"

echo.
echo Iniciando Tharkys...
start "" "%~dp0..\tharkys.exe"

endlocal
exit /b 0
