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
  authored code plus `Transformations/` and the `+uiextras/` helper package
  (dialog widgets, not the data-browser tree -- see below).
- **`RepoRoot`** = the repository root (parent of `src/`). Holds only the shared
  data-file resources. EEGLAB is not bundled: it is expected on the MATLAB path,
  and `EEGLabEnvironment` offers to download and install it (and the plugins) if
  missing.

## Launching

Run **`startAlakazam`** (function at the repo root): it adds `src/` to the path
and constructs the app; the app then adds its `Transformations/`.
To use the bare `Alakazam` command instead, add `src/` to your MATLAB path once
(via `pathtool` or a `startup.m`).

## Authored code (edit these)

| Path | Role |
|---|---|
| `startAlakazam.m` | Root launcher: adds `src/` to the path, constructs the app. |
| `src/Alakazam.m` | Main application class: lifecycle, tree callbacks, transformation dispatch, persistence. |
| `src/EEGLabEnvironment.m` | Ensures EEGLAB and the required plugins (bva-io, XDF, ICLabel, FastICA) are installed, that EEGLAB has actually been *run* at least once in the current MATLAB session (not just found on the path -- see `ensureEEGLabInitialized`), and warns if the Signal Processing or Statistics and Machine Learning toolboxes are missing; called once at startup. |
| `src/AlakazamPlotter.m` | Renders EEG datasets into tabs of the app's plots tabgroup (plotting split out of the main class). |
| `src/MinMaxPyramid.m` | Precomputed min/max pyramid: the decimation engine for fast signal plotting. |
| `src/SignalView.m` | Fast scrolling continuous-signal view (replaces the removed legacy plotting tool). |
| `src/EpochView.m` | ERP-image view of epoched multichannel data: a time x trial heatmap for the current channel (up/down arrows step it), rows grouped by bin, plus a trial-average trace below -- replaces an earlier overlaid-line-traces plot (which didn't scale past a handful of trials/channels) and its own since-removed "all channels, one trial" mode (replaces Tools.plotEpochedTimeMulti). |
| `src/AverageView.m` | Trial-average view with error bands and overlay (replaces Tools.plotEpochedTimeMultiAverage). |
| `src/FourierView.m` | Keyboard-driven frequency-domain view (one channel's spectrum at a time, band shading, zoom/pan; up/down arrows step the channel, left/right the trial -- same interaction model AverageView uses; replaces Tools.plotFourier). |
| `src/TimeFrequencyView.m` | Grid of per-bin ERSP heatmaps (`TransTools.ComputeErsp`'s precomputed output), one channel at a time; up/down arrows step the channel, an instant re-slice since every channel was computed up front. The app's first multi-tile-grid view. |
| `src/ScalpDistributionView.m` | Grid of per-bin scalp topographies (`TransTools.DrawScalpMap`), scrubbable by a `uislider`; only draws the bins ticked on in a sibling `AverageView` tab, if one is open. Mouse/slider-only, no keyboard navigation. |
| `src/AlakazamRibbon.m` + `src/AlakazamRibbon.html` | uihtml-based control-strip ribbon (Home/Tools/Grand Average); discovers transformations from `src/Transformations/*/*.json`. Hand-written self-contained HTML page, no build step. |
| `src/WorkSpaceTree.m` + `src/WorkSpaceTree.html` | uihtml-based data-browser tree (replaces the old Java-Swing `uiextras.jTree.Tree`). The `.html` is a **built artifact**, assembled from `src/webtree/src/*` by `src/webtree/`'s own npm/esbuild pipeline (see `src/webtree/README.md`) -- edit the source there, not the `.html` directly, then rebuild and re-copy. |
| `src/@WorkSpace/` | Per-format file loaders, `.wksp` session persistence, and construction of the app's **two** `WorkSpaceTree` instances (`Tree` for data & analyses, `GrandAveragesTree` for grand averages -- see `CreateTreeComponent.m`). |
| `src/AlakazamSettings.m` + `src/SettingsDialog.m` | Global settings: `AlakazamSettings` defines the schema (tabs/sections/settings, persisted to `prefdir()/AlakazamSettings.json`); `SettingsDialog` builds the editor UI from that schema. |
| `src/TransformSettings.m` | Per-transformation "last used options", scoped to the *currently open workspace* (unlike `AlakazamSettings`, which is machine-wide) -- `get`/`set` by transform id, with `.wksp` save/load folding the whole store in as one more JSON field (see `WorkSpace.save`/`load`). Wired into `DefineBins`, `ArtefactDetect`, `AutoEyeICA`, `AutoGEDAI`, `Baseline` and `Fourier`. Not wired into `Average`/`ScalpDistribution` (no options at all), `IIRFilter` (its dialog is a binary `.mlapp`, not text-editable to seed), `ReRef`/`SelectData` (delegate to EEGLAB's own `pop_reref`/`pop_select` dialogs, which take no seed parameter). |
| `src/GrandAverage.m` + `src/GrandAverageDialog.m` | Grand-average computation and its subject-picker dialog (Grand Average tab). |
| `src/exportGrandAveragesCSV.m` | Writes every Grand Average to one long-format, R-compatible CSV (`Alakazam.onExportGrandAverages`, Grand Average tab's "Export Grand Averages..." button) -- the app's first working export path (`Workspace.ExportsDirectory` used to be configured but never actually written to). |
| `src/@cursor/`, `src/@label/` | Small UI helper classes (plot cursors and labels). |
| `src/Transformations/<Name>/` | Analysis plugins. Each folder: `<Name>.m` (entry), `<Name>.json` (manifest), `<Name>.png` (icon). |
| `src/Transformations/+TransTools/` | Shared helpers for transformations (`CheckOptions`, `CreateFilter`, `WindowByName` (the taper-window dispatch `Fourier.m` calls), `progressbar`, `FillChanlocs`/`Dipfit1005File` for scalp-position lookups, `ComputeErsp` (`TimeFrequency.m`'s wavelet ERSP computation, pulled out here so it's callable/testable without going through that transformation's own blocking options dialog), `DrawScalpMap` (a uiaxes-compatible port of EEGLAB's `topoplot()` used by `ScalpDistributionView`, needed because `topoplot()` itself only draws via gca/gcf-implicit state and was confirmed to silently draw nothing when targeted at a uiaxes hosted in a uitab), `DivergingColormap` (the shared blue/white/red colour scale `TimeFrequencyView` and `EpochView`'s ERP-image both use for a signed, zero-centred quantity)). |
| `src/webtree/` | Node.js/esbuild source for `WorkSpaceTree.html` (see above). Not needed to *run* Alakazam (the built output is committed) -- only to change the tree's look/behaviour. |
| `src/Icons/` | Hand-drawn SVG source for every ribbon icon. `AlakazamRibbon.m` reads the View/WorkSpace/Settings/Grand Average ones from here directly at construction time (`encodeSvgFile`, the SVG counterpart of `encodeIcon`); each transformation's `Transformations/<Name>/<Name>.png` is a separately rasterized copy of `src/Icons/<Name>.svg` (kept as a PNG too since `WorkSpaceTree.iconForResult` needs a raster image for tree-node icons, and re-rasterizing isn't automatic -- regenerate it by hand after editing the `.svg`). |

> Note: the copied EEGLAB helpers are gone; the app calls the installed
> EEGLAB directly (`eeg_checkset`, `pop_select`, `pop_loadbv`, ...), so EEGLAB
> and the bva-io / ICLabel plugins must be on the MATLAB path at runtime.
> `+Tools/` no longer exists. The authored plotting code lives in `src/`
> (SignalView, EpochView, AverageView, FourierView, MinMaxPyramid).

### Dead code removed in the July 2026 audit

- **`src/@cursor/@label/label.m`** (nested class folder): a stale, pre-`uiaxes`
  copy of `src/@label/label.m` (still used `gcf`/`gca`, which silently
  targets the wrong figure/axes once hosted on a `uiaxes`). Confirmed
  unreachable before removal: nothing inside `@cursor`'s own methods
  constructed a `label`, and the only real caller (`SignalView.m`) is outside
  `@cursor`'s folder, so MATLAB always resolved to the top-level, already-
  fixed `src/@label/label.m` anyway.
- **`src/Icons/*.gif`** (`bookicon.gif`, `frequencyIcon.gif`, `pagesicon.gif`):
  zero references anywhere in `src/`. Superseded by the inline-SVG icon sets
  in the ribbon and tree.
- **`src/+uiextras/+jTree/`**: the old Java-Swing tree widget
  `WorkSpaceTree.m` replaced. Only referenced from doc-comments explaining
  the replacement (`WorkSpaceTree.m`, `CreateTreeComponent.m`) -- no live
  code called `uiextras.jTree.*` anymore.
- **`src/DefaultWorkSpace.wksp`**: an orphaned, diverged duplicate of the
  repo-root `DefaultWorkSpace.wksp` (see the `RootDir`/`RepoRoot` note
  above) -- removed; the repo-root copy was renamed to match the exact
  casing `WorkSpace.m`'s constructor requests (was `DefaultWorkspace.wksp`,
  lowercase s, which only ever loaded because Windows filesystems are
  case-insensitive).

`findjobj.m`, `findjobj_fast.m` and `uiinspect.m`, listed in an earlier pass
of this audit as dead-code candidates, turned out not to exist in the
current tree at all (`git log --all` shows they were already removed, in an
earlier "repo legibility cleanup" pass) -- `dependencies.md`'s own listing of
them was itself stale. Corrected there.

## Vendored toolkits (do not edit, see dependencies.md)

| Path | Toolkit |
|---|---|
| EEGLAB (+ bva-io, ICLabel, FastICA, GEDAI) | on the MATLAB path, not bundled (see `EEGLabEnvironment` and `dependencies.md` -- GEDAI is licensed PolyForm Noncommercial, installed separately and lazily by `AutoGEDAI.m` with explicit user consent) |
| `src/+uiextras/` | Dialog helpers (`settingsdlg`, `inputgui`, `supergui`) used by the Transformations' option dialogs. |

## How the pieces connect

```
Alakazam (app, single uifigure -- see migration.md for the AppContainer/
ToolGroup history this replaced)
  ├─ AlakazamRibbon ──> scans Transformations/*/*.json ──> uihtml ribbon (Home/Tools/Grand Average)
  ├─ WorkSpace ──> loads raw files into two EEG-struct trees:
  │     ├─ Tree             (data & analyses, DataTreePanel)
  │     └─ GrandAveragesTree (grand averages, GrandAveragesTreePanel)
  ├─ AlakazamPlotter ──> PlotsTabGroup (one uitab per open dataset) or TileGrid
  │     (Grid/Stack tiled view -- see Alakazam.setPlotsViewMode/retile)
  └─ onTransformation / evaluateDroppedBranch ──> feval(<transform>, EEG) ──> new tree node + .mat
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
- **Phase 3** (shell rewrite, this session -- see `migration.md` for the full
  history): replaced the Java-Swing `ToolGroup` app shell -- broken outright
  once `figure()` stopped creating Swing-backed windows -- with a single
  modern `uifigure`: a hand-written `uihtml` ribbon (`AlakazamRibbon`)
  replacing the MathWorks Toolstrip, a `uihtml`/webtree data-browser tree
  (`WorkSpaceTree`) replacing `uiextras.jTree`, now split into two instances
  (data & analyses / grand averages), and a `uitabgroup` (plus a hand-rolled
  Grid/Stack tile view) for plots, replacing the old MDI desktop.
- **July 2026 audit**: full pass for duplicated/dead code, stale comments,
  and correctness bugs across `src/`. See the dead-code notes above; real
  bugs found in the Transformations (`ReRef` replay broken,
  `IIRFilter`/`Fourier` issues, `WorkSpace.load` calling an unqualified
  `uigetfile2`, now fixed) are tracked wherever they were reported, not
  duplicated here.

Next: **Phase 4** (formalise the transformation contract: replace the
`EEG.Call` string-parsing and `eval` replay with a typed `{id, params}`
record) and **Phase 5** (table-drive the `@WorkSpace` loaders).
