@echo off
:: Lanza Chrome con el HUD Viewer + arranca un http.server en puerto 8000.
:: Si ya hay un server vivo en 8000, Chrome se abre igual y python falla
:: silenciosamente (port in use). Es idempotente.

start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" "http://localhost:8000/tools/hud_viewer.html"
cd /d "%~dp0.."
python -m http.server 8000
