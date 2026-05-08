@echo off
:: tools/memory_map.bat
::
:: Lanza el servidor del mapa de memoria (idempotente) y abre Chrome
:: apuntandolo. Pensado para Shift+F7 desde VS Code o doble-click.
::
:: Idempotencia: si el puerto 8765 ya responde HTTP en /healthz, no
:: relanza nada (se asume que el server ya esta corriendo de una sesion
:: anterior). Solo abre la pestana de Chrome.

setlocal
set PORT=8765
set URL=http://localhost:%PORT%/

set SCRIPT_DIR=%~dp0
set REPO_ROOT=%SCRIPT_DIR%..

:: Comprobar si el server ya esta vivo. PowerShell oneliner: TCP probe.
:: Si responde, salimos del check y vamos directo a abrir Chrome.
powershell -NoProfile -Command "$c=New-Object Net.Sockets.TcpClient;try{$c.Connect('127.0.0.1',%PORT%);exit 0}catch{exit 1}finally{$c.Dispose()}" >NUL 2>&1
if %ERRORLEVEL% EQU 0 (
    echo memory_map: server ya activo en %URL%
    goto :open_chrome
)

:: Localizar pythonw.exe (sin ventana de consola) o python.exe como fallback.
set PYW=pythonw.exe
where %PYW% >NUL 2>&1
if %ERRORLEVEL% NEQ 0 (
    set PYW=python.exe
)

echo memory_map: arrancando servidor en %URL% ...
:: Lanzar en background, sin bloquear el .bat. /B para no abrir ventana
:: nueva; pythonw.exe ya garantiza que no haya consola visible.
start "" /B %PYW% "%SCRIPT_DIR%memory_map_serve.py" --port %PORT%

:: Esperar a que el server este listo (max 5 s).
set /a tries=0
:wait_loop
powershell -NoProfile -Command "$c=New-Object Net.Sockets.TcpClient;try{$c.Connect('127.0.0.1',%PORT%);exit 0}catch{exit 1}finally{$c.Dispose()}" >NUL 2>&1
if %ERRORLEVEL% EQU 0 goto :open_chrome
set /a tries+=1
if %tries% GEQ 25 (
    echo memory_map: server no respondio en 5 s. Comprueba el log.
    exit /b 1
)
:: Sleep ~200 ms.
ping 127.0.0.1 -n 1 -w 200 >NUL
goto :wait_loop

:open_chrome
:: Abrir Chrome. Usar /B start para no esperar.
set CHROME="C:\Program Files\Google\Chrome\Application\chrome.exe"
if exist %CHROME% (
    start "" %CHROME% %URL%
) else (
    :: Fallback al navegador predeterminado.
    start "" %URL%
)
exit /b 0
