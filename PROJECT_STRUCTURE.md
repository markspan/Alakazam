# Project structure

This map separates **Alakazam's own code** from **vendored third-party
toolkits**. Only the authored code should be edited here; see `dependencies.md`
for the external toolkits.

## Authored code (edit these)

| Path | Role |
|---|---|
| `Alakazam.m` | Main application class: lifecycle, tree callbacks, plotting, transformation dispatch, persistence. |
| `BuildTabGroupAlakazam.m` | Builds the toolstrip; discovers transformations from `Transformations/*/*.json`. |
| `@WorkSpace/` | Data-browser tree, per-format file loaders, `.wksp` session persistence. |
| `@cursor/`, `@label/` | Small UI helper classes (plot cursors and labels). |
| `Transformations/<Name>/` | Analysis plugins. Each folder: `<Name>.m` (entry), `<Name>.json` (manifest), `<Name>.png` (icon). |
| `Transformations/+TransTools/` | Shared helpers for transformations (`CheckOptions`, `CreateFilter`, `SelectWindow`, `progressbar`). |
| `+Tools/plot*.m`, other authored helpers | Plotting and glue helpers written for Alakazam. |
| `DefaultWorkSpace.wksp` | Default directory config loaded at startup. |

> Note: some `+Tools/` files (`pop_*`, `eeg_*`, `load_xdf`, `HRV`, …) are copied
> from EEGLAB / third parties, not authored here. Treat those as vendored.

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

This is the output of **Phase 0** (legibility, no behaviour change):
removed the stale `eeglabolder/` tree, cleaned `.gitignore`, and documented the
authored/vendored split. The physical move of authored code into a `src/` (or
`+alakazam`) package is intentionally deferred until **Phase 1** removes the
current-working-directory / `which('Alakazam')` path dependence, because moving
files first would break startup.
