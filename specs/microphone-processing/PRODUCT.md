# MicLine

## Summary
A native macOS 27 menu-bar microphone processor. This first increment supplies a real Apple Audio Unit processing path and explicit integration boundaries for VST hosting and a virtual microphone driver.

## Visual references
The supplied macOS 27 Figma community library, Apple Human Interface Guidelines, and Explore SwiftUI. The user-provided local `.fig` was imported into OpenPencil. Keep original product designs and provenance, not a redistributed standalone Apple library.

## Behavior
1. Launch installs a persistent menu-bar control and presents the main window without restoring a closed scene. Open MicLine reopens the processing window. Closing the window does not quit. Two independent default-off options appear in onboarding and Settings: launch at login (SMAppService) and start processing when opening MicLine. Automatic processing uses only the saved virtual-output route after setup is complete; missing devices or denied access leave audio stopped. It never restores physical monitoring. Microphone audio is not recorded to disk.
2. Enumerate microphone inputs and output devices. Persist stable device identities, never transient device numbers. Do not change system defaults.
3. Start requests microphone access only when needed. Denied access explains how to grant permission. No audio is recorded to disk during ordinary operation.
4. Output must be deliberately selected. Supported routes are the current system default pair, one identical duplex device, or an input-only mono physical microphone and stereo virtual output at the same nominal rate. The restricted split route uses a process-private aggregate with verified membership, microphone channel selection and clock drift compensation. Other split routes are blocked. BlackHole is separately installed with user approval, never bundled/installed by MicLine; consumers select BlackHole, not a new MicLine device. Physical output carries an explicit feedback warning and confirmation.
5. Show live input/output RMS dBFS meters and peak overload indication. A stopped graph shows no live level. Input gain, high-pass filtering, and bypass have audible effects; bypass retains input gain but bypasses effects.
6. Users add, remove, reorder, bypass, and configure compatible Audio Units. Native editor is preferred; generic parameter controls are the fallback. Editing graph structure stops processing until Start is pressed again.
7. List VST2/VST3 filesystem candidates without executing them, clearly identified as unvalidated and unhostable. No fake effect is inserted.
8. Save device choices, gain, high-pass settings, ordered effect selection, and bounded AU parameter state on Stop/quit. An installed AUHipass state round trip is verified; third-party state compatibility is untested.
9. Device removal or engine reconfiguration stops processing and explains the interruption. No automatic fallback to speakers or an unintended microphone.
10. Plugin loading failure does not start a partially configured graph. Loading is serialized. A stopped or changed graph cannot be restarted by a stale asynchronous load.
11. Native controls support keyboard navigation, semantic labels, dynamic system appearance, and accessible level values.
12. No unmeasured latency promise. Report DSP-only execution separately from experimental timestamp-aligned waveform lag. Reject ambiguous correlations rather than presenting them as delivery latency. Callback-arrival and external call-app end-to-end latency remain unmeasured; a zero signal-alignment lag is not zero live latency. A digital-marker control reports detection threshold and raw best correlation, not categorical absence of leakage.
13. Main window focuses on route, meters, gain/low cut and compact ordered effects. Add Effect is a searchable AU sheet; diagnostics and unsupported-format information live in a native Settings window. No decorative sidebar or privacy slogan in the main workflow.
14. Dock visibility is persistent and controls native regular/accessory activation policy. Hidden Dock means absent from Command-Tab, but menu-bar access remains. Closing the last window does not quit; Quit stops and saves.
15. Optional monitoring duplicates the processed stereo mix to a selected physical stereo output at the same sample rate while preserving virtual output. Each enable requires a named-device feedback confirmation. Monitoring follows main gain; the user controls hardware volume. Turning monitoring off or changing its device stops the graph. No monitor enable state persists across launch, route change or interruption.
16. First-run and Audio Setup detect the actual BlackHole endpoint, offer the vendor download link and privacy recovery, and never install drivers or restart services. Follow the package's restart prompt; a CoreAudio reload is not guaranteed to replace it. GPL source and vendor binary licensing remain distinct.
