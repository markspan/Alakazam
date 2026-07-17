# Alakazam

An interactive MATLAB workbench for EEG and event-related potential (ERP)
analysis.

![Screenshot](Screenshots/ScreenShot.jpg)

## Overview

Alakazam is a desktop application for EEG researchers: it loads a recording,
lets the analyst apply a sequence of processing steps to it, and keeps the
full processing history as an explorable tree rather than a one-off script
result. It is built directly on the EEGLAB `EEG` data structure, so any
result can be handed off to the wider EEGLAB/ERPLAB ecosystem, and it
presents a "tree of datasets plus draggable transformations" workflow
inspired by commercial analysers such as BrainVision Analyzer: each
recording is a root node; every processing step (filtering, re-referencing,
epoching, artefact removal, averaging, ...) produces a new child node.

The methodological approach follows established, reproducible ERP/EEG
practice as described in Steven J. Luck's open textbook *Applied
Event-Related Potential Data Analysis* (see [References](#references)).

## Key features

- **EEGLAB-native data model.** Datasets are EEGLAB `EEG` structures, extended
  with a few Alakazam fields (`File`, `id`, `Call`, `params`, `DataType`,
  `DataFormat`) that record provenance and how each result was produced.
- **Two dataset trees with draggable, replayable transformations.** A
  "Data & Analyses" tree holds each recording as a root node with its
  analysis history as an explorable tree of child nodes; a separate "Grand
  Averages" tree holds combined results, which don't belong nested under any
  single subject. Applying a transformation to the selected dataset creates
  a new child node; dragging a processed branch onto another dataset
  re-applies the same chain of steps to it. A branch's right-click menu also
  offers **Apply to All Raw Files...**, which does the same to every other
  raw recording already in the workspace in one action, rather than
  dragging onto each one by hand. **Save Template...** exports that same
  branch as a portable `.alztemplate` file (a plain JSON list of steps,
  independent of this workspace's own cache files); **Apply Template...**,
  available on any node, replays a saved template's steps onto it -- the
  same recipe applied later, in another workspace, or after Alakazam has
  been restarted.
- **Format support.** BrainVision (`.vhdr`, via the bva-io EEGLAB plugin),
  EEGLAB `.set`, and previously-saved Alakazam `.mat` sessions. Each raw file
  is cached to `.mat` on first read and only re-parsed if the raw file is
  newer than its cache.
- **Fast visualisation of long recordings.** Continuous signals are drawn by
  a purpose-built renderer that decimates through a precomputed min/max
  pyramid, so scrolling and zooming stay smooth on multi-hour,
  multi-channel data while every spike and artefact remains visible (see
  [Fast plotting](#fast-plotting)).
- **Tabbed or tiled plot views.** Open datasets show one at a time as tabs,
  or all at once arranged in a grid or stacked column, for side-by-side
  comparison.
- **A transformation library covering the standard EEG/ERP pipeline**:
  filtering, re-referencing, channel/data selection, event-to-bin
  assignment with a small purpose-built language, baseline correction,
  trial averaging (including bin-difference/interaction contrasts),
  amplitude-threshold artefact marking, automated ICA- and GEDAI-based
  artefact removal, Fourier analysis, and scalp topography plots (see
  [Transformations](#transformations)); grand averaging across subjects is
  a separate mechanism with its own tree and dialog.
- **Session workspaces.** Working directories and the processing tree are
  saved and reloaded as a workspace.

## Architecture

A single `uifigure` hosts the whole application: a control-strip ribbon
along the top (Home/Tools/Grand Average tabs, discovering transformations
automatically), the two dataset trees on the left, and the plots area on
the right (tabbed or tiled, see above). Authored application code lives
under `src/`; third-party toolkits and shared data-file resources stay at
the repository root. See [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md) for
the full map (including which pieces are build-time-only, like the Node.js
tooling behind the tree widget) and [`dependencies.md`](dependencies.md)
for the external toolkits.

At startup the application resolves two roots from its own file location, so
it does not depend on the current working directory:

- `RootDir` is the authored source tree (`src/`), holding the transformations.
- `RepoRoot` is the repository root, holding the vendored toolkits and resources.

> The ribbon and dataset trees are custom `uihtml` components, not MathWorks'
> own Toolstrip/tree widgets: an earlier version of Alakazam docked plot
> windows into a Java-Swing desktop shell, which stopped working once modern
> MATLAB releases moved `figure()` off Java Swing entirely. See
> [`migration.md`](migration.md) for that history, if you're curious why the
> UI is built the way it is.

## Fast plotting

Continuous time-series are drawn by `SignalView`, backed by `MinMaxPyramid`.
The pyramid precomputes, once, a stack of increasingly coarse levels that
store the per-bucket minimum and maximum of the signal. A redraw then reads
about one min/max column per screen pixel from the nearest level (or the
raw samples when the visible window already fits the axis), so its cost is
independent of the recording length. Because minima and maxima compose
exactly, the decimated envelope never hides a spike or a brief artefact.
The view provides pan, zoom, and y-axis magnify controls, mouse-wheel
scrolling, channel stacking, and overlays for events and marked artefacts.

## Getting started

Requirements: MATLAB (with `uifigure`/App Designer support -- the UI is built
entirely on that component family, not the classic figure/uicontrol one), the
Signal Processing Toolbox (IIR filtering in `IIRFilter`, the taper windows in
`Fourier`) and the Statistics and Machine Learning Toolbox (used by EEGLAB and
some of its plugins), plus the external toolkits listed in
[`dependencies.md`](dependencies.md), most importantly EEGLAB. Parallel
Computing Toolbox is advised (not required) for the AutoGEDAI transformation:
its GEDAI plugin dependency uses GPU acceleration when a GPU is actually
detected, and falls back to CPU (via a small compatibility shim,
`src/Compat/gpuDeviceCount.m`, on a machine without the toolbox at all)
otherwise, so a machine without a GPU is just slower, not broken.

```matlab
% From the repository root:
startAlakazam        % adds src/ to the path and opens the application
```

`startAlakazam` adds the authored source tree to the MATLAB path and constructs
the app, which in turn adds the vendored toolkits from the repository root. On
first run, EEGLAB is initialised if it is not already on the path (the global
MATLAB path is left unchanged). At startup, `EEGLabEnvironment` also checks for
the Signal Processing and Statistics and Machine Learning toolboxes and warns
(without blocking startup) if either is missing.

## Transformations

A transformation is a small plugin in `src/Transformations/<Name>/`, consisting
of an entry function `<Name>.m`, a JSON manifest `<Name>.json` (name, section,
category, icon), and an icon. Manifests are discovered automatically and placed
in the ribbon's Tools tab, grouped by the manifest's `Section` field.

A transformation receives an `EEG` structure and returns the transformed `EEG`
together with an `options` value describing what it did. When called
interactively (from the ribbon) it may prompt the user; when called with a
previously captured `options` value (when a branch is dragged onto another
dataset) it reproduces the operation without interaction. For transformations
that wrap EEGLAB `pop_*` functions, that stored value is EEGLAB's own command
history, which is replayed with `eval`; this is a deliberate part of the plugin
system rather than an oversight.

```matlab
function [EEG, options] = SelectData(input, opts)
% Example transformation that wraps an EEGLAB function.
% Returns the transformed EEG and an options value the function understands.

    if nargin < 1
        error("Alakazam:SelectData", "No data supplied");
    end

    if nargin == 1
        options = "Init";   % interactive call from the ribbon
    else
        options = opts;     % re-apply a previously captured operation
    end

    EEG = input;

    if ischar(options) || isstring(options)
        if strcmpi(options, "Init")
            % Interactive: EEGLAB returns the command history as options.
            [EEG, options] = pop_select(input);
        end
    else
        % Re-apply: replay the captured EEGLAB command on this EEG.
        eval(options.Param);
    end
end
```

The current library:

| Transformation | Does |
|---|---|
| `IIRFilter` | IIR (Butterworth) low-pass/high-pass/band-stop filtering, per channel or globally. |
| `ReRef` | Re-references the data (wraps `pop_reref`). |
| `SelectData` | Channel and/or time-range selection (wraps `pop_select`). |
| `DefineBins` | Assigns events to ERP bins with a small, purpose-built event-selection language -- see [`bin_language.md`](src/Transformations/DefineBins/bin_language.md) for the full reference. Replaces the ERPLAB EVENTLIST + BINLISTER step. |
| `Baseline` | Baseline-corrects epoched data. |
| `Average` | Averages one dataset's epoched trials into an ERP, including bin-difference/interaction contrast bins (see `bin_language.md` §11-12). |
| `ArtefactDetect` | Flags epochs exceeding an absolute amplitude threshold. |
| `AutoEyeICA` | Runs ICA, classifies components with ICLabel, and automatically removes eye components above a probability threshold. |
| `AutoGEDAI` | Denoises with GEDAI (generalized eigenvalue decomposition against a leadfield reference; Ros et al., 2025). |
| `Fourier` | FFT-based frequency-domain analysis, with windowing and resolution options. |
| `ScalpDistribution` | Scrubbable scalp-topography plot of an averaged ERP over a time window. |
| `Measure` | Quantifies ERP components in named time windows -- mean amplitude; peak amplitude + latency (absolute or local peak); area (signed / rectified / positive / negative, over the whole window or a peak-locked band); and fractional peak / area latency (e.g. 50% area latency) -- on a subject Average or a Grand Average, with an optional per-window baseline and optionally locked to a reference channel's found peak. Derived channels can be defined inline with `let` statements (e.g. `let LRP = C3 - C4`), appended to the dataset so they also show on the ERP plot and in grand averages. See [`measure.md`](src/Transformations/Measure/measure.md) for the full reference and [Measurement export](#measurement-export). |

Grand averaging (combining several subjects' `Average` results into one) is
a separate mechanism, not a transformation plugin: it has its own ribbon tab
and dialog (`GrandAverage.m`/`GrandAverageDialog.m`) and lands in the
"Grand Averages" tree rather than nested under any one subject's branch
(see [Key features](#key-features)).

## Measurement export

`Measure` turns a window on a waveform into a number: define one or more
named windows (a table editor, add/remove rows) and it computes each one's
value per bin and channel, stored on the result as `EEG.measurements`. The
dialog's own **Save.../Load...** (matching `DefineBins`' own Save/Load pair)
saves the table's current rows to a portable `.alm` JSON file, so a
window set can be reused across dialogs, workspaces, or shared with a
colleague, independent of any one dataset's Recalculate history. Because it
is an ordinary transformation, a whole
`raw -> filter -> epoch -> baseline -> artefact-reject -> average -> measure`
pipeline can be defined once and replayed across a study with Apply to All
Raw Files or a saved template (see [Key features](#key-features)) -- no need
to re-run Measure by hand on every subject.

The **Measurements** ribbon tab's **ERP** export button walks the whole
workspace (every subject branch and every Grand Average, in either tree) for
a Measure result and writes one long-format, R-compatible CSV: one row per
dataset x window x bin x channel x measure type (`mean_amplitude`,
`peak_amplitude`, `peak_latency`, `area_signed` / `area_rectified` /
`area_positive` / `area_negative`, `fractional_peak_latency`,
`fractional_area_latency` -- a measure that yields several values, such as Peak
or a peak-locked Area, contributes one row per value, so the CSV's own `value`
column stays uniformly numeric).
The same bulk-export-everything idea as **Export Grand Averages...** (see
[`exportGrandAveragesCSV.m`](src/exportGrandAveragesCSV.m)), implemented in
[`exportMeasurementsCSV.m`](src/exportMeasurementsCSV.m). The full window/
measure reference, with worked examples, is
[`measure.md`](src/Transformations/Measure/measure.md).

![ScreenshotERP](Screenshots/ERP.jpg)

![ScreenshotScalp](Screenshots/ScalpDistribution.jpg)

![ScreenshotEpoched](Screenshots/Epoched.jpg)

![ScreenshotTF](Screenshots/TimeFrequency.jpg)

## Frequency analysis (frequency tagging / RIFT)

The **Spectral Measure** transform is the frequency-domain counterpart of ERP
Measure: it quantifies steady-state / frequency-tagging responses -- SSVEP, and
Rapid Invisible Frequency Tagging (RIFT). It runs on epoched, single-trial data.

Declare the tagging fundamentals (`let f1 = 60`, `let f2 = 64`) and name each
frequency of interest as an expression over them: the fundamental (`f1`), a
harmonic (`2*f1`), or an intermodulation term (`f1+f2`, `2*f1-f2`). For every
frequency x channel x bin it computes the complex Fourier coefficient directly
at that exact frequency (a tapered single-frequency DFT, Hann or DPSS
multitaper, so harmonic / intermodulation terms off the `fs/N` grid are still
exact), and reports:

- **power / amplitude** of the trial-averaged (evoked) response and its **SNR**
  against the neighbouring frequency bins -- the amplitude-based SSVEP read-out
  used to track, for example, attentional modulation of the tagged response
  (Toffanin et al., 2009);
- **inter-trial phase-locking** (how consistently the response tracks the
  flicker across trials); and
- against an optional reference channel such as a **photodiode** recording the
  flicker, the **magnitude-squared coherence** and phase-lag between that
  reference and each EEG channel. This is the standard RIFT cross-coherence:
  the trial-wise complex cross-spectra are averaged and normalised by the
  trial-averaged autospectra, then squared -- exactly the read-out used to
  reveal tagging responses in Dimigen et al. (2025) (see
  [References](#references)).

The reference is optional (not every recording has a photodiode), so power /
SNR / phase-locking are always available and coherence is added when a
reference is set. Results export to one long-format, R-compatible CSV via the
Measurements tab's **Spectral** button
([`exportSpectralCSV.m`](src/exportSpectralCSV.m)); like any transformation, a
whole tagging pipeline can be replayed across a study with Apply to All Raw
Files or a saved template. The full reference is the
[`SpectralMeasure.m`](src/Transformations/SpectralMeasure/SpectralMeasure.m)
header.

## How-to walkthroughs

Three worked pipelines. Each is an ordinary chain of transformations, so once
built on one recording it replays across a whole study in one click with **Apply
to All Raw Files** (a branch's right-click menu) or a saved template. The marker
codes below (`"S2?"`, `"201"`, ...) are placeholders: substitute the ones your
recording actually used. Ready-made measurement windows live in
[`presets/`](src/Transformations/Measure/presets) (the Measure dialog's
**Load...** button); the full measure reference is
[`measure.md`](src/Transformations/Measure/measure.md).

The examples lean on the [`DefineBins`](src/Transformations/DefineBins) language,
which is worth knowing a little of, because it is what makes each design precise:

- **`let name = ...`** names a code or relation once so bins stay readable.
- **Wildcards and sets**: `"S2?"` matches any `S2x` marker; `a|b` or `{a b}` is a
  set of alternatives.
- **Relations**: `next(code) within (lo,hi] ms` (also `prev`, `adjacent`, `any`)
  constrains a neighbouring event; the window is signed and gates reaction time.
- **`... rt within (lo,hi] ms`** keeps a match only if its RT is in range.
- **`... timelock <relation>`** re-centres the epoch on a neighbour (e.g. the
  response) instead of the anchor: this is how a bin defined on the *stimulus*
  becomes *response-locked* (used by the LRP below).
- **Combination bins** take coefficients: `bin 3 = 0.5 bin 2 - 0.5 bin 1`.

### How to do a P300 analysis (oddball)

The P300 is a large centro-parietal positivity, 300 to 600 ms, to rare target
stimuli. Stimulus-locked.

1. **Filter** the raw recording (`IIRFilter`, e.g. 0.1 to 30 Hz).
2. **DefineBins**, splitting rare targets from frequent standards and adding the
   oddball difference wave. Here the rare bin also requires the participant to
   have actually responded, in a plausible RT window, so misses and slow lapses
   are excluded; the epoch stays **stimulus-locked** (no `timelock`, the
   deliberate contrast with the LRP below):

   ```
   epoch [-200,800] ms
   let responded = next("201") within (200,1200] ms
   bin 1 "Rare"       : "S2?" and responded
   bin 2 "Frequent"   : "S1?"
   bin 3 "Rare-Freq"  = bin 1 - bin 2
   ```

   `"S2?"` is any rare-target marker and `"S1?"` any frequent one (wildcards);
   `responded` names "a button press 200 to 1200 ms after the stimulus".
3. **Baseline** to the pre-stimulus interval (-200 to 0 ms), then
   **ArtefactDetect** to reject bad trials.
4. **Average**.
5. **Measure**: Load the `p300` preset (Pz, 300 to 600 ms, mean amplitude), or
   the `erp_components_mean_amplitude` battery. Read the `Rare` bin for the P300
   itself, and the `Rare-Freq` bin for the oddball effect.
6. **Grand Average** across subjects, then export for one long-format CSV (the
   **Measurements** ribbon tab's **ERP** button).

### How to do an LRP analysis (response-locked)

The lateralised readiness potential is the motor-cortex difference between the
hands, building up before the response. It is a **double subtraction**:
contralateral minus ipsilateral, averaged over left- and right-hand responses.
Response-locked.

1. **Filter** the raw recording.
2. **DefineBins**. This is the crux, and it shows off the language. Each bin is
   *defined on the imperative stimulus* (which holds the trial's condition), but
   `timelock`-ed onto the button press so the epoch is **response-locked** (time
   0 = the press). Split by the hand actually used, then form the coefficiented
   combination bin for the double subtraction:

   ```
   epoch [-800,200] ms
   let leftPress  = next("201") within (150,1500] ms
   let rightPress = next("202") within (150,1500] ms
   bin 1 "Left-hand"  : "S1?" and leftPress   timelock leftPress
   bin 2 "Right-hand" : "S1?" and rightPress  timelock rightPress
   bin 3 "LRP"        = 0.5 bin 2 - 0.5 bin 1
   ```

   Reading it: `"S1?"` is any imperative stimulus (the condition the bin holds);
   `leftPress` / `rightPress` name the left (`"201"`) and right (`"202"`) button
   presses once, gated to a 150 to 1500 ms RT window so anticipations and misses
   drop out; `and leftPress` keeps only stimuli followed by that press;
   `timelock leftPress` then re-centres each epoch on the press even though the
   bin is anchored at the stimulus. `next(...)` picks the nearest following
   press, so as long as trials are seconds apart it is the trial's own response.
   Bins 1 and 2 therefore contain the left- and right-hand trials, response-
   locked; `bin 3` is the double subtraction.
3. **Average**.
4. **Measure**: define the motor difference as a derived channel in the
   **Derived channels** field, and measure it on the `LRP` bin:

   ```
   let LRP = C3 - C4
   ```

   with one window (Load the `lrp` preset as a starting point, then set its
   Channels to `LRP`): -100 to 0 ms, mean amplitude, channel `LRP`. Read the
   `LRP` bin (bin 3). This appends an `LRP` channel to the dataset, so it also
   shows on the ERP plot. (Why `0.5 bin 2 - 0.5 bin 1` on `C3 - C4` is exactly
   the LRP: on `C3 - C4`, a right-hand response gives contra minus ipsi and a
   left-hand response its negation, so half their difference is the mean over
   hands of contra minus ipsi.) LRP **amplitude** is straightforward this way;
   LRP **onset latency** wants a jackknife across subjects, which is not yet
   built in.

### How to do an MMN analysis (passive auditory oddball)

The mismatch negativity is a fronto-central negativity, 150 to 250 ms, seen in
the deviant-minus-standard difference wave. Stimulus-locked, attention not
required.

1. **Filter** the raw recording (a low-pass around 20 to 30 Hz is common for
   MMN).
2. **DefineBins**, forming the deviant-minus-standard difference wave (the MMN is
   defined on this difference, not the raw deviant). For a cleaner contrast, the
   control standard here is not just any standard but the one **immediately
   before each deviant**, via `adjacent`, which matches adaptation and serial
   position between the two bins. MMN is passive, so there is no response and no
   `timelock`:

   ```
   epoch [-100,400] ms
   let standard = "S1"
   let deviant  = "S2"
   bin 1 "Deviant"        : deviant
   bin 2 "Std before dev" : standard and adjacent(deviant)
   bin 3 "MMN"            = bin 1 - bin 2
   ```

   `adjacent(deviant)` is true when the event's immediately following event is a
   deviant, so `bin 2` collects exactly the standards that directly precede a
   deviant.
3. **Baseline** to the pre-stimulus interval (-100 to 0 ms), then
   **ArtefactDetect**.
4. **Average**.
5. **Measure**: Load the `mmn` preset (Fz, 150 to 250 ms, mean amplitude,
   negative), and read the `MMN` difference bin (bin 3) at Fz.
6. **Grand Average**, then export via the **Measurements** tab's **ERP** button.

## References

Scientific/methodological:

- Luck, S. J. *Applied Event-Related Potential Data Analysis*. LibreTexts.
  [socialsci.libretexts.org](https://socialsci.libretexts.org/Bookshelves/Psychology/Biological_Psychology/Applied_Event-Related_Potential_Data_Analysis_(Luck)).
  DOI: [10.18115/D5QG92](https://doi.org/10.18115/D5QG92). Licensed CC BY 4.0.
  A practical, EEGLAB/ERPLAB-based reference for the preprocessing, averaging, and
  scoring steps that Alakazam's transformations implement.
- Lopez-Calderon, J., & Luck, S. J. (2014). ERPLAB: an open-source toolbox for
  the analysis of event-related potentials. *Frontiers in Human Neuroscience*,
  8, 213. [erpinfo.org/erplab](https://erpinfo.org/erplab). The methodological
  model for `DefineBins` (event-to-bin assignment, replacing EVENTLIST +
  BINLISTER), `Average`'s contrast-bin handling, and `GrandAverage`'s
  weighted grand-average option; not a runtime dependency, ERPLAB itself is
  not called.
- Toffanin, P., de Jong, R., Johnson, A., & Martens, S. (2009). Using frequency
  tagging to quantify attentional deployment in a visual divided attention
  task. *International Journal of Psychophysiology*, 72(3), 289-298. DOI:
  [10.1016/j.ijpsycho.2009.01.006](https://doi.org/10.1016/j.ijpsycho.2009.01.006).
  The amplitude-based SSVEP read-out `SpectralMeasure` implements (power / SNR
  at the tagging frequency, modulated by attention).
- Dimigen, O., Badea, I., Simon, I., & Span, M. M. (2025). Rapid Invisible
  Frequency Tagging (RIFT) with a consumer monitor: A proof-of-concept.
  *bioRxiv*. DOI:
  [10.1101/2025.08.14.670287](https://doi.org/10.1101/2025.08.14.670287). The
  cross-coherence read-out `SpectralMeasure` implements: magnitude-squared
  coherence between a photodiode and each EEG channel, from trial-wise cross-
  spectra normalised by the trial-averaged autospectra.
- Ros, T., et al. (2025). GEDAI: generalized eigenvalue decomposition for
  automated EEG artefact removal.
  [github.com/neurotuning/GEDAI-master](https://github.com/neurotuning/GEDAI-master).
  Used by the `AutoGEDAI` transformation.
- Pion-Tonachini, L., Kreutz-Delgado, K., & Makeig, S. (2019). ICLabel: An
  automated electroencephalographic independent component classifier,
  dataset, and website. *NeuroImage*, 198, 181-197. Used by `AutoEyeICA` to
  classify and remove eye components.
- Hyvärinen, A., & Oja, E. (2000). Independent component analysis:
  algorithms and applications. *Neural Networks*, 13(4-5), 411-430. FastICA,
  [research.ics.aalto.fi/ica/fastica](https://research.ics.aalto.fi/ica/fastica/).
  Used by `AutoEyeICA` when installed (falls back to `pop_runica`'s own
  default algorithm otherwise).
- Delorme, A., & Makeig, S. (2004). EEGLAB: an open source toolbox for
  analysis of single-trial EEG dynamics. *Journal of Neuroscience Methods*,
  134(1), 9-21. [sccn.ucsd.edu/eeglab](https://sccn.ucsd.edu/eeglab/index.php).
  The data structure and plugin ecosystem (including the bva-io BrainVision
  import plugin and ICLabel above) Alakazam is built on.
- BrainVision Analyzer, the commercial analyser whose interaction model
  inspired Alakazam.
  [brainproducts.com](https://www.brainproducts.com/promo_analyzer2.php).

Software toolkits (see [`dependencies.md`](dependencies.md) for the complete,
versioned list):
- MATLAB Toolstrip / ToolGroup demo by R. Chen.
  [undocumentedmatlab.com](http://undocumentedmatlab.com/articles/matlab-toolstrip-part-2-toolgroup-app).
  Historical: the app shell this originally adapted has since been replaced by
  a single `uifigure` with a custom `uihtml` ribbon (see
  [Architecture](#architecture) and [`migration.md`](migration.md)); kept here
  as a credit to the original adapted code, not a description of the current UI.

## Repository

Source, issues, and contributions:
[github.com/markspan/Alakazam](https://github.com/markspan/Alakazam). Alakazam is
a work in progress and contributions are welcome.

## License

See [LICENSE](LICENSE) (GPL).
