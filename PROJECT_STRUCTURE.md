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

**No `eval` anywhere in the app.** Both the transformation *dispatch* (a
fresh run from the ribbon) and *replay* (dragging a branch onto another
dataset, **Apply to All Raw Files...**, template replay) call
`feval(transformId, EEG, options)` with a stored `options`/`params` struct:
plain data, not a parsed or `eval`'d command string. An earlier design stored
EEGLAB's own "eegh" command-history string and re-executed it with `eval`;
that was replaced by this typed `{id, params}` record (Phase 4, see
"Refactoring status" below, now done rather than upcoming).

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
and constructs the app; the app then adds its own subfolders (`Views`, `Dialogs`,
`IO`, `Support`) and `Transformations/` (see `@Alakazam/setupDirectories`).
To use the bare `Alakazam` command instead, add `src/` to your MATLAB path once
(via `pathtool` or a `startup.m`) and let the app add the rest.

## Source layout (folders under `src/`)

Authored code is grouped by role. `src/` itself is added to the path
non-recursively (so the `@class` / `+package` folders are not put on the path
directly); the app adds the plain-function/class folders below explicitly.

| Folder | Holds |
|---|---|
| `src/` (top level) | The core app singletons/classes: `AlakazamPlotter`, `AlakazamRibbon` (+`.html`), `AlakazamSettings`, `WorkSpaceTree` (+`.html`), `TransformSettings`, `EEGLabEnvironment`, `GrandAverage`. |
| `src/@Alakazam/`, `src/@WorkSpace/`, `src/@cursor/`, `src/@label/` | Class folders: the main app class and its methods, per-format loaders / `.wksp` persistence, and small plot-cursor/label helper classes. |
| `src/Views/` | The plot **View** classes (`SignalView`, `EpochView`, `AverageView`, `FourierView`, `TimeFrequencyView`, `ScalpDistributionView`, `Brain3DView`, `SpectralMeasureView`, `CoherenceView`, `CoherenceTopographyView`), plus two small shared UI-component classes `ZoomPanButtons` (FourierView/SpectralMeasureView's zoom/pan/step button row) and `TimeScrubStrip` (ScalpDistributionView/Brain3DView's bin-dropdown/time-label/Play-button/slider scaffolding). |
| `src/Dialogs/` | Hand-built `uifigure` dialogs (`TransformOptionsDialog`, `MeasureDialog`, `FilterDialog`, `ReRefDialog`, `SelectDataDialog`, `ChannelEditorDialog`, `InterpolateDialog`, `RemoveComponentsDialog`, `SpectralMeasureDialog`, `GrandAverageDialog`, `SettingsDialog`). |
| `src/IO/` | Import / export / format conversion: erpset converters (`erpsetToAveraged`, `averagedToErpset`), the ERPLAB BDF importer (`erplabBdfToBinScript`), the CSV writers (`exportMeasurementsCSV`, `exportSpectralCSV`, `exportGrandAveragesCSV`) and the R-script generator (`generateRScript` + its `statsTemplate.R`). |
| `src/Support/` | Small shared helpers (`eegChannelMask`, `guessChannelTypes`, `channelTypeFromLabel`, `multiSelectField`, `spectralFreqSpecs`, `MinMaxPyramid`, plus a batch of dialog/IO helpers consolidated in the August 2026 audit: `dialogChromeColors`, `intersectLabels`/`asCell`/`mergeSeedFields`, `linesFromText`/`textFromLines`, `csvField`/`numField`/`csvBinLabel`, `firstNonEmpty`). |
| `src/Meshes/` | `BrainMesh_ICBM152.nv`, the 3D brain surface mesh `Brain3D`/`Brain3DView` project scalp topographies onto (see `TransTools.ReadBrainMeshNV`/`DrawBrainMap`) -- vendored from BrainNet Viewer (GPLv3), see `src/Meshes/README.md` and `dependencies.md`. |
| `src/Transformations/` | Analysis plugins (`<Name>/` folders) and the `+TransTools` shared-helper package. |
| `src/+uiextras/`, `src/Compat/`, `src/Icons/`, `src/webtree/` | The dialog-widget helper package, compatibility shims, SVG icon sources, and the WorkSpaceTree HTML build pipeline. |

## Authored code (edit these)

| Path | Role |
|---|---|
| `startAlakazam.m` | Root launcher: adds `src/` to the path, constructs the app. |
| `src/@Alakazam/` | Main application class (class folder): lifecycle, tree callbacks, transformation dispatch, persistence, and its many method files. |
| `src/EEGLabEnvironment.m` | Ensures EEGLAB and the required plugins (bva-io, XDF, ICLabel, FastICA) are installed, that EEGLAB has actually been *run* at least once in the current MATLAB session (not just found on the path -- see `ensureEEGLabInitialized`), and warns if the Signal Processing or Statistics and Machine Learning toolboxes are missing; called once at startup. |
| `src/AlakazamPlotter.m` | Renders EEG datasets into tabs of the app's plots tabgroup (plotting split out of the main class). |
| `src/Support/MinMaxPyramid.m` | Precomputed min/max pyramid: the decimation engine for fast signal plotting. |
| `src/Views/SignalView.m` | Fast scrolling continuous-signal view (replaces the removed legacy plotting tool). |
| `src/Views/EpochView.m` | ERP-image view of epoched multichannel data: a time x trial heatmap for the current channel (up/down arrows step it), rows grouped by bin, plus a trial-average trace below -- replaces an earlier overlaid-line-traces plot (which didn't scale past a handful of trials/channels) and its own since-removed "all channels, one trial" mode (replaces Tools.plotEpochedTimeMulti). |
| `src/Views/AverageView.m` | Trial-average view with error bands and overlay (replaces Tools.plotEpochedTimeMultiAverage). |
| `src/Views/FourierView.m` | Keyboard-driven frequency-domain view (one channel's spectrum at a time, band shading, zoom/pan; up/down arrows step the channel, left/right the trial -- same interaction model AverageView uses; replaces Tools.plotFourier). |
| `src/Views/TimeFrequencyView.m` | Grid of per-bin ERSP heatmaps (`TransTools.ComputeErsp`'s precomputed output), one channel at a time; up/down arrows step the channel, an instant re-slice since every channel was computed up front. The app's first multi-tile-grid view. |
| `src/Views/ScalpDistributionView.m` | One scalp topography (`TransTools.DrawScalpMap`) with a bin dropdown when there is more than one, scrubbable by a `uislider` (`TimeScrubStrip`); only offers the bins ticked on in a sibling `AverageView` tab, if one is open. Mouse/slider-only, no keyboard navigation. Its rotatable-3D-brain-mesh sibling `Brain3DView.m` shares the same interface (`TransTools.ResolveScalpDistribution`/`DrawBrainMap`, `TimeScrubStrip`). |
| `src/AlakazamRibbon.m` + `src/AlakazamRibbon.html` | uihtml-based control-strip ribbon (Home/Tools/Grand Average); discovers transformations from `src/Transformations/*/*.json`. Hand-written self-contained HTML page, no build step. |
| `src/WorkSpaceTree.m` + `src/WorkSpaceTree.html` | uihtml-based data-browser tree (replaces the old Java-Swing `uiextras.jTree.Tree`). The `.html` is a **built artifact**, assembled from `src/webtree/src/*` by `src/webtree/`'s own npm/esbuild pipeline (see `src/webtree/README.md`) -- edit the source there, not the `.html` directly, then rebuild and re-copy. |
| `src/@WorkSpace/` | Per-format file loaders, `.wksp` session persistence, and construction of the app's **two** `WorkSpaceTree` instances (`Tree` for data & analyses, `GrandAveragesTree` for grand averages -- see `CreateTreeComponent.m`). |
| `src/AlakazamSettings.m` + `src/Dialogs/SettingsDialog.m` | Global settings: `AlakazamSettings` defines the schema (tabs/sections/settings, persisted to `prefdir()/AlakazamSettings.json`); `SettingsDialog` builds the editor UI from that schema. |
| `src/TransformSettings.m` | Per-transformation "last used options", scoped to the *currently open workspace* (unlike `AlakazamSettings`, which is machine-wide) -- `get`/`set` by transform id, with `.wksp` save/load folding the whole store in as one more JSON field (see `WorkSpace.save`/`load`). Wired into `DefineBins`, `ArtefactDetect`, `AutoEyeICA`, `AutoGEDAI`, `Baseline` and `Fourier`. Not wired into `Average`/`ScalpDistribution` (no options at all), `IIRFilter` (its dialog is a binary `.mlapp`, not text-editable to seed), `ReRef`/`SelectData` (delegate to EEGLAB's own `pop_reref`/`pop_select` dialogs, which take no seed parameter). |
| `src/GrandAverage.m` + `src/Dialogs/GrandAverageDialog.m` | Grand-average computation and its subject-picker dialog (Grand Average tab). |
| `src/IO/exportGrandAveragesCSV.m` | Writes every Grand Average to one long-format, R-compatible CSV (`Alakazam.onExportGrandAverages`, Grand Average tab's "Export Grand Averages..." button) -- the app's first working export path (`Workspace.ExportsDirectory` used to be configured but never actually written to). |
| `src/@cursor/`, `src/@label/` | Small UI helper classes (plot cursors and labels). |
| `src/Transformations/<Name>/` | Analysis plugins. Each folder: `<Name>.m` (entry), `<Name>.json` (manifest), `<Name>.png` (icon). |
| `src/Transformations/+TransTools/` | Shared helpers for transformations: `CreateFilter`, `WindowByName` (the taper-window dispatch `Fourier.m` calls), `progressbar`, `FillChanlocs`/`Dipfit1005File`/`TemplateScalpLocs` for scalp-position lookups, `ComputeErsp` (`TimeFrequency.m`'s wavelet ERSP computation, pulled out here so it's callable/testable without going through that transformation's own blocking options dialog), `ComputeCoherenceMap`/`ComputeCoherenceTopography`, `DrawScalpMap` (a uiaxes-compatible port of EEGLAB's `topoplot()` used by `ScalpDistributionView`, needed because `topoplot()` itself only draws via gca/gcf-implicit state and was confirmed to silently draw nothing when targeted at a uiaxes hosted in a uitab), `DivergingColormap` (the shared blue/white/red colour scale `TimeFrequencyView` and `EpochView`'s ERP-image both use for a signed, zero-centred quantity), `AddSharedColorbar`/`ColorbarColumnWidth` (the dedicated-hidden-axes colorbar trick six views share, centred in a sized column), `BuildBinDropdown` (the "Bin:" label + dropdown row shared by `TimeScrubStrip` and `CoherenceTopographyView`), `ResolveScalpDistribution`/`TickedScalpBins` (shared by `ScalpDistribution`/`Brain3D` and their views), `ReadBrainMeshNV`/`DrawBrainMap`/`DrawBrainPatch` (`Brain3D`'s scalp-projection mesh and its shared patch/lighting/view drawing), `BuildSourceForwardModel`/`ComputeSourceEstimate`/`DrawSourceMap`/`ensureFieldTrip` (`Brain3D`'s optional FieldTrip-based MNE source-estimate mode, see the README's own "3D brain view" section), and the August 2026 audit's `FieldOr`/`LabelsToIdx`/`InitGuard` (the options-struct-parsing boilerplate ~21 transformations now share). `CheckOptions` was removed in that same audit, orphaned by the `IIRFilter`→`Filter` rename with zero remaining callers. |
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
- **Phase 5** (table-drive the `@WorkSpace` loaders) and an **August 2026
  audit**: four parallel sweeps (app-controller, transformation plugins,
  UI layer, I/O/data-loading) surfaced real bugs and a further round of
  duplication. Fixed: `onExportSpectral`'s misused error dialog;
  `WorkSpace`'s constructor (a malformed `if`/`elseif` left its 4-argument
  form silently unreachable, and its error branch threw a plain string
  instead of an `MException`); `@label.m`'s `buttonmotion`/`buttonup`
  referencing fields never set (a `cursor.m` copy-paste remnant, currently
  dead since every caller passes empty callbacks); the trailing-separator
  path bug across `@WorkSpace` (`strcat` assumed a directory string always
  ended in a separator; the constructor's own fallback-defaults path,
  built with `fullfile`, does not -- silently produced an empty tree on a
  fresh install). Deduplicated: `TransTools.FieldOr`/`LabelsToIdx`/
  `InitGuard` (options-struct boilerplate across ~19 transformation
  files), `TransTools.AddSharedColorbar` (6 views), `Views/ZoomPanButtons`
  (FourierView/SpectralMeasureView), `Views/TimeScrubStrip`
  (ScalpDistributionView/Brain3DView), a dialog-chrome colour helper and
  several small `Support/` helpers (see that row above), and the
  `@WorkSpace` loaders themselves (`resolveCachePaths`/`registerRootNode`,
  shared by all four format loaders; `open.m` collapsed to one small
  format table). `@cursor`/`@label` brought onto the project's own
  UpperCamelCase property standard.
- **Phase 4** (formalise the transformation contract): done, confirmed
  during this pass, not tracked separately when it landed. Dispatch and
  replay both already call `feval(transformId, EEG, options)` with a typed
  `options`/`params` struct; there is no `EEG.Call` string-parsing or
  `eval` replay left anywhere in `src/` (see "Coding standards" above).

No further phase is currently planned.
