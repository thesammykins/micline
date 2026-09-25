# MicLine — Windows 11 x64 test build

This is an early native Swift/WinSDK port. It is not the macOS release and has
no automatic updater, Audio Units, VST hosting, sound isolation or monitoring.

## Install and test

1. Download the `MicLine-Windows-x64` artifact from the successful **Windows
   desktop test build** workflow on `windows/main`. Extract the archive.
2. Check the SHA-256 checksum beside `MicLine-Windows-x64-Setup.exe` and the
   source revision in `BUILD.txt`. This tester installer is **unsigned**. It has
   no publisher reputation; do not disable SmartScreen, antivirus or other system
   protections. If your policy blocks unsigned apps, stop and report the block.
3. Run the installer as your normal user. It installs only MicLine and its runtime
   files under `%LOCALAPPDATA%\Programs\MicLine`. No developer tools are required.
   The portable ZIP is an alternative; keep its runtime DLLs beside the EXE.
4. Install [VB-CABLE](https://vb-audio.com/Cable/) separately if needed, following
   the vendor's administrator/restart instructions and license terms. MicLine
   never installs a driver or changes system default audio devices.
5. Open MicLine. It starts **stopped**. Choose your microphone, its input channel,
   and **CABLE Input (VB-Audio Virtual Cable)** as the virtual output. Renamed or
   other virtual outputs are not supported by this first build.
6. In Windows microphone privacy settings, permit desktop microphone access.
   Press **Start** in MicLine. In your call app, explicitly choose **CABLE Output
   (VB-Audio Virtual Cable)** as the microphone. Speak and check reception.
7. Compare gain and low cut. Bypass disables low cut but retains gain. There is
   no physical monitoring path; do not turn on Windows “Listen to this device”.
8. Press **Pause** and confirm the call app becomes silent and microphone capture
   stops. Closing the window keeps processing running with tray access; **Quit**
   stops and exits. Nothing automatically resumes after relaunch or interruption.

Use a short test call with a trusted participant. Audio never needs to be saved
to disk. This build's latency and sound quality still need real-device testing.

## Report a problem

Include the revision from `BUILD.txt`, Windows version, device model, selected
channel, and exact stopped/error message. Describe whether the meters or call
app received audio. Do not send recordings, private device inventories, settings
files, or unsanitized logs. A screenshot is useful after redacting personal data.

Test unplug/replug and sleep/wake: the route should stop, never select speakers,
and require Rescan/Start. Keyboard-only controls and Narrator need desktop
acceptance testing. Moving between monitors of different DPI may require reopening.

Uninstall through Windows Installed apps. Settings remain at
`%LOCALAPPDATA%\MicLine\settings.json`; remove that file yourself if you want a
fresh setup. VB-CABLE is separate and is not removed by MicLine's uninstaller.

## Build

Use Swift 6.2.3 x64 with Visual Studio 2022 C++ tools and the Windows SDK, in an
x64 developer shell. From this directory:

```powershell
swift build -c release
$bin = swift build -c release --show-bin-path
$test = Start-Process "$bin/MicLine.exe" -ArgumentList '--self-test' -Wait -PassThru
$test.ExitCode # 0 means success; the desktop executable has no console window.
./package.ps1
```

`--self-test` runs offline DSP/settings tests and opens no device. `--fixture`
with `empty`, `configured`, `active`, `recovery`, or `channel-recovery` renders synthetic UI only.
CI fixtures are native-rendering evidence, not a live microphone test.

Packaging requires NSIS, MSVC `dumpbin` and the MSVC x64 redist directory.
Runtime dependencies are inspected recursively, copied app-local, and tested
with the developer PATH removed. Windows CI uses a Server 2022 runner, so a
successful build is not a substitute for Windows 11 desktop acceptance.
