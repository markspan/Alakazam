# Project structure

This map separates **Alakazam's own code** from **vendored third-party
toolkits**. Only the authored code should be edited here; see `dependencies.md`
for the external toolkits.

## Coding standards

New and refactored code follows the MATLAB coding standard at
https://github.com/matlab/rules/blob/main/matlab-coding-standards.md
(lowerCamelCase functions/methods, UpperCamelCase classes/properties,
4-space indents, an H1 line after each declaration, no repeated blocks,
`fullfile`/`fileparts` for paths, `try`/`catch` with `MException`).

Deliberate, documented exception: **`eval` is retained** for the plugin
system. Transformations wrap EEGLAB `pop_*` functions, which return their
"eegh" command history as a code string; that string is stored on the
dataset and re-executed with `eval` to replay the operation headlessly when
a branch is dragged onto another dataset. The strings originate from EEGLAB
and the app itself (not untrusted external input). The transformation
*dispatch* already uses the safer `feval(transformId, EEG)`; only the
history *replay* uses `eval`, and it should stay contained and commented.

## Layout at a glance

The authored code lives under `src/`. Vendored toolkits and shared data-file
resources stay at the repository root. The app resolves two roots at startup:

- **`RootDir`** = the `src/` folder (this file's own location). Holds the
  authored code plus `Transformations/`, `Icons/` and `DefaultWorkSpace.wksp`.
- **`RepoRoot`** = the repository root (parent of `src/`). Holds the vendored
  toolkits (`eeglab/`, `mlapptools/`, `+Tools/`, `+uiextras/`, device SDKs) and
  the shared data-file resources.

## Launching

Run **`startAlakazam`** (function at the repo root): it adds `src/` to the path
and constructs the app; the app then adds the vendored toolkits from `RepoRoot`.
To use the bare `Alakazam` command instead, add `src/` to your MATLAB path once
(via `pathtool` or a `startup.m`).

## Authored code (edit these)

| Path | Role |
|---|---|
| `startAlakazam.m` | Root launcher: adds `src/` to the path, constructs the app. |
| `src/Alakazam.m` | Main application class: lifecycle, tree callbacks, transformation dispatch, persistence. |
| `src/AlakazamPlotter.m` | Renders EEG datasets into docked figures (plotting split out of the main class). |
| `src/MinMaxPyramid.m` | Precomputed min/max pyramid: the decimation engine for fast signal plotting. |
| `src/SignalView.m` | Fast scrolling continuous-signal view (replaces the removed Tools.plotECG). |
| `src/EpochView.m` | Keyboard-driven epoched multichannel view (replaces Tools.plotEpochedTimeMulti). |
| `src/AverageView.m` | Trial-average view with error bands and overlay (replaces Tools.plotEpochedTimeMultiAverage). |
| `src/FourierView.m` | Frequency-domain view with band shading and zoom/pan (replaces Tools.plotFourier). |
| `src/BuildTabGroupAlakazam.m` | Builds the toolstrip; discovers transformations from `src/Transformations/*/*.json`. |
| `src/@WorkSpace/` | Data-browser tree, per-format file loaders, `.wksp` session persistence. |
| `src/@cursor/`, `src/@label/` | Small UI helper classes (plot cursors and labels). |
| `src/Transformations/<Name>/` | Analysis plugins. Each folder: `<Name>.m` (entry), `<Name>.json` (manifest), `<Name>.png` (icon). |
| `src/Transformations/+TransTools/` | Shared helpers for transformations (`CheckOptions`, `CreateFilter`, `SelectWindow`, `progressbar`). |
| `src/Icons/` | Tree/node icons used by the data browser. |
| `src/DefaultWorkSpace.wksp` | Default directory config loaded at startup. |

> Note: the eeglab-core copies have been removed from `+Tools/`; the app now
> calls the installed EEGLAB (`eeg_checkset`, `eeg_emptyset`, `pop_select`,
> `pop_newtimef`, ...) directly, so EEGLAB must be on the MATLAB path at
> runtime. What remains in `+Tools/` is the BrainVision import cluster
> (`pop_loadbv`, `readbvconf`, `parsebvmrk`, `ismatlab`) pending a switch to
> the bva-io plugin, the MoBILAB helpers (`EEG2labeledSignalSet`,
> `dataSourceXDF`) which carry local edits, `filtfilt`, and the authored
> `hEEG`. The authored plotting code lives in `src/` (SignalView, EpochView,
> AverageView, FourierView, MinMaxPyramid).

## Vendored toolkits (do not edit — see dependencies.md)

| Path | Toolkit |
|---|---|
| `eeglab/` | EEGLAB (untracked, obtained externally) |
| `ledalab/` | Ledalab EDA analysis |
| `+uiextras/`, `mlapptools/` | GUI layout / uifigure helpers |
| `findjobj.m`, `findjobj_fast.m`, `uiinspect.m` | Yair Altman Java helpers |
| `copyrights/` | jsonlab, dndcontrol, ECG class, … |
| `+TMSi/`, `+Cortrium/` | Device-vendor SDKs |

## How the pieces connect

```
Alakazam (app)
  ├─ BuildTabGroupAlakazam ──> scans Transformations/*/*.json ──> toolstrip gallery
  ├─ WorkSpace ──> loads raw files into an EEG-struct tree (data browser)
  └─ ActionOnTransformation / Evaluate ──> feval(<transform>, EEG) ──> new tree node + .mat
```

The core data structure throughout is the EEGLAB `EEG` struct, extended with
Alakazam fields (`File`, `id`, `Call`, `params`, `DataType`, `DataFormat`).

## Refactoring status

- **Phase 0** (legibility): removed the stale `eeglabolder/` tree, cleaned
  `.gitignore`, documented the authored/vendored split.
- **Phase 1** (path independence): compute roots from the file location, drop
  `savepath` and the working-directory dependence, resolve resources absolutely.
- **`src/` move**: authored code relocated under `src/`; the app resolves
  `RootDir` (src) and `RepoRoot` (repo root) separately, launches via
  `startAlakazam`.
- **Phase 2** (decompose the main class): plotting split into
  `AlakazamPlotter`; the duplicated persistence block extracted into
  `persistResultNode`; dead code removed; methods and locals renamed to the
  naming standard above; docstrings added throughout.

Next: **Phase 3** (formalise the transformation contract: replace the
`EEG.Call` string-parsing and `eval` replay with a typed `{id, params}`
record) and **Phase 4** (table-drive the `@WorkSpace` loaders).
