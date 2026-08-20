# Alakazam

An interactive MATLAB workbench for EEG and event-related potential (ERP)
analysis.

![Screenshot](Screenshots/ScreenShot.jpg)

## Overview

Alakazam is a desktop application for EEG researchers: it loads a recording,
lets the researcher apply a sequence of processing steps to it, and keeps the
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
  available on any dataset node, replays a saved template's steps onto it:
  the same recipe applied later, in another workspace, or after Alakazam
  has been restarted. (Not offered on a rendered report node in the
  Reports tree, see [Statistical analysis](#statistical-analysis) -- a
  report has none of the real dataset fields a transformation expects.)
- **Format support.** BrainVision (`.vhdr`, via the bva-io EEGLAB plugin),
  EEGLAB `.set`, ERPLAB erpsets (`.erp`, read directly as an already-averaged
  root dataset, no ERPLAB installation required, see `erpsetToAveraged`),
  and previously-saved Alakazam `.mat` sessions. Each raw file is cached to
  `.mat` on first read and only re-parsed if the raw file is newer than its
  cache. Any Averaged dataset's right-click menu offers **Export ERPset...**,
  the reverse conversion (`averagedToErpset`), to hand a result back to
  ERPLAB.
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
  artefact removal, Fourier analysis, and scalp topography plots, including
  a rotatable 3D brain view with an optional real MNE source estimate (see
  [Transformations](#transformations) and [3D brain view](#3d-brain-view));
  grand averaging across subjects is a separate mechanism with its own tree
  and dialog.
- **Design-aware statistical reporting.** Exporting ERP or Spectral Measure
  results also writes a companion Quarto/R report to a persistent Reports
  folder: one statistical test per window/frequency and measure type,
  chosen to fit the actual design -- within-subjects (descriptive
  statistics, a paired test, or a linear mixed model for 3+ conditions),
  between-subjects or mixed once subjects are assigned to groups via
  **Grouping...** (a Welch *t*-test/ANOVA, or a linear mixed model with a
  condition x group interaction), or a one-sample test against zero for a
  difference bin -- every *t*-test-family comparison also backed by a
  Bayes Factor and a bootstrapped effect-size confidence interval as a
  robustness check, with APA-styled tables, violin plots, and a closing
  forest plot of every effect size in the report. It is a real,
  human-editable Quarto document underneath, not a fixed template (see
  [Statistical analysis](#statistical-analysis)).
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

Requirements: MATLAB (with `uifigure`/App Designer support: the UI is built
entirely on that component family, not the classic figure/uicontrol one), the
Signal Processing Toolbox (used by the `Filter` transform and the taper windows in
`Fourier`) and the Statistics and Machine Learning Toolbox (used by EEGLAB and
some of its plugins), plus the external toolkits listed in
[`dependencies.md`](dependencies.md), most importantly EEGLAB. Parallel
Computing Toolbox is advised (not required) for the AutoGEDAI transformation:
its GEDAI plugin dependency uses GPU acceleration when a GPU is actually
detected, and falls back to CPU (via a small compatibility shim,
`src/Compat/gpuDeviceCount.m`, on a machine without the toolbox at all)
otherwise, so a machine without a GPU is just slower, not broken.
[FieldTrip](https://www.fieldtriptoolbox.org/) is an optional, larger
(~400 MB) dependency needed only for `Brain3D`'s Source-estimate mode (see
[3D brain view](#3d-brain-view)); it downloads on first use of that mode,
after an explicit consent prompt, not at startup.

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
together with an `options` struct describing what it did. When called
interactively (from the ribbon) it prompts the user and remembers the chosen
`options` (`TransformSettings`) for next time; when called with a previously
captured `options` struct (dragging a branch onto another dataset, **Apply to
All Raw Files...**, or replaying a saved template) it reproduces the operation
without interaction, via a direct `feval(transformId, EEG, options)` call:
plain data, not a parsed or `eval`'d command string. Every transformation opens
with the same `nargin`/`'Init'`-sentinel guard,
[`TransTools.InitGuard`](src/Transformations/+TransTools/InitGuard.m).

```matlab
function [EEG, options] = SelectData(input, varargin)
% Example transformation (trimmed from the real SelectData.m).
% Returns the transformed EEG and an options struct the function understands.

    [opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:SelectData', varargin{:});
    if interactive
        % Interactive: prompt for options, remember them for next time.
        options = SelectDataDialog(input.chanlocs);
        if isempty(options)
            EEG = [];   % cancelled, no node, no compute
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

The current library:

| Transformation | Does |
|---|---|
| `Filter` | FIR windowed-sinc, zero-phase high-pass / low-pass / notch filtering (EEGLAB's `firfilt`, Kaiser window). Each filter is set by just a frequency and a dB rating (stopband attenuation); the filter order, transition band and window are chosen automatically. |
| `ChannelEditor` | Edit channel labels, types and locations. |
| `ReRef` | Re-references the data (wraps `pop_reref`). |
| `SelectData` | Channel and/or time-range selection (wraps `pop_select`). |
| `Interpolate` | Interpolates bad channels. |
| `Resample` | Changes the sampling rate of continuous data. |
| `DefineBins` | Assigns events to ERP bins with a small, purpose-built event-selection language: see [`bin_language.md`](src/Transformations/DefineBins/bin_language.md) for the full reference. Replaces the ERPLAB EVENTLIST + BINLISTER step. |
| `Baseline` | Baseline-corrects epoched data. |
| `Average` | Averages one dataset's epoched trials into an ERP, including bin-difference/interaction contrast bins (see `bin_language.md` §11-12). |
| `ArtefactDetect` | Flags epochs exceeding an absolute amplitude threshold. |
| `RemoveComponents` | Manually subtracts ICA components chosen by hand. Shown in the ribbon as "ICA". |
| `AutoEyeICA` | Runs ICA, classifies components with ICLabel, and automatically removes eye components above a probability threshold. |
| `AutoGEDAI` | Denoises with GEDAI (generalized eigenvalue decomposition against a leadfield reference; Ros et al., 2025). |
| `Fourier` | FFT-based frequency-domain analysis, with windowing and resolution options. |
| `ScalpDistribution` | Scrubbable scalp-topography plot of an averaged ERP over a time window. |
| `Brain3D` | The same scrubbable ERP, projected onto a rotatable 3D brain surface, either as a scalp-topography projection (default) or a real MNE source estimate (see [3D brain view](#3d-brain-view)). |
| `Measure` | Quantifies ERP components in named time windows: mean amplitude; peak amplitude + latency (absolute or local peak); area (signed / rectified / positive / negative, over the whole window or a peak-locked band); and fractional peak / area latency (e.g. 50% area latency), on a subject Average or a Grand Average, with an optional per-window baseline and optionally locked to a reference channel's found peak. Derived channels can be defined inline with `let` statements (e.g. `let LRP = C3 - C4`), appended to the dataset so they also show on the ERP plot and in grand averages. Shown in the ribbon as "ERP Measure". See [`measure.md`](src/Transformations/Measure/measure.md) for the full reference, [Measurement export](#measurement-export) and [Statistical analysis](#statistical-analysis). |
| `TimeFrequency` | Wavelet time-frequency analysis: a per-bin, channel-stepped heatmap of event-related spectral power change relative to a pre-stimulus baseline (ERSP, dB). |
| `SpectralMeasure` | Quantifies frequency-tagging / SSVEP / RIFT responses at named frequencies (a fundamental, its harmonics, or intermodulation terms): power, SNR, inter-trial phase-locking, and, against an optional photodiode reference, coherence and phase-lag, per channel and bin; batch-exported via the Export/Report tab's **Spectral & Report** button. Shown in the ribbon as "Spectral Measure". See [Frequency analysis](#frequency-analysis-frequency-tagging--rift). |
| `CoherenceMap` | Time-resolved coherence of every channel to a reference (e.g. a photodiode) as a per-channel time x frequency heatmap, via a Morlet wavelet or a fixed-window STFT: the RIFT-figure view (Dimigen et al., 2025). Shown in the ribbon as "Coherence Map". |
| `CoherenceTopography` | Scalp head-map of every channel's coherence to a reference (e.g. a photodiode) per bin, at the reference's auto-detected tagging frequency. Shown in the ribbon as "CohTopo". |

Grand averaging (combining several subjects' `Average` results into one) is
a separate mechanism, not a transformation plugin: it has its own ribbon tab
and dialog (`GrandAverage.m`/`GrandAverageDialog.m`) and lands in the
"Grand Averages" tree rather than nested under any one subject's branch
(see [Key features](#key-features)).

## 3D brain view

`Brain3D` opens the same scrubbable, per-bin averaged ERP as
`ScalpDistribution`, but drawn on a rotatable 3D brain (click-and-drag to
orbit) instead of a flat 2D topoplot, with a **Projection** dropdown
choosing how the data is drawn:

- **Scalp topography** (the default) is the same spherical-spline
  interpolation `ScalpDistribution`'s flat topoplot uses, projected onto a
  brain-shaped surface (a BrainNet Viewer ICBM152 mesh) purely for
  legibility. It is **not source-localized**: the colour scale is the
  measured scalp voltage itself (µV, signed, symmetric about zero), exactly
  as in the flat 2D plot.
- **Source estimate (MNE)** is a real inverse computation: a
  Tikhonov-regularized minimum-norm estimate, noise-normalized dSPM-style
  (Dale et al., 2000, see [References](#references)), using
  [FieldTrip](https://www.fieldtriptoolbox.org/)'s template BEM head model,
  template 10-5 electrode positions, and a template cortical-sheet source
  model, drawn directly on that cortical surface. Selecting it the first
  time prompts to download FieldTrip (about 400 MB, one time, opt-in, see
  [`dependencies.md`](dependencies.md)); switching into it, or onto a bin
  not yet computed, takes a moment longer than scalp mode while the
  leadfield/inverse is built (cached afterwards per channel set/bin).

  **Its colour scale looks nothing like scalp mode's, on purpose.** dSPM
  normalization corrects raw minimum-norm's bias toward superficial
  sources and turns the result into a statistic, approximately "how many
  noise standard deviations above baseline", comparable *across* source
  locations, which raw dipole-moment magnitude is not. It is still **not**
  on a µV-like physical scale, so the colorbar is labelled "dSPM
  (noise-normalized)", not an amplitude; do not compare its numbers to
  scalp mode's µV scale. One further simplification worth knowing: the
  assumed noise covariance behind both the regularization and the dSPM
  normalization itself is a scaled identity, not an independently
  estimated one, since Alakazam's pipeline runs on already-averaged ERPs,
  with no single-trial baseline available at this stage to estimate a real
  noise covariance from (see
  [`ComputeSourceEstimate.m`](src/Transformations/+TransTools/ComputeSourceEstimate.m)
  for the full derivation).

  **This is template-based, not a per-subject localization.** No
  per-subject MRI or digitised electrode positions are used (same "10-5
  template by channel label" approach the rest of Alakazam uses for scalp
  topography): a real inverse computation, more physiologically grounded
  than the scalp-topography projection, but still an approximation.

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
Raw Files or a saved template (see [Key features](#key-features)), no need
to re-run Measure by hand on every subject.

The **Export/Report** ribbon tab's **ERP & Report** button walks the whole
workspace (every subject branch and every Grand Average, in either tree) for
a Measure result and writes one long-format, R-compatible CSV: one row per
dataset x window x bin x channel x measure type (`mean_amplitude`,
`peak_amplitude`, `peak_latency`, `area_signed` / `area_rectified` /
`area_positive` / `area_negative`, `fractional_peak_latency`,
`fractional_area_latency`; a measure that yields several values, such as Peak
or a peak-locked Area, contributes one row per value, so the CSV's own `value`
column stays uniformly numeric), plus a `group` column (see
[Groups](#groups-setting-up-a-between-subjects-or-mixed-design), blank unless
subjects have been assigned one).
The same bulk-export-everything idea as **Export Grand Averages...** (see
[`exportGrandAveragesCSV.m`](src/IO/exportGrandAveragesCSV.m)), implemented in
[`exportMeasurementsCSV.m`](src/IO/exportMeasurementsCSV.m). The full window/
measure reference, with worked examples, is
[`measure.md`](src/Transformations/Measure/measure.md). The same button also
renders a companion statistical report, see
[Statistical analysis](#statistical-analysis).

![ScreenshotERP](Screenshots/ERP.jpg)

![ScreenshotScalp](Screenshots/ScalpDistribution.jpg)

![ScreenshotEpoched](Screenshots/Epoched.jpg)

![ScreenshotTF](Screenshots/TimeFrequency.jpg)

## Statistical analysis

Exporting Measure or Spectral Measure results (the **Export/Report** ribbon
tab's **ERP & Report** and **Spectral & Report** buttons, see
[Measurement export](#measurement-export) and
[Frequency analysis](#frequency-analysis-frequency-tagging--rift)) writes a
companion [Quarto](https://quarto.org/) report, alongside a private copy of
its own CSV so the report stays reproducible even if the original export is
later overwritten, both saved into a dedicated **Reports** folder inside the
workspace's Exports directory. Unlike an ordinary export, a rendered report
is not a one-off file to go hunting for: it gets its own node in a third
workspace tree (**Reports**, alongside **Data & Analyses** and **Grand
Averages**), which survives closing and reopening the workspace, and an
**Open in browser** button for viewing it with full styling (the app's own
embedded viewer is a narrower, older browser than a real one, so long tables
and a sticky table of contents render better outside it). Rendering
(`quarto render <name>.qmd`, self-contained HTML) produces a short,
APA-styled results report, not just a table: tables in three-line APA
format, violin plots showing the actual distribution rather than just a bar
and an error bar, and narrative prose ("A linear mixed model revealed a
significant effect of bin, *F*(2, 18) = 6.4, *p* = .008, ...").

### What gets tested, and what question it answers

The report is design-aware: it is built at generation time in MATLAB, where
the actual bin structure (`EEG.bindesc`) and, once assigned, each subject's
between-subjects group (see [Groups](#groups-setting-up-a-between-subjects-or-mixed-design)
below) are both still known -- neither is recoverable from the flat CSV
alone -- so it can choose the statistical test each window/frequency x
measure-type combination actually calls for, rather than one generic script
re-discovering the design at runtime. One section per window (ERP) or named
frequency (Spectral) x measure type:

| Design | Test(s) | Question it answers |
|---|---|---|
| One ordinary bin | Descriptive statistics only | What is this measure's mean/SD? (no comparison is possible with one condition) |
| Two ordinary bins | Paired *t*-test + Cohen's *dz* (bootstrapped CI) + Bayes Factor, Wilcoxon signed-rank robustness check, Shapiro-Wilk normality note | Does this measure differ between the two conditions, within subjects? |
| Three or more ordinary bins | Linear mixed model (subject random intercept + slope for bin, falling back to intercept-only if that fails to converge) + partial eta-squared with CI + Holm-corrected model-based pairwise contrasts (`emmeans`), Friedman test robustness check | Does this measure differ across conditions, within subjects -- using every subject's available bins even if one is missing for them? Which specific pairs of conditions differ? |
| One ordinary bin, **2 groups** assigned | Independent-samples Welch *t*-test + Cohen's *d* (bootstrapped CI) + Bayes Factor, Mann-Whitney *U* robustness check | Does this measure differ **between** the two groups (e.g. patients vs. controls)? |
| One ordinary bin, **3+ groups** assigned | Welch's ANOVA + Games-Howell pairwise comparisons | Does this measure differ between the groups? Which pairs of groups differ? |
| Two or more ordinary bins, **groups** assigned | Linear mixed model with a condition x group interaction (same random-effects/fallback logic as above) + partial eta-squared with CI + Holm-corrected within-group and between-group pairwise comparisons (`emmeans`) | Does the **condition effect itself differ between groups** (the interaction -- usually the actually-interesting question in a mixed design)? Plus: is there a main effect of condition, or of group, on its own? |
| Combination/difference bin (amplitude, area, power, SNR, ITC, coherence, ...) | One-sample *t*-test (+ Wilcoxon) against zero, Cohen's *dz* (bootstrapped CI) + Bayes Factor | Is this effect (a priming effect, an oddball effect, ...) actually present? |
| Combination/difference bin, a **latency** (peak, fractional peak, fractional area) | Descriptive statistics only | (latency has no natural zero to test *against* -- see below) |
| Combination/difference bin, a **circular** quantity (phase, phaselag) | Descriptive statistics only | (an angle wrapping at &plusmn;&pi; is not valid for an ordinary linear test -- see below) |
| Combination/difference bin (amplitude/area/power/...), **groups** assigned | One-sample test **within each group** + independent-samples test of the difference score **between groups**, each with Cohen's *d*/*dz* (bootstrapped CI) + Bayes Factor | Does the effect exist within each group? Does the effect's **size** differ between groups (e.g. "is the priming effect different in patients than in controls")? |
| Combination/difference bin, a **latency**, **groups** assigned | Independent-samples test **between groups** only (still no vs.-zero test) | Does the effect's *timing* differ between groups? |
| Combination/difference bin, **circular**, **groups** assigned | Descriptive statistics only, per group | (still no linear test is valid, one-sample or between-groups) |

The 3+-bin and mixed-design rows deliberately use a **linear mixed model**
(`lme4`/`lmerTest`), not a repeated-measures or split-plot ANOVA: the LMM's
whole point here is that a subject missing one bin still contributes their
other bins to the fit, instead of being listwise-dropped from the entire
channel the way a classic RM-ANOVA would drop them. A maximal model (random
intercept **and** slope per subject) is tried first and falls back to a
random-intercept-only model, narrated in the report, if the maximal one
fails to converge to a non-singular fit -- typically too few
subjects/observations for that many random parameters. The 3+-group
between-subjects row uses **Welch's ANOVA + Games-Howell**, not classic
ANOVA + Tukey, for the same reason the paired/between tests already default
to Welch over Student's *t*: it does not assume equal variances between
groups, which real between-subjects EEG samples rarely satisfy exactly.

A combination bin's own test is always kept separate from the omnibus test
over the ordinary bins above it, even when both are in the same report: its
scores are a linear combination of the other bins' scores, not an
independent condition, so folding it into the same model would be
statistically invalid. A **latency** has no natural "zero" to test *against*
(zero would mean "no difference" for an amplitude; it means nothing of the
kind for a point in time), which is why it drops the one-sample test but
keeps the between-groups one -- a latency is still an ordinary linear
quantity, groups can still be validly compared on it. A **circular**
quantity (phase/phaselag, an angle wrapping at &plusmn;&pi; radians) drops
*every* test, one-sample and between-groups alike, since neither is valid
for circular data without dedicated circular-statistics machinery this
generator does not have.

Every *t*-test-family comparison in the table above (paired, one-sample-vs-
zero, independent 2-group, and the within-/between-group combo-bin
variants) is also backed by a Bayes Factor (`BayesFactor::ttestBF`) as an
added robustness check alongside its Wilcoxon/Mann-Whitney/Friedman
equivalent, and every Cohen's *d*/*dz* effect size carries a bootstrapped
(BCa, 200 resamples) confidence interval, not just a point estimate. The
omnibus LMM tests report partial eta-squared with a genuine confidence
interval (`effectsize::F_to_eta2`, via the model's F-statistic) instead of
marginal R^2 for exactly this reason -- R^2 alone has no CI to plot.

Every section's own key test result also feeds one final cross-report
summary table, Benjamini-Hochberg (BH/FDR) corrected across every channel,
window/frequency and measure-type test the whole export produced, not just
within one section's own pairwise comparisons, plus a closing **forest
plot** (effect size + CI, faceted by effect-size type since Cohen's *d* and
partial eta-squared are different scales) so every effect in the report can
be compared at a glance, not just read off one table at a time. Each
channel's own analysis runs inside its own error boundary, so an edge case
on one channel (too few usable subjects for a normality check, missing data
for that channel only, ...) is reported for that one channel alone and does
not stop the rest of the report from rendering.

### Groups: setting up a between-subjects or mixed design

Every design starts out within-subjects: every bin/condition is assumed to
be measured on every subject, matched by `dataset` in the CSV. To ask a
between-subjects question instead ("do patients and controls differ"),
assign each subject to a group first, via **Grouping...** (the Home ribbon
tab's own **Design** group) -- the "Edit Subjects" dialog: one row per
subject -- every root node in the Data & Analyses tree -- with a free-text
**Group** label; leave it blank for "no group". A subject left blank is
excluded from every group-based test (with a count and a reason in the
rendered report), but still counted normally in a report that turns out to
have no groups active at all. Like the workspace's own directories, group
assignment lives only in this session until saved with **Save WorkSpace**.

Once at least two distinct group labels are actually in use, both exporters
add a `group` column to their CSV, and `generateQuartoReport` switches every
relevant section from its within-subjects test to the matching
between-subjects or mixed one in the table above -- automatically, from the
data, with nothing else to configure. A workspace where nobody has been
assigned a group (or everybody shares the same one label) renders exactly as
it always has.

The same dialog has two more columns, **Person ID** and **Session**, for
linking multiple raw-file recordings of the same person (e.g. "...day1",
"...day2") together -- give them the same Person ID and an optional Session
label ("Day 1", "Pre", "Post", ...) to record that they are repeated
measurements of one person, not unrelated subjects. Person ID is pre-filled
per raw file with whatever substring varies once every part of the
filename common to *all* raw files in the workspace is stripped out (an
experiment name shared by every recording cannot help tell subjects apart,
so it is not worth leaving in the suggestion). Both columns reach the
exported CSV (`person_id`/`session`) for a researcher's own downstream use,
but `generateQuartoReport` does not yet treat session as a statistical
factor the way it does bin or group -- that is groundwork for a future
multi-session design, not yet a wired-up test.

### It's just R and Quarto underneath

The generated `.qmd` is an ordinary, human-editable Quarto document, not a
locked report format: every test in the table above is a plain
`tidyverse`/`rstatix`/`lme4`/`emmeans`/`BayesFactor` call (see the package
list below) over a `dat` tibble read straight from the CSV copy sitting next
to it. Open the `.qmd` itself (in the Reports folder, next to its `.html`
and its own CSV copy) in RStudio, VS Code, or any text editor, and add,
change, or remove anything -- a fully Bayesian alternative (`brms`), a
random-effects structure the built-in LMM does not try, a custom plot, a
subset of channels or subjects, extra covariates joined in from elsewhere --
exactly as in any other Quarto/R document, then render it again (`quarto
render <name>.qmd`, or the "Render" button in RStudio/VS Code). The
auto-generated report is a statistically-considered starting point for this
specific export's own design, tailored to it rather than generic, but it is
not the last word on it: if a test exists in R, it can go in this report.

If Quarto or R (with the `tidyverse`, `rstatix`, `ggpubr`, `gt`,
`BayesFactor`, `lme4`, `lmerTest`, `emmeans`, `performance` and
`effectsize` packages -- installed automatically by the report's own setup
step on first render) are not found on this machine, the `.qmd` and its CSV
are still written and the export still succeeds; render it manually once
they are available (the export's completion dialog gives the exact
command).

Generated by [`generateQuartoReport.m`](src/IO/generateQuartoReport.m).

## Frequency analysis (frequency tagging / RIFT)

The **Spectral Measure** transform is the frequency-domain counterpart of ERP
Measure: it quantifies steady-state / frequency-tagging responses, SSVEP, and
Rapid Invisible Frequency Tagging (RIFT). It runs on epoched, single-trial data.

Declare the tagging fundamentals (`let f1 = 60`, `let f2 = 64`) and name each
frequency of interest as an expression over them: the fundamental (`f1`), a
harmonic (`2*f1`), or an intermodulation term (`f1+f2`, `2*f1-f2`). For every
frequency x channel x bin it computes the complex Fourier coefficient directly
at that exact frequency (a tapered single-frequency DFT, Hann or DPSS
multitaper, so harmonic / intermodulation terms off the `fs/N` grid are still
exact), and reports:

- **power / amplitude** of the trial-averaged (evoked) response and its **SNR**
  against the neighbouring frequency bins, the amplitude-based SSVEP read-out
  used to track, for example, attentional modulation of the tagged response
  (Toffanin et al., 2009);
- **inter-trial phase-locking** (how consistently the response tracks the
  flicker across trials); and
- against an optional reference channel such as a **photodiode** recording the
  flicker, the **magnitude-squared coherence** and phase-lag between that
  reference and each EEG channel. This is the standard RIFT cross-coherence:
  the trial-wise complex cross-spectra are averaged and normalised by the
  trial-averaged autospectra, then squared, exactly the read-out used to
  reveal tagging responses in Dimigen et al. (2025) (see
  [References](#references)).

For the time-resolved picture, the **Coherence Map** transform draws the
coherence between each channel and a reference (photodiode) as a per-channel
**time x frequency heatmap**, the plot the RIFT figures show (Dimigen et al.,
2025), using either a Morlet wavelet or a fixed-window STFT decomposition.

The reference is optional (not every recording has a photodiode), so power /
SNR / phase-locking are always available and coherence is added when a
reference is set. Results export to one long-format, R-compatible CSV via the
Export/Report tab's **Spectral & Report** button
([`exportSpectralCSV.m`](src/IO/exportSpectralCSV.m)), which also renders a
companion statistical report for it (see
[Statistical analysis](#statistical-analysis)) -- phase and phaselag are
reported descriptively only where a test would not be statistically valid
(see that section), power/amplitude/SNR/ITC/coherence get the full
within-subjects/between-subjects/mixed treatment like any ERP measure. Like
any transformation, a whole tagging pipeline can be replayed across a study
with Apply to All Raw Files or a saved template. The full reference is the
[`SpectralMeasure.m`](src/Transformations/SpectralMeasure/SpectralMeasure.m)
header.

## How-to walkthroughs

Three worked pipelines, plus a fourth that is a complete, reproducible run on
real published data rather than a recipe (see
[below](#a-worked-example-start-to-finish-the-erp-core-n400-dataset)). Each
is an ordinary chain of transformations, so once built on one recording it
replays across a whole study in one click with **Apply to All Raw Files**
(a branch's right-click menu) or a saved template. The marker
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

1. **Filter** the raw recording (`Filter`, e.g. 0.1 Hz high-pass, 30 Hz low-pass).
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
6. **Grand Average** across subjects, then export for one long-format CSV and a
   companion statistical report (the **Export/Report** ribbon tab's **ERP &
   Report** button, see [Statistical analysis](#statistical-analysis)). If
   subjects belong to different groups (e.g. patients vs. controls), assign
   them first with **Grouping...** (Home tab, Design group) to get a
   between-subjects/mixed comparison instead of a within-subjects one.

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
6. **Grand Average**, then export via the **Export/Report** tab's **ERP &
   Report** button. Since `MMN` is a difference bin measured as mean
   amplitude, the companion statistical report tests it against zero (see
   [Statistical analysis](#statistical-analysis)), the natural way to ask
   whether the mismatch response is actually present.

### A worked example, start to finish: the ERP CORE N400 dataset

Unlike the three recipes above, this one is a complete, reproducible run on
real published data, using a template ([`N400.alztemplate`](N400.alztemplate))
that ships in the repository, ending in an actual rendered statistics
report -- not a generic recipe with placeholder marker codes.

**The data.** The ERP CORE N400 experiment (Kappenman, Farrens, Zhang,
Stewart, & Luck, 2021, see [References](#references)) is a semantic-priming
paradigm: each trial shows a *prime* word followed by a *target* word, and
the target is either semantically **related** to the prime (e.g. TABLE then
CHAIR) or **unrelated** (e.g. RAKE then SPIDER). The participant presses one
of two buttons on each trial to judge which. Luck's textbook chapter 2
walks through processing one participant; chapter 3 repeats it across "10 of
the 40 participants in the actual study" -- the same 10-participant subset
used here (`Data/Luck/ch3` in a local checkout: ten
`<id>_N400_preprocessed.set` EEGLAB recordings, already filtered/referenced,
ready to be epoched, cleaned and averaged). Get the data itself from the
textbook's own exercise-data archive
([doi.org/10.18115/D50056](https://doi.org/10.18115/D50056)) or the full
ERP CORE release
([doi.org/10.18115/D5JW4R](https://doi.org/10.18115/D5JW4R)); it is not
bundled with this repository. The textbook's own worked example measures
the N400 at CPz (where it is typically largest) over roughly 200-600 ms;
the template below measures a slightly narrower, nearby window (Cz, 300-500
ms) as its own choice, not a reproduction of the book's exact numbers.

**The bins.** `N400.alztemplate`'s `DefineBins` step imports the
experiment's own bin descriptor (`BDF_N400.txt`, in ERPLAB's original BDF
format, one condition per event-code set):

```
bin 1 "Prime word, related to subsequent target word"     : 111|112
bin 2 "Prime word, unrelated to subsequent target word"    : 121|122
bin 3 "Target word, related to previous prime, followed
        by correct response"   : 211|212 and next(201) within [200,1500] ms
bin 4 "Target word, unrelated to previous prime, followed
        by correct response"   : 221|222 and next(201) within [200,1500] ms
bin 5 "N400" = bin 4 - bin 3
```

Bins 3 and 4 both require a correct-response marker (`201`) within 200 to
1500 ms of the target, excluding misses and implausibly fast guesses; `bin
5` is the classic N400 contrast itself, unrelated minus related targets.

**The template, step by step** (Home tab, **Grouping** is not needed here --
this walkthrough has no between-subjects groups, see
[Statistical analysis](#statistical-analysis)):

1. **AutoGEDAI** denoises the continuous recording (GEDAI, generalized
   eigenvalue decomposition against a leadfield reference), auto strength,
   a 0.4 Hz high-pass, no automatic epoch/channel rejection at this stage.
2. **DefineBins** applies the five bins above and epochs -200 to 800 ms
   around each event.
3. **Baseline** corrects to -100 to -10 ms pre-stimulus.
4. **ArtefactDetect** flags epochs exceeding &plusmn;100 µV.
5. **Average** produces one ERP per bin, including the `bin 4 - bin 3`
   contrast wave.
6. **Measure** quantifies mean amplitude, 300-500 ms, channel Cz, labelled
   window `N400`.

Import each participant's raw recording, apply the template once (drag it
onto the first imported dataset, or right-click -> **Apply Template...**),
check the result, then right-click that same processed branch and choose
**Apply to All Raw Files...** to replay the identical six steps over the
other nine recordings in one action -- rather than dragging the template
onto each of the ten root nodes by hand. **Grand Average** across all ten,
then the **Export/Report** tab's **ERP & Report** button writes the CSV and
renders the companion Quarto report.

**What actually got tested.** This particular `Measure` step defines one
window (`N400`, Cz, 300-500 ms), applied to whichever bins the averaged
dataset actually resolved a waveform for; in this run that produced a
mean-amplitude value for each of the four *ordinary* bins for all ten
subjects, but not for the `bin 5` contrast wave itself, so this report's own
evidence for the N400 comes from the omnibus comparison across the four
ordinary conditions below, not a separate one-sample-vs-zero test on the
difference wave (adding a second `Measure` window row that targets the
`N400` bin directly would additionally produce that framing -- see the
[design table](#what-gets-tested-and-what-question-it-answers) above,
"combination/difference bin"). With no groups assigned, this is the
"three or more ordinary bins, no groups" row: a linear mixed model.

Ten of ten subjects contributed a value in every one of the four
conditions, so a real render of this export produced:

| bin | *M* (µV) | *SD* | *n* |
|---|---|---|---|
| Prime, related | 0.178 | 1.647 | 10 |
| Prime, unrelated | 0.186 | 2.027 | 10 |
| Target, related | 3.563 | 2.247 | 10 |
| Target, unrelated | 0.804 | 1.763 | 10 |

The maximal linear mixed model (random intercept **and** slope per subject)
did not converge to a non-singular fit with only 10 subjects x 4 conditions,
so the report fell back to a random-intercept-only model, narrating that
fallback rather than silently switching. That model still found a
significant effect of bin, *F*(3.0, 27.0) = 19.95, *p* < .001, partial
&eta;<sup>2</sup> = .689, 95% CI [.494, 1.000] (marginal *R*<sup>2</sup> =
.348). Holm-corrected model-based pairwise contrasts (`emmeans`) narrowed
that omnibus effect down to exactly three significant pairs, all involving
one condition: Prime,related - Target,related (*p* < .001), Prime,unrelated
- Target,related (*p* < .001), and Target,related - Target,unrelated (*p* <
.001) -- every other pair, including Prime,related vs. Prime,unrelated, was
not significant. A Friedman test on the same 10 complete-data subjects, run
as a rank-based robustness check, agreed: &chi;<sup>2</sup>(3) = 18.12, *p*
< .001. The report's own closing summary table lists this as the single
test the export produced, still significant after Benjamini-Hochberg
correction.

**The question this answers, and what the numbers say.** Whether N400 mean
amplitude at Cz differs across the four conditions -- and it does, with a
very large effect (partial &eta;<sup>2</sup> = .689 is well past Cohen's
"large" benchmark of .14; the wide CI reflects the small, 10-subject
sample, not a weak effect). The pairwise table shows *why*: it is not that
all four conditions differ, but that Target, related (M = 3.56 µV)
stands apart from the other three, which do not differ from each other.
Target, unrelated (M = 0.80 µV) is markedly less positive than
Target, related in this 300-500 ms window, exactly the textbook N400
pattern (Kappenman et al., 2021; Kutas & Hillyard, 1980) -- a semantically
unrelated target elicits a larger centro-parietal negativity than a related
one, while the two prime conditions (which carry no semantic relationship
to score yet) sit indistinguishably near zero, as expected.

## References

Scientific/methodological:

- Luck, S. J. *Applied Event-Related Potential Data Analysis*. LibreTexts.
  [socialsci.libretexts.org](https://socialsci.libretexts.org/Bookshelves/Psychology/Biological_Psychology/Applied_Event-Related_Potential_Data_Analysis_(Luck)).
  DOI: [10.18115/D5QG92](https://doi.org/10.18115/D5QG92). Licensed CC BY 4.0.
  A practical, EEGLAB/ERPLAB-based reference for the preprocessing, averaging, and
  scoring steps that Alakazam's transformations implement. Its own worked N400
  example, [`N400.alztemplate`](N400.alztemplate) ported to Alakazam, is the
  [full worked example](#a-worked-example-start-to-finish-the-erp-core-n400-dataset)
  above.
- Kappenman, E. S., Farrens, J. L., Zhang, W., Stewart, A. X., & Luck, S. J.
  (2021). ERP CORE: An open resource for human event-related potential
  research. *NeuroImage*, 225, 117465. DOI:
  [10.1016/j.neuroimage.2020.117465](https://doi.org/10.1016/j.neuroimage.2020.117465).
  The N400 experiment (and nine others) the [worked example](#a-worked-example-start-to-finish-the-erp-core-n400-dataset)
  above is drawn from; data via
  [doi.org/10.18115/D5JW4R](https://doi.org/10.18115/D5JW4R).
- Kutas, M., & Hillyard, S. A. (1980). Reading senseless sentences: Brain
  potentials reflect semantic incongruity. *Science*, 207(4427), 203-205.
  DOI: [10.1126/science.7350657](https://doi.org/10.1126/science.7350657).
  The original discovery of the N400, the component the
  [worked example](#a-worked-example-start-to-finish-the-erp-core-n400-dataset)
  above measures.
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
- Oostenveld, R., Fries, P., Maris, E., & Schoffelen, J.-M. (2011). FieldTrip:
  open source software for advanced analysis of MEG, EEG, and invasive
  electrophysiological data. *Computational Intelligence and Neuroscience*,
  2011, 156869. DOI:
  [10.1155/2011/156869](https://doi.org/10.1155/2011/156869).
  [fieldtriptoolbox.org](https://www.fieldtriptoolbox.org/). The template
  head model, electrode positions, and cortical-sheet source model
  `Brain3D`'s Source-estimate mode builds its minimum-norm inverse on; an
  optional dependency, not bundled (see [3D brain view](#3d-brain-view)).
- Dale, A. M., Liu, A. K., Fischl, B. R., Buckner, R. L., Belliveau, J. W.,
  Lewine, J. D., & Halgren, E. (2000). Dynamic statistical parametric
  mapping: combining fMRI and MEG for high-resolution imaging of cortical
  activity. *Neuron*, 26(1), 55-67. DOI:
  [10.1016/S0896-6273(00)81138-1](https://doi.org/10.1016/S0896-6273(00)81138-1).
  The dSPM noise-normalization `Brain3D`'s Source-estimate mode applies to
  its minimum-norm inverse (see [3D brain view](#3d-brain-view)).
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
