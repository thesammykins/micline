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
foreach ($state in 'empty','configured','active','recovery','channel-recovery') {
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
        $expected = switch ($state) { empty {'No input endpoints'} configured {'Ready'} active {'synthetic fixture'} recovery {'unavailable'} channel-recovery {'choose an available input channel'} }
        if (!$status.Contains($expected)) { throw "Incorrect $state status: $status" }
        if ($state -eq 'channel-recovery') {
            $selected = [DesktopProbe]::SendMessage([DesktopProbe]::GetDlgItem($window, 102), 0x147, [IntPtr]::Zero, [IntPtr]::Zero)
            if ($selected.ToInt64() -ne -1) { throw 'Missing saved channel silently selected a fallback' }
        }
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
        if ($state -eq 'active') {
            # A second launch must exit without replacing or stopping this session.
            $second = Start-Process $Exe -ArgumentList '--fixture', 'configured' -PassThru
            if (!$second.WaitForExit(5000) -or $second.ExitCode -ne 0) { throw 'Second-instance handoff failed' }
            if ((Read-Text ([DesktopProbe]::GetDlgItem($window, 111))) -ne 'Pause') { throw 'Second launch changed session state' }
            [void][DesktopProbe]::SendMessage($window, 0x111, [IntPtr]111, [IntPtr]::Zero)
            if ((Read-Text ([DesktopProbe]::GetDlgItem($window, 111))) -ne 'Start') { throw 'Pause did not reset Start' }
            if ((Read-Text ([DesktopProbe]::GetDlgItem($window, 115))) -ne '-90.0 / -90.0 dBFS') { throw 'Pause retained stale meters' }
            if (![DesktopProbe]::IsWindowEnabled([DesktopProbe]::GetDlgItem($window, 101))) { throw 'Pause did not unlock route selection' }
        }
        # WM_COMMAND for the real Quit control; don't kill the tested process.
        [void][DesktopProbe]::SendMessage($window, 0x111, [IntPtr]112, [IntPtr]::Zero)
        if (!$process.WaitForExit(5000) -or $process.ExitCode -ne 0) { throw 'Quit failed' }
        Write-Host "Native $state fixture: status/control assertions and capture passed"
    } finally {
        if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
        $process.Dispose()
    }
}

# Exercise the installer on this disposable CI user. Preserve an unrelated file
# to ensure uninstall never recursively removes user content at the chosen path.
$installDir = Join-Path $env:RUNNER_TEMP 'MicLine-install-test'
New-Item -ItemType Directory -Force $installDir | Out-Null
Set-Content (Join-Path $installDir 'keep.txt') 'unrelated test data'
$setup = Start-Process "$PSScriptRoot/dist/MicLine-Windows-x64-Setup.exe" -ArgumentList '/S', "/D=$installDir" -Wait -PassThru
if ($setup.ExitCode -ne 0) { throw "Installer failed: $($setup.ExitCode)" }
$savedPath = $env:Path
try {
    $env:Path = "$env:WINDIR\System32;$env:WINDIR"
    $check = Start-Process "$installDir/MicLine.exe" -ArgumentList '--self-test' -Wait -PassThru
    if ($check.ExitCode -ne 0) { throw 'Installed app offline self-test failed' }
    $smoke = Start-Process "$installDir/MicLine.exe" -ArgumentList '--smoke' -PassThru
    if (!$smoke.WaitForExit(15000) -or $smoke.ExitCode -ne 0) { throw 'Installed stopped-app smoke test failed' }
} finally { $env:Path = $savedPath }
$uninstall = Start-Process "$installDir/Uninstall.exe" -ArgumentList '/S', "_?=$installDir" -Wait -PassThru
if ($uninstall.ExitCode -ne 0 -or (Test-Path "$installDir/MicLine.exe")) { throw 'Uninstall failed' }
if (!(Test-Path "$installDir/keep.txt")) { throw 'Uninstall deleted unrelated data' }
Write-Host 'Per-user install, stopped launch, offline self-test and safe uninstall passed'
