# MicLine for Windows — first desktop test build

## Summary

Provide an installable Windows 11 x64 microphone processor for initial desktop
testing. Develop on `windows/main`; retain `main` for macOS. Keep Swift wherever
practical without making Apple framework compatibility a prerequisite.

Status: proposed first-build scope, pending approval before product implementation.
This is not a claim that a Windows build or installer currently exists.

## Visual references

Use the existing compact route, meter and everyday-control hierarchy in
`design/openpencil/sound-check-v2/micline-sound-check-v2.fig`. Add Windows concepts
to that same document and present them for approval before implementing the UI.
Use native Windows controls and window conventions, not copied macOS chrome.

## Behavior

1. The first tester build installs on Windows 11 x64 without Xcode, Visual Studio
   or a Swift development toolchain. Any runtime prerequisite is disclosed before
   installation. Installation and uninstallation do not change audio defaults,
   install virtual drivers, or register automatic launch without explicit consent.
2. First launch is stopped. The user chooses a microphone, input channel and
   virtual output before explicitly starting. This initial tester build does not
   automatically start processing on launch, after device recovery or after sleep.
   This is a deliberate first-build limitation relative to macOS.
3. The route uses an independently installed VB-CABLE playback endpoint. Guidance
   explains that the call app must select its paired recording endpoint. Missing
   VB-CABLE offers the official vendor link and a rescan; it does not block opening
   the app or install anything. No endpoint named “MicLine Microphone” is promised.
4. Show device names but retain stable endpoint identities. Never silently select
   a different microphone or output, including after removal or default-device
   changes. Unavailable saved devices remain visibly unavailable.
5. Only an explicitly supported virtual-output route may start in this build.
   Physical speaker/headphone monitoring is deferred rather than enabled through
   a generic output picker that risks feedback.
6. Processing provides input gain (-24 to +12 dB), optional low cut (20–300 Hz;
   default 80 Hz), bypass and input/output RMS and sample-peak meters. Bypass keeps
   gain and bypasses low cut. Channel selection must not leak other input channels.
7. Pause immediately stops microphone capture and output, clears live meters,
   and stays paused until an explicit start. A queued startup or device event must
   not undo pause or quit. Errors never start a partially configured route.
8. Denied desktop microphone access, no available input, invalid channel/format,
   missing virtual output and interrupted devices have actionable stopped states.
   A route change stops processing and requires another explicit start.
9. The notification-area menu exposes Show, Pause and Quit. Closing the window
   leaves an active session running with tray access. Quit stops capture/output,
   saves settings and exits. Reopening or a second launch shows the existing app
   instead of creating another processing session.
10. Persist route identities, channel, gain and low-cut settings. Invalid or
    incompatible settings cannot start capture, select fallback devices or produce
    unbounded gain. Do not import AU state as if it were a Windows effect preset.
11. No microphone PCM is written to disk. Diagnostics are opt-in, bounded and
    separate from processing; no microphone test starts merely by installing,
    launching or running automated smoke checks.
12. Controls support keyboard operation, readable system scaling and Narrator
    labels. Status and errors remain understandable without color or hover.
13. The build clearly identifies itself as an early Windows test version. It does
    not advertise Apple Sound Isolation, Audio Units, VST hosting, automatic
    updates, physical monitoring or measured call-app latency. These are deferred.
14. Test instructions identify the exact build and explain runtime prerequisites,
    VB-CABLE endpoint selection, privacy pause, safe uninstallation and how to
    report failures without sending microphone recordings or unsanitized logs.
