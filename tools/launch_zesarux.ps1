# Launcher de ZEsarUX que oculta la ventana de consola que Windows le asigna
# (ZEsarUX se compila como console subsystem en Win, asi que start "" abre una
# ventana negra con la GPL/cabecera). Start-Process -WindowStyle Hidden la
# oculta; la ventana SDL del juego sigue visible.
#
# Uso desde el .bat:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\launch_zesarux.ps1 ^
#       -ZesExe "..." -SnaPath "..." -Zoom 3

param(
    [Parameter(Mandatory=$true)] [string]$ZesExe,
    [Parameter(Mandatory=$true)] [string]$SnaPath,
    [int]$Zoom = 3,
    [int]$Port = 10000
)

$argList = @(
    '--noconfigfile',
    '--disable-debug-console-win',
    '--machine', '128k',
    '--joystickemulated', 'Kempston',
    '--zoomx', "$Zoom", '--zoomy', "$Zoom",
    '--disablefooter',
    '--nosplash',
    '--nowelcomemessage',
    '--disable-first-start-wizard',
    '--disable-restore-windows',
    '--no-show-david-in-memoriam',
    '--hide-minimized-windows',
    '--disable-all-first-aid',
    '--enable-remoteprotocol',
    '--remoteprotocol-port', "$Port",
    '--snap', $SnaPath
)

Start-Process -WindowStyle Hidden -FilePath $ZesExe -ArgumentList $argList

# Trae la ventana SDL del juego al frente con foco y mueve el cursor a su
# centro (asi el primer click/teclazo va al juego sin tener que apuntar).
# Mismo patron que unpause_spectaculator.ps1: TOPMOST momentaneo + NOTOPMOST.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFg {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr i, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
}
"@

# Espera hasta 5s a que ZEsarUX spawnee su ventana SDL.
$deadline = (Get-Date).AddSeconds(5)
do {
    Start-Sleep -Milliseconds 200
    $p = Get-Process -Name zesarux -ErrorAction SilentlyContinue |
         Where-Object { $_.MainWindowHandle -ne 0 } |
         Select-Object -First 1
} while (-not $p -and (Get-Date) -lt $deadline)

if ($p) {
    $h = $p.MainWindowHandle
    [WinFg]::ShowWindow($h, 9) | Out-Null         # SW_RESTORE
    [WinFg]::SetForegroundWindow($h) | Out-Null
    [WinFg]::SetWindowPos($h, [IntPtr]::new(-1), 0, 0, 0, 0, 0x0013) | Out-Null  # TOPMOST
    [WinFg]::SetWindowPos($h, [IntPtr]::new(-2), 0, 0, 0, 0, 0x0013) | Out-Null  # NOTOPMOST
    [WinFg]::SetForegroundWindow($h) | Out-Null

    # Cursor al centro de la ventana del emu.
    $rect = New-Object WinFg+RECT
    if ([WinFg]::GetWindowRect($h, [ref]$rect)) {
        $cx = [int](($rect.Left + $rect.Right) / 2)
        $cy = [int](($rect.Top  + $rect.Bottom) / 2)
        [WinFg]::SetCursorPos($cx, $cy) | Out-Null
    }
}
