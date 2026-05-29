@echo off
REM ============================================================================
REM  Rebuild the web wrapper AND deploy it to GitHub Pages, in one step.
REM
REM  Why both steps: the on-screen build stamp + the cache-bust hash live INSIDE
REM  the wasm, set at COMPILE time. Re-deploying alone ships the same binary, so
REM  the stamp never changes -- only a rebuild bumps it. This bat does both:
REM    1) cmake --build  -> regenerates build_stamp.h (current time) + fresh wasm
REM    2) deploy_pages.sh -> ships bin/ to Jay-droid133/tharkys with cache-busting
REM                          and the self-update bootstrap (version.txt), so a
REM                          phone auto-reloads to the latest build on its own.
REM
REM  NOTE: we call Git Bash by full path on purpose. Bare "bash" on this machine
REM  resolves to WSL (C:\Windows\System32\bash.exe), which has a different
REM  filesystem view and would break the deploy script.
REM ============================================================================
setlocal
set "PORT=%~dp0"
set "GITBASH=C:\Program Files\Git\bin\bash.exe"

echo === [1/2] Rebuilding web wrapper (regenerates build stamp + wasm hash) ===
call "C:\emsdk\emsdk_env.bat" || goto :err
cmake --build "%PORT%build-web" -j 8 || goto :err

echo.
echo === [2/2] Deploying to GitHub Pages ===
if not exist "%GITBASH%" goto :nobash
cd /d "%PORT%"
"%GITBASH%" scripts/deploy_pages.sh || goto :err

echo.
echo === Done. Live at https://jay-droid133.github.io/tharkys/ ===
echo (The on-screen stamp should now match this build's time. Phones auto-update.)
exit /b 0

:nobash
echo.
echo *** Git Bash not found at "%GITBASH%" ***
echo Edit this .bat and point GITBASH at your bash.exe.
exit /b 1

:err
echo.
echo *** BUILD/DEPLOY FAILED (see output above) -- nothing was deployed ***
exit /b 1
