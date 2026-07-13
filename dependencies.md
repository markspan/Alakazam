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

## Build-time only (not needed to run the app)

| Tool | Location | Purpose |
|---|---|---|
| Node.js + npm (`yy-tree`, esbuild) | `src/webtree/` | Regenerates `src/WorkSpaceTree.html` from `src/webtree/src/*` (the workspace tree's JS/CSS). Only needed when editing the tree's look/behaviour -- the built output is committed, so a fresh clone does not need Node.js to run Alakazam. See `src/webtree/README.md`. |

## Follow-up (not done in this pass)

- **Un-track `src/+uiextras/`** and fetch it as an external install, the way
  EEGLAB already is. Deferred because a fresh clone would then need a
  documented setup step; decide the trade-off before doing it.
- **History size:** `.git` is ~214 MB, inflated by the old `eeglabolder/`
  history. Shrinking it needs a history rewrite (`git filter-repo`) and a
  force-push, which is destructive and coordinated separately.
