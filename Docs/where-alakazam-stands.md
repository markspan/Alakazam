# Where Alakazam Stands

*In-depth capability review · sixth pass · 4 October 2026*

A scalp ERP workbench measured against EEGLAB, FieldTrip, ERPLAB, BrainVision Analyzer and MNE-Python: what it does better than any of them, what it is missing, and what it is deliberately not trying to be.

## Since the fifth pass (28 September)

- **Four gaps closed.** Standard cleaning: PREP and ASR wrap the reference implementations, AutoReject implements autoreject's algorithm (a Python package) and is tested against a literal evaluation of its criterion, and ArtefactDetect has a flat-line detector. A scaffold: `newTransformation` writes a transformation that runs under the contract from the start, and the developer guide says what a transformation may do to the dataset it is given. A field library for the generated dialog: 22 of the 38 transformations with settings now use it, against 14 of 32. And file formats: every major one opens, from one registry.
- **Every hand-written computation was audited against the toolbox that does the same** (`Docs/toolbox-audit.md`), and where FieldTrip computes the same thing, `FieldTripReferenceTest` now holds Alakazam to it. The audit found one plain error, TimeFrequency's baseline, and brought Alakazam's conventions into line with FieldTrip's where they differed. It has a section of its own below.
- **The two report defects named on 30 September are fixed.** Symbols are written as Unicode letters, with a test that fails on TeX math in any report source, and the Reports tree lists only the workspace's own reports. A report now draws only the grand averages made from its own datasets, where it drew every grand average in the tree, stale ones included.
- **GEDAI follows its newest release**, and the release that ran is recorded with each result; its epoch size and sliding window are asked for, as GEDAI's own dialog asks.
- **Source estimation is at parity with FieldTrip, on template anatomy, through FieldTrip's own functions.** dSPM is normalised by the baseline's noise covariance, which Average now stores; regions of an atlas get their own time courses (Source Regions, `ft_sourceparcellate`); ERPs can be fitted with a dipole or a mirrored pair (Dipole Fit, `ft_dipolefitting`); and LCMV and DICS beamformers (Beamformer, `ft_sourceanalysis`) map power change on the cortical sheet or on a volume grid drawn on the template MRI. Each is checked against FieldTrip's own functions or against a source simulated in the template head. It is the parity paragraph's main change below.
- **Plugins install from the application**, from a zip file or a GitHub repository, release or folder, checked before anything is installed, into a folder an update leaves alone. Half of gap 03 is closed.
- **The manual is online**, at <https://markspan.github.io/Alakazam/>, rebuilt from each release. Two releases, V0.4.4.4 and V0.4.4.5.
- 41 transformations instead of 35; 186 test classes instead of 161, holding 1,965 tests.

> **The reports still need attention, less than on 30 September.** They are R and Quarto documents assembled as text by MATLAB, and most of their tests check that text: its structure, its CSV columns, now also that it carries no TeX math. A few tests render a report and read the numbers back out of it (the ERP statistics report, the data-quality report, the RESS section), but they are tagged slow and need R and Quarto, so they run in the full suite only, on one machine. No test renders the scalp or source cluster reports, and the escaped α in the cluster report was found by a user. What would close it: those render tests in CI (gap 04), a rendered cluster report among them, and a snapshot of each report's rendered text to diff against.

## What is being reviewed

*Scope, before anything is called a gap*

Alakazam is a workbench for **scalp-recorded EEG and event-related potentials**: from raw recordings through preprocessing, epoching and averaging, to measurement, group statistics and a written result. That sentence is the whole scope, and it determines what counts as a lack.

It is not an MRI or anatomy package, and not a MEG or intracranial platform. Those need a different imaging modality or different sensor physics entirely, and marking their absence as a deficiency would be reviewing Alakazam against someone else's design brief.

Source estimation is a different matter and belongs in the review. Estimating the cortical generators of a scalp potential is an EEG technique, not an MRI one: it is done from the electrodes, and a head model can be a template rather than a participant's own scan. Alakazam does it, so it is assessed below on how far it goes rather than excluded. What is out of scope is the *MRI* half: ingesting individual structural scans to build subject-specific anatomy. Eye tracking is in scope for the same reason: joined onto the EEG, it supplies the events and the covariates of fixation-related analyses.

What follows is measured in the lane above: 41 transformations, its own bin-definition language (which defines regression models as well as averages), measurement with error estimates, permutation and mixed-effects group statistics, five generated reports (ERP statistics, spectral statistics, data quality, scalp cluster statistics and source cluster statistics), a manual, and a plugin architecture underneath all of it.

## The design claim: extension cost

*Three files, one of them six fields long*

Alakazam's central design decision is that a capability is a plugin, and that a plugin costs the author nothing but the algorithm. A transformation is a folder under `src/Transformations/` holding an entry function, a JSON manifest and an icon. Nothing else, anywhere in the codebase, is edited.

```matlab
% MyThing/MyThing.json: this file IS the registration
{"Name":"MyThing","Description":"...","Entry":"MyThing.m",
 "Icon":"MyThing.png","Section":"1. Preprocessing","Category":"EEG"}

% MyThing/MyThing.m
function [EEG, options] = MyThing(input, varargin)
    [opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:MyThing', varargin{:});
    if interactive
        options = TransformOptionsDialog(...defaults...);
        TransformSettings.set('MyThing', options);
    else
        options = opts;
    end
    EEG = ...your algorithm...;
end
```

*The ribbon scans `Transformations/*.json` when it is built, so there is no central list to append to and no menu code to write. `newTransformation` writes these files, with a test class and a manual section, to start from.*

The omissions are the point. The author writes no menu registration, no settings dialog (field types are inferred from the defaults passed in, or declared as fields: a channel or bin picker by label, a table of rows, a preview, a field that depends on another), no history or provenance bookkeeping, no replay branch beyond the four lines above, no caching and no export code.

What arrives with those three files: a ribbon button in the correct group, a generated settings dialog, settings remembered between runs, replay by dragging the branch onto another dataset, **Apply to All Raw Files** (spread over worker processes), template replay, a node in the provenance tree, and a line in the exported analysis script. Every call also passes one seam, `TransTools.invoke`, which checks what the plugin returns and names the plugin when it breaks the contract.

The comparison that matters is EEGLAB, the only one of the five with a real plugin system. There, a plugin is an `eegplugin_*.m` that registers its own menus through `uimenu` callbacks, plus a `pop_*` function carrying a hand-written dialog and argument parsing, plus the correct `com` history string that `eegh` needs for the operation to be reproducible, plus the algorithm. Two of those files are plumbing the author writes and can get wrong, and history-string correctness in particular is a well-known source of silently unreproducible analyses. FieldTrip and MNE-Python have no plugin system at all: they are libraries, so extending means writing a function, which is simpler still and arrives with no interface, no discovery, no dialog and no provenance. BrainVision Analyzer does not admit new first-class transforms.

On the ratio of algorithm code to plumbing code, Alakazam is the best of the six. The last fortnight is the evidence: Deconvolve, EyeTracking, RESS, PREP, ASR, AutoReject, Source Regions, Dipole Fit and Beamformer each wrap or implement a substantial published method, and each is a folder, not a change to the host. That is a real architectural achievement and it is the thing to defend.

The same fortnight shows its small print. A result that needs a picture of its own (Dipole Fit's dipoles, Beamformer's maps) needs a view, and a view is not a plugin: it is a class the plotter has to be told about, in host code. A transformation from outside can therefore only produce what the existing views already show, which for anything genuinely new is the limit that matters (gap 02).

## Where it is state of the art

*Nine claims, each with what it rests on*

"State of the art" here means: reflects current published methodological best practice, and does so more completely or more accessibly than the comparison packages. Each claim below names the basis so you can check it.

### 1. Measurement error as a first-class output

Alakazam computes the standardized measurement error of every score it reports, per measurement window, per channel, choosing the estimator by score type: a closed form for mean amplitude, where the mean of the average equals the average of the per-trial means, and a bootstrap for non-linear scores such as peak amplitude and the fractional-area latencies, which have no analytic identity to exploit.

That per-window choice matters more than it sounds. A subject can be clean in one time range and hopeless in another, and a whole-recording noise summary averages exactly that distinction away. SME is also comparable across subjects and labs in a way a rejection percentage never is. Overlap-corrected trials from Deconvolve are scored the same way, so a deconvolved subject gets an SME too.

Two corrections since August, both to an error estimate rather than a score. The aSME that Average stores with each waveform divided by every trial in a bin, rejected ones included, whenever rejection had left NaN trials in the bin (fixed 26 September). And a grand average with subjects weighted by their trial counts drew the weighted mean with the unweighted standard error across subjects, two different estimators; its band is now the standard error of the weighted mean, and its pooled aSME uses the same weights (fixed 1 October). The per-window SME of the data-quality report was right throughout.

*Basis: Luck et al. (2021), and validated against ERPLAB 13.10's own aSME (claim 8). ERPLAB reports SME too and deserves credit for bringing it into common use; the others in this comparison do not. Alakazam's addition is the automatic analytic-versus-bootstrap choice and the per-window granularity. The weighted band's formula is in `Docs/toolbox-audit.md`, which also notes that ERPLAB's own weighted band is too wide (read from its source, not run).*

### 2. Data quality as a document, not a number

The per-subject quality report combines SME with rejection and truncation counts, per-trial noise, per-channel flagging and interpolation rates, and robust outlier detection using median absolute deviation rather than standard deviation, because with a handful of subjects the outliers being looked for would inflate an SD enough to hide inside it. It says what each cleaning step did: rectification, PREP, ASR and AutoReject each with a table of their own, and how well each subject's eye track was synchronised with the EEG. Since 2 October it also cites the method behind each cleaning step that ran, and only those.

Every threshold is printed alongside its reasoning, and the report states plainly that it flags rather than acts, and that exclusion criteria set after looking at the data are not exclusion criteria. That is methodological hygiene built into the output rather than left to the user's conscience.

*Basis: verified in the working tree, including the provenance tables and the references. I know of no comparison package that emits a per-subject QC document of this kind; the nearest is assembling one yourself from ERPLAB's numbers.*

### 3. TFCE as the default for cluster inference

Permutation testing offers threshold-free cluster enhancement as the recommended option, with classic cluster correction available as the alternative, on the scalp and in source space. TFCE removes the arbitrary cluster-forming threshold that classic cluster inference requires, and that threshold is a well-documented researcher degree of freedom.

Most packages that offer TFCE at all offer it as an option you must know to select. Making it the default is a small decision with real consequences for what gets published.

*Basis: Smith & Nichols (2009) for TFCE, Maris & Oostenveld (2007) for the permutation framework. The implementation is FieldTrip's: in the pinned build, its exact TFCE (Chen et al., 2026), with no step size to choose. In source space the scoring step runs as a compiled port of FieldTrip's own routine, which a test holds to FieldTrip's p-values on the same random seed (`src/mex/README.md`), and the permutations are spread over the available cores. Verified: the dialog offers "TFCE (recommended)" preselected.*

### 4. Mixed models chosen from a derived design

With three or more conditions, or conditions crossed with groups or sessions, the group statistics are linear mixed models rather than repeated-measures ANOVA, so a subject missing one bin contributes their remaining bins instead of being dropped from the channel entirely. The maximal random structure the design justifies is fitted first, with an explicit, narrated fallback to random-intercept-only on a singular fit. Two conditions get a paired test.

The design itself is derived from the workspace rather than declared twice: group, person and session are read from what the user has already recorded, the model follows from that, and the random effect is grouped by *person* so somebody measured in two sessions counts once. Where the recordings cannot support a factor (an empty cell, or nobody measured twice), the report fits the simpler model and prints the reason, instead of fitting an interaction it cannot estimate and presenting the result as intended.

Where per-trial scores were exported, the report also fits the model to the trials rather than the subject averages, beside the averaged test. Each mixed-model section also reports a Bayes factor for the effect it tests, from the model it actually fitted, so a design that fell back to a simpler model gets that model's Bayes factor.

*Basis: Barr et al. (2013) for maximal random structure, Frömer et al. (2018) and Volpert-Esmond & Bartholow (2021) for single-trial models, Rouder et al. (2012) for the default priors of `BayesFactor::lmBF`; verified in the fifth pass, including the fallback ladder and its printed reasons. Neither ERPLAB, FieldTrip nor BrainVision Analyzer fits mixed models at all; EEGLAB does through LIMO, which is a separate toolbox with its own learning curve.*

### 5. The report writes itself

The output is a Quarto document that renders to self-contained HTML, and opens in Word for a manuscript. Each comparison gets the one test chosen for its design, in an APA-formatted three-line table beside a violin plot of the actual distribution: its effect size, a confidence interval where one can be computed, a Bayes factor beside every *t*-test and in every mixed-model section, and a one-sentence caption saying what the test tests. A reading guide opens the document, naming only the kinds of evidence the report actually contains, and a summary closes it with every section's main test in one table, the primary tests corrected together for the false discovery rate, the secondary ones listed uncorrected, and a forest plot of the effect sizes by kind. A RESS section reports each filter's null (the filter applied where its flicker was absent) and the checks the method's authors ask a reader to make.

The generated `.qmd` is an ordinary, editable R document, not a locked format, so the user can take it over at any point; its R lives in template files rather than in MATLAB strings. This is the feature that would make someone switch tools, and I know of nothing comparable in the other five: they hand you numbers and leave the writing to you. How reliably the reports are produced is a separate question, in the box at the top.

*Basis: verified in the fifth pass and by rendering the report fixtures, including the design-aware section dispatch. On the RIFT export at Oz, the mixed-model Bayes factors for the condition effect run from 3.8 to 303. BrainVision Analyzer has report templates, but not model selection.*

### 6. The bin-definition language

A purpose-built declarative language for assigning events to bins, with sets, aliases, relations to neighbouring events, windows measured in milliseconds, samples or ordinal event position, reaction-time filtering, response-locking, an `epoch` statement and combination bins that can reference other combination bins. The same bins define a regression model: Deconvolve applies DefineBins without cutting epochs and fits one event type per bin, so one language describes both the average and the deconvolution of an experiment.

What lifts it above ERPLAB's BINLISTER, whose job it replaces, is the diagnostics: 40 distinct explanatory parse errors, each showing the offending line, a caret under the mistake, a plain-language explanation and usually a corrected example; the fortieth refuses a bin number used twice. A BINLISTER syntax error is a considerably lonelier experience. An importer translates existing BINLISTER descriptor files, flagging by hand anything with no equivalent, and on Luck's chapter 8 data it assigns every one of 642 events to the same bin as BINLISTER.

*Basis: verified in the working tree: 40 `throwParseError` sites across the parser, every example in the language reference parsed through the real engine, and the BINLISTER comparison in `Docs/luck.md`.*

### 7. Reproducibility that produces a program

Every dataset in the tree records how it was made, as typed `{id, params}` data rather than a command string to be re-executed. That record drives replay onto other datasets, and the whole tree can be exported as runnable MATLAB: looped over subjects where the pipelines match, with divergent parameters hoisted and annotated, and the bin script written as a sidecar rather than inlined. Templates carry whole analyses, and the library's templates are replayed on their own data by a test that compares what they produce with the numbers recorded when they were checked (`LibraryReplayTest`), so a change that moves a published result fails rather than passing unnoticed.

The toolboxes the results depend on are pinned: FieldTrip to a dated build, Unfold to 1.3.1, EYE-EEG to 1.01, the PREP pipeline to 0.56.0, each installed on first use after the user agrees. GEDAI is the exception, kept at its newest release by choice, and the release that ran is recorded with each result. A version that moved under an analysis would change published numbers without anyone choosing it, and the pin, or the record, is what makes a result re-runnable on another machine a year later.

*Basis: verified in the working tree and `dependencies.md`. EEGLAB's `eegh` is the nearest equivalent and depends on plugin authors emitting correct history strings by hand; EEGLAB itself is left unpinned, which the dependencies file says.*

### 8. Checked against published outputs, and against FieldTrip

Alakazam's steps have been compared with the outputs they re-implement, and the comparisons are written down in the repository. Against Luck's published stage files for the ERP CORE data, re-referencing and spherical-spline interpolation are bit-identical, the ERPLAB erpset bridge is exact both ways on all ten published N400 sets, and the chain from bins to average reproduces the book's `1_N400.erp` to 0.0004 µV with the exact accepted and rejected trial counts. Measurement and SME were checked against ERPLAB 13.10 directly.

For frequency tagging, the default coherence estimator agrees with EEGLAB's `newcrossf` to about 0.001 on ten recordings, and the group means at Oz come out at 0.283 and 0.238 against the paper's 0.280 and 0.241. RESS, given its authors' frequency grid, reproduces their spatial filters to ten decimals and their eigenvalues to four on all twenty filters of those recordings. For deconvolution, the face-saccade recording of Ehinger & Dimigen (2019) rebuilt from a shipped template gives a stimulus waveform at Oz that correlates with the authors' own script's at *r* = 0.9998 from -200 to 1000 ms, with a largest difference of 3.2 µV.

New in this pass, the computations Alakazam does itself are held to FieldTrip where FieldTrip does the same: the time-frequency ERSP to 0.027 dB, the wavelet coherence to 0.006, the PSD to 1e-15, Spectral Measure's amplitude, phase, ITC and SNR to rounding, and Baseline and DC-Detrend. Each of those tests was seen to fail on the error it guards. The source estimation added in this pass is held the same way: the noise covariance is `ft_timelockanalysis`'s to 1e-10, and dSPM with it is `ft_inverse_mne`'s prewhitened filter to 1e-9; and sources simulated in the template head are found again, a dipole within 10 mm with under 5% of the data unexplained, and an oscillating source within 15 mm by LCMV on the sheet and on the grid, and by DICS on the sheet. The published comparisons found and fixed three bugs, and one case where Alakazam is right and ERPLAB is not; the FieldTrip comparisons are part of the audit below.

*Basis: `Docs/luck.md`, `Docs/dimigen.md`, chapter 17 of the manual and the RESS audit, which give the precision of each comparison; `Docs/toolbox-audit.md` and `FieldTripReferenceTest` for the FieldTrip checks; `NoiseCovarianceTest`, `DipoleFitTest` and `BeamformerTest` for the source checks, whose simulations use the same head model to make the data and to find the source, so they check the pipeline, not anatomical accuracy; `Docs/transformation-provenance.md` for which steps wrap a toolbox and which are Alakazam's own. The RIFT and deconvolution comparisons are one study each, and the deconvolution one is one participant; the documentation says so.*

### 9. Overlap correction as an ordinary step

Where events come faster than a response decays (reading, free viewing, visual search, a button press after every stimulus), an average carries parts of its neighbours' responses. Deconvolve fits every bin at once against the whole continuous recording, so a sample explained by two events is credited to both. The result comes back shaped like an average, with the same bins, so measurement, scalp maps, grand averages and the reports read it without knowing it came from a regression.

Each bin gets a formula in Unfold's own notation: an intercept by default, or factors, linear terms, splines and circular splines, with the columns the toolbox will build shown before anything is fitted. It returns one waveform per bin, overlap-corrected single trials (an ERP image with the overlap gone, and trial-level noise figures), or one waveform per model term at chosen values. It refuses what cannot mean anything: data with a DC offset, two bins over the same events, a design with too little data left after artefact exclusion. It notes two bins at a fixed lag, and warns when a modelled event outside the bins keeps a near-constant lag to another, the usual reason the solver does not converge.

*Basis: Smith & Kutas (2015), Ehinger & Dimigen (2019), Dimigen & Ehinger (2021); the fitting is Unfold's, pinned at 1.3.1, and the result was checked against the authors' script (claim 8). Unfold itself and MNE-Python's regression functions are scripting interfaces; I know of no other package that offers overlap correction from a dialog, driven by the same bins as the averages, with checks on the design before the fit.*

## Where it is at parity

*Good, not distinctive*

Filtering, resampling, re-referencing, interpolation, epoching, baseline correction and averaging are all present and all conventional. The filter design exposes a frequency and a stopband attenuation and chooses order, transition band and window itself; each channel can carry its own settings; and the dialog plots the frequency response of the kernels it will apply, which is what a methods section should report about a filter. Time windows follow FieldTrip's latency rule throughout: the nearest sample at each end, and a window wholly outside the epoch refused rather than quietly widened to all of it.

Wavelet time-frequency (now blank within half a wavelet of the epoch's ends, as FieldTrip leaves it), Fourier analysis with its phase, spectral measures for frequency-tagging and SSVEP designs (their transform and tapers the Signal Processing Toolbox's, their phase measured from the event, as FieldTrip measures it), RESS spatial filters, coherence maps and topographies (every bin's topography side by side), and scalp distributions are all comparable to what EEGLAB offers, and frequency tagging has a photodiode timing check that reports the lag and jitter of each trigger code against the diode. The ERP image sorts trials by reaction time or any event field, and averages, spectra and continuous recordings can be drawn over one another.

Eye tracking is at parity by construction: the join is EYE-EEG's own code, the same that EEGLAB users run, with Alakazam adding the file lookup by name, a refusal when the synchronisation is poor, and a line in the quality report. It reads EyeLink recordings only.

Source estimation sits here now in the full sense: at parity with FieldTrip within the scope set out at the top, on FieldTrip's template head model, electrodes and cortical sheet, and computed by FieldTrip's own functions throughout. The distributed estimates are dSPM, normalised by the noise covariance of the baseline (Average stores it, pooled over the trials as FieldTrip's tutorial and MNE estimate it, and the inverse is FieldTrip's prewhitened minimum norm), and sLORETA, with eLORETA beside them in the source reports, which also show point-spread functions. Region time courses come from an atlas by `ft_sourceparcellate`, as an ordinary dataset whose channels are regions, so Measure, grand averages and the reports read them as they read electrodes. ERPs are fitted with an equivalent dipole or a mirrored pair by `ft_dipolefitting`, as ICA components already were. LCMV and DICS beamformers map the change in power between two windows through one common filter, on the cortical sheet or on a regular volume grid, the grid drawn on slices of the template MRI by `ft_sourceinterpolate`. Cluster permutation statistics run in source space as well as on the scalp. Still absent: group statistics on beamformer maps, source-level connectivity (PCC, coherence between regions), FieldTrip's less used scanning methods (MUSIC, SAM, the residual-variance scan), and a participant's own head model, the last because that is the MRI-shaped dependency the tool deliberately does not take on. FieldTrip, Brainstorm and MNE-Python still go further where individual anatomy, MEG or source connectivity is needed; for scalp EEG on a template head, Alakazam now offers FieldTrip's main source methods from dialogs, though not the group statistics on beamformer maps that FieldTrip's tutorials end with.

Artefact handling is current, and since 30 September complete in the sense the fifth pass asked for. ICLabel for automated component classification is the field standard, and GEDAI *(Ros et al., 2025)* for generalized-eigendecomposition artefact correction is genuinely recent and kept at its newest release. PREP removes line noise, finds bad channels and computes the robust average reference through the PREP pipeline itself; ASR repairs bursts through EEGLAB's clean_rawdata; AutoReject derives per-channel thresholds by cross-validation, as autoreject does. The detection suite has ERPLAB's main detectors (absolute threshold, sample-to-sample difference, step function and moving-window peak-to-peak) and a flat-line detector, records which detector rejected which trial, and was checked against ERPLAB on Luck's data; a manual rejection view covers what no threshold catches. Where FastICA is not installed, the eye-artefact ICA runs extended Infomax without stopping to ask.

Legend: ● yes · ◐ partial · ○ no

|   | Alakazam | EEGLAB | FieldTrip | ERPLAB | BVA | MNE-Py |
|---|---|---|---|---|---|---|
| Declarative plugin registration | ● | ○ | ○ | ○ | ○ | ○ |
| Options UI generated | ● | ○ | ○ | ○ | ○ | ○ |
| Provenance without author effort | ● | ◐ | ○ | ◐ | ◐ | ○ |
| Emits a runnable script | ● | ◐ | ○ | ◐ | ◐ | ○ |
| Bin-definition language | ● | ○ | ○ | ● | ◐ | ○ |
| SME on reported scores | ● | ○ | ○ | ● | ○ | ○ |
| Per-subject QC report | ● | ○ | ○ | ◐ | ◐ | ◐ |
| TFCE by default | ● | ○ | ◐ | ○ | ○ | ◐ |
| Mixed-effects group models | ● | ◐ | ○ | ○ | ○ | ◐ |
| Design derived and shown | ● | ◐ | ○ | ○ | ○ | ○ |
| Prose statistical report | ● | ○ | ○ | ○ | ◐ | ○ |
| Usable without writing code | ● | ● | ○ | ● | ● | ○ |
| Source estimation | ● | ◐ | ● | ○ | ◐ | ● |
| Overlap correction (rERP) | ● | ◐ | ◐ | ○ | ○ | ● |
| Standard cleaning pipelines | ● | ● | ◐ | ○ | ◐ | ● |
| BIDS | ○ | ● | ◐ | ○ | ○ | ● |
| Plugin distribution channel | ◐ | ● | ○ | ◐ | ○ | ● |
| Versioned plugin API | ○ | ◐ | ◐ | ◐ | ◐ | ● |

*Moved in this pass: standard cleaning pipelines from no to yes (PREP, ASR, AutoReject); source estimation from partial to yes, on template anatomy, which is the scope this review sets (individual head models stay out by design); and the plugin channel from no to partial (installing, but not finding). Only the Alakazam column was re-checked; the others are carried over from the fourth pass.*

## What the audit found

*Eight changes that move numbers, each pinned by a test*

On 30 September and 1 October every scientifically relevant computation that Alakazam does in its own code, rather than in a toolbox's, was read beside the reference implementation that does the same. The short answer was reassuring: most of that code is either something no toolbox offers (the bin language, the photodiode check, RESS as its authors wrote it, autoreject in MATLAB) or a small computation already checked against the toolbox it replaces. One computation was plainly wrong. The rest of the list below is conventions that differed from FieldTrip's, and defects found while bringing them into line.

| Step | What was wrong | What it did |
|---|---|---|
| TimeFrequency (M26) | The baseline lay within half a wavelet of the epoch's start, where the wavelet reaches past the data, and was the mean of the dB values. | Power after the stimulus came out too high: stationary noise read +1.4 to +1.5 dB at 4 to 6 Hz. |
| Coherence Map, wavelet | Coherence was computed at the very ends of the epoch, where the wavelet is in effect shorter. | Neighbouring frequencies were mixed in exactly where an onset is read: a 60 Hz response bled into the 64 Hz row. |
| Grand average, weighted | The line was the trial-weighted mean, the band the unweighted standard error. | Band and pooled aSME did not belong to the line they were drawn around. |
| Spectral Measure, phase | Phase was measured from the epoch's first sample. | The same response read a different phase depending on how long before the event the epoch began. |
| Spectral Measure, `newcrossf` | A rejected trial reached `newcrossf` as NaN. | After any rejection, every row's coherence and phase lag were missing. |
| Baseline | One rejected sample inside the window made the mean NaN. | That channel of that trial became entirely missing. |
| DC-Detrend, continuous | The fitting range, entered in ms, was read on a time axis in seconds. | A 0 to 1000 ms range covered the first 1000 seconds. |
| Time windows, ten steps | Windows took the samples inside them; one wholly outside the epoch silently became the whole epoch. | Window ends move by at most one sample; an impossible window is now refused. |

*Nodes computed before 1 October keep their old result until they are recalculated. Alongside, defects that changed what was shown rather than what was computed: a report drew grand averages that no longer matched the tree, Derive Channels on an average left the view unable to draw it, and in the continuous view the magnification moved channels with a DC level off their rows, every redraw left another copy of each area event's label, and a stale axes width drew a sawtooth that is not in the data. The fifth pass's seven defects (Average's errors under rejection, two NaN propagations, the average reference, two in Fourier and one in RESS) are listed in that pass, in the repository's history, and in `issues.manual.md`.*

The fifth pass's defects were found by running every step on real data for the manual. These were found by reading every hand-written computation beside the toolbox that does the same, which is the more systematic of the two, and it leaves behind tests against an outside reference rather than against Alakazam's own earlier output. That is the habit that makes the rest of this page believable.

## What it lacks

*In scope, ranked by consequence*

> **Closed since the fourth pass.** Single-trial regression and deconvolution (claim 9). **Closed since the fifth:** standard automated cleaning (PREP, ASR, AutoReject, a flat-line detector); the scaffold (`newTransformation`, and the dataset contract in the developer guide); the generated dialog's ceiling (`+DialogFields`: channel and bin pickers by label, tables, checked text, previews, limits and dependent fields, to which Interpolate and Derive Channels gave up their hand-written dialogs); and file formats (EDF, BDF, GDF, Neuroscan and ANT, EGI, XDF, Micromed, Nicolet and FIF alongside the four read before, each through its dedicated EEGLAB reader with FieldTrip's File-IO as the fall-back, from one registry). Five of the fifth pass's nine gaps are gone, each closed by a plugin or a library, none by a change to what a transformation is.

### 01. BIDS

*Capability*

No BIDS import or export. In a few years this has gone from a nicety to something funders, journals and data-sharing mandates assume. A tool whose distinctive strength is reproducibility not speaking the field's reproducibility interchange format is an uncomfortable position to hold. It is now the largest capability gap.

Import is the more valuable half: it opens every public dataset to the tool, which is also the cheapest way to get people trying it. The format registry that closed the file-format gap is where a BIDS reader would go.

**Cost to close:** moderate, and well-trodden. **Blocks:** depositing data, and reading anyone else's.

### 02. The plugin contract has no version, and no views

*Architectural*

The return half of the contract is enforced: every call goes through `TransTools.invoke`, which checks the outputs (two of them, a dataset or a plot or nothing, an options struct, a consistent cancel) and reports a violation against the plugin by name, and `TransformContractTest` asserts that nothing bypasses it. The developer guide now also says what a transformation may do to the dataset it is given.

What is still missing is the half about time and environment. There is no API version, so a host change can break a third-party transformation with nothing to say which host it was written for. A plugin's manifest may now declare a `Version` of its own and the functions it `Requires`, which the installer checks and reports; but that is checked once, at installation, not when the ribbon is built, and the 41 built-in manifests still carry the same six fields, so the toolboxes Deconvolve, EyeTracking, SourceEstimate, PREP, AutoGEDAI and the source steps fetch on first use are declared nowhere. The rule that options must survive a JSON round trip, which templates and the script exporter depend on, is written down but checked only by the in-tree tests; `invoke` deliberately leaves it to a conformance check that does not exist yet.

And a plugin cannot bring a view. The plotter chooses a result's view from a list in host code, so a transformation whose result needs a picture of its own, as Dipole Fit's and Beamformer's did, needs a change to the host; one installed from outside can only produce what the existing views show.

**Cost to close:** small for the contract: an API version checked at scan time, `Requires` checked when the ribbon is built, and a conformance function an author runs, JSON round trip included. Moderate for views: a manifest field naming the view class and the field it draws, read by the plotter.

### 03. No way to find a plugin

*Architectural*

Half of this gap closed in this pass. **Install** takes a plugin from a zip file or a link (a zip on the web, or a GitHub repository, release or folder), checks it before anything is installed (a complete manifest, a name that hides nothing, a zip that writes nowhere else), shows what it found and that it is code that will run with the user's rights, and installs it outside the application, where an update leaves it. **Installed** lists each plugin with its version and where it came from, and updates or uninstalls it.

What is still missing is finding one. EEGLAB has a plugin manager with a catalogue, MNE-Python has PyPI; Alakazam installs a plugin whose link someone has given you, and nothing tells you a plugin exists, or that an installed one has a newer release. The model makes extensions cheap to write and now cheap to install; circulating them still depends on word of mouth.

**Cost to close:** small: a list of known plugins in the repository (or a GitHub topic) that the Install dialog reads, and a check of each installed plugin's recorded source for a newer release, as the application's own updater does.

### 04. The test suite runs on one machine

*Friction*

186 test classes with 1,965 tests, tagged by cost, run by hand before a push. The repository's two workflows package a release and publish the manual; neither runs a test (the manual's workflow checks only that the page it publishes is complete). So the evidence behind claims 1 to 9, the FieldTrip reference tests and the report renders included, is a green run nobody else sees, and a contributor learns about a failure from the maintainer, if at all. For a project whose credibility rests on its checks, that evidence should be public: a run on every push that anyone can inspect.

**Cost to close:** moderate. MathWorks' GitHub actions run MATLAB tests in CI, with licensing that depends on whether the repository is public; EEGLAB, FieldTrip and the pinned toolboxes have to be fetched there, the tests that need R or Quarto can run as a separate job, and the tests that need the example data need a way to reach it.

### 05. Decoding, signal regressors, and headless operation

*Lower*

No MVPA. Multivariate decoding is a legitimate scalp-EEG technique rather than an out-of-scope one, so it belongs on the list, but it is a research programme rather than a feature and MVPA-Light and MNE-Python are well established. Deconvolve regresses on events; a stimulus feature that is itself a signal (a speech envelope, a luminance trace) needs a temporal response function, which the mTRF toolbox and MNE-Python provide. And Alakazam is GUI-first: Apply to All runs on several workers, but it is started from the window, and the script exporter is a one-way door out, so cluster use is reachable only through the exported script.

**Cost to close:** high for decoding; moderate for the others. None is on the critical path.

## What it is not trying to be

*Absent by design, and rightly*

### MRI-based individual anatomy

Not source estimation, which Alakazam does and which is assessed above, but the MRI side of it: segmenting a participant's structural scan, building a subject-specific head model, coregistering digitised electrode positions to it. That is a second imaging modality with its own file formats, its own preprocessing and its own expertise, and taking it on would change what the tool is. Template head models are the right trade for a scalp workbench, and FieldTrip, Brainstorm and MNE-Python are there for anyone who needs the individual version.

### MEG and intracranial recordings

Different sensor physics, different file formats, different preprocessing conventions, different community. FieldTrip and MNE-Python serve both; a scalp EEG workbench has no obligation to. (A FIF file opens through FieldTrip's reader with every channel in it, so that its EEG can be selected.)

### Deep connectivity analysis

Coherence is present because it is useful alongside frequency-tagging work. Granger causality, phase-locking value, weighted phase-lag index and directed measures are a research programme with its own validity debates, and adding a thin version would be worse than not having one.

### Eye-movement analysis for its own sake

The eye track is joined so that it can supply events and covariates to the EEG. Fixation maps, scanpaths, reading measures and eye-tracker calibration belong to eye-tracking software; the tracker's own saccade and fixation detection is taken as it comes.

## Verdict by audience

*One paragraph each*

**A user who does not write code.** The strongest option of the six, and now including source analysis: distributed estimates, region time courses, dipole fits and beamformers, from dialogs. FieldTrip and MNE-Python are unusable without scripting. EEGLAB and ERPLAB are usable but leave you assembling the record of what you did and writing up the statistics yourself. BrainVision Analyzer is comparable on usability and costs money. Alakazam is the only one that carries you from recordings to a written, statistically defensible result without leaving the application, and the only one where the QC and the reproducibility record are produced rather than assembled. It has a manual, online, that walks through published analyses step by step, and the standard cleaning pipelines a reviewer expects to see named. Recalculate what the two defect lists touch: anything computed before 26 to 28 September for the fifth pass's, and time-frequency maps, wavelet coherence, Spectral Measure phase and its `newcrossf` coherence, weighted grand averages and DC-Detrend on continuous data computed before 1 October.

**An eye-movement, reading or fast-presentation lab.** A real option. Join an EyeLink track, take its saccades and fixations as events with their measures, fit fixation-related potentials with a spline on saccade amplitude, and look at the overlap-corrected trials in a sorted ERP image, without writing code. The limits: EyeLink only, events rather than continuous regressors, and one published figure and one participant as the check so far.

**A lab that wants its own methods in the tool.** The cheapest of the six to extend, by a clear margin, and the only one where the plumbing is free rather than boilerplate; the fortnight since the fourth pass added nine substantial methods, each as a folder. The return contract is enforced, the developer guide says what the rest of it is, a generator writes the first files, the dialog fields cover what used to force a hand-written dialog, and a plugin written elsewhere now installs from its zip or its GitHub page, checked before it runs. The qualifications: there is no versioned contract, nothing to find plugins with, and a plugin cannot bring a view of its own, so a method whose result needs a new kind of picture still needs the host changed.

**A methods developer.** Not the right home, and it should not try to be. FieldTrip and MNE-Python have the depth, individual anatomy, MEG, the connectivity and the ecosystem; Alakazam's source analysis now covers FieldTrip's main methods on a template head, but through FieldTrip, not beyond it. Alakazam's contribution is upstream of that: making a rigorous, reproducible, well-documented scalp ERP analysis something an ordinary researcher can complete correctly, overlap-corrected ones included.

> **What is checked and what is recalled.** Read from the `Development` tree on 4 October 2026, after V0.4.4.5: the 41 manifests and their fields, which transformations use the generated dialog, the format registry, the artefact detectors, the parser's error sites, the report generators and which tests render a report, the TFCE route and its equivalence test, the toolbox pins and the GEDAI updater, the two workflows, the test suite as MATLAB enumerates it, the plugin installer and its tests, the source steps added today with their tests and simulations (run, not quoted), FieldTrip's own list of source-analysis methods, and the absence of BIDS, decoding and a plugin catalogue. The audit's findings and figures are quoted from `Docs/toolbox-audit.md`, the changelog and the commits that made them; the validation figures from `Docs/luck.md`, `Docs/dimigen.md`, chapter 17 of the manual and the RESS audit, not re-run. Claims 4 and 5 were not re-read in this pass and stand as the fifth pass verified them.
>
> One thing the 30 September addendum said was too strong. It said the reports' tests check their text and not the rendered page; tests that render the ERP statistics and data-quality reports already existed, though tagged slow. Its conclusion holds for the cluster reports, which no test renders, and the box at the top says so.
>
> The other five packages are from training knowledge and are not verified. They move quickly, my information has a cutoff, and the commercial one is hardest to stay current on. Treat those columns as orientation and confirm any cell a decision rests on, particularly a ○ that would be awkward if it had since become a ●.

---

*Alakazam in-depth capability review · sixth pass, against the Development tree after V0.4.4.5, 4 October 2026.*
