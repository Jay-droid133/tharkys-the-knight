@echo off
:: build_all.bat - Compila release Y standalone, lanza Spectaculator con standalone.
:: Usado como default build task (F6 en VS Code). Para solo release usar
:: build_and_spectaculator.bat; para solo standalone build_and_standalone.bat.

:: Auto-sync level editor exports si estamos en un worktree
echo %~dp0 | findstr /i "worktrees" >NUL
if %ERRORLEVEL% EQU 0 (
    echo Sincronizando datos del level editor...
    copy /Y "C:\NUEVO_JUEGO\code\bg_gfx.asm"     "%~dp0bg_gfx.asm"     >NUL 2>&1
    copy /Y "C:\NUEVO_JUEGO\code\screen_data.asm" "%~dp0screen_data.asm" >NUL 2>&1
)
echo === Preprocessors ===
python "%~dp0..\tools\backup_bg_sprites.py"
python "%~dp0..\tools\export_hud_sprites.py"
python "%~dp0..\tools\sync_bg_pickups.py" --no-rle
python "%~dp0..\tools\compress_bg_rle.py"
python "%~dp0..\tools\inject_pickup_sprites.py"
python "%~dp0..\tools\import_magic_compass_hud.py"
python "%~dp0..\tools\build_sfx.py"
if %ERRORLEVEL% NEQ 0 ( echo ERROR build_sfx & pause & exit /b 1 )
python "%~dp0..\tools\build_tap_with_splash.py"
if %ERRORLEVEL% NEQ 0 ( echo ERROR build_tap_with_splash pre & pause & exit /b 1 )
python "%~dp0..\tools\build_minimap_overlay.py"
if %ERRORLEVEL% NEQ 0 ( echo ERROR build_minimap_overlay & pause & exit /b 1 )
python "%~dp0..\tools\build_splash_zx0.py"
if %ERRORLEVEL% NEQ 0 ( echo ERROR build_splash_zx0 & pause & exit /b 1 )
python "%~dp0..\tools\build_loading_185.py"
if %ERRORLEVEL% NEQ 0 ( echo ERROR build_loading_185 & pause & exit /b 1 )
python "%~dp0..\tools\build_standalone_story.py"
if %ERRORLEVEL% NEQ 0 ( echo ERROR build_standalone_story & pause & exit /b 1 )
python "%~dp0..\tools\check_screen_buffer.py"
if %ERRORLEVEL% NEQ 0 ( echo ERROR check_screen_buffer & pause & exit /b 1 )

echo === Compilando RELEASE ===
"I:\PROGRAMACION\COMPILADORES\sjasmplus-1.21.1.win\sjasmplus.exe" --fullpath --syntax=abfF --sld="%~dp0..\NuevoJuego.sld" --lst="%~dp0tmp.lst" main.asm > "%TEMP%\sjasmplus_rel.tmp" 2>&1
set BUILD_REL_ERR=%ERRORLEVEL%
type "%TEMP%\sjasmplus_rel.tmp"
python "%~dp0..\tools\parse_build_stats.py" "%TEMP%\sjasmplus_rel.tmp" "%~dp0build_stats.json"
del "%TEMP%\sjasmplus_rel.tmp" 2>NUL
if %BUILD_REL_ERR% NEQ 0 ( echo ERROR sjasmplus release & pause & exit /b 1 )

:: Postproc release: build_tap_with_splash genera juego_release.tap
python "%~dp0..\tools\build_tap_with_splash.py"

echo === Compilando STANDALONE ===
"I:\PROGRAMACION\COMPILADORES\sjasmplus-1.21.1.win\sjasmplus.exe" --fullpath --syntax=abfF -DSTANDALONE=1 --sld="%~dp0..\NuevoJuego.sld" --lst="%~dp0tmp_standalone.lst" main.asm > "%TEMP%\sjasmplus_sa.tmp" 2>&1
set BUILD_SA_ERR=%ERRORLEVEL%
type "%TEMP%\sjasmplus_sa.tmp"
del "%TEMP%\sjasmplus_sa.tmp" 2>NUL
if %BUILD_SA_ERR% NEQ 0 ( echo ERROR sjasmplus standalone & pause & exit /b 1 )

echo ==============================
echo  Builds OK: juego.{tap,sna} + juego_standalone.{tap,sna}
echo ==============================

echo Iniciando Spectaculator con juego_standalone.sna...
start "" "C:\Program Files (x86)\Spectaculator\Spectaculator.exe" "%~dp0juego_standalone.sna"
start /b powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0unpause_spectaculator.ps1"

exit /b 0
