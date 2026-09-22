# MicLine engineering guide

MicLine is a focused native macOS microphone processor, not an app-audio router.
Keep changes small, explicit and idiomatic. Prefer system controls and the existing
graph over frameworks, generic wrappers or hypothetical extension points.

## Architecture

- `Sources/MicLine/`: SwiftUI app, main/menu views, Settings/onboarding, effect
  library and diagnostic launch mode. AppKit handles activation and native editors;
  ServiceManagement handles opt-in login launch.
- `Sources/MicLineCore/AudioGraph.swift`: main-actor graph lifecycle, controls,
  AU state/editor ownership, cancellation and device-change recovery.
- `PrivateAudioRoute.swift`: process-private aggregate, clock/member/channel
  verification. `Devices.swift` enumerates Core Audio devices by stable UID.
- `Plugins.swift`: registered AU discovery, unsupported VST filesystem candidates,
  bounded session persistence. Never load a binary just to discover metadata.
- `Sources/AudioSupport/`: C atomic meters and bounded capture buffers.
- `Latency.swift` / `RouteProbe.swift`: offline/correlated signal diagnostics.
- `Sources/MicLineMeasure/`: explicit command-line measurement tools.
- `Resources/`: bundle metadata, entitlements and original app icon.
- `scripts/`, `.github/workflows/`: local builds, packaging and CI. Read
  `docs/RELEASING.md` before changing signing or release behavior.

## Audio invariants

- No allocation, logging, locks, filesystem or UI work in our C realtime paths.
  UI polling and graph edits belong on the main actor, never audio callbacks.
- Stop the engine before destroying its private aggregate. Keep unpublished
  engine/route state alive across AU awaits; reject stale generation tokens.
- Persist UIDs, never numeric AudioDeviceIDs. Never silently substitute a route,
  change system defaults, physical volume or shared device sample rates.
- Verify aggregate membership, stream order, clock/drift and channel maps before
  starting. AVAudioEngine owns formats: negotiate through connections, not HAL
  stream-format writes. Fail closed on changed topology or unavailable devices.
- Bypass skips effects/EQ but retains gain. Structural effect edits stop audio.
- Automatic processing is a separate, default-off opt-in from login launch.
  Only a saved virtual-output route may auto-start. Physical monitoring requires
  explicit device-specific feedback confirmation; never restore it on launch.
- BlackHole is an external user-installed dependency, never bundled or installed
  by the app. GPL source and vendor binary terms are distinct. No custom driver.
- AUv2 plugins may run in-process; do not claim crash isolation. VST2/VST3 hosting
  is not implemented. Filesystem candidates are not validated plugins.
- Timestamp-aligned waveform lag is not callback delivery or call-app latency.
  Correlation thresholds do not prove zero leakage. Preserve signed polarity
  while detecting either polarity by magnitude.

## UI and product

- Main window: route, levels, gain, compact ordered effects, processing state.
  Settings: onboarding/recovery, startup/Dock preferences, advanced diagnostics.
- Use native SwiftUI controls, semantic colors, system typography, keyboard and
  accessibility labels. Avoid promotional copy, decorative sidebars and generic
  dashboards. “Local processing” belongs in factual privacy information.
- Both Dock policies must retain menu access. Window close does not quit or stop
  processing. Quit must stop and save. Login registration must use SMAppService.
- Match revised `design/` concepts where useful; actual native layout and
  verified behavior take precedence. Never redistribute Apple kit source assets.
- Render and inspect affected states before finishing UI changes; include empty,
  configured, active and recovery states. Do not call a mockup runtime evidence.

## Build, test and release

```sh
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
swift test --parallel
./scripts/build.sh
codesign --verify --strict --verbose=2 build/MicLine.app
open build/MicLine.app
git diff --check
actionlint
```

Requires an actual macOS 27 host and Xcode 27 SDK (Swift 6, Swift 5 language mode).
GitHub's `xcode-27` runner is public preview; do not fall back to macOS 26 and
claim runtime coverage. Live tests require permission and explicit endpoints;
use headphones and bounded probes. Never save microphone PCM to disk. Tests
should challenge channel isolation, cancellation, asymmetric delays and missing
devices rather than mirror implementation. No blanket coverage targets.

Keep app identity `com.sammy.micline` stable. Development signing, Developer ID,
notarization and Git signatures are separate. Never expose/export credentials
into source or logs, weaken Gatekeeper or silently use ad-hoc signing. No ASC
record creation, public release or deployment without explicit authorization.
CI must use pinned actions, minimal permissions and no signing secrets on PRs.

Use focused conventional commits. Unsigned Git commits using Sammy's verified
noreply identity are explicitly approved for this repository; preserve any later
signing configuration. Do not rewrite reviewed history. Raw evidence is local
and ignored (`evidence/`); commit only selected product documentation screenshots
under `docs/images/`, reproducible fixtures and original design assets.
