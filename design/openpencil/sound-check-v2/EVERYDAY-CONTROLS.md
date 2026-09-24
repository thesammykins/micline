# Everyday controls

Editable source: `micline-sound-check-v2.fig`, page **Everyday · Controls**.
Inspected export: `everyday-controls.png`. Render source: `everyday-controls.jsx`.
Original vector geometry, no Apple kit assets. Uses the existing sound-check
document's charcoal panels, text and level colours. Static design, not runtime proof.
Approved design implemented for 1.1.0; native captures and motion findings are
kept locally under evidence/everyday-controls/.

## Controls and explanation

Implemented iteration: dial mode uses a 56-point control beside the gain value
and mode selector, rather than an extra full-height row. Slider mode expands
below the same value controls. The panel settles with a 0.34-second damped spring
(0.9 damping fraction); Reduce Motion uses a 0.12-second fade. Meter ballistics
are unaffected. A restrained recessed rim supplies the hardware reference without
replacing the native design language. Static FIG states do not verify motion.

- Menu bar: eight equal-height rounded segments, a small microphone icon, fixed
  footprint. Map measured output RMS to the existing dBFS scale; green below
  −18, amber from −18 to −9, red above −9. Inactive segments stay subdued.
  Red is not a clip claim; clipping requires a sample peak at or above 0 dBFS.
  Show clipping and exact readings in the popover. Support light/dark contrast
  with an original-colour image, plus a monochrome preference. Never animate
  made-up activity. Preserve a distinguishable paused/disconnected state.
- Gain: bounded rotary control, vertical drag and keyboard adjustment, no wrap.
  Keep an editable numeric value. A slider is an equally capable alternative;
  both edit the same gain. Explain that software gain affects voice and noise,
  cannot repair clipping at the physical microphone, and is not hardware gain.
- Range preferences: retain −24…+12 dB defaults initially. Validate finite,
  ordered bounds including zero. Reject a new range excluding the current gain
  with an explanation, rather than silently changing sound. Do not expand the
  supported DSP range until gain-stage behavior is verified. Migration must
  preserve existing sessions and all gain entry points must share validation.
- Low cut: explain reduced low-frequency rumble and possible loss of vocal
  warmth. The curve is illustrative, not a measured spectrum. Off/On compares
  this filter only. Listening needs the explicitly confirmed headphone route.
- Effects: sliders icon opens the editor; info opens an anchored explanation.
  Retain accessible names, keyboard access and hover tooltips. Existing effect
  enable/reorder/remove actions remain available, including via a context menu.
  Generic third-party effects get factual chain/bypass help, not invented advice.
- Help opens on click/focus as well as hover. Use an info icon, not an eye that
  implies visibility. Keep explanations brief with an optional deeper lesson.
- Compact mode shows input/output names, both meters and state. An expand action
  returns to controls; it does not rebuild audio. Persist window mode separately.
  Errors remain visible in compact mode; full route names are available in help.

## Processing intent

User request supersedes the old default-off startup preference for this
behavior. Distinguish desired processing from an engine momentarily stopped for
an edit; never use `running` alone as restart intent.

| Situation | Intended behavior |
| --- | --- |
| First launch / no permission or route | Guide setup; no substituted endpoint |
| Setup complete, saved virtual route | Start automatically; explain background capture |
| Ordinary launch | Start configured virtual route; login launch remains separate |
| Raw microphone check | Keep input capture active, transfer session ownership, suspend processed output |
| Complete/cancel check | Restore previous processing intent and route |
| Diagnostics | Own capture temporarily; restore only if intent still requests it |
| Add/reorder/remove effect | Rebuild then resume latest intended chain |
| Device disappears | Wait visibly; recover only the same UID and verified topology |
| Repeated start failure | Bounded retries then actionable recovery, no restart loop |
| Explicit privacy pause | Stop capture and retain pause until explicit resume |
| Sleep/wake | Revalidate route and resume only active intent |
| Physical output | Keep device-specific monitoring confirmation; no automatic launch monitoring |
| Quit | Stop capture; no resurrection |

Show “Processing”, “Checking raw microphone”, “Waiting for microphone”, “Paused”
or a specific error. Remove the prominent routine Start/Stop action. Keep pause
in the menu so capture is always controllable. Bypass is not pause: it keeps gain
and audio flowing. No retry may override privacy pause, setup ownership or Quit.

## Teaching and comparison

Teach physical level first, then low cut/noise reduction if needed, then gentle
compression. Avoid a universal EQ/compressor order: corrective EQ before a
compressor changes its response; EQ after compression shapes the result.
Use the user's live input/output meters and a clearly labelled A/B action, with
headphone monitoring only on request. Do not claim automatic loudness matching:
the current bypass retains gain but plugins can change perceived loudness.
Record any new lesson clips only after approved controls are implemented.

Audio references consulted:
- [Shure livestream settings](https://content.shure.com/story/livestream-audio-guide-shure/page/5)
- [Shure vocal recording and mixing](https://www.shure.com/en-US/insights/how-to-record-and-mix-vocals)
- [Apple effects](https://www.apple.com/by/logic-pro/plugins-and-sounds/)

## Update warning investigation

On 2026-09-24 the running executable was `build/MicLine.app`, version 0.1.0,
with no Sparkle feed/key (intentional development configuration). Installed
`/Applications/MicLine.app` was 1.0.1 with the public feed and Ed25519 public key.
The HTTPS feed returned HTTP 200 and two release items. This verifies hosting
and configuration, not a fresh update installation. Settings copy now explains
development builds; no signing secrets or release configuration changed.

## Verification before shipping

Inspect native colour contrast, actual-size meter, empty/active/paused/recovery
states, compact window and keyboard help. Exercise restart intent across raw
check cancellation, effect edits, device loss, privacy pause and sleep/wake.
Verify gain limits across persistence, direct input, dial and slider. Keep the
existing audio safety boundaries; do not replace them with UI-only tests.

## Follow-up refinements

The same document now includes a light main-window variant and the native
System / Light / Dark setting. Menu routes are device pickers. Familiar actions
use icons with accessible names and hover help. Compact mode uses a native 0.35-second resize anchored at the top edge, with
content fading in place. Reduce Motion skips the window resize animation.
Frame captures exposed and verified the fix for the previous immediate resize.
Onboarding keeps its navigation fixed and crossfades step contents.
