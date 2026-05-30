@echo off
REM ============================================================================
REM  Pack the web build into a zip ready to drag into itch.io's HTML project.
REM
REM  Itch.io requires the entry HTML to be named exactly "index.html" at the
REM  ROOT of the zip (no top-level folder). This script:
REM    1) Renames tharkys.html -> index.html.
REM    2) Bundles the wasm + js + manifest + icons next to it.
REM    3) Zips them flat into port\build-web\tharkys_itch.zip.
REM
REM  After running, in itch.io:
REM    Edit game -> "Kind of project" = HTML
REM    Uploads   -> drag tharkys_itch.zip in
REM    Tick     "This file will be played in the browser"
REM    Embed options -> Viewport ~1024x768, "Click to launch in fullscreen"
REM    (You can keep juego_standalone.tap as an additional downloadable file.)
REM
REM  Prereq: a fresh build at port\build-web\bin\ (run port\build_and_deploy_web.bat
REM  or `cmake --build port\build-web` first).
REM
REM  Note: this zip is intentionally the bare emscripten HTML, NOT the Pages
REM  build with the self-update bootstrap injected. Itch serves each upload
REM  from a unique URL, so the Pages-specific cache-bust trick (version.txt
REM  fetch) isn't needed in the iframe. The wasm filename stays fixed inside
REM  the zip; itch's per-upload URL handles cache busting for you.
REM ============================================================================
setlocal
set "PORT=%~dp0"
set "BIN=%PORT%build-web\bin"
set "WEB=%PORT%web"
set "STAGE=%PORT%build-web\itch_stage"
set "OUT=%PORT%build-web\tharkys_itch.zip"

if not exist "%BIN%\tharkys.wasm" goto :nobuild
if not exist "%WEB%\manifest.webmanifest" goto :noweb

REM Fresh staging dir.
if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%" || goto :err

REM index.html = renamed tharkys.html (itch wants exactly this name at root).
copy /Y "%BIN%\tharkys.html"          "%STAGE%\index.html"     >nul || goto :err
copy /Y "%BIN%\tharkys.js"            "%STAGE%\"               >nul || goto :err
copy /Y "%BIN%\tharkys.wasm"          "%STAGE%\"               >nul || goto :err
copy /Y "%WEB%\manifest.webmanifest"  "%STAGE%\"               >nul || goto :err
copy /Y "%WEB%\icon-192.png"          "%STAGE%\"               >nul || goto :err
copy /Y "%WEB%\icon-512.png"          "%STAGE%\"               >nul || goto :err

REM Zip flat (no top-level folder) via Python's stdlib -- no extra deps.
if exist "%OUT%" del /q "%OUT%"
python -c "import shutil; shutil.make_archive(r'%OUT:.zip=%', 'zip', r'%STAGE%')" || goto :err

echo.
echo === DONE ===
echo Zip ready: %OUT%
echo Drag this into itch.io's "Uploads" with "Kind of project" = HTML.
echo.
echo Files at the root of the zip:
dir /b "%STAGE%"
exit /b 0

:nobuild
echo.
echo *** No build found at "%BIN%\tharkys.wasm".
echo *** Build first:  port\build_and_deploy_web.bat
echo ***          or:  cmake --build port\build-web
exit /b 1

:noweb
echo.
echo *** Missing PWA assets in "%WEB%".
echo *** Generate icons + manifest: python port\web\gen_icons.py
exit /b 1

:err
echo.
echo *** FAILED -- see output above. Nothing was zipped. ***
exit /b 1
