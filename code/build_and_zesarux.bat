@echo off
:: Mismo build que build_and_spectaculator.bat, pero arranca ZEsarUX con
:: ZRCP habilitado y lanza el watcher track_player.py para que el level
:: editor pueda dibujar la posicion del player en tiempo real.
::
:: Requisitos:
::   - ZEsarUX en I:\PROGRAMACION\EMUS\ZEsarUX_windows-12.1\zesarux.exe
::   - Python en PATH

:: Auto-sync level editor exports si estamos en un worktree
echo %~dp0 | findstr /i "worktrees" >NUL
if %ERRORLEVEL% EQU 0 (
    echo Sincronizando datos del level editor...
    copy /Y "C:\NUEVO_JUEGO\code\bg_gfx.asm"     "%~dp0bg_gfx.asm"     >NUL 2>&1
    copy /Y "C:\NUEVO_JUEGO\code\screen_data.asm" "%~dp0screen_data.asm" >NUL 2>&1
)
echo Exportando HUD sprites desde JSON...
python "%~dp0..\tools\export_hud_sprites.py"
echo Comprimiendo BG sprites (RLE in-place, idempotente)...
python "%~dp0..\tools\compress_bg_rle.py"
echo Compilando para ZEsarUX...
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

:: Cualquier instancia previa estorba (puerto ZRCP ocupado). Cerramos.
taskkill /F /IM zesarux.exe >NUL 2>&1
:: Y matamos un watcher anterior si quedo huerfano.
wmic process where "name='python.exe' and commandline like '%%track_player.py%%'" delete >NUL 2>&1

echo Iniciando ZEsarUX con ZRCP (puerto 10000)...
:: --joystickemulated Kempston: el juego lee Kempston (puerto 31) ademas de QAOP.
::   Las teclas de cursor del PC se mapean al joystick emulado por defecto.
:: Tambien sigues pudiendo usar QAOP en el teclado, y SPACE/M/N segun el juego.
:: --zoomx/--zoomy: 1=256x192 nativo, 2=512x384, 3=768x576 (1080p), 4=1024x768.
::   Cambia este valor para ajustar el tamano de la ventana del emu.
::   Nota: si vas a usar ShaderGlass encima, mejor zoom=1 para que el shader
::   tenga maximo detalle por scanline (luego ShaderGlass escala).
:: --disablefooter / --disableborder: ventana limpia, solo el canvas del juego.
::   Quita uno de los dos si quieres recuperar el footer (FPS) o el borde Spectrum.
set ZES_ZOOM=1
:: ZEsarUX en Windows abre su propia ventana de consola (es console subsystem).
:: Lo lanzamos via tools/launch_zesarux.ps1 con Start-Process -WindowStyle Hidden
:: para ocultarla (la ventana SDL del juego sigue visible). El .ps1 contiene la
:: lista de flags (joystick, zoom, sin footer/border/welcome/wizard, ZRCP, etc).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\launch_zesarux.ps1" ^
    -ZesExe "I:\PROGRAMACION\EMUS\ZEsarUX_windows-12.1\zesarux.exe" ^
    -SnaPath "%~dp0juego.sna" ^
    -Zoom %ZES_ZOOM% ^
    -SgExe "C:\Users\JJ\Downloads\ShaderGlass-1.2.3.1-win-x64\ShaderGlass.exe" ^
    -SgProfile "%~dp0..\tools\zesarux.sgp"

echo Iniciando watcher de posicion del player...
start "track_player" /MIN python "%~dp0..\tools\track_player.py"

exit /b 0
