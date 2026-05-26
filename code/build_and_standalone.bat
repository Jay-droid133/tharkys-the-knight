@echo off
:: Build STANDALONE: variante con flujo wrapper-on-Z80 dentro del binario.
:: Diferencias vs build_and_zesarux.bat:
::   - Llama a build_splash_zx0.py antes de sjasmplus (genera code/bg_splash.zx0)
::   - sjasmplus con -DSTANDALONE=1 (activa los IFDEF en main.asm)
::   - Output: juego_standalone.tap + juego_standalone.sna
::   - No corre build_tap_with_splash.py al final (no aplica a standalone)
::
:: El release tradicional (juego.tap/sna sin flujo on-Z80) lo sigue produciendo
:: build_and_zesarux.bat / build_and_spectaculator.bat sin tocar.

:: Auto-sync level editor exports si estamos en un worktree
echo %~dp0 | findstr /i "worktrees" >NUL
if %ERRORLEVEL% EQU 0 (
    echo Sincronizando datos del level editor...
    copy /Y "C:\NUEVO_JUEGO\code\bg_gfx.asm"     "%~dp0bg_gfx.asm"     >NUL 2>&1
    copy /Y "C:\NUEVO_JUEGO\code\screen_data.asm" "%~dp0screen_data.asm" >NUL 2>&1
)
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
echo Regenerando splash_prompt.bin desde bg_sprites.json...
python "%~dp0..\tools\build_tap_with_splash.py"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: build_tap_with_splash pre-sjasmplus fallido
    pause
    exit /b 1
)
echo Comprimiendo splash bg-185 con ZX0...
python "%~dp0..\tools\build_splash_zx0.py"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: build_splash_zx0 fallido
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
echo Compilando STANDALONE (--define STANDALONE=1)...
"I:\PROGRAMACION\COMPILADORES\sjasmplus-1.21.1.win\sjasmplus.exe" --fullpath --syntax=abfF -DSTANDALONE=1 --sld="%~dp0..\NuevoJuego.sld" --lst="%~dp0tmp_standalone.lst" main.asm > "%TEMP%\sjasmplus_standalone.tmp" 2>&1
set BUILD_ERR=%ERRORLEVEL%
type "%TEMP%\sjasmplus_standalone.tmp"
del "%TEMP%\sjasmplus_standalone.tmp" 2>NUL
if %BUILD_ERR% NEQ 0 (
    echo ERROR: Compilacion STANDALONE fallida
    pause
    exit /b 1
)
echo ==============================
echo  STANDALONE: juego_standalone.tap + juego_standalone.sna
echo ==============================

:: Lanzar Spectaculator con el SNA standalone para test
echo Iniciando Spectaculator con juego_standalone.sna...
start "" "C:\Program Files (x86)\Spectaculator\Spectaculator.exe" "%~dp0juego_standalone.sna"
start /b powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0unpause_spectaculator.ps1"

exit /b 0
