# Implementation and acceptance

## Context
Initial repository: empty, unborn local `master`, no source or project guidance. Toolchain: Xcode 27.0 build 27A5237l, macOS SDK 27.0, Swift 6.4, arm64 macOS 27.0 on Apple M3 Pro. No remote baseline exists.

## Proposed changes
- SwiftPM builds a native SwiftUI executable; the bundle script supplies LSUIElement, durable ID `com.sammy.micline`, microphone usage description and audio-input entitlement. Sign using the existing Apple Development identity, with an environment override and no ad-hoc fallback. No external package dependencies.
- Core Audio enumerates device streams and stable UIDs. AVAudioEngine I/O nodes share one AUHAL on this runner. Use Apple's internal aggregate for the current default pair, set CurrentDevice once for a same-device route, or create a process-private aggregate for an input-only mono physical mic and stereo virtual output at equal nominal rates. Other split pairs are rejected. Never mutate global defaults. Snapshot defaults consistently, recheck after asynchronous loading, and stop on reconfiguration.
- Graph: selected microphone → input meter → gain mixer → high-pass EQ → ordered Apple Audio Units → output meter/main mixer → selected output. Bypass uses effect bypass properties. AVAudioEngine owns conversion; actual device rates/buffers are reported rather than promised.
- C11 atomic meter state is preallocated; taps only traverse float samples and publish atomics. No UI dispatch, locks, filesystem work, or heap allocation in our meter callback. Main-actor polling reads snapshots at 10 Hz. Apple/plugin internals are outside this guarantee.
- Plugin registry metadata is scanned without instantiating VST binaries. VST extension matches are explicitly unvalidated filesystem candidates. AU hosting requests Apple's out-of-process option where supported; AUv2 is still in-process. VST3 requires an Objective-C++/C++ SDK bridge. SDK 3.8 uses MIT, but its advertised tested toolchains stop before macOS/Xcode 27; compatibility has not been tested here, not proven impossible. VST2 SDK is discontinued and cannot simply be downloaded for a new host. Unsupported records remain visible.
- A native app cannot become a Core Audio input merely by creating an AVAudioEngine. BlackHole 2ch 0.7.1 was separately installed on this runner with explicit user approval. MicLine does not install/bundle it or publish a MicLine device. Global input/output defaults were not changed.
- Main actor owns graph mutation. Device/configuration changes stop graph; device lists poll every two seconds. Persist settings in UserDefaults with bounded validation on restore. AU fullStateForDocument saves on Stop/quit, up to 1 MiB per effect; actual AUHipass state round-trip passes. Generation tokens reject stale loads; cancellation checks after permission/plugin awaits prevent delayed starts. There is no plugin timeout/quarantine or hot failover to a dry stream yet.

## Boundaries and concrete next integration

`AudioGraph` owns AU instantiation, restoration, ordering and editor lifecycle. `PluginRecord` is the format boundary. Add a VST3 host implementation at this boundary only after building SDK module/factory loading, IComponent/IAudioProcessor processing and IEditController/IPlugView NSView attachment. VST3 cannot be passed to AVAudioEngine as if it were an Audio Unit; a render adapter and isolated scanner are required. No empty host abstraction is presented as implemented functionality.

`PrivateAudioRoute` creates a unique, nonpersistent process-private aggregate ordered [mic, virtual output], with the virtual device as main clock and mic drift compensation enabled. Read back full ordered membership, active physical UID set, owned AudioSubDevice UID set and drift flags before mapping, then recheck after prepare. Active device IDs are not drift-property owners: query OwnedObjects with the AudioSubDevice class qualifier. The first verified member has exactly one input and no outputs, proving microphone channel offset zero under the SDK stream-order contract. Map Input scope/element 1 to [0]; let AVAudioEngine establish mono client format through connection/tap, never direct HAL stream-format writes. Keep a local strong aggregate reference across AU awaits and stop the engine before destruction on every exit. This route was exercised at 48 kHz/512 frames with built-in mic and BlackHole. Arbitrary other hardware, long-running drift, unplug and restart stress remain unverified. Two independently clocked engines with an ObjC++ SPSC/drift-control bridge remain a possible fallback, not implemented code.

`RouteProbe` captures bounded in-memory raw and consumer waveforms with audio host/sample timestamps; `Capture.c` never writes PCM to disk. Signed ±250 ms correlation DC-centers samples, ranks both polarities by magnitude and rejects competing peaks, clipping, discontinuities and insufficient matches. The metric is experimental timestamp-aligned waveform lag, **not callback delivery latency**. The final unmuted 48 kHz/512-frame run matched 20/20 trials both bypassed and with Elgato Compressor active, with zero timestamp-aligned lag. A zero lag can occur because driver timestamps preserve sample position. Earlier muted and uncentered/ambiguous runs are not valid delivery-latency evidence. A separate digital-marker control mutes MicLine output, writes a marker only to the virtual device, and reports consumer correlation and strongest signed raw correlation against a 0.7 magnitude threshold. It does not prove zero leakage. Future delivery measurement must record callback-entry monotonic times per buffer; true call-app latency additionally requires consumer instrumentation or a physical loopback.

## Authoritative references

- [Apple AUHAL and separate-device constraints](https://developer.apple.com/library/archive/technotes/tn2091/_index.html)
- [Aggregate devices and drift correction](https://support.apple.com/en-us/102171)
- [AUv2/AUv3 host discovery, instantiation and UI](https://developer.apple.com/documentation/audiotoolbox/migrating-your-audio-unit-host-to-the-auv3-api)
- [Native AU editor request](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/requestviewcontroller(completionhandler:))
- [VST3 SDK](https://github.com/steinbergmedia/vst3sdk) and [licensing](https://steinbergmedia.github.io/vst3_dev_portal/pages/VST+3+Licensing/Index.html)
- [VST2 SDK discontinuation](https://forums.steinberg.net/t/vst-2-sdk-discontinued/201774)
- [Apple hardware microphone disconnect](https://support.apple.com/guide/security/hardware-microphone-disconnect-secbbd20b00b/web)

## Acceptance contract
| ID | Observable outcome | Risk / failure oracle | Probe | Artifact | Excluded claim |
|---|---|---|---|---|---|
| A1 | Existing work preserved | Initial files unexpectedly overwritten | git status, directory/guidance read | docs/RESULTS.md | No preexisting source |
| A2 | Architecture and native design | Fake hosting/routing API | source research, OpenPencil export | specs/, design/ | Community library reuse without access/license |
| A3 | macOS 27 build and launch | Wrong SDK or failed process | swift build, bundle launch | scripts/, build/ | Distribution signing |
| A4 | Native menu and principal screens | Only a mockup | screenshot + UI inspection | evidence/ | UI alone proves audio |
| A5 | Hardware graph | Meters disconnected or output feedback | explicit selected-device probe | docs/RESULTS.md | Unrun hardware checks |
| A6 | Plugins | AU/VST confusion, invalid load | registry tests and actual AU editor probe | tests + evidence | VST host implemented |
| A7 | Latency | DSP benchmark sold as end-to-end | robust statistics + capture correlation | scripts/, evidence/ | Unmeasured ADC/consumer latency |
| A8 | Independent review | Self-report only | read-only verifier on final source | docs/RESULTS.md | Review substitutes execution |

## Testing and validation
Use Swift Testing for metadata discovery, persistence bounds, meter math, and latency correlation with asymmetric known delays. Synthetic timing is explicitly a control, not microphone evidence. Run live routing only after explicit endpoint selection and microphone permission; never silently route microphone to speakers. Capture UI and inspect rendered result.

## Experiment preregistration
| Treatment | Control | Held constant | Intended difference | Safety boundary | Interpretation | Unsupported claim |
|---|---|---|---|---|---|---|
| Delayed, attenuated fixture | Original deterministic probe | sample rate, probe samples | Known delay | Offline disposable data | Correlation finds known lag | Real driver latency |
| Actual input→chain→loopback capture | Raw-input reference | rate, selected endpoints, effect chain | Routing/processing delay | Explicit Start and output choice | Only valid if correlated captures exist | Acoustic/ADC time before input reference |

## Parallelization
Coordinator is sole source writer. Read-only local audio investigator and OpenPencil design specialist operate independently. A read-only verifier follows the final build. No workers delegate; no pushes or shared infrastructure changes.
