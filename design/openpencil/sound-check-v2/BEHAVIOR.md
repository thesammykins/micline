# Interaction contract

## Audio and persisted state

The prototype simulates every state. Native implementation must implement these
contracts before any displayed success can be driven by real audio:

- Setup and ordinary processing cannot own audio simultaneously. Entering setup
  while processing asks to stop first; no silent interruption of an active call.
- Permission approval does not start capture. Start Sound Check is explicit;
  ending setup, disconnect, window close or cancellation stops its engine.
- Raw check uses the chosen physical input/channel with no MicLine effects, no
  software trim, no physical or virtual output. Explain that device/OS processing
  may still exist upstream. Do not call it an unprocessed hardware measurement.
- Gain guidance uses sample peaks, not AES17 RMS; roughly −18 to −6 dBFS speaking
  peaks are a starting range. Never score the user's voice, promise “perfect”,
  change hardware gain, or infer speech from level alone. Silence/noise/clipping
  require different messages. Peak observations supplement manual confirmation.
- Effect trials operate on a copy of the chain. Keep commits only that change;
  Undo/Skip/cancel restores the preceding state. No duplicate AU on resume. If
  load or parameter validation fails, retain the prior chain and offer Skip.
- AUSoundIsolation is optional, discovered by Apple's exact component identity.
  Verify the voice-mode values and parameter ranges on the instantiated unit;
  do not hardcode an arbitrary wet/dry target as universally ideal. Measure
  latency and CPU before recommending it for calls. No VoiceProcessingIO switch
  is required solely to discover this AU.
- Compression starts gentle, with no automatic make-up gain chase. Parameter
  choices and gain-reduction display require AU validation, not imaginary meters.
- Audition needs a named physical output and explicit feedback confirmation.
  Skipping audition must not let a later compressor preview bypass that gate.
  Before/after should be level-aware; a louder version is not necessarily better.
  No recorded microphone PCM is saved, uploaded or embedded in demonstrations.
- Downstream check is separate: explicit Start Output Check sends to the selected
  virtual device. A user confirmation represents their observation, not automatic
  proof. Ending setup stops the check. Auto-start remains separate and default off.
- Persist only choices/completed lessons locally. Resume never resumes capture.
  Mic/channel changes invalidate level observations; changing output invalidates
  downstream confirmation. Resume cards name the checkpoint, not a generic 100%.

## Deliberate prototype simplifications

Navigation shows the intended screens, including sample success states, without
measuring or permission requests. Microphone/output selects are synthetic choices,
not persisted hardware settings. Original/Processed changes the visible selection
only; no audio is played. The example Studio Cable is not a real installed-device
claim. A production app must render the actual selected name in the handoff.

The companion has Play/Pause, seek, captions, text steps and collapse. Collapse
pauses video. Changing steps destroys the previous player. Escape collapses it.
The native version needs screen-edge-aware placement, focus return, VoiceOver
announcements on meaningful changes only, and minimum text sizes. No aggressive
spotlight dimming, cursor grabbing, automatic scrolling or timed tip dismissal.

Use a dedicated setup coordinator; use TipKit for later opt-in explanations and
nonobvious affordances, not to implement the complete ordered setup state machine.

## Implemented recordings and limits

Four native-control recordings were captured after implementation and integrated
from `Resources/SetupLessons/`: raw meter/automatic stop, isolation comparison,
compression comparison, and virtual-output handoff/check. Each is silent and
has adjacent equivalent text. They use the real built controls, not the browser
prototype. Isolation/compression recordings demonstrate controls with audio off;
the output clip does not claim reception in a call app.

Welcome, permission and microphone selection currently use text lessons. A fresh
macOS permission prompt was not reset solely to make footage. No target call-app
footage is included without choosing that app and version.

Raw checks automatically stop after five seconds, preserving only a numerical
highest-peak observation in the open view. Effect/output checks stop after thirty
seconds. Timers belong to the graph and are invalidated by stop/device changes.
No preview route or capture resumes from a saved checkpoint.

The source window snapshots are sampled (approximately 6–8 fps averaged over UI
actions, up to 1.33 s gaps). This is adequate for these discrete teaching controls,
not a 30 fps capture or meter-animation performance claim. See the media README
for dimensions, timing and provenance. Playback never starts automatically.

## Small first-user evaluation

Ask a new user to configure a mic and confirm reception in their usual call app.
Do not explain terminology beforehand. Observe wrong-device choices, time spent
looking for gain, whether they distinguish a demo from live signal, whether they
can skip effects, and whether they can resume after denial/disconnect. Verify
keyboard-only use and caption/text equivalence. Keep findings concrete; there is
no evidence yet that this proposal outperforms the old onboarding.
