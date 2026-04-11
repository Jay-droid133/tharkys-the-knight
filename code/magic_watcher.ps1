$watcherPath = $PSScriptRoot
$triggerFile = Join-Path $watcherPath "_magic_run.json"

Write-Host "MAGIC WATCHER - NUEVO JUEGO" -ForegroundColor Cyan
Write-Host "Watching: $triggerFile" -ForegroundColor DarkGray
Write-Host "Waiting for signal from Level Editor..." -ForegroundColor Gray

while ($true) {
    if (Test-Path $triggerFile) {
        Write-Host "SIGNAL DETECTED!" -ForegroundColor Yellow
        try {
            Start-Sleep -Milliseconds 100
            Remove-Item $triggerFile -Force -ErrorAction SilentlyContinue

            Write-Host "Building and launching..." -ForegroundColor Cyan
            Push-Location $watcherPath
            & cmd.exe /c "build_and_spectaculator.bat"
            Pop-Location

            Write-Host "Done. Ready for next signal." -ForegroundColor Gray
        }
        catch {
            Write-Host "Error: $_" -ForegroundColor Red
            if (Test-Path $triggerFile) { Remove-Item $triggerFile -Force }
        }
    }
    Start-Sleep -Milliseconds 500
}
