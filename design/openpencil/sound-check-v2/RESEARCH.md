# Guided setup research · 24 September 2026

This is a current-source review, not a claim that every pattern was invented in
2026 or that competitor apps were installed and user-tested. Product manuals,
Apple guidance and the current MicLine app were inspected. Recommendations below
are design judgments; no conversion or usability improvement has been measured.

| Reference | Observed pattern | MicLine decision |
| --- | --- | --- |
| [Apple onboarding guidance](https://developer.apple.com/design/human-interface-guidelines/onboarding) | Short, optional instruction in context, near the action being explained. | A focused task window with one choice; no first-run control inventory. Resume from Help. |
| [TipKit current documentation](https://developer.apple.com/documentation/tipkit/) and [WWDC24](https://developer.apple.com/videos/play/wwdc2024/10070/) | Eligibility, dismissal history and ordered tips; Apple explicitly cautions against whole-app tours using tips. | Dedicated stateful sound check for setup. TipKit only for occasional later feature discovery, with app-local history. No CloudKit dependency. |
| [Krisp noise-cancellation test](https://help.krisp.ai/hc/en-us/articles/4420135589020-Test-Krisp-AI-Noise-Cancellation) | Hear original and processed sound in the actual environment before a call. | A reversible comparison step, with headphone confirmation. Do not copy its recording/report upload path; MicLine retains no microphone PCM on disk. |
| [Krisp setup advice](https://help.krisp.ai/hc/en-us/articles/28473541732636-Best-practices-for-Krisp-AI-Noise-Cancellation) | Source quality and stacked processing matter. | Establish raw mic level before effects. Explain double processing only when relevant, not as first-run homework. |
| [Riverside lobby checks](https://support.riverside.com/hc/en-us/articles/12999448781469-Join-studio-as-a-producer) | Device tests appear beside device selectors; headphone use is explicit. | Check the selected mic locally first. Require a named headphone output before audition, and separate downstream call-app confirmation. |
| [OBS quick start](https://obsproject.com/kb/quick-start-guide) | Repeatable guided configuration tailored to purpose. This is an established, not new, pattern. | A resumable Help → Sound Check with selective rechecking after device changes. Avoid an unnecessary persona questionnaire. |
| [SoundSource AUSoundIsolation guide](https://www.rogueamoeba.com/support/knowledgebase/?showArticle=SoundSource-SoundIsolation) | Apple sound isolation is a hostable AU with voice modes and wet/dry control. | Offer a simple optional voice-cleanup lesson, with advanced AU controls later. Compatibility and latency still require real MicLine validation. |

## Important correction

Earlier notes conflated Apple noise reduction with voice-processing I/O and
system Mic Modes. Apple also supplies the **AUSoundIsolation** effect:
[official AudioToolbox declaration](https://developer.apple.com/documentation/audiotoolbox/kaudiounitsubtype_ausoundisolation).
The local macOS 27 SDK declares subtype `vois`, wet/dry parameter 0 and sound-type
parameter 1. MicLine's real registered-AU browser displayed AUSoundIsolation and
AUDynamicsProcessor during capture. This proves discovery, not latency, audio
quality, routing compatibility or Developer ID loading.

## Chosen direction

Three chapters: Your mic → Your sound → Your apps. Show a single question, one
relevant control, one sentence of coaching and a clear next action. Keep advanced
measurements, troubleshooting alternatives and technical definitions out of the
normal path. A 600-point native setup sheet is distinct from the approved 720-point main
processor; the primary app layout approval remains intact.

A 304-point companion is a real optional player, not a decorative talking head.
It remains beside the task, can collapse, pauses on step changes, and reflows below
on smaller displays. The proposed native version is a child panel tied to the
setup window: no permanent always-on-top overlay or extra Dock item. During a
cross-app setup step, offer an explicit “Keep guide visible” option; otherwise
respect app switching and Stage Manager. The browser prototype models the docked
layout and collapse, not native panel behavior or system picture-in-picture.

More demonstrations should replace prose, not add another information stream.
Default to a poster frame and an obvious Play control. No autoplay beside a live
meter; pause demo playback before listening. Every clip has captions and a short
text equivalent. Reduced Motion uses the poster/text by default, while allowing
an explicit play request. No forced waiting for a clip to finish.

## What still needs a real user check

Ask a first-time user to reach a call-app input meter without terminology coaching.
Observe: finding the physical mic vs virtual output; recognizing raw clipping;
understanding Original/Processed; finding help and skipping effects; recovering
from denied access and a missing driver. Record task errors and observed confusion,
not a fabricated usability score. Verify 1280×800 layouts, larger text, VoiceOver,
keyboard focus, Stage Manager, and dual displays in the native implementation.

## Native MicLine alignment (user correction)

Use the existing app's system typography, semantic colors, native buttons,
compact forms and meter capsule. Remove the bespoke green palette, oversized
headings and decorative chapter treatment from the first web study. The sheet
uses a modest title, progress text, one task, and standard Back/Continue/Set Up
Later actions. Production controls follow the user's accent and appearance.
Native window chrome is provided by macOS, never redrawn from the artboard.
The companion uses an ordinary titled utility panel with close, transport and
caption controls. The concept's main processor stays at its approved width.

Apple references: [sheets](https://developer.apple.com/design/human-interface-guidelines/sheets),
[windows](https://developer.apple.com/design/human-interface-guidelines/windows),
and [offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help).
These pages require JavaScript in the text browser; no unobserved detailed rule
is attributed to them. The implementation also follows the provided native
SwiftUI/window-management guidance and existing repository UI conventions.
