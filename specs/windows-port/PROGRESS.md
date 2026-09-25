# Windows port progress

Approved scope: PRODUCT.md and TECH.md, with Swift/WinSDK fallback authorized.
Branch: `windows/main`. macOS `main` contains only the common orb setup change.
User authorized pushes, Windows CI builds and tester artifacts, not releases.

## Milestones and evidence

1. Build foundation: official Swift 6.2.3 / Windows x64 compilation and offline
   self-test passed in run 36125695786. Orb setup is published on `main`;
   cold/warm checks passed (4.3 seconds / 0.37 seconds).
2. Independent implementation: Windows WASAPI/DSP C ABI and Swift native frontend
   share `Windows/Sources/WindowsAudio/include/WindowsAudio.h` as the contract.
   UI owns state/persistence/tray, audio owns COM/session/clock/buffer lifetimes.
3. Integration passed in [Windows CI run 36127879735](https://github.com/thesammykins/micline/actions/runs/36127879735):
   native build, embedded non-elevated manifest check, offline self-test, packaged
   launch without developer PATH, five native fixtures, pause/second-instance
   behavior, per-user install, stopped launch and safe uninstall preserving an
   unrelated file. All five final captures were inspected: readable controls,
   matching system backgrounds, no dense ticks, clipping or overlap.
4. Handoff: unsigned installer and portable ZIP are available in the run's
   `MicLine-Windows-x64` artifact (14-day retention). No public release was made.
   Live mic-to-call-app acceptance requires the user's Windows desktop.

Tested source: [f7b2453](https://github.com/thesammykins/micline/commit/f7b2453cb10280fb601172a62b0370b73452217c).
Downloaded artifact hashes match CI's accompanying checksums:

```text
52d274f09d45674eae521c652fc9889c18f8f89a3ad4e23b020b460730c42f16  MicLine-Windows-x64-Setup.exe
076dc01652d48dc753426a980ad71745af5a416b061f524f3a3a9bec6398c0b2  MicLine-Windows-x64-Portable.zip
```

Remaining desktop acceptance: clean Windows 11 x64 installation, microphone
permission denial, named microphone → VB-CABLE → call-app reception, pause/quit
releasing the real microphone, unplug/replug and sleep recovery, listening
quality, Narrator, keyboard-only use and 100–200% display scaling. The Server
2022 synthetic fixtures do not verify these behaviors or establish latency.

The Windows branch additionally ensures `g++` is present during orb setup.
Two warm setup runs completed in 0.52/0.43 seconds; resume took 0.003 seconds.
Shell syntax/ShellCheck and a fresh minimal-environment login-shell tool lookup
passed. The shared static-check setup is already published on macOS `main`;
the DSP addition stays on `windows/main` and does not change the default branch.

Local portable DSP checks pass with both optimized GCC and Address/Undefined
Behavior Sanitizers. They cover gain retained in bypass, low-cut response,
asymmetric channel selection, silence, non-finite input and ±500 ppm clock skew
over 180 seconds of simulated audio per direction.

The canonical FIG now contains an additive `Windows · Native test build` page.
OpenPencil 0.15.1 read-back preserves all prior macOS node identities, geometry
and text. The configured reference was rendered and inspected. This records the
approved native-control direction, not approval of the exact Windows layout;
that layout and Windows 11 usability remain for tester review.

## Validation contracts

- Offline synthetic tests exercise asymmetric channels, gain retained in bypass,
  high-pass rejection/passband and bounded adaptive clock skew in both directions.
- No startup, fixture or CI path opens microphone capture.
- Selected-device loss/sleep/startup failure stops; never fall back or auto-resume.
- Clean package smoke test removes developer PATH; installer cannot bundle driver
  or disable platform protections. Native fixture rendering is not live-audio proof.

## Current decisions

- Use Swift/WinSDK native controls for the first build to avoid SwiftCrossUI's
  required old WinUI preview runtime. Keep existing compact route/meter/control
  hierarchy; no dashboard or alternative visual design.
- C++ is limited to WASAPI and allocation-free DSP behind a C ABI. Swift owns app
  behavior and native UI. No third-party DSP/UI framework is required initially.
- No new custom driver, AU compatibility, VST host or denoiser in this increment.
