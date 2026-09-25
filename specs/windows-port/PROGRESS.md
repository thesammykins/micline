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
3. Integration: build native executable, run offline DSP tests, package runtime
   dependencies and per-user installer. Capture and inspect native UI states.
4. Handoff: exact artifact checksum, install instructions and desktop audio checks.
   Live mic-to-call-app acceptance requires the user's Windows desktop.

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
