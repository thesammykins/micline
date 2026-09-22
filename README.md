# MicLine

Native SwiftUI menu-bar microphone processor for **macOS 27+**. This is a working development scaffold, **not yet a Wave Link replacement**: Audio Units run, and a restricted private aggregate routes a supported physical microphone to separately installed BlackHole. VST hosting and measured call-app delivery latency remain unfinished. MicLine itself installs no driver and changes no system audio defaults.

## Build and run

Requires Xcode 27 with the macOS 27 SDK selected in `xcode-select`, and a local Apple signing identity. No package dependencies.

```sh
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
./scripts/build.sh
open build/MicLine.app
swift test
```

Open the waveform menu-bar icon, then **Open MicLine**. If macOS restores the app without a main window, use Window → MicLine. Closing the main window leaves the menu-bar app running; use **Quit MicLine** to stop and exit.

The durable bundle ID is `com.sammy.micline`. The build script uses the existing local Apple Development identity and verifies the signature. On another machine, set `MICLINE_SIGNING_IDENTITY` to your certificate name/hash. It deliberately fails rather than falling back to ad-hoc signing. Reuse the same ID and certificate to retain microphone permission; the first transition from an ad-hoc build can require a new approval. No App Store Connect certificate or app record was created. This is local development signing, not a notarized distribution build.

## Use safely

1. Choose the **current system default input/output pair**, the same duplex device for both, or an **input-only mono physical microphone → stereo virtual output** at the same sample rate. The last route uses a temporary process-private aggregate with verified channel membership and clock drift compensation. Other split pairs are rejected; there is no automatic substitution.
2. Prefer **Test microphone with output muted** first. If the built-in MacBook microphone is silent, open the lid: Apple silicon laptops physically disconnect it when closed.
3. Normal Start asks for permission and confirms physical-output monitoring. Use headphones; speakers near the microphone can cause feedback. Start never happens automatically outside explicit `--probe` diagnostics.
4. Adjust gain/low cut. Expand Plugin library to add registered AU effects. Reorder with arrows, toggle effects, and open **Controls** for the native editor or parameter fallback. Structural edits stop processing; press Start again.
5. Bypass skips EQ/effects but retains gain. Stop saves plugin parameter state. Quit also stops and saves. A missing/failed plugin or route change stops safely; crash-proof AUv2 hosting is not provided.

VST2/VST3 records are **unvalidated filesystem candidates**, not confirmed loadable plugins. Their controls and processing are unavailable. AU and VST are different formats.

## Output and latency limitations

BlackHole must be installed separately. Select a supported physical microphone → **BlackHole 2ch** route in MicLine, then **BlackHole 2ch** as the input in the consuming app. This does not publish a device named MicLine. Other hardware and external call-app delivery remain unverified. MicLine does not change system defaults. See [architecture](specs/microphone-processing/TECH.md).

```sh
swift run -c release MicLineMeasure --devices
swift run -c release MicLineMeasure --plugins
swift run -c release MicLineMeasure --offline
open build/MicLine.app --args --probe --report "$PWD/evidence/example-report.json"
open build/MicLine.app --args --probe --virtual-output --report "$PWD/evidence/example-report.json"
open build/MicLine.app --args --probe --virtual-output --isolation --report "$PWD/evidence/example-report.json"
open build/MicLine.app --args --probe --virtual-output --loopback --report "$PWD/evidence/example-report.json"
```

Run one diagnostic at a time, quitting the previous app instance first. Open the main window to start it. Diagnostics use isolated preferences and save metrics, never microphone PCM. The plain probe uses the default route with physical output muted; `--virtual-output` selects an existing virtual output. `--effect` chooses an exact registered AU name. The isolation control sends a digital marker only into BlackHole while muting MicLine's own output, and reports detection thresholds rather than claiming zero leakage.

**Offline timings are DSP execution time, not microphone latency.** **Check loopback signal alignment…** plays 20 quiet speaker bursts and reports experimental timestamp-aligned waveform lag. It rejects discontinuities, clipping, DC and ambiguous peaks, handles either polarity, and requires 16 valid trials. **Audio timestamps are not callback-arrival times, so signal alignment is not delivery latency.** Unmute the selected speaker before testing; MicLine never changes that setting. Call-app end-to-end latency remains unmeasured.

Vendor binaries are not bundled in this repository. Audio Unit compatibility is not universal, and VST hosting remains unavailable.

See [results and remaining work](docs/RESULTS.md) and the [product contract](specs/microphone-processing/PRODUCT.md). Build artifacts are under `build/`.
