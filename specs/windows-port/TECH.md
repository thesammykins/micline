# Windows port: build and validation plan

## Context

Implement [PRODUCT.md](PRODUCT.md) on `windows/main`, not macOS `main`. The branch
starts with the common orb-setup commit; subsequent Windows changes stay here.
The repository default branch remains `main`; do not change it or release policy
as a side effect of this port.

The inspected macOS baseline is `9ee2efb835cc2c231f63c6e419f039d4a2a98eb9`:

- `Package.swift` requires macOS 27 and Sparkle 2.10.0.
- `Sources/MicLineCore/Plugins.swift` combines reusable session validation and
  level math with Apple AU discovery/types.
- `MeterReading.swift` combines reusable meter ballistics with Combine display
  bindings. `Sources/AudioSupport` contains C11 atomic meters and bounded capture
  with Apple buffer adapters.
- `AudioGraph.swift`, `Devices.swift`, `PrivateAudioRoute.swift` and
  `SetupEffect.swift` depend on Apple audio APIs. They cannot be translated into
  Windows audio simply by changing imports.

Status: approved first-build scope with Swift/WinSDK fallback. The implementation
uses Swift 6.2.3 and native Win32 controls, plus a C++17 WASAPI/DSP bridge.
Authorized GitHub Actions runs provide Windows Server 2022 build and desktop
fixture checks. No Windows 11 runner is connected; live audio remains unverified.

## Implementation decisions

### 1. Prove the Windows build and deployment path

Use a Windows x64 CI build with the official Swift toolchain, Visual Studio C++
tools and Windows SDK. Pin tool/action revisions and persist dependency locks.
Keep permissions at contents:read; upload workflow artifacts, not GitHub Releases.
Artifacts follow repository access rules and are not inherently private. Exclude
macOS signing/notarization jobs from Windows branch activity.
Never run live microphone probes in CI. Branch pushes, Windows CI and tester
artifacts were authorized; public releases and merging into macOS main were not.

The minimal Swift/WinSDK executable compiled in Windows CI. Swift/WinSDK itself
needs no third-party UI package. The dependency evaluation selected the native
fallback for the first tester build:

- Preferred declarative candidate: SwiftCrossUI v0.9.0, revision
  `f8bdf05729ae1cd1b7f3ec4e57177a6965052146`, WinUIBackend.
- Its current bindings require Windows SDK 17763 and Windows App Runtime
  1.5.240205001-preview1. Do not silently install this old preview on the tester's
  machine or assume a current stable runtime is interchangeable.
- Swift Bundler's researched Windows-capable revision is
  `aaaf4a9a55fa8b509c6599be9c49bac153047dfc`; its older stable release is not the
  Windows deployment baseline. Generic bundles recursively include allowed
  Swift/MSVC DLLs, but do not automatically supply the required WinUI runtime.
- Use native Win32 controls from Swift/WinSDK rather than ship the old preview
  runtime. This retains Swift but sacrifices declarative view reuse. Do not
  change to a C# frontend without discussing the tradeoff.

Approve the Windows concept in the canonical FIG before implementing product UI.
Do not present a browser/design rendering as native Windows validation.

### 2. Extract only reusable logic

`Windows/Package.swift` isolates Windows targets without resolving Sparkle or
Apple frameworks. The Swift frontend preserves the macOS level calibration and
ballistics formula while using Windows-specific settings and endpoint IDs.
There is no AU effect model in this increment and no claim of preset portability.
Avoid restructuring macOS code solely to share these small formulas while the
Windows product differs; shared extraction can follow a second proven consumer.

### 3. Implement the Windows audio route

Keep lifecycle/control state in Swift and realtime processing behind a narrow C
ABI. Use event-driven shared-mode WASAPI with explicitly selected endpoints;
negotiate supported formats without modifying shared hardware rates or volume.
Represent opening/running/paused/failed states explicitly and reject stale opens.

The miniaudio duplex example requires lockstep devices; it does not solve this
route's independent clocks. Use WASAPI directly with 48 kHz float shared-mode
autoconversion, preserving the input channel count and selecting one channel.
Duplicate the processed mono signal into the cable's stereo render stream.
A preallocated 16384-frame FIFO uses linear interpolation with bounded ±1000 ppm
correction and 2048 initial silent frames (about 43 ms of buffering, not a
call-app latency measurement). Stop on invalidation, discontinuity after the
first packet, timeout or sustained buffer faults. No allocation, logging, UI or
filesystem operations belong in the processing loop.

Implement gain and high-pass DSP with explicit channel/format contracts. Preserve
meter calibration and bypass-retains-gain semantics. Device invalidation and
sleep stop capture; recovery does not switch endpoints or restart automatically.
Defer RNNoise, VST3, generic/native plugin editors and monitoring until the
basic route and installer are proven.

### 4. Package for a non-developer desktop

Produce an x64 installer plus source revision, checksum and test instructions. Package
only redistributable dependencies with notices; verify launch without a toolchain
or developer PATH. This repository has no Windows signing workflow; availability
of a suitable identity is unverified. Resolve test-distribution expectations and never disable
SmartScreen or other system protections. No driver is bundled. Per-user install,
uninstall, settings retention and shortcut behavior must be explicit and tested.

## Testing and validation

- Product 1/14: install, launch, uninstall and reinstall on clean Windows 11 x64,
  without developer tools; inspect the exact installer and runtime DLL inventory.
- Product 2/4/7/8/10: unit-test endpoint persistence, malformed settings, pause
  during opening, stale completion, missing device and restart behavior.
- Product 5/6: synthetic asymmetric multichannel inputs prove channel isolation,
  gain, bypass and filter response. Verify meters using independent expected
  values, including silence, clipping and non-finite samples.
- Product 6/8: long-running synthetic clock-skew tests in both directions prove
  bounded queues and useful drift correction, rather than only fixed-rate
  conversion. Inject discontinuities and under/overruns.
- Product 3/7/11: explicit, bounded live mic-to-cable tests on named Windows
  endpoints, followed by reception in a real call app. No saved PCM. Confirm
  pause/quit release microphone capture, and unplug/sleep never select speakers.
- Product 9/12: inspect native empty/configured/active/recovery states; exercise
  tray lifecycle, second launch, keyboard/Narrator and 100–200% display scaling.
- Keep DSP execution, stream timing and call-app delay distinct. Do not publish a
  latency claim based on a loopback correlation or successful CI build.

## Ownership

Swift owns windows, tray actions, settings and user intent. The C ABI owns device
enumeration and the worker lifetime. Stop signals cancellation then joins the
worker before returning, preventing stale startup from surviving pause or quit.
The COM MTA worker releases its sessions before COM teardown. UI polling reads
atomic meters and state; it never receives realtime callbacks.

## Research sources

- [Swift Windows installation](https://www.swift.org/install/windows/)
- [SwiftCrossUI Windows backend](https://github.com/moreSwift/swift-cross-ui/blob/f8bdf05729ae1cd1b7f3ec4e57177a6965052146/Sources/SwiftCrossUI/SwiftCrossUI.docc/Backends/WinUIBackend.md)
- [Swift WinUI runtime prerequisites](https://github.com/moreSwift/swift-winui/blob/c4f1cb75c02f4a4fdefcef2e5c5c4388c7cf9389/README.md)
- [Swift Bundler Windows packaging](https://github.com/moreSwift/swift-bundler/blob/aaaf4a9a55fa8b509c6599be9c49bac153047dfc/Sources/SwiftBundler/Bundler/GenericWindowsBundler.swift)
- [WASAPI](https://learn.microsoft.com/en-us/windows/win32/coreaudio/wasapi)
- [miniaudio duplex timing warning](https://github.com/mackron/miniaudio/blob/master/examples/simple_duplex.c)
- [VB-CABLE installation and endpoints](https://vb-audio.com/Cable/)
