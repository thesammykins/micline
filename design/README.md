# MicLine design source and provenance

Historical SVG/PNG/FIG design drafts were removed as part of the scoped
pre-public cleanup. The application uses real SwiftUI/AppKit controls and system
typography. Mockups are design references, not runtime verification.

## Reference links

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Apple design resources](https://developer.apple.com/design/resources/)
- [Apple Design Resources License](https://developer.apple.com/apple-design-resources-license/)
- [Explore SwiftUI](https://exploreswiftui.com/)

These links identify reference material only. They do not claim permission to
copy or redistribute any resource.

## Flow and native component mapping

1. Menu-bar waveform → quick popover: input/output levels, gain, bypass, Start/Stop, Open MicLine, Quit.
2. Main window → choose input/output → routing validation → explicit Start → microphone permission → load AU chain → processing.
3. Physical-output confirmation prevents accidental feedback. Unsupported split routes explain the default-pair/duplex limitation. Denied permission or device loss stops audio and explains recovery. No automatic fallback to another microphone or speakers.
4. Plugin library → registered AU Add → ordered chain → native Controls or parameter fallback. Reordering/removing stops the graph. VST entries are unvalidated and disabled.
5. Measurement sheet → explicit virtual consumer and physical stimulus selections → test → report; missing prerequisites disable playback. Scope excludes ADC/call buffering and is stated before running.

The live UI maps these to native `MenuBarExtra`, `Window`, `Picker`, `Toggle`, `Slider`, `GroupBox`, `DisclosureGroup`, confirmation dialogs, sheets and an AppKit plugin window. Meter semantics use RMS dBFS and a peak overload color plus accessible values. SwiftUI handles platform control appearance; design mockups do not hard-code Apple's template assets into the app.

Research references: [Apple macOS HIG](https://developer.apple.com/design/human-interface-guidelines/macos), [menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [privacy](https://developer.apple.com/design/human-interface-guidelines/privacy), [color](https://developer.apple.com/design/human-interface-guidelines/color), [Explore SwiftUI](https://exploreswiftui.com/), [native alerts](https://exploreswiftui.com/library/alert). The specialist reviewed Picker/MenuPickerStyle, Toggle, Gauge, sidebar/list styles and toolbar patterns. A popover is justified by the live dual meters and gain; full chain editing remains in the main window.
