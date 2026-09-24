# External dependencies

Alakazam is a thin application layer over several third-party MATLAB toolkits.
None of these are authored here and **none should be modified in this repo**.
They are expected to be present on the MATLAB path at runtime. The large ones
are deliberately kept out of version control (see `.gitignore`); obtain them
from the sources below and place them where noted.

> Version numbers are recorded where the toolkit states one. Entries marked
> _(unversioned)_ ship no version string; pin them by noting the download date
> or commit when you next update them.

## Core analysis toolkits (kept locally, not tracked)

| Toolkit | Location | Version | Source |
|---|---|---|---|
| EEGLAB | `eeglab/` | current (unpinned) | https://sccn.ucsd.edu/eeglab/ |
| bva-io, ICLabel | EEGLAB plugins (`Documents/MATLAB/eeglab/.../plugins/`) | current (unpinned) | installed automatically by `EEGLabEnvironment.ensure()` if missing |
| FastICA | `Documents/MATLAB/FastICA/` | 2.5 | https://research.ics.aalto.fi/ica/fastica/ -- installed automatically by `EEGLabEnvironment.ensure()`; used by `AutoEyeICA` when present (falls back to `pop_runica`'s own default algorithm otherwise) |
| GEDAI | `Documents/MATLAB/GEDAI/` | 1.7 | https://github.com/neurotuning/GEDAI-master -- **licensed PolyForm Noncommercial 1.0.0** (free for personal/noncommercial research use only, separate licence needed for commercial use); installed lazily on first `AutoGEDAI` run, only after the user explicitly consents to the download (see `AutoGEDAI.m`'s `ensureGEDAI`) |
| FieldTrip | `Documents/MATLAB/fieldtrip/` | 20260812, pinned (see below) | https://www.fieldtriptoolbox.org/ -- **GPLv2/v3**; the full release (~400 MB, not the "lite" build, which strips the template head/source models this needs), installed lazily on first use of `Brain3DView`'s Source-estimate mode, only after the user explicitly consents (see `TransTools.ensureFieldTrip`). Pinned to a specific dated build (deliberately, unlike EEGLAB's own always-latest install) so source-modeling results stay reproducible across a project rather than shifting under a user whenever a new FieldTrip snapshot appears -- update `TransTools.ensureFieldTrip`'s `fieldTripUrl` by hand when a refresh is actually wanted. |
| Unfold | `Documents/MATLAB/unfold/` | 1.3.1, pinned | https://github.com/unfoldtoolbox/unfold -- **GPLv3**; regression-based, overlap-corrected ERPs (rERPs by linear deconvolution, Ehinger & Dimigen 2019; Dimigen & Ehinger 2021, J Vis 21(1):3), installed lazily on first use of the regression-based ERP path, only after the user explicitly consents (see `Unfold.ensure`). The MATLAB toolbox is the maintained, widely used implementation of this method, and the one Alakazam builds against; Unfold.jl is a newer port, less tested and less used, and nothing here depends on it. Pinned to the tag's source archive rather than tracking a branch for reproducibility alone: a version that moves under an analysis changes published numbers without anyone choosing that, and the pin is what makes a result re-runnable on another machine a year later. Upgrading is a deliberate act (change the version here, re-run the suite), not a side effect of when someone installed. The archive deliberately does NOT carry the three git submodules (`lib/gramm`, `lib/eegvis`, `lib/ept_TFCE`): all three are plotting or second-level statistics that Alakazam does not use, and leaving them out is what keeps this a plain archive install with no git requirement. Verified on the archive: `init_unfold` runs and `uf_designmat`/`uf_glmfit` resolve, with one warning about the absent TFCE folder that `Unfold.startToolbox` switches off. |
| EYE-EEG | `Documents/MATLAB/eye-eeg/` | v1.01, pinned | https://github.com/olafdimigen/eye-eeg (Dimigen, Sommer, Hohlfeld, Jacobs & Kliegl, 2011) -- **GPLv3**; the EEGLAB plugin that joins an eye tracker's recording onto the EEG: `parseeyelink` reads an EyeLink `.asc`, `pop_importeyetracker` lines the two clocks up through the triggers both received (a regression over every shared one) and adds the gaze and pupil signals as `EYE` channels, with the tracker's own saccades, fixations and blinks as events. Used by the `EyeTracking` transformation, installed lazily on first use and only after the user explicitly consents (see `EyeEeg.ensure`). Pinned to the tag's source archive for reproducibility; v1.01 specifically carries the fix for EEGLAB 2025.1 and later, whose event handling broke eye-movement detection in 1.0. The archive's `internal/` folder holds the helpers the `pop_` functions call and has to be on the path as well (`EyeEeg.attach`). SR Research's `edf2asc` is NOT a dependency: it is used when it happens to be installed, to convert an `.edf` for which no `.asc` was supplied, and otherwise the `.asc` is asked for. It is part of SR Research's own developer kit and cannot be shipped. |

`eeglabolder/` was an older bundled EEGLAB copy; it has been removed. Only one
EEGLAB lives on the path at a time.

Alakazam is now a dedicated EEG/ERP project (no peripheral-physiology
transformations remain -- see `README.MD`'s Overview). Ledalab (electrodermal
activity) and MoBILAB, listed here in earlier passes of this doc from when
the app had a broader multi-modal-physiology scope, have zero references
anywhere in `src/` and are not actual dependencies of anything currently in
the codebase; dropped from this list.

## Utility toolkits (currently tracked in-repo)

These are vendored into the repository today. They are third-party and should be
treated as read-only. Consider un-tracking them and listing them here as
external installs in a later pass (see "Follow-up" below).

The MoBILAB, TMSi, Cortrium, jsonlab and dndcontrol code has been removed: the
app now reads only BrainVision files (via the bva-io EEGLAB plugin) and
previously-saved `.mat` datasets.

**Removed in the July 2026 audit** (see `PROJECT_STRUCTURE.md`'s
refactoring-status section for the full audit this came from):
- `src/+uiextras/+jTree/` -- the old Java-Swing tree widget `WorkSpaceTree`
  replaced (a uihtml/CEF component, see `src/WorkSpaceTree.m` and
  `src/webtree/`). Nothing in `src/` referenced `uiextras.jTree` anymore
  except comments explaining the replacement.

**Removed**: `mlapptools` (`src/Transformations/IIRFilter/mlapptools.m` +
`WidgetID.m`, its only helper) -- it existed solely so `IIRFilterApp`
could pin its settings dialog on top of Alakazam's own window
(`GetGuiWinToMakeModal`/`setAlwaysOnTop`), by reaching into an
undocumented internal MATLAB figure structure. That structure changed
shape on R2026a ("Unrecognized field name 'CEF'"), which is what caused a
real, reported crash (see `migration.md`). Replaced with `uifigure`'s own
native `WindowStyle = 'alwaysontop'`, a documented, version-stable
property that does the same thing directly -- mlapptools had no other
caller anywhere in `src/`, so nothing else needed to change.

`findjobj.m`, `findjobj_fast.m` and `uiinspect.m` (Y. Altman,
https://undocumentedmatlab.com) were listed here in an earlier pass as
candidates for removal, evidently left over from the old Java-Swing
`ToolGroup` shell -- but they turn out not to exist anywhere in the current
tree at all (`git log --all -- '*findjobj*' '*uiinspect*'` shows they were
already removed, in an earlier "repo legibility cleanup" commit predating
this pass). This listing was itself stale; corrected.

## Data assets (tracked in-repo)

| Asset | Location | Version | Source |
|---|---|---|---|
| BrainMesh_ICBM152.nv | `src/Meshes/` | unversioned, fetched 2026-08-18 | https://github.com/mingruixia/BrainNet-Viewer -- **GPLv3**, same licence as Alakazam itself; see `src/Meshes/README.md` for format/coordinate notes. Used by the `Brain3D` transformation/`Brain3DView` for the rotatable 3D scalp-topography-on-a-brain view. |

## Build-time only (not needed to run the app)

| Tool | Location | Purpose |
|---|---|---|
| Node.js + npm (`yy-tree`, esbuild) | `src/webtree/` | Regenerates `src/WorkSpaceTree.html` from `src/webtree/src/*` (the workspace tree's JS/CSS). Only needed when editing the tree's look/behaviour -- the built output is committed, so a fresh clone does not need Node.js to run Alakazam. See `src/webtree/README.md`. |
| Node.js + npm (`marked`) | `src/help/` | Generates `src/AlakazamHelp.html`, the in-app help page, from `README.MD`. Unlike the tree above, this output is **not** committed: it embeds every screenshot as base64 and runs to about 5 MB. A fresh clone therefore has no help page until it is built; the Help button explains this and offers `README.MD` instead. See `src/help/README.md`. |

## Follow-up (not done in this pass)

- **Un-track `src/+uiextras/`** and fetch it as an external install, the way
  EEGLAB already is. Deferred because a fresh clone would then need a
  documented setup step; decide the trade-off before doing it.
- **History size:** `.git` is ~214 MB, inflated by the old `eeglabolder/`
  history. Shrinking it needs a history rewrite (`git filter-repo`) and a
  force-push, which is destructive and coordinated separately.
