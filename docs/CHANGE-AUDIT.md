# Release-preparation change audit — 24 September 2026

Changes are grouped for the 1.0.0 release. The original supplied FIG is
preserved; raw diagnostics and complete captures remain ignored in `evidence/`.
`hunk diff` was used for the scoped and complete working-tree review.

## Audio and saved settings

- `Sources/MicLineCore/PrivateAudioRoute.swift`: explicit input/output channel
  maps, duplex/rate handling and aggregate validation.
- `Sources/MicLineCore/AudioGraph.swift`: route lifecycle, input-only check,
  setup ownership, nonpersisting preview graphs and generation-bound deadlines.
- `Sources/MicLineCore/SetupEffect.swift`: exact Apple effect discovery and
  validated, serializable setup presets.
- `Sources/MicLineCore/Devices.swift`: remove obsolete direct-route restriction.
- `Sources/MicLineCore/Plugins.swift`: persist optional channel selections.

## Native interface

- `Sources/MicLine/MicLineApp.swift`: bounded main window, useful menu panel,
  channel controls and entry to microphone calibration.
- `Sources/MicLine/LevelMeterView.swift`: rounded colour zones and compact meters.
- `Sources/MicLine/MonitorView.swift`: capability-based monitoring eligibility.
- `Sources/MicLine/SettingsView.swift`: permission request, optional driver setup,
  repeated guided setup and input-only diagnostic entry.
- `Sources/MicLine/RouteChannelPickers.swift`: actual available mono/pair choices.
- `Sources/MicLine/VirtualDeviceGuide.swift`: external installation, rescan and
  optional manual audio-service restart guidance.
- `Sources/MicLine/OnboardingView.swift`: ordered setup, resume, recovery and
  explicit downstream check, with optional lessons.
- `Sources/MicLine/InputCheckView.swift`: raw microphone level guidance and
  five-second check with a retained numerical peak.
- `Sources/MicLine/EffectTrialView.swift`: temporary Keep/Undo effect trials and
  named headphone confirmation.
- `Sources/MicLine/SetupLessonView.swift`: attached recorded/text lessons and
  native AppKit video playback with pause-on-dismiss.
- `Resources/SetupLessons/`: four silent MP4 demonstrations and capture notes.

## Design references

- `design/openpencil/release-review/`: approved main/menu/meter/driver artboards,
  exports, authoring script, earlier sound-check study and integrity manifest.
- `design/openpencil/sound-check-v2/`: complete 29-screen editable FIG, journey and
  recovery exports, research, behavior contract, state inventory and browser
  prototype/authoring sources. Browser states remain simulated.

## Release and verification

- `.github/workflows/build-signed-artifact.yml`: pinned asc notarization,
  tag-triggered signing, notarization, GitHub Releases and Pages deployment.
- `.github/workflows/validate-release-tooling.yml`: notarization regression gate.
- `scripts/notarize.sh`, `scripts/test-notarize.py`: accepted-result/log checking
  and six credential-free failure-path tests.
- `scripts/verify-sparkle-fixture.sh`: deterministic signed delta application and
  tamper/wrong-key rejection.
- `scripts/build.sh`: bundle local recorded setup lessons before signing.
- `Tests/MicLineCoreTests/CoreTests.swift`: meaningful route, preset restoration
  and discarded-preview persistence regressions; redundant smoke test removed.
- `Tests/MicLineUITests/EffectReorderingTests.swift`: redundant encoding round-trip
  removed, with behavioral drag-order coverage retained.
- `.github/ISSUE_TEMPLATE/bug_report.yml`: precise third-party AU compatibility
  reporting without claiming all Audio Units work.
- `docs/RELEASING.md`, `docs/RELEASE-SETUP.md`, `docs/RESULTS.md`: release procedure,
  automated release procedure, credential status and bounded evidence.

## Latest revision

- `AGENTS.md`: active user sessions resume after structural effect edits.
- `AudioGraph.swift`, `EffectsView.swift`, `MicLineApp.swift`: guarded automatic
  rebuild/resume, loading controls and explanatory copy.
- `OnboardingView.swift`, `SetupLessonView.swift`, `Resources/SetupLessons/`:
  ten compressed chapters, retained looping player, timed captions, full guide
  sheet, inline intro/completion lessons, Back navigation and specific copy.
- `DiagnosticsView.swift`, `MeasurementView.swift`, `SettingsView.swift`: copy cleanup.
- `scripts/publish-release.sh`, `scripts/prepare-release-feed.py`,
  `scripts/release-version.py`, `scripts/test-release-tooling.py`: immutable
  release publication, previous-feed preservation, version ordering and tests.
- `scripts/package-dmg.sh`, `scripts/build.sh`, release workflow: new exact
  Developer ID certificate pins. Public Sparkle trust root documented.

External changes: repository made public after a redacted history scan; Pages
configured for Actions; four environment secrets and five public variables
configured. Dedicated Developer ID and Notary credentials created with explicit
approval. Private material remains outside source. No existing credentials
revoked. Apple accepted the local app at this preparation stage; publication
is recorded below.
Stage Manager restored on after recordings; MicLine left stopped with Clear and
saved route/settings preserved. Hunk reviewed the complete working-tree diff.

## 1.0.0 setup correction

`AudioGraph.swift` now transfers capture ownership to setup without a manual Stop
gate. `InputCheckView.swift` starts raw capture on entry and restarts it after a
microphone/channel change. Main-window and Advanced Settings checks use this same
flow. Settings prevents duplicate setup sheets. Live verification from processing
showed a changing raw meter, automatic five-second stop and retained peak; no
output or microphone recording was used.

## Published 1.0.0

Source commit `374170e` is tagged and published. Subsequent documentation records
the final outcome. CI-only corrections: macOS-compatible encrypted PKCS#12
export, DMG primary-signature assessment context, and v* Pages deployment policy.
No published release assets were replaced. Public DMG checksum, notarization,
Gatekeeper and Sparkle archive/feed verification passed. Full inventory above
remains applicable; no private credential material was committed.

## README and repository documentation cleanup

- `README.md`: product overview, current release link, one live screenshot,
  short setup and a single development-skill paragraph; stale release and
  BlackHole-only restrictions removed.
- `.agents/skills/micline-development/SKILL.md`: repository-owned build, signing,
  architecture, diagnostic and release guidance moved out of the README.
- `docs/GETTING-STARTED.md`: detailed user walkthrough and recovery guidance.
- `docs/images/`: two inspected native screenshots and capture provenance.
- `AGENTS.md`, `CONTRIBUTING.md`, `SUPPORT.md`: link to the relevant skill or guide;
  contribution checks now call for meaningful rather than mandatory new tests.
- `docs/RESULTS.md`: records the raw-check configuration failure encountered
  during screenshot capture as an unresolved 1.0.1 investigation candidate.

Local Markdown links and whitespace checks pass. Hunk reviewed this documentation
diff. No app code, release tag, saved route or persistent effect changes are part
of this cleanup.

## 1.0.1 patch

- `AudioGraph.swift`: one bounded restart of a stopped, unchanged raw-input engine.
- `README.md`, `docs/images/`: use Samantha's supplied PNG unchanged; remove the
  older capture with the sharing badge and white corners.
- `CHANGELOG.md`, `docs/releases/`: versioned user-facing release notes.
- `prepare-release-feed.py`, `publish-release.sh`, release workflow and existing
  release-boundary test: require notes and include escaped inline notes in the
  signed Sparkle feed and GitHub release body.
- Release procedure and results updated with evidence and investigation limits.

No generated image was used. Existing 1.0.0 release files remain immutable.

The first 1.0.1 candidate stopped before publication because ElementTree had
renamed Sparkle's namespace prefix. Sparkle's writer subsequently emitted an
undefined prefix. The real 1.0.0 feed reproduced this failure; normalising its
verified local working copy and preserving the sparkle prefix resolves it. The
two-release fixture now includes our first-feed serialization step. Publishing
is explicitly restricted to Actions with GH_TOKEN and SPARKLE_PRIVATE_KEY; no
local Keychain fallback exists.


Final acceptance documentation updates `docs/RELEASE-SETUP.md` and
`docs/RESULTS.md`: successful hosted 1.0.1 release, real installed 1.0.0 upgrade,
final-build microphone check and the limit of delta transport evidence. This
section records the audit in `docs/CHANGE-AUDIT.md`. No additional app changes
or release credential changes accompany these documentation updates.
