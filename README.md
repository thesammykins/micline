# MicLine

A native macOS 27 microphone processor. Choose your microphone, arrange Audio Unit
effects, and send the filtered signal to BlackHole for your call or recording app.
Gain, low cut, live levels and bypass stay close at hand in a compact window and
native menu-bar menu.

If MicLine is useful to you, you can support its development.

<a href="https://ko-fi.com/sammykins/tip"><img src="docs/images/kofi-support.avif" alt="Support MicLine on Ko-fi" height="32"></a>

<!-- Unmodified official Ko-fi creator-kit button, retrieved 2026-09-22.
Source: https://cdn.prod.website-files.com/5c14e387dab576fe667689cf/670f5a01c01ea9191809398c_support_me_on_kofi_blue.avif
Permission/provenance: https://more.ko-fi.com/brand-assets and https://help.ko-fi.com/hc/en-us/articles/360021025553-How-to-use-Ko-fi-with-Github
SHA-256: 2bdae72d7087b7ab46de81154c12cf5cdf42999155cc7c56592969ea5b8a7083 -->

## Install and use

1. Install **BlackHole 2ch** separately from [Existential Audio](https://existential.audio/blackhole/).
   Close audio apps and follow the installer’s restart prompt. MicLine does not
   include a driver or alter system audio defaults.
2. Build locally below, or use an authorized, signed/notarized DMG. Drag MicLine to
   Applications and open it there. No public release is currently promised.
3. Onboarding checks for BlackHole and offers two independent, default-off options:
   **Launch MicLine at login** and **Start processing when MicLine opens**.
4. Choose a microphone and **BlackHole 2ch** output, add effects, then press Start.
   Allow microphone access when macOS asks. In your other app, choose **BlackHole
   2ch** as its microphone—not the physical mic.
5. Bypass skips low cut/effects but retains gain. Effects run top to bottom; adding,
   removing or reordering stops processing. Effect settings save on Stop or Quit.

**Settings → General** controls Dock visibility and startup. Hiding the Dock icon
also removes MicLine from Command-Tab; the waveform menu-bar item remains. Closing
a window does not stop audio. Quit does. Login launch uses macOS Login Items and
may require approval in System Settings. Install the app in Applications before
enabling it; moving the app can invalidate its registration.

Automatic processing opens the saved microphone only for a saved virtual-output
route. Missing devices, unsupported routes or denied permission leave it stopped;
it never falls back to speakers. Physical monitoring requires explicit confirmation.
Disable automatic processing if you do not want the microphone opened on launch.

### Listen while processing

Choose a physical stereo monitor output in **Settings → Audio Setup**, then use
the ear button beside the main window's output selector and confirm the named
output. Use headphones: speakers can feed back into the mic.
Monitoring sends the same processed mix to BlackHole and your listening device,
follows the main gain, and never changes hardware volume. All three devices must
already use the same sample rate. Turning monitoring off or changing its device
stops both outputs; press Start to resume BlackHole only. Monitoring never resumes
automatically.

## BlackHole setup and recovery

Open **Settings → Audio Setup** to check detection, choose BlackHole, or open
microphone privacy settings. MicLine identifies the registered Core Audio endpoint,
not merely an installer or a file on disk.

- **Missing after installation:** close/reopen MicLine and consumer apps, then
  Check again. Follow the official installer’s reboot instructions if still missing.
- **Can it work without rebooting?** The vendor documents reloads for manual
  install/uninstall paths; this is **not a guaranteed substitute** for its package’s
  restart requirement. Reloading interrupts all audio/calls and may require admin
  access. MicLine never performs it. See [official installation guidance](https://github.com/ExistentialAudio/BlackHole/wiki/Installation).
- **No mic signal:** allow MicLine under System Settings → Privacy & Security →
  Microphone; open the lid when using a MacBook’s built-in mic.
- **No sound in a call:** explicitly choose BlackHole 2ch as that app’s microphone
  and reopen its audio session. BlackHole does not play through speakers by itself.
- **Route rejected:** supported routes are the current system-default pair, one
  duplex device, or an input-only mono physical mic → stereo virtual output at the
  same nominal rate. MicLine creates/verifies a temporary private aggregate for
  the latter. It does not silently change shared device sample rates.

BlackHole remains a separate dependency. Its [source license](https://github.com/ExistentialAudio/BlackHole/blob/master/LICENSE)
is GPLv3; official compiled binaries/installers and branding have separate vendor
terms. No BlackHole binary, installer, source or branding is redistributed here.
Bundling/integration beyond the external device boundary needs licensing review.

## Effects and limits

- **Audio Units:** real registered AU effects, ordered processing and native editor
  support. Third-party AUv2 code can run in-process;
  crashes, malicious plugins and every editor are not isolated or certified.
- **VST2/VST3:** no host yet. Files found on disk are unsupported candidates, not
  validated plugins. MicLine does not load them.
- No per-application audio routing, custom virtual driver or automatic device fallback.
- No claim of zero latency: the diagnostic reports timestamp-aligned waveform lag,
  not callback delivery or call-app end-to-end latency. Correlation below a threshold
  is not proof of zero leakage. Long-duration drift and device recovery need more testing.

## Privacy

See [Privacy and diagnostic reports](docs/PRIVACY.md) for local storage, report
contents, manual sharing and update-network behavior.

## Build and test

Requires Apple silicon, macOS 27 and Xcode 27 selected with `xcode-select`. SwiftPM
pins the official Sparkle 2.10.0 dependency. Keep bundle ID `com.sammy.micline` and
signing identity stable so microphone permission survives rebuilds.

```sh
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
swift test --parallel
./scripts/build.sh
codesign --verify --strict --verbose=2 build/MicLine.app
open build/MicLine.app
```

Set `MICLINE_SIGNING_IDENTITY` to an existing local certificate when needed. The
build must not silently fall back to ad-hoc signing. Developer ID distribution,
notarization, DMG packaging, exact CI secret names and artifact retention are
documented in [Release builds](docs/RELEASING.md). App Store Connect records are not
needed for Developer ID distribution. GitHub uses the `xcode-27` preview runner;
macOS 26 runners cannot execute this minimum-macOS-27 app.

Diagnostics are under **Settings → Advanced**. Explicit launch probes use a separate
preferences domain and store metrics, not microphone recordings. The device/plugin
inventory outputs and launch-probe JSON below are not sanitized; see
[report privacy](docs/PRIVACY.md#developer-reports-and-inventories) before sharing.
Offline output contains synthetic DSP timing metrics:

```sh
swift run -c release MicLineMeasure --devices
swift run -c release MicLineMeasure --plugins
swift run -c release MicLineMeasure --offline
open build/MicLine.app --args --probe --virtual-output --report "$PWD/evidence/smoke.json"
```

Quit previous instances first; run one audio diagnostic at a time. Physical speaker
tests can feed back—use headphones and review the warning before starting.
If a command-line probe opens without a window, choose **Window → MicLine** to
start it. Probe results are written only after the run completes.

## Architecture

SwiftUI/AppKit owns windows and controls. Main-actor `AudioGraph` owns AU lifecycle,
gain/EQ, private aggregate routing and cancellation. Core Audio resolves stable
device UIDs and verifies clocks/channel maps. C11 atomics publish meters to the UI;
bounded capture buffers support diagnostics without writing PCM to disk.

See [AGENTS.md](AGENTS.md) for engineering commands/invariants, [technical spec](specs/microphone-processing/TECH.md)
for routing details, and [verification history](docs/RESULTS.md) for scoped results.
Design provenance is recorded in `design/`; mockups are not runtime evidence.

## License

Copyright 2026 Sammykins. MicLine is licensed under [Apache-2.0](LICENSE).
Contributions use the same license; see [CONTRIBUTING.md](CONTRIBUTING.md).
Third-party materials retain their own terms, listed in [NOTICE](NOTICE).
Report vulnerabilities only through the private route in [SECURITY.md](SECURITY.md).
