# Alakazam developer guide

This guide is for people who change Alakazam: add a transformation, fix a
view, extend a report, or cut a release. Using Alakazam is described in the
[user manual](manual/manual.qmd); what Alakazam is, in the
[README](README.MD).

Four companion documents hold the detail this guide points to rather than
repeats:

| Document | What it holds |
|---|---|
| [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md) | A file-by-file map of `src/`, the vendored toolkits and the build-time tooling |
| [`dependencies.md`](dependencies.md) | Every external toolkit, its pinned version, licence, and how it is installed |
| [`DATA.md`](DATA.md) | The datasets the tests, templates and manual use, and where to get them (none are in the repository) |
| [`Docs/transformation-provenance.md`](Docs/transformation-provenance.md) | Which transformations wrap a toolkit call and which carry their own method |

The project history is in [`CHANGELOG.md`](CHANGELOG.md); why the interface is
built on `uihtml` rather than MathWorks' own widgets is in
[`migration.md`](migration.md).

## Architecture

A single `uifigure` hosts the whole application. Along the top is a ribbon
(`AlakazamRibbon`, a `uihtml` component); down the left, three trees
(`WorkSpaceTree`, also `uihtml`: Data & Analyses, Grand Averages, Reports);
on the right, the plot area (`PlotsTabGroup`, one `uitab` per open dataset,
which can be re-laid as a grid or a stack).

At startup the application resolves two roots from its own location, so it
never depends on the current folder:

- `RootDir`, the authored source tree (`src/`), which holds the
  transformations;
- `RepoRoot`, the repository root, which holds the vendored toolkits and
  shared resources.

`startAlakazam` adds `src/` to the path and constructs the app; the app adds
the rest (`setupDirectories`). `EEGLabEnvironment` initialises EEGLAB when it
is not already on the path, without touching the saved MATLAB path.

### The classes that matter

| Class | Role |
|---|---|
| `Alakazam` (`src/@Alakazam/`) | The application. One method per file. **A method file needs a matching declaration in `Alakazam.m`**: without it MATLAB silently ignores the file, and the symptom is a callback that does nothing. |
| `WorkSpace` (`src/@WorkSpace/`) | The workspace: its three folders, the trees, stored transformation settings, the design (groups, persons, sessions). |
| `WorkSpaceTree` | One tree. A flat `id -> struct` map of nodes, pushed to the HTML side as JSON. Knows which context-menu actions a node offers (`optsFor`). |
| `AlakazamPlotter` | Opens a dataset in a tab and chooses its view (see [Views](#views)). |
| `AlakazamRibbon` | The ribbon. Discovers transformations from their manifests at startup. |
| `TransformSettings` | Per-workspace memory of each transformation's last options, which is what seeds its dialog. |
| `AlakazamSettings` | Machine-wide preferences (the **Global** settings dialog), schema-driven. |
| `ViewFocus` | Carries the channel and bin a user is looking at from one view to the next. |

### The data model

Every dataset is an EEGLAB `EEG` structure (Delorme & Makeig, 2004), so any
node can be handed to EEGLAB, ERPLAB or FieldTrip unchanged. Alakazam adds a
few fields:

| Field | Meaning |
|---|---|
| `File` | The node's cache file. Always overwritten on load with the path it was actually read from. |
| `id`, `Call`, `params` | The transformation that produced the node and the options it used: what Recalculate, Apply to All, templates and Export as Code replay. |
| `DataType` | `TIMEDOMAIN` or `FREQUENCYDOMAIN`. |
| `DataFormat` | `CONTINUOUS`, `EPOCHED` or `Averaged`. |
| `bindesc` | Bin descriptors written by `DefineBins` (label, script, events, reaction times, trials). |
| `etc.alz` | Provenance: what a step did that the numbers alone do not show (interpolated cells, rectified channels, which artefact detector rejected which trial, the Deconvolve model). The data-quality report reads it. |

A transformation that changes what the numbers *mean* while leaving them
looking ordinary (rectification, interpolation, a unit change) must leave a
record in `etc.alz`; otherwise nothing downstream can see it.

### The cache

Every node is a file in the workspace's cache folder: a recording's results
live in a subfolder named after the recording, and a node's children in a
subfolder named after the node's own file stem. Beside each `<node>.mat` are
two small records:

- `<node>.mat.json`: what kind of node it is (format, bins, flags), so a scan
  can build the tree without loading data;
- `<node>.mat.meta`: the transformation, its exact options and the data's
  shape, so a branch can be replayed, recalculated or saved as a template
  without loading every step in full.

Both are rewritten when missing or older than the node. `persistResultNode`
writes a node; `loadNodeEEG` reads one. ICA activations (`icaact`) are never
saved: EEGLAB recomputes them, and they doubled the size of every node below
an ICA step.

### Views

`AlakazamPlotter.plotCurrent` picks a view by the node's `id`, then by the
fields it carries, then by `DataType` and `DataFormat`:

| Dataset | View |
|---|---|
| continuous time domain | `SignalView` |
| epoched | `EpochView` (ERP image) |
| averaged | `AverageView` |
| frequency domain | `FourierView` |
| `TimeFrequency`, `ScalpDistribution`, `Brain3D`, `SpectralMeasure`, `CoherenceMap`, `CoherenceTopography`, `CrossCorrelation`, `Covariance` | a view of their own |
| a rendered report | `ReportView` |

Every view derives from `AlakazamView`. A view that shows one channel or
bin at a time implements `currentFocus` and `applyFocus`, which is how the
channel a user was looking at follows them to the next node.

`SignalView` draws continuous data through a `MinMaxPyramid`: a precomputed
stack of per-bucket minima and maxima, from which a redraw reads about one
min/max column per screen pixel. Its cost is independent of the recording's
length, and because minima and maxima compose exactly, no spike or brief
artefact is ever decimated away.

## Transformations

A transformation is a folder `src/Transformations/<Name>/` holding:

- `<Name>.m`, the entry function;
- `<Name>.json`, the manifest: `Name` (the ribbon label), `Description`
  (the tooltip), `Entry`, `Icon`, `Section` (the ribbon group, e.g.
  `"1. Preprocessing"`) and `Category`;
- `<Name>.png`, the ribbon icon;
- its dialog and any helpers used by it alone.

Manifests are found at startup and placed on the ribbon's **Tools** tab by
their `Section`. Every non-package folder under `Transformations` is offered
as a transformation (`RibbonScanTest` pins this), so a helper shared between
transformations lives in a package: `+TransTools` for general helpers,
`+Unfold`, `+EyeEeg` and `+ClusterStats` for their own domains. A helper used
by one transformation stays in that transformation's folder.

### The contract

```matlab
function [EEG, options] = SelectData(input, varargin)
% Example transformation (trimmed from the real SelectData.m).

    [opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:SelectData', varargin{:});
    if interactive
        % Interactive: prompt for options, remember them for next time.
        options = SelectDataDialog(input.chanlocs);
        if isempty(options)
            EEG = [];        % cancelled: no node, no compute
            options = [];    % BOTH outputs, always
            return;
        end
        TransformSettings.set('SelectData', options);
    else
        % Replay: reuse a previously captured options struct as-is.
        options = opts;
    end

    EEG = pop_select(input, buildSelectArgs(input, options){:});
end
```

- Called with one argument, a transformation is interactive: it opens its
  dialog, seeded from `TransformSettings.get('<Name>')`, and stores what was
  chosen. Called with an options struct, it replays with no dialog. That one
  rule is what makes Recalculate, dragging a branch, **Apply to All Raw
  Files**, templates and Export as Code work.
- Every call goes through `TransTools.invoke`, which checks the returned
  shape (two outputs; an `EEG` that is empty, a struct or a graphics handle;
  `options` a struct, empty or the `'Init'` sentinel) before it reaches the
  tree. `TransformContractTest` specifies this seam and asserts that nothing
  bypasses it. It also brings the per-channel arrays of the result
  (`stErr`, `aSME`, `etc.alz.interpolated`) in step with its channels, by
  label (`TransTools.AlignChannelCompanions`), so a step that adds or drops
  channels with EEGLAB's own functions need not know they exist.
- **Options are plain data**, never a command string that is `eval`'d.
  Channels and bins are stored by **label**, not index, and resolved against
  the dataset at compute time, so a stored choice replays on another subject
  whose montage or bin order differs.
- **Options must survive JSON.** Templates round-trip through
  `jsonencode`/`jsondecode`, which collapses a one-element struct array to a
  bare object and hands a same-shaped JSON array back as a struct array.
  Store lists of records as cell arrays of scalar structs and normalise on
  replay (see `Measure.m`'s note on `windows`).
- A transformation with no options still takes and returns `options`
  (`Average`, `ScalpDistribution` and `Brain3D` accept `struct('Param','Init')`).

### Dialogs

A dialog returns the options on OK and `[]` on Cancel or when its window is
closed. `TransformOptionsDialog` builds a standard one from
`{label; field}, default` pairs and infers each field's kind from its default
(a cell array of strings is a drop-down, a logical a checkbox, a number a
numeric field, anything else text).

A default can also be a field object from `src/Dialogs/+DialogFields`, which
is what keeps a transformation on the generated dialog when it needs more:

| Field | For |
|---|---|
| `Choice(items, selected, 'Values', v)` | a drop-down whose shown items and stored values differ |
| `Number(x, 'Limits', [lo hi], 'Integer', tf)` | a number with limits |
| `Channels(EEG, selected, 'Multiple', 'Required')` | the dataset's channels by label, with All, None and Scalp EEG |
| `Bins(EEG, selected, 'Differences', tf)` | the dataset's bins by label, with All, None and Differences |
| `Table(columns, rows, 'MinRows', n)` | rows of fields, with Add and Remove; returns a cell of structs, the JSON-safe shape |
| `TextArea(text, 'Validate', @(t) ...)` | a block of text checked at OK, by the parser the step runs |
| `Plot(@(ax, values) ...)` | a preview redrawn whenever a value changes; adds nothing to the options |

Every field takes `'EnabledWhen', @(values) ...` (greyed out, and not
validated, while false; `values` holds every field's current value by name)
and `'Tooltip'`. OK asks each enabled field to `validate` and stays open with
its message when one refuses. A new kind of field is a subclass of
`DialogFields.Field` (`build`, `value`, and optionally `height`, `width`,
`spansBothColumns`, `validate`, `refresh`); the dialog needs no change.
Interpolate, Derive Channels and Baseline show the range: a required channel
list, a checked script, and a live preview.

A dialog of its own is a `uifigure` placed with `fitOnScreen`, coloured with
`dialogChromeColors`, and must set `CloseRequestFcn` to its Cancel path. It
is the right choice when the dialog is an editor rather than a form (Measure's
windows, DefineBins' script with its bin preview), not merely because a field
is a channel list or a table.

### Recalculate

A node offers **Recalculate** when its transformation is listed in
`WorkSpaceTree.RecalculableTransforms`, a single list pinned by
`RecalculableTransformsTest`. Leave a transformation off it when its dialog
cannot be reseeded from stored options (Photodiode, EventEditor) or when it
has none.

### What a transformation may do to the dataset

A transformation is handed a dataset and returns one, and everything
downstream (the views, the other steps, the reports, a replay on another
subject) reads what it returns. So:

- **Start from what you were given**: `EEG = input;`, then change what the
  method changes. Every field you do not touch survives: EEGLAB's, Alakazam's
  own (`DataType`, `DataFormat`, `bindesc`) and the records earlier steps
  left in `EEG.etc.alz`.
- **Keep the description true to the data.** When the data's shape changes,
  so do `nbchan`, `pnts`, `trials`, `chanlocs`, `times` and `DataFormat`
  (`'CONTINUOUS'`, `'EPOCHED'` or `'Averaged'`; `inferDataFormat` derives it
  from the shape). `DataType` is `'TIMEDOMAIN'` for waveforms; a spectrum is
  `'FrequencyDomain'`, with its own axis.
- **Time is in seconds when continuous, milliseconds when epoched or
  averaged**, as every loader leaves it.
- **Channels and bins are labels.** Options store labels, resolved against
  the dataset at compute time (`TransTools.LabelsToIdx`), so a stored choice
  replays on a montage in another order, or one lacking a channel.
- **Rejection is `NaN`, never deletion.** A rejected epoch is `NaN` on every
  channel, a rejected channel-epoch on that channel; trials keep their
  places, and Average leaves `NaN` out. A reconstructed cell is recorded with
  `TransTools.RecordInterpolated`, or it is invisible to the data-quality
  report.
- **Say what you did in `EEG.etc.alz.<step>`**, plain data only (it is saved,
  and exported): the settings that mattered, what was changed, and the
  version of any toolbox that did the work. Never overwrite another step's
  record. The data-quality report reads the records it knows
  (`dataQualityMetrics`); a new one that a reader of the results needs gets
  a provenance row there.
- **Leave `id`, `File`, `Call` and `params` alone**: the host sets them when
  it stores the result (`onTransformation`, `persistResultNode`).
- **Refuse, do not guess.** Input of the wrong kind is an `MException` with
  the transformation's id and a sentence saying what to do instead; so is a
  toolbox that fails quietly (see `PREP`'s handling of `prepPipeline`).

### Adding a transformation: the checklist

`newTransformation(name, ...)` (src/Support) writes the first steps: the
folder with an entry function that follows the contract, the manifest, a
placeholder icon and its SVG source, a test class, a manual section with an
options table, and the entry on the Recalculate list. It refuses to
overwrite anything. What it cannot write is the method, its tests of
substance and its description.

1. The folder, entry function, manifest and icon, following the contract.
   The icon is drawn as `src/Icons/<Name>.svg` (24 x 24, the ribbon blue
   `#4a7fc9`) and the PNG beside the manifest is rasterized from it:
   `node src/webtree/rasterize.mjs src/Icons/<Name>.svg
   src/Transformations/<Name>/<Name>.png 24` (needs `@resvg/resvg-js`).
2. A test class in `tests/` (see [Testing](#testing)): the compute on a small
   fixture, the replay, and the dialog's OK and Cancel paths.
3. `RecalculableTransforms`, if it can be recalculated.
4. A row in `Docs/transformation-provenance.md` if it wraps a toolkit call.
5. If Export as Code should spell it natively, an entry in
   `src/IO/nativeTransformCall.m` **and** a case in
   `NativeExportEquivalenceTest`, which compares every field of both routes
   and fails when a native emission has no case.
6. If it needs a toolbox that is not bundled, a description of it for
   `TransTools.EnsureToolbox` (name, pinned archive, version, licence; see
   `PREP/prepToolbox.m`), a row in `alakazamDependencies` and in the
   manual's table of toolboxes. `TransTools.ToolboxAvailable` answers the
   same question without asking, for tests. A method that learns from the
   scalp (a reference, a covariance, an interpolation) takes its channels
   from `TransTools.ScalpChannels`, which leaves the peripherals out.
7. A section in the manual's transformation reference
   (`manual/chapters/`), with its dialog and result pictures added to
   `src/help/capture/manualShots.m`. `ManualTest` fails when a
   transformation has no section.

## The library

`library/` holds the files a user starts an analysis from, by kind:
`templates/`, `binscripts/` and `measures/`. Apply Template and the
DefineBins and ERP Measure **Load...** dialogs open there the first time in
a session and remember the last folder per kind after that
(`pickLibraryFile`; `libraryFolder` finds the folder from its own location).
`library/README.md` sets the rules and indexes every file; `LibraryTest`
enforces them:

- every file loads the way the application reads it;
- every measurement file has a `source` block (`reference`, `doi`,
  `agreement`, `note`), with `agreement` one of `matches`, `partly`,
  `differs`, `not compared` or `no source`, and a reference unless it is
  `no source`;
- every file is listed in the README.

`LibraryReplayTest` (tagged `Slow`, skipped where the data or a toolbox is
missing) replays each template on its own data through `TransTools.invoke`,
as Apply Template does, and compares with the numbers recorded in
`Docs/luck.md`, `Docs/dimigen.md` and chapters 17 and 20 of the manual. A
new template with a recorded result gets a case there.

A measurement window from the library is an a priori choice only when its
source is known, so a window with no source says so rather than borrowing a
reference that does not describe it.

## Reports

The statistical, cluster, source-cluster and data-quality reports are Quarto
documents generated in MATLAB (`src/Reports/generate*Report.m`) from the
design as MATLAB knows it, then rendered with Quarto and R. The R code lives
in `src/Reports/rscripts/` as `.R`, `.Rpart` and `.qmd` templates that are
**inlined** into the generated document rather than sourced, so a report is
a single self-contained file a user can edit; see
[`src/Reports/rscripts/README.md`](src/Reports/rscripts/README.md). A
byte-identical golden check guards the inlining, and a test that searches
MATLAB source for R code must read it through `sourceWithTemplates`.

The in-app report viewer is a current Chromium, but it is served through
MATLAB's connector, whose content-security policy refuses `data:` styles and
scripts. Reports are therefore rendered with every resource inlined.

### Cluster and source statistics

| Function | Purpose |
| --- | --- |
| [`ClusterStats`](src/ClusterStats.m) | The scalp cluster-based permutation test (FieldTrip's `ft_timelockstatistics`). |
| [`SourceClusterStats`](src/SourceClusterStats.m) | The source-space test: inverts each subject, builds the design, runs the permutation, summarises the clusters. |
| [`ClusterStats.buildDesign`](src/+ClusterStats/buildDesign.m) | Subjects and a contrast to FieldTrip's design matrix; shared by both tests. |
| [`ClusterStats.runMontecarlo`](src/+ClusterStats/runMontecarlo.m) / [`poolMontecarlo`](src/+ClusterStats/poolMontecarlo.m) | Run the permutation, optionally split across workers, and recombine the split runs into the result one run would give. |
| [`ClusterStats.tfceStatfun`](src/+ClusterStats/tfceStatfun.m) | A statfun returning the TFCE score, which lets the compiled kernel run inside FieldTrip's public `'max'` correction without patching FieldTrip. |
| [`TransTools.BuildSourceForwardModel`](src/Transformations/+TransTools/BuildSourceForwardModel.m) | Template head model, electrodes and cortical sheet, cached per channel set and sheet. |
| [`TransTools.SourceEstimateKey`](src/Transformations/+TransTools/SourceEstimateKey.m), [`DataFingerprint`](src/Transformations/+TransTools/DataFingerprint.m), [`StoredSourceEstimate`](src/Transformations/+TransTools/StoredSourceEstimate.m) | The two checks a stored source estimate must pass before it is reused, and the one lookup both consumers ask through. |
| [`alakazam_tfce.c`](src/mex/alakazam_tfce.c) | The compiled TFCE kernel, built on first use; FieldTrip's own implementation is the fallback. |

`SourceClusterMexTest` requires the accelerated route to give exactly the
p-values of FieldTrip's own; `SourceEstimateTest` requires a reused estimate
to give the same statistic as a computed one; `PointSpreadTest` holds the
point-spread figures the report prints to account.

## Testing

Run the suite from the repository root:

```matlab
addpath('tests'); runAlakazamTests('quick');   % everything but the Slow cases
addpath('tests'); runAlakazamTests('full');    % all of it, before any push
addpath('tests'); runAlakazamTests('slow');    % only the heavy cases
```

Tags: `Slow` (measured wall clock, nothing else), `External` (needs R,
Quarto, a compiler or a toolbox download), `KnownGap` (a documented gap a
default run may exclude). A case whose data is absent is filtered by
assumption, and a skip is not a pass: say so when reporting a run.

Conventions the suite depends on:

- **Each test class sets its own path** in `TestClassSetup` with
  `PathFixture`s. Verify a new test with the plain suite path, never with a
  hand-added `addpath`; a `PathFixture` adds one folder, not a tree.
- **Never run a second MATLAB while the suite runs.** The render tests shell
  out to Quarto and Rscript, and a competing MATLAB kills that child with an
  error that looks exactly like a real failure.
- **Dialogs are driven by a timer.** A modal dialog is exercised by a `timer`
  that sets its controls and presses a button. The first `uifigure` in a
  `-batch` session takes many seconds to bring the UI framework up, so give
  the timer about 25 s, and on the driver's error path press **Cancel**
  rather than deleting the figure.
- **Never call `drawnow` right after deleting a `uifigure`** in `-batch`
  when no `uihtml` is alive: MATLAB hangs.
- A green test proves nothing until it has been seen to fail: break the code
  it guards, watch it fail, restore.
- Lint every edited file with `checkcode`.

## Documentation

Three documents, each for one audience:

| Document | Audience | Format |
|---|---|---|
| [`README.MD`](README.MD) | Someone deciding whether Alakazam is for them | Markdown |
| This guide | Contributors | Markdown |
| [The user manual](manual/manual.qmd) | Researchers using Alakazam | Quarto |

Alongside them, [`CHANGELOG.md`](CHANGELOG.md) records what changed per release.

### The manual

`manual/manual.qmd` is the book's spine: its front matter and one
`{{< include >}}` per chapter file in `manual/chapters/`. Citations are
`[@key]`, resolved from `manual/references.bib`; pictures are in
`manual/images/`, named `<tool>-dialog` and `<tool>-result` for the
transformation reference. Build it with Quarto (bundled with RStudio, or
from quarto.org); no R is needed, since the manual has no code chunks:

```
quarto render manual/manual.qmd --to html    # manual/manual.html, self-contained
quarto render manual/manual.qmd --to typst   # manual/manual.pdf
```

The PDF is typeset with Typst, which Quarto bundles, so it needs no LaTeX
installation. Its design, in the application's own colours, is the template
partial `manual/_typst/typst-template.typ`: the cover, the chapter banners
(a dialog's blue title bar over the ribbon's navy group-label strip), the
tables' navy header rows, code blocks and callouts. The fonts are Noto Sans
and Noto Mono, vendored in `manual/fonts/` under the SIL Open Font License
(see its README), so the PDF looks the same wherever it is built.

`manual/manual.pdf` is committed, so the manual can be read from a clone or
on GitHub without rendering anything: re-render it when the text changes,
and commit it with the change. The HTML is not committed (it embeds every
figure). The **Help** button shows it: `Alakazam.buildHelpPage` renders it
when it is missing or older than its sources, and copies it, adapted for the
app's viewer, to `src/AlakazamHelp.html`, which is not committed either. The
release workflow renders both again and ships them with the package.

### The pictures

Every picture in the manual is regenerated from the running application by
[`src/help/capture/captureManualImages.m`](src/help/capture/captureManualImages.m),
driven by the list in
[`manualShots.m`](src/help/capture/manualShots.m):

```matlab
addpath('src/help/capture');
captureManualImages();                                   % all of them
captureManualImages('Only', {'filter-dialog'});          % one
captureManualImages('Datasets', {'rift'});               % one dataset's
```

Each dataset's raw file is copied into a scratch workspace with its own
cache, results are computed through `TransTools.invoke` and shown through
the app's own plotter, and a dialog is caught by a timer, exported and
closed (closing is Cancel). Nothing in a real workspace is changed. The one
dataset that opens an existing workspace (the Grand Average and report
pictures) may only select nodes and open cancellable dialogs: **Data Quality
Report** has no dialog and writes a report the moment it is pressed, and the
exports open a system file picker a timer cannot reach, so neither is on the
list. The datasets are those in `DATA.md`.

### Style

- British spelling (artefact, behaviour, colour).
- No em dashes anywhere, and no double hyphens standing in for one: Quarto
  and many Markdown renderers turn `--` into a dash.
- Say what a step does and why, with the reference that justifies it;
  prefer a number measured in this code base to an assertion.

## Releases

All work happens on the **Development** branch, and releases are tagged there.
`main` trails deliberately and is brought level only when asked.

A release is two steps:

1. A commit `Bump version to Vx.y.z` changing only `VERSION_FALLBACK` in
   `src/alakazamVersion.m`, pushed to Development.
2. A tag on that commit, pushed:

   ```
   git tag -a V0.4.4 -m "Alakazam 0.4.4"
   git push origin refs/tags/V0.4.4:refs/tags/V0.4.4
   ```

Tags start with a capital **V**, which is what `.github/workflows/release.yml`
triggers on. It builds the in-app help and the manual, packages the tree
with them, and publishes the release in a few minutes.

A stray lowercase tag `v0.4.4` exists on an older commit. On a
case-insensitive file system a loose ref `refs/tags/v0.4.4` *is*
`refs/tags/V0.4.4`, so `git tag V0.4.4` fails with "already exists". Run
`git pack-refs --all` before creating a tag whose name differs from an
existing one only in case, and again after: packed refs compare names
case-sensitively.

## References

- Delorme, A., & Makeig, S. (2004). EEGLAB: an open source toolbox for
  analysis of single-trial EEG dynamics including independent component
  analysis. *Journal of Neuroscience Methods*, 134(1), 9-21.
  [doi:10.1016/j.jneumeth.2003.10.009](https://doi.org/10.1016/j.jneumeth.2003.10.009)

The full bibliography is in the manual.
