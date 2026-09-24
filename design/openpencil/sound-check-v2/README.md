# MicLine sound check · experience study 02

Approved design reference for the native setup implementation. Supersedes the
dense two-card concept in `../release-review/`. The browser remains a simulation;
see `docs/RESULTS.md` for implementation and runtime evidence.

## Review

Open `index.html` for the interactive flow, or serve this directory locally:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory design/openpencil/sound-check-v2
```

Then visit http://127.0.0.1:8765/. Begin with “Set up my mic”. The top selector and
bottom recovery controls are **review tools**, not part of the shipping product.
All device names and meter readings in the prototype are synthetic. Buttons model
state transitions; no audio, permission, installation or service action occurs.
Only the explicit official BlackHole link opens an external site.

`micline-sound-check-v2.fig` preserves the original design pages and adds **Sound
Check · Journey** and **Sound Check · Recovery** with 29 editable artboards.
The FIG's video frames are editable schematic posters. Video capture follows implementation. `flow.json` is the readable state/copy inventory; `flow.js`
is its browser representation. `build-fig.js` embeds that same inventory.

## Full journey and branches

Your mic: welcome → permission → microphone/channel → explicit start → raw level.
Your sound: optional sound isolation → named headphone confirmation → comparison
→ optional compression → comparison. Your apps: virtual output → call-app choice
→ explicit output check → user-confirmed reception → stopped main window.

Recovery includes denied permission, no signal, clipping, no hardware gain knob,
unavailable effect, another AU, missing driver, install/rescan/restart guidance,
missing downstream signal, device disconnect, resume and everyday gain help.
Each has an escape to a working stopped app; no BlackHole gate.

Read [RESEARCH.md](RESEARCH.md) for sources and design rationale, and
[BEHAVIOR.md](BEHAVIOR.md) for transition/recording contracts.

## PiP production order

Sammy approved this direction and requested: finish the OpenPencil screens,
implement the main app to spec, record stable controls, then integrate onboarding.
The FIG/browser video surfaces remain storyboards. Preliminary search recordings
were excluded. Four final native-control recordings now live in
`Resources/SetupLessons/`; they were captured after implementation and are
integrated into attached native lesson popovers. See that directory’s README
for capture limits. Native recovery uses concise contextual messages where a
separate full window would add unnecessary navigation.

Original layout/copy/geometry: Apache-2.0 under repository license. No competitor
screenshots, Apple design kit or bundled font. Device names are synthetic.

## Reproduce designs

```sh
openpencil eval design/openpencil/micline-refinement-candidate.fig \
  --stdin -o design/openpencil/sound-check-v2/micline-sound-check-v2.fig \
  --json < design/openpencil/sound-check-v2/build-fig.js
```

App preview and export are design validation only. Audio correctness, native
permission behavior, panel focus and final Developer ID effects remain separate.
