# Verification — 22 September 2026

MicLine is a tested development app, not a notarized public release. The private
repository is [thesammykins/micline](https://github.com/thesammykins/micline).
Raw local evidence stays in ignored `evidence/`. Machine-specific screenshots
and detailed setup measurements are excluded from public documentation.
Design mockups are not runtime evidence.

## Productization checks

- Local `swift test --parallel`: **16/16 passed**, including inverted correlation,
  aggregate/monitor topology, invalid monitor rejection, real offline gain and AU
  state round trip. Release build, strict codesign, actionlint, ShellCheck, shell
  syntax and property-list checks passed.
- Actual main, menu, Settings, onboarding, monitor confirmation and missing-device
  preview were captured and inspected. Onboarding's initially compressed scroll
  area was corrected so setup/permission controls remain visible above Continue.
  The missing-device capture is explicitly simulated; BlackHole was not removed.
- Both Dock activation policies were exercised, including persistence across
  relaunch and retained menu access. The original Painter icon was inspected over
  light/dark backgrounds, integrated as ICNS and seen in the running Dock.
- Login registration/unregistration succeeded through SMAppService. A real
  logout/login was not performed. Automatic processing was separately enabled,
  exercised on relaunch, then disabled. It never restores physical monitoring.
  Closing main, quitting and relaunching presents a fresh main scene; command-line
  diagnostic launches may still require Window → MicLine before their task starts.
- The main application was tested with hardened runtime enabled using the existing
  Apple Development identity and **only the audio-input entitlement**. No JIT or
  library-validation exception was added. This is not Developer ID acceptance.

## Audio evidence and limits

Authorized live checks exercised a physical microphone, separately installed
virtual output and Audio Units. No system defaults, shared sample rates or
hardware volume were changed. No vendor binaries are distributed here.

- Live checks covered active/bypass intervals, gain changes and non-silent meters.
- Loopback checks covered bypass and active processing. Timestamp-aligned waveform
  lag is **not wall-clock delivery or call-app end-to-end latency**.
- A consumer marker was not detected in raw microphone capture above the test's
  magnitude threshold. This is not proof of zero leakage; small leaks under real
  microphone noise can go undetected.
- Confirmed monitoring was exercised briefly with attenuated gain and live meters.
  The initial startup stopped on a benign engine
  configuration notification. The correction continues only if the engine is
  running and all aggregate/device/clock/channel-map invariants still pass;
  otherwise it stops. The corrected live UI remained Processing. Turning Monitor
  off stopped both outputs and reset the switch. No independent monitor gain exists.

Earlier rejected muted/DC-dominated/ambiguous runs are not latency evidence.
The signed-polarity regression detects the independently delayed inverted marker
at lag 317; the old implementation selected a false positive sidelobe at lag 337.
Earlier reviews corrected categorical isolation claims and stale routing docs.

## Packaging and release boundary

The artifact-only workflow uses pinned actions, minimal permissions, hosted
`xcode-27`, and explicit main-ref/confirmation/variable gates before credential
import. The `release-signing` environment has a main-branch policy, but no required
reviewer or configured secrets/variables. Enforcement of its protection is not
verified on the current private-repository plan; it must not be treated as a
protected credential boundary. Hosted signing remains unconfigured and fail-closed.
Ordinary CI uses no signing secrets. A real
[macOS 27 CI run](https://github.com/thesammykins/micline/actions/runs/35681462631)
passed for the initial integrated product candidate; later commits require their
own green check before acceptance.

The local inspection DMG contains the signed development app, a designed native
background and Applications link. `hdiutil verify` and app strict signature checks
pass. Timestamped Developer ID signing hung during the local attempt and was
stopped. **No notarization/stapling or signed hosted workflow success is claimed.**
Repository signing secrets are not configured; exact protected setup requirements
are in [RELEASING.md](RELEASING.md). No public release was created.

Independent source/static review found no remaining qualifying defect after the
monitoring fix; final artifact review is tracked with the final candidate.
Residual risk: preview-runner availability, long-duration drift/dropouts, hot-unplug
stress, third-party AU compatibility/crash isolation, login-session behavior and
external call-app delivery. VST2/VST3 hosting and app-based routing remain absent.
