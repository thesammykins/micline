param([string]$Exe = "$PSScriptRoot/dist/MicLine/MicLine.exe")
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DesktopProbe {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h, int id);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder text, int capacity);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
}
'@
$captures = Join-Path $PSScriptRoot 'dist/screenshots'
New-Item -ItemType Directory -Force $captures | Out-Null
function Read-Text($handle) {
    $text = [Text.StringBuilder]::new(1024)
    [void][DesktopProbe]::GetWindowText($handle, $text, $text.Capacity)
    return $text.ToString()
}
foreach ($state in 'empty','configured','active','recovery') {
    $process = Start-Process $Exe -ArgumentList '--fixture', $state -PassThru
    try {
        $window = [IntPtr]::Zero
        for ($i=0; $i -lt 100; $i++) {
            Start-Sleep -Milliseconds 100
            $process.Refresh()
            if ($process.HasExited) { throw "Fixture $state exited early: $($process.ExitCode)" }
            $window = $process.MainWindowHandle
            if ($window -ne [IntPtr]::Zero) { break }
        }
        if ($window -eq [IntPtr]::Zero) { throw "Fixture $state has no native window" }
        $status = Read-Text ([DesktopProbe]::GetDlgItem($window, 117))
        $expected = switch ($state) { empty {'No input endpoints'} configured {'Ready'} active {'synthetic fixture'} recovery {'unavailable'} }
        if (!$status.Contains($expected)) { throw "Incorrect $state status: $status" }
        $routeEnabled = [DesktopProbe]::IsWindowEnabled([DesktopProbe]::GetDlgItem($window, 101))
        if ($routeEnabled -eq ($state -eq 'active')) { throw 'Route enablement contradicts processing state' }
        $rect = [DesktopProbe+RECT]::new()
        [void][DesktopProbe]::GetWindowRect($window, [ref]$rect)
        $bitmap = [Drawing.Bitmap]::new($rect.R-$rect.L, $rect.B-$rect.T)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $dc = $graphics.GetHdc()
        try { if (![DesktopProbe]::PrintWindow($window, $dc, 2)) { throw "PrintWindow failed: $state" } }
        finally { $graphics.ReleaseHdc($dc) }
        $bitmap.Save((Join-Path $captures "$state.png"), [Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose(); $bitmap.Dispose()
        # WM_COMMAND for the real Quit control; don't kill the tested process.
        [void][DesktopProbe]::SendMessage($window, 0x111, [IntPtr]112, [IntPtr]::Zero)
        if (!$process.WaitForExit(5000) -or $process.ExitCode -ne 0) { throw 'Quit failed' }
        Write-Host "Native $state fixture: status/control assertions and capture passed"
    } finally {
        if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
        $process.Dispose()
    }
}
