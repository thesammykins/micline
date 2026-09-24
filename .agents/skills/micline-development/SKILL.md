---
name: micline-development
description: Build, test, debug and release MicLine locally. Use when changing this repository's native macOS UI, microphone graph, Audio Unit hosting or GitHub release tooling.
---

# MicLine development

Run commands from the repository root. Read [AGENTS.md](../../../AGENTS.md)
for the audio invariants and task-specific authority. This is a repository-owned
skill maintained alongside the app; it does not install tools or grant permission
to run live audio, access credentials or publish releases.

## Build and verify

Requires Apple silicon, macOS 27 and Xcode 27 selected with `xcode-select`.
SwiftPM pins Sparkle 2.10.0. Keep bundle ID `com.sammy.micline` stable.

```sh
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
swift test --parallel
MICLINE_SIGNING_CERTIFICATE_SHA1='APPROVED_DEVELOPMENT_CERTIFICATE_SHA1' ./scripts/build.sh
codesign --verify --strict --verbose=2 build/MicLine.app
git diff --check
```

Use an approved Apple Development identity's exact 40-character fingerprint;
`security find-identity -v -p codesigning` lists available identities. The build
never falls back to ad-hoc signing. Launch `build/MicLine.app` through the native
app tool or Finder and inspect the affected UI. macOS 26 cannot provide runtime
coverage for this app. A development build does not enable production updates.

For workflow or shell changes, also run:

```sh
actionlint
shellcheck scripts/build.sh scripts/package-dmg.sh scripts/verify-sparkle-fixture.sh scripts/notarize.sh scripts/publish-release.sh
python3 scripts/test-notarize.py
python3 scripts/test-release-tooling.py
./scripts/verify-sparkle-fixture.sh
```

Reuse checks that reach the changed behavior. Add regression coverage for real
failure modes, not implementation details. UI changes require inspected runtime
states; design exports are references, not runtime proof.

## Find the implementation

| Area | Entry point |
| --- | --- |
| Main window, menu and startup | `Sources/MicLine/MicLineApp.swift` |
| Guided setup and checks | `OnboardingView.swift`, `InputCheckView.swift`, `EffectTrialView.swift` in `Sources/MicLine/` |
| Audio lifecycle, effect editors, cancellation | `Sources/MicLineCore/AudioGraph.swift` |
| Device identity and private aggregate | `Devices.swift`, `PrivateAudioRoute.swift` in `Sources/MicLineCore/` |
| AU discovery and saved chain | `Sources/MicLineCore/Plugins.swift` |
| Realtime meters and bounded buffers | `Sources/AudioSupport/` |
| Offline and explicit live probes | `Sources/MicLineMeasure/` |
| Signing, distribution and CI | `scripts/`, `.github/workflows/` |

SwiftUI/AppKit owns UI. Main-actor AudioGraph owns lifecycle and graph edits;
C11 atomics publish meters. Persist device UIDs, not numeric IDs. No allocation,
logging, locks or filesystem work in realtime callbacks. Stop the engine before
its private aggregate is destroyed and reject stale async generations.

Setup owns its capture sessions. Opening a raw check transfers capture from the
normal route; it does not need a virtual output. Structural effect edits resume
active user processing but must never unmute or resume diagnostic/setup sessions.

## Diagnostics and live checks

Read [diagnostic privacy](../../../docs/PRIVACY.md#developer-reports-and-inventories)
before sharing inventories or launch-probe output; these are not sanitized.

```sh
swift run -c release MicLineMeasure --devices
swift run -c release MicLineMeasure --plugins
swift run -c release MicLineMeasure --offline
```

Live checks need user authority, named endpoints and bounded duration. Use
headphones for physical monitoring. Never save microphone PCM, change system
defaults, hardware volume or shared device sample rates. Quit other MicLine
instances and run one diagnostic at a time.

For an authorized launch probe, launch the built app with
`--probe --virtual-output --report /absolute/path/to/evidence/smoke.json`.
Probe preferences are separate; output is written after completion. If it opens
without a window, choose Window → MicLine. Keep raw evidence in ignored
`evidence/`; commit only reviewed product screenshots to `docs/images/`.

## Releases and references

Read [release procedure](../../../docs/RELEASING.md) before changing signing or
publication. An authorized `vMAJOR.MINOR.PATCH` tag on main triggers Developer ID
signing, app/DMG notarization, GitHub Releases and the signed Sparkle Pages feed.
Secrets belong in GitHub's release-signing environment, never source or logs.
Do not create a release as a side effect of documentation work.

- [Release setup and acceptance](../../../docs/RELEASE-SETUP.md)
- [Verification history](../../../docs/RESULTS.md)
- [Routing design](../../../specs/microphone-processing/TECH.md)
- [Editable design references](../../../design/)
- [Contributing](../../../CONTRIBUTING.md)
