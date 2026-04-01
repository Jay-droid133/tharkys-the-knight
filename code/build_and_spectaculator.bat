@echo off
:: Auto-sync level editor exports si estamos en un worktree
echo %~dp0 | findstr /i "worktrees" >NUL
if %ERRORLEVEL% EQU 0 (
    echo Sincronizando datos del level editor...
    copy /Y "C:\NUEVO_JUEGO\code\bg_gfx.asm" "%~dp0bg_gfx.asm" >NUL 2>&1
    copy /Y "C:\NUEVO_JUEGO\code\screen_data.asm" "%~dp0screen_data.asm" >NUL 2>&1
)
echo Compilando para Spectaculator (F6)...
"I:\PROGRAMACION\COMPILADORES\sjasmplus-1.21.1.win\sjasmplus.exe" --fullpath --syntax=abfF main.asm > "%TEMP%\sjasmplus_out.tmp" 2>&1
set BUILD_ERR=%ERRORLEVEL%
type "%TEMP%\sjasmplus_out.tmp"
for /f "delims=" %%L in ('findstr /i "RAM Libre" "%TEMP%\sjasmplus_out.tmp"') do set FREE_BYTES=%%L
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

:: Check if Spectaculator is already running
tasklist /FI "IMAGENAME eq Spectaculator.exe" 2>NUL | find /I "Spectaculator.exe" >NUL
if %ERRORLEVEL% EQU 0 goto :INJECT

:: Not running - launch fresh
echo Iniciando Spectaculator...
start "" "C:\Program Files (x86)\Spectaculator\Spectaculator.exe" "juego.tap"

:: Bring to front once after launch
start /b powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0unpause_spectaculator.ps1"
goto :END

:INJECT
echo Spectaculator ya esta corriendo. Inyectando .tap...
start "" "C:\Program Files (x86)\Spectaculator\Spectaculator.exe" "juego.tap"
:: Bring to front, keep on top, and unpause
start /b powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0unpause_spectaculator.ps1"

:END
exit /b 0
