# Release assessment — 24 September 2026

**RELEASED: 1.0.0.** The hosted tag workflow passed Developer ID signing,
Apple acceptance of app and DMG, stapling, Gatekeeper, GitHub publication and
Pages deployment. Public download checksum and Sparkle signatures verified.
See [release setup record](RELEASE-SETUP.md) for source and run identity.
An installed 1.0.0 → 1.0.1 update remains the next acceptance exercise.

## Current implementation and evidence

- Setup takes over capture automatically. Opening Check Microphone while the
  saved route is processing starts a raw, input-only check immediately. The live
  check showed changing levels, then stopped automatically with a retained peak.
  Advanced Settings uses the same flow; duplicate setup entry is disabled.

- 34 Swift tests pass on macOS 27 / Xcode 27 / SDK 27. Removed redundant smoke and
  serialization checks; retained channel isolation, cancellation, DSP, hostile
  payload and update-authenticity checks. Replaced a generic AU round trip with
  restoration of the actual Apple setup presets. A preview-persistence regression
  protects the saved session from discarded trials.
- ARM64 Developer ID build, strict signature verification, Apple acceptance,
  staple validation and Gatekeeper acceptance pass.
- Explicit mono input-channel and output-pair selection now use a verified private
  aggregate, including duplex inputs and mismatched nominal rates with drift
  compensation. Static topology tests pass. Real fifine input 1 → BlackHole 16ch
  outputs 1–2 produced nonzero input/output meters at 96 kHz. Real asymmetric-rate,
  alternate channel and downstream-consumer acceptance remain outstanding.
- Input-only raw checks run on fifine input 1 without an output connection, verify
  output I/O is disabled, and stop automatically after five seconds. Native UI
  readback confirmed capture, automatic stop and retained highest-peak reading.
  No microphone PCM was saved. Device/OS processing upstream may still exist.
- Main window is 720 points wide, with bounded height and scrolling effects.
  Rounded colour-zoned meters preserve existing RMS/sample-peak ballistics.
  Native main, microphone check, effect previews and setup output screens were
  inspected. Narrow preview meters use compact ticks to prevent overlap.
- Native setup requests permission explicitly, separates raw level from effects,
  supports optional Apple Sound Isolation and Dynamics Processor trials, and
  requires named physical-output confirmation before audition. Draft graphs do
  not persist. Keep commits only the added effect; Undo leaves the chain alone.
  Both Apple presets load and restore their configured state locally. Physical
  listening quality, CPU and effect latency are not yet measured.
- Ordinary processing cannot start while setup owns audio. Raw checks stop after
  five seconds; preview/output checks stop after thirty. Deadlines cancel with
  the graph and reject stale generations. Independent review found a stale UI
  timeout; it was fixed by moving deadlines into the audio graph.
- The selected virtual-output check starts and stops through the native setup
  flow. Downstream success requires the user’s observation; it is not inferred
  from MicLine’s own meters. No receiving call app was verified in this pass.
- Ten step-specific silent guides total 253,572 bytes. Native AVQueuePlayer
  looping and timed captions accompany the real control recordings; Reduce
  Motion disables autoplay. The full guide sheet and inline introduction were
  inspected in the signed build, including continued playback after a cycle.
- Adding, moving and removing effects now rebuilds and resumes an active user
  session. Live checks exercised those edits with Clear and Apple Hipass.
  Setup/diagnostic sessions never auto-resume; explicit Stop invalidates pending
  restarts. Independent review found and fixed a muted-diagnostic resume case.
- The signed, hardened build loaded the installed Clear AU and started the
  fifine input 1 to BlackHole 16ch outputs 1–2 route at 96 kHz. This is bounded
  compatibility evidence, not a claim about every AU or audible sound quality.
- The supplied FIG is preserved. OpenPencil’s live MCP opened the completed
  29-screen journey/recovery design. Design exports are not runtime evidence.

The first UI-driven routing check exceeded its originally approved five-second
limit when Stop automation failed. MicLine was quit and verified stopped; the
user was informed. Subsequent live checks were expressly authorised and the raw
check was given an automatic graph-owned stop. Do not cite that first attempt as
a successful bounded test.

## Release tooling

The two-release Sparkle fixture verifies full archives, signed deltas, delta
reconstruction, preservation of previous release URLs and rejection of tampering
or wrong keys. Six notarization and two release-boundary tests pass. The tag
workflow signs, notarizes and publishes release assets, then deploys Pages.
Published-release retries preserve immutable downloads and restore the latest
verified feed. The 1.0.0 hosted run and public feed deployment passed.

The repository is public; dedicated Developer ID, Notary and Sparkle credentials
are provisioned in GitHub's release-signing environment. There is no manual
reviewer gate, following the requested tag-only release process.

VST hosting is deferred: the inspected local effects have Audio Unit counterparts.
Per-app routing is a design-led stretch goal, outside this release. BlackHole
remains an optional external installation; alternatives can be selected. Guidance
covers rescan and the vendor’s optional audio-service restart, with interruption
and administrator warnings. Third-party AU support is not universal; the issue
form requests exact plugin/version/architecture and reproduction details. The installed Clear AU was exercised in the final hardened build.

Raw logs, complete window captures and capture timing are local and ignored under
`evidence/onboarding-v2/` and `evidence/release-2026-09-24/`.

# Earlier verification — 22 September 2026

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

## Post-release documentation capture finding

On 24 September 2026, a local development build using the 1.0.0 source reported
“The microphone engine stopped during configuration” when opening a raw check
after starting/stopping a route and removing a temporary Apple dynamics effect.
One retry also failed. Earlier takeover checks passed. This is a candidate for
1.0.1 investigation, not a confirmed diagnosis or a fixed issue. No runtime code
was changed in the README cleanup.
