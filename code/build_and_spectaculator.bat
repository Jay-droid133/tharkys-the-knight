@echo off
:: Auto-sync level editor exports si estamos en un worktree
echo %~dp0 | findstr /i "worktrees" >NUL
if %ERRORLEVEL% EQU 0 (
    echo Sincronizando datos del level editor...
    copy /Y "C:\NUEVO_JUEGO\code\bg_gfx.asm" "%~dp0bg_gfx.asm" >NUL 2>&1
    copy /Y "C:\NUEVO_JUEGO\code\screen_data.asm" "%~dp0screen_data.asm" >NUL 2>&1
)
echo Exportando HUD sprites desde JSON...
python "%~dp0..\tools\export_hud_sprites.py"
echo Sincronizando code-ref sprites desde bg_sprites.json (raw, RLE despues)...
python "%~dp0..\tools\sync_bg_pickups.py" --no-rle
echo Comprimiendo BG sprites (RLE in-place, idempotente)...
python "%~dp0..\tools\compress_bg_rle.py"
echo Inyectando pickup sprites si faltan (idempotente, no-op tras editor re-export)...
python "%~dp0..\tools\inject_pickup_sprites.py"
echo Sincronizando sprite del magic compass HUD (id 36)...
python "%~dp0..\tools\import_magic_compass_hud.py"
echo Verificando CurrentScreenBuffer caps...
python "%~dp0..\tools\check_screen_buffer.py"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Algun room excede CurrentScreenBuffer cap. Build abortado.
    echo Solucion: ampliar buffer en variables.asm o reducir placements del room.
    pause
    exit /b 1
)
echo Compilando para Spectaculator (F6)...
"I:\PROGRAMACION\COMPILADORES\sjasmplus-1.21.1.win\sjasmplus.exe" --fullpath --syntax=abfF main.asm > "%TEMP%\sjasmplus_out.tmp" 2>&1
set BUILD_ERR=%ERRORLEVEL%
type "%TEMP%\sjasmplus_out.tmp"
for /f "delims=" %%L in ('findstr /i "RAM Libre" "%TEMP%\sjasmplus_out.tmp"') do set FREE_BYTES=%%L
:: Volcar el uso por banco a build_stats.json para que el level editor lo lea.
python "%~dp0..\tools\parse_build_stats.py" "%TEMP%\sjasmplus_out.tmp" "%~dp0build_stats.json"
del "%TEMP%\sjasmplus_out.tmp" 2>NUL
if %BUILD_ERR% NEQ 0 (
    echo ERROR: Compilacion fallida
    pause
    exit /b 1
)
echo.
for /f "tokens=7" %%H in ("%FREE_BYTES%") do set /a FREE_DEC=%%H
echo ==============================
echo  Bytes libres: %FREE_DEC%
echo ==============================

echo Iniciando Spectaculator...
start "" "C:\Program Files (x86)\Spectaculator\Spectaculator.exe" "juego.sna"

:: Bring to front once after launch
start /b powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0unpause_spectaculator.ps1"

exit /b 0
