# Wait for Spectaculator to finish loading the .tap
Start-Sleep -Milliseconds 2500

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class SpectaculatorHelper {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr h, IntPtr i, int x, int y, int cx, int cy, uint f);


}
"@

$p = Get-Process Spectaculator -ErrorAction SilentlyContinue |
     Where-Object { $_.MainWindowHandle -ne 0 } |
     Select-Object -First 1

if ($p) {
    $h = $p.MainWindowHandle
    [SpectaculatorHelper]::ShowWindow($h, 9)       # SW_RESTORE
    [SpectaculatorHelper]::SetForegroundWindow($h)
    # Briefly set TOPMOST then remove it - reliably brings to front without staying pinned
    [SpectaculatorHelper]::SetWindowPos($h, [IntPtr]::new(-1), 0, 0, 0, 0, 0x0013)  # TOPMOST
    [SpectaculatorHelper]::SetWindowPos($h, [IntPtr]::new(-2), 0, 0, 0, 0, 0x0013)  # NOTOPMOST
    [SpectaculatorHelper]::SetForegroundWindow($h)
}
