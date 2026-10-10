# Technical note: Deconvolve and the Unfold workflow

How Alakazam's **Deconvolve** transformation calls the Unfold toolbox, step by
step against the toolbox's own account of its workflow, and every place where
Alakazam adds to it or departs from it.

*Checked against the code on 9 October 2026 (Development, after V0.4.5) and
against Unfold 1.3.1, the version Alakazam installs. "The intended workflow" is
`docs/docs_sphinx/toolboxWorkflow.rst` in that release. The toolbox and its
method are described by Ehinger & Dimigen (2019); the regression ERP approach
it builds on by Smith & Kutas (2015).*

## In short

Deconvolve runs Unfold's documented pipeline, in its order, with the toolbox's
own functions, and with the toolbox's own defaults wherever it has one:

| Workflow step (toolboxWorkflow.rst) | Toolbox function | In Deconvolve |
|---|---|---|
| Definition of the design | `uf_designmat` | called once, every event type with its own formula |
| Time expansion | `uf_timeexpandDesignmat` | called, `'stick'` (the default) |
| Removing artefactual data | `uf_continuousArtifactDetect`, `uf_continuousArtifactExclude` | called, with `uf_combineWinrej` to join marks |
| Imputation of missing data | `uf_imputeMissing` | called where a number is missing, `'median'` (its default) unless another method, or a refusal, is chosen |
| Fitting | `uf_glmfit` | called, `'lsmr'` (the default), or `'matlab'` or `'glmnet'` as chosen |
| Condensing | `uf_condense` | called for the model's terms; the other results read the same betas directly |
| Prediction (from the tutorials) | `uf_predictContinuous`, `uf_addmarginal` | called for the model's terms |
| Plotting | `uf_plotParam` and others | not called: Alakazam's own views |
| Group-level statistics | left to the user | Grand Average and Alakazam's cluster test |
| rERP without deconvolution | `uf_epoch`, `uf_glmfit_nodc` | called with **Overlap correction** off, in place of the time expansion and `uf_glmfit` |

What Alakazam adds lies before the first step and after the last. Before it,
DefineBins' bins are turned into Unfold's event types and formulas (section 1).
After it, the fitted betas are turned into one waveform per bin, in the shape
Average produces, or into overlap-corrected trials (section 2.7). Section 3
lists the checks Alakazam adds, and section 4 every setting where Deconvolve
does something other than the toolbox's default.

## 1. Two ways of choosing events

**Unfold chooses events by their code.** `uf_designmat`'s `eventtypes` lists
the codes each formula applies to, optionally grouped (`{{'A1','A2','A3'},{'B'},{'C'}}`
in its help). What distinguishes the events of one type is a formula over
their fields in `EEG.event`, in Wilkinson notation, and conditions are
predictors: the tutorials fit a 2 × 2 design as one event type, `'fixation'`,
with `'y ~ 1 + cat(stimulusType)*cat(color)'`. A condition's waveform is what
the model predicts for it, not an average of its epochs.

**DefineBins chooses events by context**, in ERPLAB's bin language: "S1
followed by a correct response within 200 to 1000 ms". An event can be in
several bins ("All stimuli" and "Rare"), and a bin can be computed from others
("bin 3 = bin 2 - bin 1"). Neither can be said in `eventtypes`; in a plain
Unfold script it would mean writing new fields onto `EEG.event` by hand first.

Deconvolve keeps the bins as the way events are chosen and the formula as what
explains their response. `Unfold.binModel` makes the translation, without the
toolbox and without fitting anything:

- **One event type per set of bins.** Each event's bin membership
  (`EEG.event(i).bini`, written by DefineBins) is a set of bins, and every
  distinct set that has events becomes one Unfold event type
  (`binCombinations`). With bins that share no events that is one type per
  bin, named `bin_<label>`. An event in both "All stimuli" and "Rare" is of
  the type `bin_All_stimuli_and_Rare`: one row of the design, one stick. Two
  sticks at the same latency would explain its data as the sum of two
  responses.
- **One formula per type.** A bin's formula is the one written for it, and
  `'y ~ 1'` when there is none; a formula written without `y ~` is given one.
  A type shared by several bins takes their common formula, or else every
  term of all of them (`sharedFormula`); a formula that takes a term out with
  `-` cannot be merged and is refused.
- **Combination bins are not event types.** They have no events of their own.
  They are computed after the fit, from the fitted waveforms, as Average
  computes them from averages (`resolveComboBins`, in the order
  `TransTools.ComboOrder` works out for both).
- **Events in no bin** can be modelled as nuisance, one type per event code
  (`evt_<code>`, formula `'y ~ 1'`), and dropped from the result. Every such
  code is modelled unless the dialog says otherwise, because overlap is
  removed only where it is modelled. `boundary` events are never modelled.
- **The event list handed to the toolbox is rewritten** (`rewriteEvents`): one
  row per modelled event, with `.latency`, `.type` and only the fields some
  formula names, each copied from the event the row came from. They are
  copied by row, not by latency, since two events can share a sample. A row
  whose type does not use a field gets a placeholder, 0 or `''`; a missing
  number stays NaN, as `uf_designmat` itself makes it, for 2.4.

This is the design of the toolbox paper's own tutorial, which models three
event types with a formula each (`{'saccade','stimonset','buttonpress'}`
with `{'y ~ 1 + spl(sac_amplitude,5)','y~1','y~1'}`): the bins take the
place of the saccades and stimuli, and the nuisance codes that of the button
press.

**What one type per bin cannot say.** In one event type with `cat(bin)`, a
covariate can have a single slope shared by every bin
(`y ~ 1 + cat(bin) + rt`). With a type per bin, each bin's formula has its own
slope, as `cat(bin) * rt` would. With `y ~ 1` everywhere the two fit the same
waveforms; they differ only where a shared slope is wanted, which Deconvolve
does not offer.

## 2. The workflow, step by step

With the part of toolboxWorkflow.rst each step implements, in the order
`Unfold.fitBins` runs them but for one: missing values (2.4) are handled
between the design (2.1) and its time expansion (2.2), where
`uf_imputeMissing` has to come.

### 2.0 Continuous data with events

The workflow starts from "continuous data with events". Deconvolve refuses
anything that is not continuous (`Unfold.requireContinuous`) before its dialog
opens. The bins are applied to the continuous recording by DefineBins in
tags-only mode, without an epoch window, which writes `EEG.bindesc` and each
event's `.bini` and leaves the data continuous (`applyBins` in
`Deconvolve.m`).

With overlap correction, Deconvolve also refuses a recording with a DC offset
(`requireCentredData`, section 3): the time-expanded design has no constant
term. A regression on epochs (2.10) has an intercept at every sample, which
takes up a standing voltage as an average does, so there it is not refused.

### 2.1 Definition of the design: `uf_designmat`

`Unfold.designMatrix` sets `EEG.event` to the rewritten list and calls
`uf_designmat` once, the event types as a list of one-element lists and the
formulas as a list in the same order:

```matlab
EEG = uf_designmat(EEG, 'eventtypes', {{'bin_A'}, {'bin_B'}, {'evt_201'}}, ...
    'formula', {'y ~ 1', 'y ~ 1 + spl(rt, 5)', 'y ~ 1'});
```

With a single event type, the type and its formula are passed unwrapped
(`'eventtypes', {'bin_A'}, 'formula', 'y ~ 1'`), as the toolbox passes each
type to itself: `uf_designmat` splits a list of formulas only when it has two
or more, and a list of one reaches its parser and fails.

Nothing else is passed, so the toolbox's defaults apply: reference coding
(`'codingschema', 'reference'`, the first level in sorted order as the
intercept), factors marked with `cat()`, and spline knots at quantiles
(`'splinespacing', 'quantile'`). A formula can use anything `uf_designmat`
accepts: factors, interactions, linear terms, `spl()`, `circspl()` and
`2dspl()`.

The dialog builds the same design on the events alone, with the same call,
so the columns the toolbox will make are shown, and a formula it refuses is
reported, before anything is fitted.

### 2.2 Time expansion: `uf_timeexpandDesignmat`

```matlab
EEG = uf_timeexpandDesignmat(EEG, 'timelimits', windowMs / 1000);
```

Only the window is passed, so the method is the default, `'stick'`: one
column per predictor per sample of the window. The window is the dialog's
**Window**, -200 to 800 ms unless changed (the toolbox has no default; it
must be given). The time bases (`'splines'`, `'fourier'`), which
toolboxWorkflow.rst calls an advanced feature, are not offered.

### 2.3 Removing artefactual data

toolboxWorkflow.rst asks for continuous, uncleaned data, and for bad stretches
to be removed from the design rather than from the data:
`uf_continuousArtifactExclude` takes a `winrej` matrix (a start and an end
sample per row, as EEGLAB's) and sets those rows of the time-expanded design
to zero. It notes the consequence, that parts of a response are then
estimated from different numbers of events. Deconvolve works this way, in
three parts.

1. **The scan.** With **Artefact threshold** above 0,
   `uf_continuousArtifactDetect` with the dialog's threshold, window and step,
   which start at the toolbox's own (150 µV in a 2000 ms window, stepped by
   100 ms), and with the channels **Artefact scan on** names: every channel,
   the toolbox's default, or the scalp EEG only (`eegChannelMask`), which
   keeps an eye channel's much larger swings from marking the recording. The
   toolbox hands the scan to ERPLAB's `basicrap`, which compares each window's
   peak-to-peak amplitude with the threshold. The scan is given the dataset's
   own events, boundaries included, as it is in an Unfold script, so
   `basicrap` scans each stretch between cuts on its own (`forArtefactScan`;
   on that copy only, it also fills in `chanlocs.type` and `epoch` where they
   are absent, since the scan reads both).
2. **The cuts.** Unfold itself does nothing with `boundary` events, since it
   expects uncleaned data. Deconvolve accepts a recording with cuts and leaves
   out, on each side of every cut, as many samples as the longer side of the
   response window (800 ms by default): a window spanning a cut would be
   fitted across a join between moments that were never adjacent
   (`boundaryIntervals`). The zones around the cuts and the scan's marks are
   joined by the toolbox's own `uf_combineWinrej`.
3. **The exclusion**: `uf_continuousArtifactExclude(EEG, 'winrej', excluded)`.

A threshold of 0 skips the scan; the zones around the cuts are left out either
way. Deconvolve refuses before fitting when more than half of the recording is
marked (section 3).

### 2.4 Imputation of missing data: `uf_imputeMissing`

toolboxWorkflow.rst says that a missing predictor value has to be imputed or
its event excluded, and offers `uf_imputeMissing` for it, after the design is
defined; `uf_designmat` warns that NaNs should be imputed before fitting.
Deconvolve does this where some event lacks a number its formula uses:

```matlab
EEG = uf_imputeMissing(EEG, 'method', missingValues);
```

between `uf_designmat` and `uf_timeexpandDesignmat`, with **Missing values**
as the method: `'median'` (the toolbox's default), `'mean'`, `'marginal'` (a
random draw from the type's other values) or `'drop'`, which zeroes the
event's row of the design, so that the event is left out of the model and of
the overlap correction too. A fifth choice, **Refused**, stops before the
toolbox is reached, naming the bin and how many of its events lack the
value. The toolbox's warning that more than 5% of a predictor is missing is
carried into the result's notes.

Three consequences are Alakazam's to handle, and are handled:

- A waveform per bin (2.7) is held at the values the events have: a missing
  value is not one of them, so the pooled values leave it out, while the
  filled-in value is what the fit used.
- With `'drop'`, `Unfold.binModel` leaves out of the bins exactly the events
  the toolbox will drop (those missing a number their formula uses), so the
  bins count, average and cut trials without them, and the values a waveform
  is held at do not include theirs. `fitBins` checks that the rows the
  toolbox zeroed are those events, and stops if they are not.
- A factor some event has no level of cannot be built by `uf_designmat`
  (it stops with "Input Event Values have to be string or numeric"), and
  `uf_imputeMissing` fills in numbers, so such a factor is refused whatever
  **Missing values** says, naming the bin and the toolbox's reason.

### 2.5 Fitting: `uf_glmfit`

```matlab
EEG = uf_glmfit(EEG, 'method', method, 'lsmriterations', solverIterations, ...
    'glmnetalpha', glmnetAlpha);
```

**Solver** chooses the method:

- **The toolbox's default**, `'lsmr'`, an iterative solver on the sparse
  design, channel by channel. Its iteration limit is **Solver iterations**,
  which starts at the toolbox's own 400. The toolbox warns, rather than fails,
  when it runs out of iterations; Deconvolve catches that warning and puts it
  in the result's notes.
- **Exact**, `'matlab'`: MATLAB's own solver, all channels at once. It needs
  no iteration limit, so it never stops short, but the toolbox's help warns
  that for moderate to big designs it needs a great deal of memory ("40-60GB
  is easily reached"). On a design lsmr solves, it gives lsmr's answer.
- **Regularised**, `'glmnet'`: a penalised fit, lasso by default, ridge with
  **glmnet alpha** 0, elastic net between them, its strength chosen by
  cross-validation (`cvglmnet`, at `'lambda_1se'`). Its betas are shrunk
  towards zero, so they are not the least-squares waveforms; lasso sets some
  exactly to zero. The toolbox fits glmnet with an intercept for the whole
  recording, which it keeps as a column of its own (`'glmnet-DC-Correction'`,
  NaN in `X`, its beta in `beta_dcCustomrow`); Alakazam leaves that column out
  of every bin's waveform and subtracts it from the overlap-corrected trials
  with the neighbours. The glmnet library ships with Unfold, with a Windows
  build that runs under MATLAB R2026a.

The toolbox's two other methods are not offered, for the reasons its own help
gives: `'par-lsmr'` is lsmr in parallel, which "does not seem to be any
faster" and is "Not recommended"; `'pinv'` is "generally not recommended due
to floating point instability".

### 2.6 Condensing: `uf_condense`

`uf_condense` takes the betas from `EEG.unfold.beta_dc` and, where a time basis
was used, transforms them back into samples. With stick expansion the time
basis is the identity (`EEG.unfold.timebasis = eye(windowlength)`), so its
betas are `beta_dc` unchanged. The model's terms are taken through
`uf_condense`; the waveforms per bin and the trials read `beta_dc` and
`EEG.unfold.times` directly, which are the same numbers. Unfold keeps times
in seconds; Alakazam converts them to milliseconds.

### 2.7 From betas to a result

toolboxWorkflow.rst ends with plotting. Deconvolve returns one of three
results, chosen under **Result**.

**One waveform per bin** (the default), in the shape Average produces:
`DataFormat` "Averaged", channels × samples × bins, the same `bindesc`, so
Measure, scalp maps, Grand Average and the reports read it unchanged. For each
event type, `referencePrediction` weights the betas of the type's own columns
(`cols2eventtypes`) by one design row:

- the intercept and factor columns: the mean of the type's own rows of `X`,
  so each factor is at the bin's own mix of levels;
- a continuous term: its mean over every modelled event whose formula uses
  it, pooled across types (`plan.pooled`), so the same value for every bin;
  a missing value, and an event left out by `'drop'`, are not counted (2.4);
- a spline: the mean of its basis over the pooled values, evaluated by the
  toolbox's own `splinefunction` with the fitted knots and `removedSplineIdx`.
  A spline that is not circular is averaged only over the range every type
  using it shares, since outside a type's own values its spline extrapolates;
  where the types share no values each is averaged over its own, and the
  notes say which happened. A 2D spline is averaged over the pooled pairs of
  its two fields, inside the box they share;
- an interaction with a continuous term: rebuilt with that term at its pooled
  mean, by calling `uf_designmat` on the type's own events
  (`pooledInteractions`), so its columns are built as the fitted ones were.

A bin's waveform is then the average of its types' waveforms, weighted by how
many of the bin's events each holds, which is Average's rule for an event in
several bins. The combination bins and the baseline (2.8) follow. `stErr` is
filled with zeros, since an lsmr fit gives no standard error.

This step is Alakazam's own computation from the documented fields of
`EEG.unfold` (`X`, `colnames`, `cols2eventtypes`, `cols2variablenames`,
`variablenames`, `variabletypes`, `splines`, `eventtypes`, `beta_dc`), not a
toolbox call, and the pooling is the reason. `uf_addmarginal` sets each event
type's terms from that type's own events, so a covariate whose values differ
between bins (slower responses in one condition) would show up as a
difference between them. At pooled values the covariate is held constant,
which is what makes a term a control (Dimigen & Ehinger, 2021). With `y ~ 1`
everywhere the waveform is the intercept, exactly the toolbox's beta.

**The model's terms**, by the toolbox's own route:

```matlab
result   = uf_condense(EEG);
result   = uf_predictContinuous(result, 'auto_method', 'quantile', 'auto_n', 10, ...
                                'predictAt', predictAt);
marginal = uf_addmarginal(result, 'type', marginalType);    % 'MEM' or 'AME'
```

`predictAt` comes from **Terms evaluated at** (`"sac_amplitude = 0.5 1 2; rt =
300 500"`, read by `Unfold.predictionValues`); a term not named there is
evaluated at ten quantiles of its own values, the toolbox's default. **Other
terms added at** sets `uf_addmarginal`'s type: their mean value (`'MEM'`, the
toolbox's default), or their average marginal effect (`'AME'`), a spline
averaged over the events' own values, as a waveform per bin has it. The two
differ only for a spline, and most for a circular one, whose mean angle can
be a direction no event had. Each term of each binned event type becomes one
waveform, labelled "<bin>: <term>"; the nuisance types are dropped.

**Overlap-corrected trials**: one epoch per binned event, the recording around
it minus every other event's fitted response (`Unfold.overlapCorrectedTrials`),
computed as data − X<sub>dc</sub>β + the event's own share. This is the
toolbox's "modelled plus residuals" view (`uf_erpimage` with `addResiduals`,
tutorial 7), for every channel and as data rather than a picture. Each lag is
placed on the row `uf_timeexpandDesignmat` itself uses,
`round(round(latency) + k + tmin · srate − 1)`, so the data and the betas stay
paired. A trial whose window touches an excluded sample, or runs off the
recording, is dropped and counted.

### 2.8 Plotting: not used, and the baseline

The results go to Alakazam's own views (ERP plots, scalp maps, and EpochView's
ERP image for the trials), not to `uf_plotParam`.

The baseline follows the toolbox. `uf_condense` returns the betas without a
baseline, and so does Deconvolve unless **Baseline-correct the result** is
ticked; it is not ticked on first use. When it is, the window (the pre-event
part of the response window unless changed) is taken as `uf_plotParam` takes
its own `'baseline'`: the samples from the start up to, but not including,
the stop, so -200 to 0 ms leaves out the sample at 0 ms. A beta's zero is
wherever the model put it, so a waveform to be read beside an average that
Baseline corrected needs correcting too.

### 2.9 Group-level statistics

toolboxWorkflow.rst leaves statistics to the user and recommends
cluster-based permutation, with the EPT-TFCE toolbox. Deconvolve's results are
averaged datasets, so Grand Average, the statistics reports and the cluster
test take them as they take any average. The cluster test is FieldTrip's, with
threshold-free cluster enhancement as its default (manual, chapter 14).
EPT-TFCE itself is not installed: it is a git submodule of Unfold, empty in
the source archive Alakazam installs, and nothing in the fitting path uses it.

### 2.10 rERP without deconvolution: `uf_epoch`, `uf_glmfit_nodc`

toolboxWorkflow.rst also describes a mass-univariate regression on epochs,
without deconvolution, and the toolbox's tutorials use it to show what
deconvolution changes. Deconvolve runs it with **Overlap correction** off, in
place of 2.2, 2.3 and 2.5, on the same design (2.1, 2.4):

```matlab
EEG = uf_epoch(EEG, 'winrej', winrej, 'timelimits', windowMs / 1000);
EEG = uf_glmfit_nodc(EEG, 'method', method, 'glmnetalpha', glmnetAlpha);
```

- `winrej` holds the scan's marks (2.3) and each cut as a stretch of one
  sample. `uf_epoch` leaves out every event whose window touches one of them,
  so an epoch spanning a cut is left out, as DefineBins leaves one out; and,
  through EEGLAB's `pop_epoch`, every event whose window runs off the
  recording.
- `uf_epoch` rounds each latency to the nearest sample, where Alakazam's own
  epoching floors it as EEGLAB does; and `pop_epoch` stops a sample before the
  window's end (-200 to 790 ms at 100 Hz), as DefineBins does.
- The method is `uf_glmfit_nodc`'s own default, `'pinv'`, the
  pseudo-inverse of the epochs-by-predictors design, a small system here, or
  the exact or glmnet solver as chosen under **Solver**.
- `pop_epoch` reads fields an Alakazam dataset need not carry (`setname` among
  them), so the copy handed to `uf_epoch` is given every field of EEGLAB's own
  empty dataset that it lacks, a time axis for EEGLAB to rebuild in its
  milliseconds, and each event's row of the plan, which the toolbox carries
  into the epochs (`forEpoching`). That row tells which events became epochs:
  the others are not in the fit, so the bins count and average without them
  (`Unfold.keepEvents`).

With `y ~ 1` a bin's waveform is the mean of its epochs, as Average gives it
but for the rounding; with a formula, it is the same regression as a
deconvolution, with the neighbours' overlap left in. **The trials** are the
epochs as `uf_epoch` cut them, nothing subtracted. **The model's terms** come
from `uf_condense`, `uf_predictContinuous` and `uf_addmarginal` as before,
which return the betas as `beta_nodc`. Bins at a fixed lag, and codes locked
to another type, are not noted: a regression on epochs fits each epoch on its
own and has nothing to tell apart.

## 3. Checks Alakazam adds

None of these changes a number the toolbox computes. Each refuses a fit that
could not give a usable answer, or notes what the reader needs to know.

| Check | When | What it does |
|---|---|---|
| A DC offset, with overlap correction: on the median channel, \|mean\| above one standard deviation (`requireCentredData`) | before | refuses, naming DCDetrend or a high-pass Filter. The time-expanded design has no constant term, so a standing voltage would have to come out of the event responses. |
| No bin holds any event | before | refuses |
| A bin holds no event in this recording | before | notes it; the bin is empty in the result |
| A field a formula names: absent from the recording, without a number on every one of the bin's events, or the same on all of them (`checkVariables`) | before | refuses, naming the bin. The last is common with EYE-EEG, which writes 0 into every field that does not apply. |
| A number missing on some of the bin's events, with **Missing values** set to refuse | before | refuses, naming the bin and the count |
| A factor level missing on some of the bin's events | before | refuses, whatever **Missing values** says (2.4) |
| A formula `uf_designmat` refuses | before | each type is tried alone, and the refusal names the bin (`namedRefusal`) |
| Factor levels of one letter each (`oneLetterFactors`) | when `uf_designmat` refuses | says why: see section 5 |
| Two bins at an exactly constant lag, with overlap correction (`fixedLagNotes`) | before | notes that their waveforms are not identified apart |
| A modelled code in no bin locked to another type, with overlap correction: median lag shorter than the window, 80 % of each type's events within 40 ms of it, spread under 20 ms (`Unfold.timeLockedEvents`) | before | notes it, in the dialog too; named as the likely cause if the solver then does not converge |
| Without overlap correction, events left out by `uf_epoch` | after epoching | notes how many; none at all is refused |
| Codes in no bin left out | before | notes that their overlap stays in the bins |
| More than half of the recording marked as artefact (`requireEnoughDataLeft`) | before the fit | refuses |
| The solver ran out of iterations | after | notes it |
| The fit returned NaN (`requireFiniteBetas`) | after | refuses |

## 4. Where Deconvolve differs from the toolbox's defaults

**Settings that start at the toolbox's default**, with Alakazam's alternative
offered beside it:

| Setting | Toolbox default, and Deconvolve's first choice | The alternative offered |
|---|---|---|
| **Artefact scan on** (`uf_continuousArtifactDetect` `'channels'`) | every channel | the scalp EEG only: an eye channel's range is several times the EEG's, so scanning it can leave out much of the recording |
| **Other terms added at** (`uf_addmarginal` `'type'`) | their mean value, `'MEM'` | their average marginal effect, `'AME'`: a circular spline's mean angle can be one no event had |
| **Baseline-correct the result** | no baseline (`uf_condense`) | a window, taken as `uf_plotParam` takes one |
| **Terms evaluated at** (`uf_predictContinuous`) | ten quantiles | values named per term |
| **Missing values** (`uf_imputeMissing` `'method'`) | the median | the mean, a random draw (`'marginal'`), the events left out (`'drop'`), or a refusal |
| Artefact threshold, window and step | 150 µV, 2000 ms, 100 ms | any values |
| **Solver** (`uf_glmfit` and `uf_glmfit_nodc` `'method'`) | each function's own: `'lsmr'`, and `'pinv'` on epochs | MATLAB's exact solver (`'matlab'`), or glmnet's regularised fit (`'glmnet'`) |
| **glmnet alpha** (`'glmnetalpha'`) | 1, lasso | 0, ridge, or between them |
| **Solver iterations** (`uf_glmfit` `'lsmriterations'`) | 400 | any number |
| **Overlap correction** | on: `uf_timeexpandDesignmat` and `uf_glmfit` | off: `uf_epoch` and `uf_glmfit_nodc` (2.10) |

`'codingschema'`, `'splinespacing'` and the stick time expansion are the
toolbox's defaults and are not settings.

**Options stored before the scan's channels, the marginal effect and
missing values were settings** (templates saved with V0.4.5 or earlier) have
none of these fields. They were run with the scalp-only scan, `'AME'`, a
refusal of missing numbers and, where the field is absent, a pre-event
baseline, and they replay and reopen with those, so a template gives the
result it always gave. Without **Solver** or **Overlap correction** they are
fitted as they always were, by deconvolution with lsmr. The shipped Ehinger & Dimigen Figure 11
template (manual, chapter 17) now states its choices, the scalp EEG only,
`'AME'` and the median (nothing is missing in its data), so its numbers in
the chapter are unchanged.

**Where Deconvolve does something the toolbox does not do at all**:

| | Toolbox | Deconvolve | Why |
|---|---|---|---|
| Choosing events | event codes (`eventtypes`) | DefineBins' bins, one event type per set of bins | ERPLAB's bin language, and events in several bins (section 1) |
| Cuts in the recording | nothing | the longer side of the window left out on each side of every cut | a window across a cut is fitted across a join (2.3) |
| A waveform per bin | none | the prediction at pooled values | a term held constant across bins is a control (2.7) |

## 5. Toolbox behaviours kept as they are

Alakazam calls the toolbox as a script does and keeps its results as they are.
These behaviours of Unfold 1.3.1, unchanged in its current version, are worth
knowing; the manual (chapter 9, "How the Unfold toolbox is called") describes
each and when it can arise.

- `uf_combineWinrej` ends a joined stretch where the later-starting one ends,
  so a marked stretch lying wholly inside another shortens it.
- `uf_designmat` cannot build a factor whose levels are all single letters
  when another event in the model lacks the field (MATLAB's `struct2table`
  then reads the levels as characters).
- ERPLAB's moving window, which the scan uses, skips the first sample and
  less than one step at the end of each stretch.
- `uf_predictContinuous` and `uf_addmarginal` summarise a continuous term
  without its values that are exactly zero, as the toolbox's own message
  says.
- `uf_imputeMissing` fills in a spline's basis columns one by one, so a
  filled-in event's row is not the spline at any one value.
- Its warning that more than 5% of a predictor is missing counts the missing
  values against every event in the model, not against the type's own (its
  source says so, as a deliberate correction).
- Its `'marginal'` method keeps the values it drew for one predictor and
  draws into the same list for the next, so it stops ("Unable to perform
  assignment") when two predictors miss different numbers of values.
  Deconvolve then refuses with that reason and suggests another method.

## 6. Installing and starting the toolbox

- Unfold is installed on first use, with consent, from the source archive of
  tag 1.3.1 (`Unfold.ensure`). The version is pinned so that results do not
  change with the date of installation.
- It is started with its own `init_unfold` (`Unfold.startToolbox`): EEGLAB is
  ensured first, since `init_unfold` opens EEGLAB's window when it is absent;
  the initialiser's printed lines are captured; and MATLAB's warning about the
  missing EPT-TFCE folder is switched off around the call. The three git
  submodules (gramm, eegvis, EPT-TFCE) are plotting and statistics libraries
  the fit does not use, so the archive is enough and git is not needed.
- `Unfold.isAvailable` answers whether the toolbox can be used, without
  installing or asking.

## 7. Where the code is

| File | Part |
|---|---|
| `src/Transformations/Deconvolve/Deconvolve.m` | the transformation: bins applied, options read, the fit called |
| `src/Transformations/Deconvolve/DeconvolveDialog.m` | the dialog, with the design preview |
| `src/Transformations/+Unfold/binModel.m` | bins into event types and formulas (section 1) |
| `src/Transformations/+Unfold/designMatrix.m` | the `uf_designmat` call (2.1) |
| `src/Transformations/+Unfold/fitBins.m` | sections 2.2 to 2.8 |
| `src/Transformations/+Unfold/overlapCorrectedTrials.m` | the trials (2.7) |
| `src/Transformations/+Unfold/predictionValues.m` | **Terms evaluated at** into `predictAt` |
| `src/Transformations/+Unfold/timeLockedEvents.m` | the time-locked pairs (section 3) |
| `src/Transformations/+Unfold/keepEvents.m`, `pooledValues.m`, `formulaVariables.m` | the events in the fit, the values a waveform is held at, and a formula's fields |
| `src/Transformations/+Unfold/ensure.m`, `startToolbox.m`, `isAvailable.m` | installing and starting (section 6) |

## 8. How it is tested

- `UnfoldBinsTest`: the translation of bins, nuisance codes, nested and
  combination bins, the recovery of overlapping responses that averaging
  smears, and the shape of the result.
- `UnfoldCovariatesTest`: formulas, terms held at pooled values, splines,
  2D splines and interactions, the terms by the toolbox's route with `'MEM'`
  by default and `'AME'` on request, ten quantiles by default, and missing
  numbers: the median filled in as by hand, `'drop'` giving the model
  without those events, the refusals, and `'marginal'`'s stop.
- `OverlapCorrectedTrialsTest`: the trials average back to the fitted
  waveforms, every trial loses its overlap, and cuts drop only the trials
  around them.
- `DeconvolveTest`: the transformation, the scan between cuts and on every
  channel by default, the baseline window as `uf_plotParam` takes it, and
  older options replaying as they ran. `UnfoldSolversTest`: the exact solver
  giving lsmr's answer, glmnet's lasso and ridge, and the regression on epochs
  (a bin the mean of its epochs, cut by hand as `uf_epoch` cuts them, epochs
  on an artefact or across a cut left out, the trials and terms from it, an
  offset no obstacle there). `DeconvolveDialogTest`: the dialog,
  its defaults and its choices. `UnfoldToolboxTest`: installing and starting.
- `LibraryReplayTest` replays the Figure 11 template (manual, chapter 17) on
  the authors' recording and holds it to the chapter's numbers.

## References

- Dimigen, O., & Ehinger, B. V. (2021). Regression-based analysis of combined
  EEG and eye-tracking data: Theory and applications. *Journal of Vision,
  21*(1), 3. <https://doi.org/10.1167/jov.21.1.3>
- Ehinger, B. V., & Dimigen, O. (2019). Unfold: An integrated toolbox for
  overlap correction, non-linear modeling, and regression-based EEG analysis.
  *PeerJ, 7*, e7838. <https://doi.org/10.7717/peerj.7838>
- Smith, N. J., & Kutas, M. (2015). Regression-based estimation of ERP
  waveforms: I. The rERP framework. *Psychophysiology, 52*, 157-168.
  <https://doi.org/10.1111/psyp.12317>
