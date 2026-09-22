# MicLine verification — 22 September 2026

## Current checkpoint

**Signed, running AU-processing prototype; not a complete Wave Link replacement.** This section supersedes the archived earlier checkpoint below.

- BlackHole and Audio Units were installed separately for authorized testing. MicLine did not change system audio defaults, and no vendor binaries are in the repository.
- `./scripts/build.sh` builds and verifies the signed app; `swift test --parallel` passes **13/13** tests. Two intentional synchronous scheduling advisories remain.
- `PrivateAudioRoute` now supports an input-only mono physical microphone → stereo virtual output at equal nominal rates. A unique process-private aggregate uses BlackHole as clock main with mic drift correction. Ordered membership, active physical UIDs, owned AudioSubDevice UIDs/drift flags and channel map are verified before start. It establishes mono through AVAudioEngine connections, not direct HAL stream-format writes. The engine stops before aggregate destruction, including cancelled AU loads. Other arbitrary split routes remain blocked.
- Live processing and relevant UI states were exercised; machine-specific measurements, plugin inventory outcomes, and local evidence filenames are withheld. Stopped-editor behavior is not proven reliable for this plugin.
- MicLine still has no VST2/VST3 host; a valid vendor bundle is a prerequisite, not a substitute for implementing one.

### Signal evidence is not delivery latency

The digital-marker control mutes MicLine's own output, sends a deterministic marker only into the virtual device, and compares separate raw-mic/virtual-input captures. Detailed measurement results and raw evidence filenames are withheld. **Not detecting the marker above the configured magnitude threshold is not proof of zero leakage.** No PCM is saved. Broader repeatability remains a risk.

The acoustic loopback measurement results are withheld. This is waveform delivery into the separately captured local virtual input, not an instrumented call app or a measurement of wall-clock delivery latency.

Earlier muted, ambiguous, and DC-dominated runs are **invalid delivery-latency evidence**; they motivated the estimator correction.

The current harness DC-centers samples, rejects separated competing peaks, searches signed ±250 ms and requires 16/20 accepted trials. UI and JSON call this **experimental timestamp-aligned waveform lag**, not microphone/callback/call-app delivery latency. Even zero waveform lag is compatible with nonzero delivery delay because driver timestamps preserve signal position. Callback-entry time instrumentation and an external consumer or physical-loopback measurement remain future work. Offline DSP timings below remain correctly scoped, not end-to-end evidence.

### Independent review and remaining limits

Final bounded independent verdict: **PASS WITH RESIDUAL RISK**, no remaining actionable defect in reviewed scope. Review accepted aggregate membership/clocking, channel mapping and lifecycle/cancellation. Findings corrected: categorical “marker absent” wording; stale docs; and ignored negative correlation. Polarity now participates by magnitude while signed coefficients remain reported. The retained red regression selected the wrong +0.328 sidelobe at lag 337 before the fix; the passing test requires the inverted marker at independently chosen lag 317 with correlation <−0.99. The reviewer inspected final isolation evidence; the coordinator executed/read the final acoustic rerun. No lifetime/concurrency stress, hot-unplug, long-duration drift, hostile-plugin test or external call-app test was performed.

Outstanding: VST hosting; true delivery latency instrumentation; third-party stopped-editor compatibility; long-running realtime/device recovery tests. No near-zero latency or production-ready replacement claim is made.

---

## Archived earlier checkpoint — historical, not current status

**Everything below describes the earlier no-driver snapshot. Its blockers, test count, review verdict and next actions are superseded by the current checkpoint above.** Historical files are retained so failed assumptions and subsequent corrections remain inspectable.

## Outcome

**Running, signed macOS 27 development scaffold; full Wave Link replacement blocked/incomplete.** Actual AU processing/editor APIs, device enumeration, native UI, persistence, offline DSP and repeatable measurement infrastructure are implemented. VST hosting, a published virtual microphone, arbitrary split-device transport and measured microphone-to-call-app latency are not implemented/verified.

## Final environment and checks

- `./scripts/build.sh`: **PASS**, release build and signed `build/MicLine.app`.
- `codesign --verify --strict build/MicLine.app`: **PASS**. The audio-input entitlement and stable designated requirement were verified. Certificate rotation, OS policy changes and user resets can still require approval.
- `swift test`: **10/10 PASS**. Includes meter math, settings bounds/order, VST candidate fixtures, AU/device enumeration, asymmetric correlation at 317 frames, silence rejection, percentile ranks, offline DSP gain, AU parameter-state round trip, shared-HAL routing policy, and bounded interleaved capture/discontinuity detection.
- One compiler advisory remains: synchronous `scheduleBuffer` is intentional because the async overload waits for completion before playback can be started. Not a suppressed failure.

## Real hardware versus fixtures

No virtual endpoint was exposed. VST test directories are deliberately **unvalidated synthetic filesystem candidates**, not plugin-host validation.

The final signed app's probe exercised callback flow and engine execution, **not non-silent microphone/effect behavior**. Detailed device configuration and measurement results are withheld.

[Apple documents](https://support.apple.com/guide/security/hardware-microphone-disconnect-secbbd20b00b/web) that Apple silicon MacBooks physically disconnect their built-in microphone when closed. This limited the archived checkpoint; do not bypass that hardware privacy protection.

Real UI exercised: main window; input/output selectors; gain/bypass updates in the diagnostic graph; native Audio Unit editor; waveform menu-bar icon/popover; Open MicLine; loopback-measurement sheet with disabled measurement and missing-virtual-device explanation. Screenshots were inspected for readable labels, controls and clipping. No permission dialog was accepted by UI automation.

## Measured timing, correctly scoped

Actual AVAudioEngine manual rendering measured **per-block DSP execution milliseconds**, excluding microphone, HAL, driver, scheduling and consumer. The measurement values are withheld. They are not end-to-end latency.

**Consumer-visible end-to-end p50/p95/max: not measured.** There is no virtual endpoint, and the physical microphone was disconnected by the lid. The active harness cannot manufacture a result under these conditions. It captures raw and consumer samples in bounded memory, uses timestamps and waveform correlation over 20 trials, rejects clipped/discontinuous/weak runs, and requires 16 accepted trials. It remains experimental until checked against a real electrical/acoustic reference. It excludes ADC before the raw tap and buffering inside the eventual call app.

Bottlenecks to investigate next: input/output device stream latency and safety offsets, hardware buffering, independent-device clocks/resampling, plugin-declared latency and consumer buffering. The DSP benchmark cannot establish near-zero practical latency.

## Independent review and corrections

Read-only verification initially returned FAIL; all material findings were corrected and rereviewed:

1. Shared AUHAL wrongly received separate input/output IDs. Now reject non-default split pairs before permission/capture; same-device route sets HAL once. Snapshot defaults consistently and recheck after AU loading. Asymmetric route tests pass.
2. Task cancellation could allow capture to begin after a permission/plugin await. Added checks around those awaits and before engine start, plus cancellation teardown for the active harness.
3. VST extension matches looked like validated plugin discovery. Source, UI and tests now explicitly describe unvalidated filesystem candidates.

Final verdict: **PASS WITH RESIDUAL RISK**; focused final route-race correction PASS. Verifier independently ran tests/build/signature checks and inspected atomic callback code; no owned render-path allocation or lock was found. Float/uint32 atomics were lock-free on this arm64 runner. No lifetime/concurrency stress, malicious-plugin crash test or device hot-unplug test was run.

## Acceptance status and remaining work

| Probe | Status |
|---|---|
| Initial state/guidance preserved | PASS |
| Intended SDK build/sign/launch | PASS |
| Native menu/main/editor/measurement UI | PASS for inspected states; dark/high-contrast/accessibility traversal not exhaustively tested |
| Devices, selected route, live signal | PARTIAL: actual callbacks, but non-silent signal blocked by closed lid |
| Plugins | PARTIAL: actual Apple AU instantiate/editor/state; VST host absent, third-party compatibility untested |
| Unit/integration/offline timings | PASS; true end-to-end timing BLOCKED |
| Independent final review | PASS WITH RESIDUAL RISK |

Remaining engineering: VST3 SDK bridge and isolated scanning; lawful VST2 feasibility; dedicated virtual endpoint or approved existing driver; independent I/O clocks and resampling; explicit aggregate channel mapping; audio-thread stress/dropout accounting; plugin crash/hang recovery and dry failover; device-change hardware tests; non-silent capture and consumer-visible latency validation. AUv2 may crash the host; requesting out-of-process instantiation is not a universal isolation guarantee. Graph work currently runs on the main actor, not a dedicated non-realtime executor. Plugin state saves on Stop/quit rather than on every editor gesture.

A concrete test prerequisite is a separately installed [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole), via its official installer or `brew install blackhole-2ch`. Its documentation supports Apple silicon/macOS 10.10+, but macOS 27 behavior must still be tested here. Installation writes a system HAL driver and may require closing audio apps/restarting; it was **not performed**. BlackHole is GPLv3, not MIT; bundling/integrating it into a non-GPL application requires separate licensing analysis or a vendor license. Do not treat external installation approval as permission to bundle it, restart audio services or change system defaults.
