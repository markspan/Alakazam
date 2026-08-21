# Meshes

`BrainMesh_ICBM152.nv` -- a 3D brain surface mesh (81,924 vertices, 163,840
triangular faces), used by `Brain3D`/`Brain3DView` to project an averaged
ERP's scalp topography onto a rotatable 3D brain instead of a flat 2D
topoplot (see `+TransTools/ReadBrainMeshNV.m` and `+TransTools/
DrawBrainMap.m`).

- **Source:** [BrainNet Viewer](https://www.nitrc.org/projects/bnv/)
  (Xia, Wang & He, 2013), `Data/SurfTemplate/BrainMesh_ICBM152.nv` in its
  GitHub mirror, <https://github.com/mingruixia/BrainNet-Viewer>. Fetched
  2026-08-18.
- **Licence:** GPLv3 (see that repository's own `LICENSE`), the same
  licence as Alakazam itself -- see the repository root `LICENSE`.
- **Format:** plain ASCII. One line with the vertex count, that many lines
  of `x y z` (mm), one line with the face count, that many lines of `i j k`
  (1-based vertex indices). See `ReadBrainMeshNV.m`'s own header comment.
- **Coordinates:** real-world mm, MNI-ish space, verified directly against
  dipfit's `standard_1005.elc` electrode template (which `Brain3D` also
  resolves channel positions from, via `TransTools.TemplateScalpLocs`):
  both are centred on the origin with a comparable head radius (electrodes
  ~85-90mm, enclosing this brain mesh's ~70mm radius), so
  `TransTools.DrawBrainMap` projects one directly onto the other with no
  separate registration/rescaling step. This is a visually convincing,
  roughly anatomically plausible alignment, not a validated coregistration.
