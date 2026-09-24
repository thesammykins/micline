# MicLine release design candidate

Status: main-window design direction approved by Sammy on 24 September 2026.
The guided sound-check extension in SOUND-CHECK.md is being designed before UI implementation. These are editable mockups, not app
screenshots or evidence of working audio routing.

Open `micline-release-review.fig` and select **Release Review**. It preserves all
five original pages and adds ten review artboards. The approved source FIG in the
parent directory is unchanged. `revise.js` reproduces the new page with native
OpenPencil nodes; it uses the original document and Inter Regular/Bold. Original
project content and inherited icon notices follow the parent package's licenses.

## Decisions shown

- Main window: 720 pt content width. Height is 574 + 56 × visible effect rows,
  up to four visible rows and capped to the available display. The effects list
  scrolls; route, meters and processing controls stay visible. Larger text gets
  a measured native minimum rather than clipping. The artboards show zero, two
  and six effects. Native window controls, switches and keyboard behavior remain.
- Routing: explicit physical input channel/mono selection and output channel pair.
  The example uses a duplex interface and an alternative virtual device. The
  44.1 → 48 kHz example is a target behavior, not demonstrated conversion support.
- Onboarding: an explicit Allow Microphone button invokes the system permission
  prompt during setup. Denial links to privacy settings. Set Up Later always opens
  the stopped app; completing setup does not start capture. Output selection uses
  device capabilities, not the BlackHole name or a virtual-transport-only filter.
  Physical routes retain the device-specific feedback confirmation at Start.
- BlackHole: optional vendor-install guide. Rescan and a user-initiated Core Audio
  restart guide precede the reboot fallback. Never reload audio automatically;
  interrupting all apps' audio needs explicit confirmation. The vendor's installer
  may still require a reboot, so do not promise otherwise.
- Menu bar: route/channel summary, compact output meter, Start/Stop, bypass,
  confirmed monitoring, main window, Settings and Quit. No effect editor or route
  matrix in the popover. Monitor action uses the same confirmation as the main UI.
- Meters: RMS fills a rounded 18 pt track. The filled portion crosses green,
  amber (−18 dBFS), and red (−9 dBFS) zones. Sample peak is white; held peak is
  separately coloured. CLIP means a sample reached 0 dBFS, not merely a red bar.
  Values remain dBFS, not dBTP or analog VU. Preserve existing timing/calibration;
  no decorative animation or interpolation that hides a transient. The subtle
  static highlight has a solid Reduce Transparency fallback. Native material can
  be evaluated after implementation without putting refractive effects over ticks.

## Audio implementation after design approval

1. Persist channel selections alongside device UIDs, with migration for existing
   mono sessions. Expose only channel choices actually available on the device.
2. Generalise aggregate membership/flattened channel maps for duplex and
   multichannel devices. Explicitly silence unrelated channels and verify maps
   after every topology change; do not just remove the mono guard.
3. Negotiate the processing rate through AVAudioEngine/Core Audio. Prove differing
   device rates without writing physical device rates. If the system cannot
   negotiate a safe route, fail with a specific explanation, never a substituted
   device. Validate both 44.1 → 48 and 48 → 44.1 with bounded signal tests.
4. Remove onboarding's virtual-device gate. Keep automatic processing restricted
   to explicitly eligible saved virtual routes; choosing another device is not
   authorization to auto-start physical monitoring.
5. Reuse meaningful isolation, cancellation and meter tests. Add only tests for
   new channel/rate boundaries, then exercise the real approved hardware routes.

## Scope decisions

VST hosting is deferred. The inspected local Clear, SonoBus and Virtuoso effects
have AU counterparts; Elgato's effects are also available as AU bundles. This
metadata inventory does not establish that each plug-in loads or processes safely.
A specifically needed VST-only effect is the trigger to revisit hosting.

Per-app routing stays a stretch goal. Before implementation, compare an embedded
extension with a dockable companion using real app-selection/mixing tasks. This
candidate deliberately contains neither; no routing architecture change is made.

The issue form now asks for AU name/vendor/version, editor and failure phase and
states that compatibility varies. Final Developer ID testing should cover the
locally available effects without promising universal AU compatibility.

## Test cull

Removed the Codable-only drag payload round trip and machine-dependent discovery
smoke test (which required a plug-in name containing “High”). Kept behavior tests
for drag ordering, hostile payloads, channel isolation, meter math, cancellation,
AU state and update authenticity. The subsequent approved implementation passes 34 focused tests; see
`docs/RESULTS.md` for current runtime evidence.

## Reproduce and inspect

From the repository root:

```sh
openpencil eval design/openpencil/micline-refinement-candidate.fig \
  --stdin -o design/openpencil/release-review/micline-release-review.fig \
  --json < design/openpencil/release-review/revise.js
openpencil export design/openpencil/release-review/micline-release-review.fig \
  --page 'Release Review' --font-policy strict \
  -o design/openpencil/release-review/overview.png
```

Headless OpenPencil 0.15.1 wrote/reopened this FIG with strict font resolution.
The live MCP bridge subsequently opened the complete sound-check-v2 FIG. Exported mockups
were visually inspected; no runtime layout, animation or audio claim follows.
