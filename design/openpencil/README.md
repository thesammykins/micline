# MicLine native OpenPencil design

Portable design reference, not a screenshot of the shipping app or runtime proof.
The canonical file is `micline-refinement-candidate.fig`. Keep this directory
together when transferring it; `previews/` contains all five page overviews and
a larger main-screen preview. No plug-ins, audio recordings, or private runtime
evidence are included.

## Open on another Mac

1. Install [OpenPencil](https://openpencil.dev/). This package was checked with
   desktop and CLI version **0.15.1** on 24 September 2026.
2. Choose **File → Open** and select `micline-refinement-candidate.fig`.
3. Select the pages Screens, Components, States and Flows, Installer, and
   Effect Reordering. The content remains editable native nodes, not flattened
   screenshots. Save edits to a new file to preserve the approved original.
4. If text differs, check **Inter Regular and Bold**. The tested CLI reports
   both bundled faces available without substitution. No font binaries are
   included here; obtain Inter from [its official project](https://rsms.me/inter/)
   under the [SIL Open Font License](https://github.com/rsms/inter/blob/master/LICENSE.txt).
   Production MicLine uses macOS system typography; the design uses Inter.

No external image files, component libraries, Apple design kits, or Figma
account are required. BlackHole is mentioned as a product dependency; its driver
is neither included nor needed to open this design.

Verify the package from this directory:

```sh
shasum -a 256 -c SHA256SUMS
```

## Provenance and permissions

This is the later, independently reviewed native-node refinement, **not** one of
the unverified drafts removed by the repository's earlier provenance cleanup.
The repository policy requires original geometry and documented permissions.
MicLine geometry, layout, copy,
components and reordering states were authored for this project with native
OpenPencil primitives. Device and effect examples are synthetic; the diagnostic
examples originated from synthetic offline encoder fixtures. They contain no
personal device identifiers or filesystem paths.

The four-page refinement was approved at SHA-256
`2c571701829eaf9bd6bb1a874d474b84d0eea88e42232055fb9645a622efa8a3`.
The subsequent native grip/removal revision added Effect Reordering and was
independently approved as an implementation direction. The retained source hash,
verified again for this transfer, is:

```text
a766c2f87e66a73bd9f4a7224018b6ad881e14cbc561dd7b20ee002c26e4de29
```

Original project content is Copyright 2026 Sammykins, Apache-2.0; see
`licenses/Apache-2.0.txt`. Embedded icon vectors were inserted through
OpenPencil/Iconify from Lucide, including Feather-derived icons. Their exact
creation-time package versions were not recorded. Preserve the complete
ISC/MIT notices in `licenses/Lucide-Feather-LICENSE.txt`; that notice was retrieved
from Lucide revision `f06ac67e33d645c40b8ce19a0419c85c5d7dd751`. It does not claim
that revision was the original icon source version.

Inspection found no image fills, external-library instances, or bundled font
files. The FIG archive contains its native canvas, minimal thumbnail and document
metadata only. No Apple/community-kit geometry or artwork is included. Names
and trademarks remain their owners' property; the package grants no trademark
rights.

## Persistence and rendering checks

The unchanged canonical file has five visible pages, **1,376 nodes**, **518 TEXT**
nodes, **18 COMPONENT** nodes and **61 VECTOR** nodes. Node totals by page:
Screens 390; Components 74; States and Flows 437; Installer 23; Effect Reordering
452. OpenPencil also exposes an empty internal canvas in its scripting API;
this is not a sixth content page.

A separate OpenPencil CLI process opened and saved the entire document to a
temporary FIG, exited, and another process reopened it. Page/node counts and
the recursive names, types, text, geometry, fonts, fills, strokes and vector-path
properties compared identically. The reserialized file hash differed, so this
package preserves the approved original bytes instead. Desktop opening was
also observed; desktop save was not confirmed because the live-editor bridge
was unavailable. The persistence proof is the separate-process CLI round trip,
not a claimed desktop save/close pass.

Every page was exported with strict font resolution and visually inspected.
Previews were composited onto `#F5F5F5` to make transparent canvas areas readable.
They are generated from the canonical FIG, with no screenshot overlays.

Known retained design limitations: the precise-slider component wraps Min/Max
and clips a helper label; diagnostic mockups intentionally show only part of
their JSON; dragging overlays intentionally overlap. These are not transfer
corruption. The archival design includes historical state/approval annotations
and may differ from later native implementation details. Do not treat its
installer notes or accessibility promises as current runtime acceptance.

## Re-export

With the installed OpenPencil CLI:

```sh
openpencil info micline-refinement-candidate.fig --json
openpencil export micline-refinement-candidate.fig --page Screens --font-policy strict -o screens.png
openpencil export micline-refinement-candidate.fig --node 0:4 --scale 2 --font-policy strict -o main.png
```

Repeat page export with each exact page name above. The approximately 278 KB FIG
and PNG previews fit ordinary Git; this package uses neither Git LFS nor external
asset storage. `SHA256SUMS` covers all package files except itself.
