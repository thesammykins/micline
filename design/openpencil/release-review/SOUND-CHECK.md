# Guided sound check

Design extension requested 24 September 2026. The main-window direction is
approved; this addition is a design proposal, not implemented runtime behavior.

## Experience

Use the actual main window as the teaching surface. One anchored coaching card
at a time, with Back, Skip this step and End sound check. Never cover the control
being taught. A compact progress label names the current task rather than showing
a modal checklist. Resume from Help → Sound Check; do not repeat dismissed tips
on each launch. Device changes invalidate the microphone check, not every lesson.

1. **Let MicLine hear you.** Explain the permission before the native request.
   Allow Microphone requests access without starting capture. Denied access gives
   a Settings link and a retry. Set Up Later opens a usable stopped window.
2. **Find your voice.** Choose the physical microphone and channel. An explicit
   Start Sound Check begins input-only metering, with effects bypassed and no
   physical or virtual output. Show Listening and Stop throughout. Ask for a normal
   sentence, then the loudest voice they expect to use. No recording or upload.
3. **Leave room for louder moments.** Highlight raw sample peaks, not RMS, as the
   gain guide. Suggest roughly −18 to −6 dBFS speaking peaks as a starting range,
   not a certification of good sound. A clipped input asks the user to lower the
   microphone/interface gain; software trim cannot undo clipping. If hardware
   gain is unavailable, suggest mic position before software gain. Never write
   system input volume or device controls automatically. Silence, wrong channel,
   unavailable input and sustained noise receive different guidance. No signal
   alone is not proof of a broken microphone. Offer manual Continue at all times.
4. **Keep the voice, soften the room.** Optional noise reduction. Ask the user to
   pause, then speak while comparing processed and bypassed sound. Audition only
   after explicit headphone/output selection and existing feedback confirmation.
   Apple voice processing / system Voice Isolation must be proven on the chosen
   route before offering it. Do not label a noise gate or high-pass filter as
   cancellation. If unavailable, explain and offer a compatible installed AU or
   Skip; never funnel users into an installation or a purchase.
5. **Even out loud and quiet words.** Optional Apple dynamics/compressor lesson.
   Explain what changes before applying a gentle, reversible preset. Preview
   preserves the previous chain/state; Keep commits, Undo restores. Expose actual
   gain reduction only if the chosen AU reports it reliably. Do not infer it from
   input/output meter differences. Compare at similar loudness, then recheck
   output peaks. No automatic make-up gain chasing a loudness target.
6. **Use it in your call.** Select the output device, with optional BlackHole help.
   Explain that the call app must select that virtual microphone. Show the actual
   device name to look for; let the user confirm reception in their target app.
   Completing the guide does not claim that the external app receives audio or
   silently enable automatic processing.

## Coaching and demonstrations

Tooltips answer: what this changes, when to use it, and the next helpful action.
Short hover help remains available; longer cards open by click and keyboard,
with VoiceOver labels, sensible focus return and Escape dismissal. Avoid automatic
focus jumps, timed dismissal, tooltip piles and tips reappearing while typing.

Examples:
- Input: “Your microphone before MicLine’s effects. Red CLIP means the incoming
  signal has already distorted. Lower gain on your microphone or interface.”
- Gain: “Makes the signal entering your effects louder or quieter. It cannot
  repair clipping that happened in the microphone.”
- Compressor: “Turns down louder moments so speech stays more even.”
- Output: “Choose this device as the microphone in your call or recording app.”

An optional “Show me” opens a small picture-in-picture-style demo card inside the
window. Prefer 8–15 second silent, captioned recordings of the final shipped UI,
with Play/Pause, Replay, Close and a static step equivalent. No autoplay, remote
video, screen-recording permission or microphone recording. Reduced Motion shows
still frames. Label demonstrations as examples; never confuse a recorded meter
with the user’s live signal. Record only after implementation is stable; no fake
video or new permission request solely for tutorial charm.

## Acceptance boundaries

First-run state, permission denial, skip/resume, missing driver, disconnected mic,
wrong channel, quiet/noisy/clipped input and keyboard-only navigation must all be
reviewable. Sound check must work without a virtual driver. Closing/ending it
stops its input-only engine. Normal processing and calibration cannot compete for
hardware. Preserve the user's chain until an explicit Keep action.

Apple sources checked:
- https://developer.apple.com/videos/play/wwdc2023/10235/
- https://support.apple.com/guide/mac-help/use-mic-modes-on-your-mac-mchle82b42f0/mac
