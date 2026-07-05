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
| Ledalab (EDA) | `ledalab/` | _(unversioned)_ | http://www.ledalab.de/ |
| MoBILAB | external EEGLAB plugin | _(unversioned)_ | https://github.com/sccn/mobilab |

`eeglabolder/` was an older bundled EEGLAB copy; it has been removed. Only one
EEGLAB lives on the path at a time.

## Utility toolkits (currently tracked in-repo)

These are vendored into the repository today. They are third-party and should be
treated as read-only. Consider un-tracking them and listing them here as
external installs in a later pass (see "Follow-up" below).

| Toolkit | Location | Purpose | Source |
|---|---|---|---|
| GUI Layout Toolbox / uiextras | `src/+uiextras/`, `uix.*` | Dockable panel layout, jTree | MathWorks / R. Jackey |
| findjobj / uiinspect | `findjobj.m`, `uiinspect.m` | Java handle access (Y. Altman) | https://undocumentedmatlab.com |

The MoBILAB, TMSi, Cortrium, jsonlab, dndcontrol and mlapptools code has been
removed: the app now reads only BrainVision files (via the bva-io EEGLAB
plugin) and previously-saved `.mat` datasets.

## Follow-up (not done in this pass)

- **Un-track `src/+uiextras/`** and fetch it as an external install, the way
  EEGLAB already is. Deferred because a fresh clone would then need a
  documented setup step; decide the trade-off before doing it.
- **History size:** `.git` is ~214 MB, inflated by the old `eeglabolder/`
  history. Shrinking it needs a history rewrite (`git filter-repo`) and a
  force-push, which is destructive and coordinated separately.
