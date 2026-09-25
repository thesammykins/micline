# Windows port progress

Approved scope: PRODUCT.md and TECH.md, with Swift/WinSDK fallback authorized.
Branch: `windows/main`. macOS `main` contains only the common orb setup change.
User authorized pushes, Windows CI builds and tester artifacts, not releases.

## Milestones and evidence

1. Build foundation: official Swift 6.2.3 / Windows x64 CI committed; first run
   pending. Orb setup is published on `main`, cold/warm checks passed.
2. Independent implementation: Windows WASAPI/DSP C ABI and Swift native frontend
   share `Windows/Sources/WindowsAudio/include/WindowsAudio.h` as the contract.
   UI owns state/persistence/tray, audio owns COM/session/clock/buffer lifetimes.
3. Integration: build native executable, run offline DSP tests, package runtime
   dependencies and per-user installer. Capture and inspect native UI states.
4. Handoff: exact artifact checksum, install instructions and desktop audio checks.
   Live mic-to-call-app acceptance requires the user's Windows desktop.

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
