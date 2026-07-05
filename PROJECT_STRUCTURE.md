# Project structure

This map separates **Alakazam's own code** from **vendored third-party
toolkits**. Only the authored code should be edited here; see `dependencies.md`
for the external toolkits.

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
| `src/Alakazam.m` | Main application class: lifecycle, tree callbacks, plotting, transformation dispatch, persistence. |
| `src/BuildTabGroupAlakazam.m` | Builds the toolstrip; discovers transformations from `src/Transformations/*/*.json`. |
| `src/@WorkSpace/` | Data-browser tree, per-format file loaders, `.wksp` session persistence. |
| `src/@cursor/`, `src/@label/` | Small UI helper classes (plot cursors and labels). |
| `src/Transformations/<Name>/` | Analysis plugins. Each folder: `<Name>.m` (entry), `<Name>.json` (manifest), `<Name>.png` (icon). |
| `src/Transformations/+TransTools/` | Shared helpers for transformations (`CheckOptions`, `CreateFilter`, `SelectWindow`, `progressbar`). |
| `src/Icons/` | Tree/node icons used by the data browser. |
| `src/DefaultWorkSpace.wksp` | Default directory config loaded at startup. |

> Note: `+Tools/` (at the repo root) mixes authored plot helpers (`plot*.m`)
> with files copied from EEGLAB / third parties (`pop_*`, `eeg_*`, `load_xdf`,
> `HRV`, ...). Splitting it is a later task; treat the copied files as vendored.

## Vendored toolkits (do not edit — see dependencies.md)

| Path | Toolkit |
|---|---|
| `eeglab/` | EEGLAB (untracked, obtained externally) |
| `ledalab/` | Ledalab EDA analysis |
| `HRV.m`, `+Tools/HRV.m` | Vollmer HRV toolbox |
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
- **`src/` move** (this change): authored code relocated under `src/`; the app
  now resolves `RootDir` (src) and `RepoRoot` (repo root) separately, and
  launches via `startAlakazam`.

Next: **Phase 2**, decompose the `Alakazam` class (extract the duplicated
node-creation / persistence block shared by `ActionOnTransformation` and
`Evaluate`, and split plotting out of the main class).
