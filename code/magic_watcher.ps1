$watcherPath = $PSScriptRoot
$triggerSpec = Join-Path $watcherPath "_magic_run.json"            # → Spectaculator
$triggerZes  = Join-Path $watcherPath "_magic_zesarux.json"        # → ZEsarUX + tracker
$triggerStop = Join-Path $watcherPath "_magic_zesarux_stop.json"   # → mata ZEsarUX + watcher

Write-Host "MAGIC WATCHER - NUEVO JUEGO" -ForegroundColor Cyan
Write-Host "Watching: $triggerSpec  (Spectaculator)" -ForegroundColor DarkGray
Write-Host "Watching: $triggerZes   (ZEsarUX + track_player)" -ForegroundColor DarkGray
Write-Host "Watching: $triggerStop  (STOP)" -ForegroundColor DarkGray
Write-Host "Waiting for signals from Level Editor..." -ForegroundColor Gray

while ($true) {
    # STOP tiene prioridad: si llega junto con un launch, atendemos primero.
    if (Test-Path $triggerStop) {
        Write-Host "STOP signal: cerrando ZEsarUX y watcher" -ForegroundColor Yellow
        try {
            Start-Sleep -Milliseconds 100
            Remove-Item $triggerStop -Force -ErrorAction SilentlyContinue

            # Mata zesarux.exe (todas las instancias)
            $zes = Get-Process -Name zesarux -ErrorAction SilentlyContinue
            if ($zes) {
                $zes | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Host ("  killed zesarux.exe x" + $zes.Count) -ForegroundColor DarkGray
            } else {
                Write-Host "  zesarux.exe no estaba corriendo" -ForegroundColor DarkGray
            }

            # Mata ShaderGlass.exe si quedo abierto enganchado al emu
            $sg = Get-Process -Name ShaderGlass -ErrorAction SilentlyContinue
            if ($sg) {
                $sg | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Host ("  killed ShaderGlass.exe x" + $sg.Count) -ForegroundColor DarkGray
            }

            # Mata SOLO el python que ejecuta track_player.py (no otros pythons)
            $pyTracks = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
                        Where-Object { $_.CommandLine -like '*track_player.py*' }
            if ($pyTracks) {
                foreach ($p in $pyTracks) {
                    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
                    Write-Host ("  killed python pid=" + $p.ProcessId) -ForegroundColor DarkGray
                }
            } else {
                Write-Host "  track_player.py no estaba corriendo" -ForegroundColor DarkGray
            }

            Write-Host "Stopped." -ForegroundColor Gray
        }
        catch {
            Write-Host "Error STOP: $_" -ForegroundColor Red
            if (Test-Path $triggerStop) { Remove-Item $triggerStop -Force }
        }
    }
    elseif (Test-Path $triggerSpec) {
        Write-Host "SIGNAL: _magic_run.json -> build_and_spectaculator.bat" -ForegroundColor Yellow
        try {
            Start-Sleep -Milliseconds 100
            Remove-Item $triggerSpec -Force -ErrorAction SilentlyContinue
            Push-Location $watcherPath
            & cmd.exe /c "build_and_spectaculator.bat"
            Pop-Location
            Write-Host "Done." -ForegroundColor Gray
        }
        catch {
            Write-Host "Error: $_" -ForegroundColor Red
            if (Test-Path $triggerSpec) { Remove-Item $triggerSpec -Force }
        }
    }
    elseif (Test-Path $triggerZes) {
        Write-Host "SIGNAL: _magic_zesarux.json -> build_and_zesarux.bat" -ForegroundColor Yellow
        try {
            Start-Sleep -Milliseconds 100
            Remove-Item $triggerZes -Force -ErrorAction SilentlyContinue
            Push-Location $watcherPath
            & cmd.exe /c "build_and_zesarux.bat"
            Pop-Location
            Write-Host "Done." -ForegroundColor Gray
        }
        catch {
            Write-Host "Error: $_" -ForegroundColor Red
            if (Test-Path $triggerZes) { Remove-Item $triggerZes -Force }
        }
    }
    Start-Sleep -Milliseconds 500
}
