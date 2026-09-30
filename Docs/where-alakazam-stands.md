# Where Alakazam Stands

*In-depth capability review · fifth pass · 28 September 2026*

A scalp ERP workbench measured against EEGLAB, FieldTrip, ERPLAB, BrainVision Analyzer and MNE-Python: what it does better than any of them, what it is missing, and what it is deliberately not trying to be.

## Since the fourth pass (21 September)

- **Overlap correction arrived.** Deconvolve fits the bins on the continuous recording through the Unfold toolbox, with a formula per bin, overlap-corrected single trials and a waveform per model term. Rebuilt from the authors' own recording, Figure 11 of Ehinger & Dimigen (2019) matches their script at *r* = 0.9998. The fourth pass's first gap is closed; it is a ninth claim below.
- **Eye tracking.** An EyeLink recording is joined onto the EEG through EYE-EEG, with the synchronisation checked and reported per subject, and a reading template runs from the eye track to deconvolved fixation-related potentials.
- **RESS for frequency tagging**, audited against Cohen & Gulbinaite's own code: the spatial filters agree to ten decimals on all ten RIFT recordings. The audit found one silent bug.
- **A 22-chapter manual** in Quarto replaced the README as the documentation; the Help button opens it, its pictures are captured from the running application, and a test fails when a transformation has no section. Writing it found seven defects in computations, listed in their own section below.
- Bayes factors in the mixed-model sections of the report, **Apply to All Raw Files** in parallel, and four releases (V0.4.4 to V0.4.4.3).
- 35 transformations instead of 32; 161 test classes holding 1,932 tests instead of 130 and 1,509.

## Addendum: 30 September

Four of the gaps below were closed two days after this pass, and one area it
rated too kindly needs saying plainly.

- **Gap 01, standard automated cleaning, is closed.** PREP, ASR and
  AutoReject are transformations of their own, and ArtefactDetect has a
  flat-line detector. PREP and ASR wrap the reference implementations (the
  PREP pipeline, pinned; EEGLAB's clean_rawdata); AutoReject implements
  autoreject's algorithm, since autoreject is a Python package, and is tested
  against a literal evaluation of its criterion. Each records what it did,
  and each has its own table in the data-quality report.
- **Gap 06, the scaffold, is closed.** `newTransformation` writes a
  transformation that runs under the contract from the start, with its test
  class, manual section and place on the Recalculate list, and the developer
  guide now states what a transformation may do to the dataset it is given.
- **Gap 07, the generated dialog, is closed.** Its fields are objects:
  channel and bin pickers by label, tables of rows, checked text, previews,
  limits, and fields that depend on others. Interpolate and Derive Channels
  lost their hand-written dialogs to it.
- **Gap 09, file formats, is closed.** EDF, BDF, GDF, Neuroscan and ANT,
  EGI, XDF, Micromed, Nicolet and FIF open alongside the four formats read
  before, each through its dedicated EEGLAB reader with FieldTrip's File-IO
  as the fall-back, from one registry.
- 38 transformations; 168 test classes.

> **The reports need extra attention.** Claim 5 below, "the report writes
> itself", is true of what the reports contain and too kind about how
> reliably they are produced. They are R and Quarto documents assembled as
> text by MATLAB, and the tests check that text (its structure, its CSV
> columns), not the rendered page, so a defect that only shows once R has run
> reaches the user first. Two were reported in the week after this pass: the cluster
> statistics report printed its significance level as an escaped
> `\(\alpha\)`, and the Reports tree listed reports from other workspaces.
> The provenance tables added for PREP, ASR and AutoReject were written
> without a render. What would close it: a rendering test in CI (with gap
> 05), a snapshot of each report's rendered text to diff against, and one
> place that escapes text for Markdown and LaTeX rather than each section
> doing its own.

## What is being reviewed

*Scope, before anything is called a gap*

Alakazam is a workbench for **scalp-recorded EEG and event-related potentials**: from raw recordings through preprocessing, epoching and averaging, to measurement, group statistics and a written result. That sentence is the whole scope, and it determines what counts as a lack.

It is not an MRI or anatomy package, and not a MEG or intracranial platform. Those need a different imaging modality or different sensor physics entirely, and marking their absence as a deficiency would be reviewing Alakazam against someone else's design brief.

Source estimation is a different matter and belongs in the review. Estimating the cortical generators of a scalp potential is an EEG technique, not an MRI one: it is done from the electrodes, and a head model can be a template rather than a participant's own scan. Alakazam does it, so it is assessed below on how far it goes rather than excluded. What is out of scope is the *MRI* half: ingesting individual structural scans to build subject-specific anatomy. Eye tracking is in scope for the same reason: joined onto the EEG, it supplies the events and the covariates of fixation-related analyses.

What follows is measured in the lane above: 35 transformations, its own bin-definition language (which now defines regression models as well as averages), measurement with error estimates, permutation and mixed-effects group statistics, five generated reports (ERP statistics, spectral statistics, data quality, scalp cluster statistics and source cluster statistics), a manual, and a plugin architecture underneath all of it.

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

*The ribbon scans `Transformations/*.json` when it is built, so there is no central list to append to and no menu code to write.*

The omissions are the point. The author writes no menu registration, no settings dialog (field types are inferred from the defaults passed in), no history or provenance bookkeeping, no replay branch beyond the four lines above, no caching and no export code.

What arrives with those three files: a ribbon button in the correct group, a generated settings dialog, settings remembered between runs, replay by dragging the branch onto another dataset, **Apply to All Raw Files** (now spread over worker processes), template replay, a node in the provenance tree, and a line in the exported analysis script. Every call also passes one seam, `TransTools.invoke`, which checks what the plugin returns and names the plugin when it breaks the contract.

The comparison that matters is EEGLAB, the only one of the five with a real plugin system. There, a plugin is an `eegplugin_*.m` that registers its own menus through `uimenu` callbacks, plus a `pop_*` function carrying a hand-written dialog and argument parsing, plus the correct `com` history string that `eegh` needs for the operation to be reproducible, plus the algorithm. Two of those files are plumbing the author writes and can get wrong, and history-string correctness in particular is a well-known source of silently unreproducible analyses. FieldTrip and MNE-Python have no plugin system at all: they are libraries, so extending means writing a function, which is simpler still and arrives with no interface, no discovery, no dialog and no provenance. BrainVision Analyzer does not admit new first-class transforms.

On the ratio of algorithm code to plumbing code, Alakazam is the best of the six. The week's additions are the evidence: Deconvolve, EyeTracking and RESS each wrap a substantial third-party method, and each is a folder, not a change to the host. That is a real architectural achievement and it is the thing to defend.

## Where it is state of the art

*Nine claims, each with what it rests on*

"State of the art" here means: reflects current published methodological best practice, and does so more completely or more accessibly than the comparison packages. Each claim below names the basis so you can check it.

### 1. Measurement error as a first-class output

Alakazam computes the standardized measurement error of every score it reports, per measurement window, per channel, choosing the estimator by score type: a closed form for mean amplitude, where the mean of the average equals the average of the per-trial means, and a bootstrap for non-linear scores such as peak amplitude and the fractional-area latencies, which have no analytic identity to exploit.

That per-window choice matters more than it sounds. A subject can be clean in one time range and hopeless in another, and a whole-recording noise summary averages exactly that distinction away. SME is also comparable across subjects and labs in a way a rejection percentage never is. Overlap-corrected trials from Deconvolve are scored the same way, so a deconvolved subject gets an SME too.

One correction this week. The aSME that Average stores with each waveform, its confidence band and its trial counts divided by every trial in a bin, rejected ones included, whenever rejection had left NaN trials in the bin: too small by the square root of kept over total, 13% with a quarter of the trials rejected. The per-window SME of the data-quality report always counted correctly. Fixed on 26 September, with a test that fails on the old code.

*Basis: Luck et al. (2021), and validated against ERPLAB 13.10's own aSME (claim 8). ERPLAB reports SME too and deserves credit for bringing it into common use; the others in this comparison do not. Alakazam's addition is the automatic analytic-versus-bootstrap choice and the per-window granularity.*

### 2. Data quality as a document, not a number

The per-subject quality report combines SME with rejection and truncation counts, per-trial noise, per-channel flagging and interpolation rates, and robust outlier detection using median absolute deviation rather than standard deviation, because with a handful of subjects the outliers being looked for would inflate an SD enough to hide inside it. It says what each cleaning step did, rectification included, and now also how well each subject's eye track was synchronised with the EEG.

Every threshold is printed alongside its reasoning, and the report states plainly that it flags rather than acts, and that exclusion criteria set after looking at the data are not exclusion criteria. That is methodological hygiene built into the output rather than left to the user's conscience.

*Basis: verified in the working tree, including the eye-tracking provenance row. I know of no comparison package that emits a per-subject QC document of this kind; the nearest is assembling one yourself from ERPLAB's numbers.*

### 3. TFCE as the default for cluster inference

Permutation testing offers threshold-free cluster enhancement as the recommended option, with classic cluster correction available as the alternative, on the scalp and in source space. TFCE removes the arbitrary cluster-forming threshold that classic cluster inference requires, and that threshold is a well-documented researcher degree of freedom.

Most packages that offer TFCE at all offer it as an option you must know to select. Making it the default is a small decision with real consequences for what gets published.

*Basis: Smith & Nichols (2009) for TFCE, Maris & Oostenveld (2007) for the permutation framework; the implementation is FieldTrip's, driven from Alakazam, with the permutations spread over the available cores. Verified: the dialog offers "TFCE (recommended)" preselected.*

### 4. Mixed models chosen from a derived design

With three or more conditions, or conditions crossed with groups or sessions, the group statistics are linear mixed models rather than repeated-measures ANOVA, so a subject missing one bin contributes their remaining bins instead of being dropped from the channel entirely. The maximal random structure the design justifies is fitted first, with an explicit, narrated fallback to random-intercept-only on a singular fit. Two conditions get a paired test.

The design itself is derived from the workspace rather than declared twice: group, person and session are read from what the user has already recorded, the model follows from that, and the random effect is grouped by *person* so somebody measured in two sessions counts once. Where the recordings cannot support a factor (an empty cell, or nobody measured twice), the report fits the simpler model and prints the reason, instead of fitting an interaction it cannot estimate and presenting the result as intended.

Where per-trial scores were exported, the report also fits the model to the trials rather than the subject averages, beside the averaged test. Each mixed-model section now also reports a Bayes factor for the effect it tests, from the model it actually fitted, so a design that fell back to a simpler model gets that model's Bayes factor.

*Basis: Barr et al. (2013) for maximal random structure, Frömer et al. (2018) and Volpert-Esmond & Bartholow (2021) for single-trial models, Rouder et al. (2012) for the default priors of `BayesFactor::lmBF`; verified in the working tree, including the fallback ladder and its printed reasons. Neither ERPLAB, FieldTrip nor BrainVision Analyzer fits mixed models at all; EEGLAB does through LIMO, which is a separate toolbox with its own learning curve.*

### 5. The report writes itself

The output is a Quarto document that renders to self-contained HTML, and opens in Word for a manuscript. Each comparison gets the one test chosen for its design, in an APA-formatted three-line table beside a violin plot of the actual distribution: its effect size, a confidence interval where one can be computed, a Bayes factor beside every *t*-test and in every mixed-model section, and a one-sentence caption saying what the test tests. A reading guide opens the document, naming only the kinds of evidence the report actually contains, and a summary closes it with every section's main test in one table, the primary tests corrected together for the false discovery rate, the secondary ones listed uncorrected, and a forest plot of the effect sizes by kind. A RESS section reports each filter's null (the filter applied where its flicker was absent) and the checks the method's authors ask a reader to make.

The generated `.qmd` is an ordinary, editable R document, not a locked format, so the user can take it over at any point; its R now lives in template files rather than in MATLAB strings. This is the feature that would make someone switch tools, and I know of nothing comparable in the other five: they hand you numbers and leave the writing to you.

*Basis: verified in the working tree and by rendering the report fixtures, including the design-aware section dispatch. On the RIFT export at Oz, the mixed-model Bayes factors for the condition effect run from 3.8 to 303. BrainVision Analyzer has report templates, but not model selection.*

### 6. The bin-definition language

A purpose-built declarative language for assigning events to bins, with sets, aliases, relations to neighbouring events, windows measured in milliseconds, samples or ordinal event position, reaction-time filtering, response-locking, an `epoch` statement and combination bins that can reference other combination bins. Since this week the same bins define a regression model: Deconvolve applies DefineBins without cutting epochs and fits one event type per bin, so one language describes both the average and the deconvolution of an experiment.

What lifts it above ERPLAB's BINLISTER, whose job it replaces, is the diagnostics: 39 distinct explanatory parse errors, each showing the offending line, a caret under the mistake, a plain-language explanation and usually a corrected example. A BINLISTER syntax error is a considerably lonelier experience. An importer translates existing BINLISTER descriptor files, flagging by hand anything with no equivalent, and on Luck's chapter 8 data it assigns every one of 642 events to the same bin as BINLISTER.

*Basis: verified in the working tree: 39 `throwParseError` sites across the parser, every example in the language reference parsed through the real engine, and the BINLISTER comparison in `Docs/luck.md`.*

### 7. Reproducibility that produces a program

Every dataset in the tree records how it was made, as typed `{id, params}` data rather than a command string to be re-executed. That record drives replay onto other datasets, and the whole tree can be exported as runnable MATLAB: looped over subjects where the pipelines match, with divergent parameters hoisted and annotated, and the bin script written as a sidecar rather than inlined. Templates carry whole analyses, and two new ones carry deconvolutions: Figure 11 of the Unfold paper, and fixation-related potentials in reading on EYE-EEG's test data.

The toolboxes the results depend on are pinned: FieldTrip to a dated build, Unfold to 1.3.1, EYE-EEG to 1.01, each installed on first use after the user agrees. A version that moved under an analysis would change published numbers without anyone choosing it, and the pin is what makes a result re-runnable on another machine a year later.

*Basis: verified in the working tree and `dependencies.md`. EEGLAB's `eegh` is the nearest equivalent and depends on plugin authors emitting correct history strings by hand; EEGLAB itself is left unpinned, which the dependencies file says.*

### 8. Checked against published outputs

Alakazam's steps have been compared with the outputs they re-implement, and the comparisons are written down in the repository. Against Luck's published stage files for the ERP CORE data, re-referencing and spherical-spline interpolation are bit-identical, the ERPLAB erpset bridge is exact both ways on all ten published N400 sets, and the chain from bins to average reproduces the book's `1_N400.erp` to 0.0004 µV with the exact accepted and rejected trial counts. Measurement and SME were checked against ERPLAB 13.10 directly.

For frequency tagging, the default coherence estimator agrees with EEGLAB's `newcrossf` to about 0.001 on ten recordings, and the group means at Oz come out at 0.283 and 0.238 against the paper's 0.280 and 0.241. RESS, given its authors' frequency grid, reproduces their spatial filters to ten decimals and their eigenvalues to four on all twenty filters of those recordings.

For deconvolution, the face-saccade recording of Ehinger & Dimigen (2019) rebuilt from a shipped template gives a stimulus waveform at Oz that correlates with the authors' own script's at *r* = 0.9998 from -200 to 1000 ms, with a largest difference of 3.2 µV; the manual lists where the analysis departs from theirs. The comparisons found and fixed three bugs, among them a moving-window artefact detector that never examined the end of the epoch and a RESS covariance that silently lost its component, and one case where Alakazam is right and ERPLAB is not.

*Basis: `Docs/luck.md`, `Docs/dimigen.md`, chapter 17 of the manual and the RESS audit, which give the precision of each comparison. The RIFT and deconvolution comparisons are one study each, and the deconvolution one is one participant; the documentation says so.*

### 9. Overlap correction as an ordinary step (new)

Where events come faster than a response decays (reading, free viewing, visual search, a button press after every stimulus), an average carries parts of its neighbours' responses. Deconvolve fits every bin at once against the whole continuous recording, so a sample explained by two events is credited to both. The result comes back shaped like an average, with the same bins, so measurement, scalp maps, grand averages and the reports read it without knowing it came from a regression.

Each bin gets a formula in Unfold's own notation: an intercept by default, or factors, linear terms, splines and circular splines, with the columns the toolbox will build shown before anything is fitted. It returns one waveform per bin, overlap-corrected single trials (an ERP image with the overlap gone, and trial-level noise figures), or one waveform per model term at chosen values. It refuses what cannot mean anything: data with a DC offset, two bins over the same events, a design with too little data left after artefact exclusion. It notes two bins at a fixed lag, and warns when a modelled event outside the bins keeps a near-constant lag to another, the usual reason the solver does not converge.

*Basis: Smith & Kutas (2015), Ehinger & Dimigen (2019), Dimigen & Ehinger (2021); the fitting is Unfold's, pinned at 1.3.1, and the result was checked against the authors' script (claim 8). Unfold itself and MNE-Python's regression functions are scripting interfaces; I know of no other package that offers overlap correction from a dialog, driven by the same bins as the averages, with checks on the design before the fit.*

## Where it is at parity

*Good, not distinctive*

Filtering, resampling, re-referencing, interpolation, epoching, baseline correction and averaging are all present and all conventional. The filter design exposes a frequency and a stopband attenuation and chooses order, transition band and window itself; each channel can carry its own settings; and the dialog now plots the impulse and frequency response of the kernels it will apply, which is what a methods section should report about a filter. Wavelet time-frequency, Fourier analysis with its phase, spectral measures for frequency-tagging and SSVEP designs, RESS spatial filters, coherence maps and topographies, and scalp distributions are all comparable to what EEGLAB offers, and frequency tagging has a photodiode timing check that reports the lag and jitter of each trigger code against the diode. The ERP image sorts trials by reaction time or any event field, and averages, spectra and continuous recordings can be drawn over one another.

Eye tracking is at parity by construction: the join is EYE-EEG's own code, the same that EEGLAB users run, with Alakazam adding the file lookup by name, a refusal when the synchronisation is poor, and a line in the quality report. It reads EyeLink recordings only.

Source estimation sits here too and has not changed since the fourth pass. The SourceEstimate transformation computes a distributed estimate against FieldTrip's template BEM head model (dSPM by default, or sLORETA), paired with template electrode positions and a template cortical sheet, and the source reports set dSPM, sLORETA and eLORETA side by side and show point-spread functions, so a reader can see how far an estimate spreads a point source. Cluster permutation statistics run in source space as well as on the scalp, and ICA components can be fitted with a single equivalent dipole. Still absent: beamformers (LCMV, DICS), dipole fits of ERPs themselves, and a participant's own head model, the last because that is the MRI-shaped dependency the tool deliberately does not take on. For a scalp workbench wanting to show plausibly where an effect arises, this is a sensible stopping point; for a source-level claim in a paper, FieldTrip, Brainstorm and MNE-Python still go considerably further.

Artefact handling is current: ICLabel for automated component classification is the field standard, and GEDAI *(Ros et al., 2025)* for generalized-eigendecomposition artefact correction is genuinely recent. The detection suite has ERPLAB's main detectors (absolute threshold, sample-to-sample difference, step function and moving-window peak-to-peak), records which detector rejected which trial, and was checked against ERPLAB on Luck's data; a manual rejection view covers what no threshold catches. Flat-line (blocking) detection is still missing.

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
| Source estimation | ◐ | ◐ | ● | ○ | ◐ | ● |
| Overlap correction (rERP) | ● | ◐ | ◐ | ○ | ○ | ● |
| Standard cleaning pipelines | ○ | ● | ◐ | ○ | ◐ | ● |
| BIDS | ○ | ● | ◐ | ○ | ○ | ● |
| Plugin distribution channel | ○ | ● | ○ | ◐ | ○ | ● |
| Versioned plugin API | ○ | ◐ | ◐ | ◐ | ◐ | ● |

*Overlap correction moved from partial to yes in this pass: Deconvolve fits the bins on continuous data through Unfold, with non-linear terms. What remains outside it are regressors that are signals rather than events, such as a speech envelope (gap 08). Only the Alakazam column was re-checked; the others are carried over from the fourth pass.*

## What the week's checking found

*Seven defects in computations, all fixed*

Writing the manual meant running every step on real data and looking at what came out, and the RESS audit compared the code line by line with its authors'. Between them they found seven defects that changed numbers. Four of them gave a plausible wrong answer rather than an obvious failure, which is the kind that survives into a paper.

| Step | What was wrong | What it did |
|---|---|---|
| Average (M1) | Standard error, aSME and trial counts divided by every trial in a bin, rejected ones included. | Bands and aSME too narrow after rejection (13% with a quarter rejected); counts, the ERPLAB export and grand-average weights too high. |
| TimeFrequency (M2) | One rejected trial made a trial sum NaN. | After rejection, the normal order, every map of that channel and bin was empty. |
| Coherence Map (M3) | The same, in the cross and auto spectra. | A channel's coherence was NaN after any rejection. |
| ReRef (M8) | A reconstructed implicit reference was added after the average reference was taken. | The reference site was left out of its own average: the average subtracted was (N+1)/N of the right one, 3% too large at 32 channels, and the channels did not sum to zero. |
| Fourier, Complex | The transform was transposed with `'`, which conjugates. | Every stored phase had the wrong sign. Magnitudes were never affected. |
| Fourier, Other (M9) | A frequency spacing coarser than the segment shortened the transform. | Only the start of each segment was transformed: 128 of 200 samples at 200 Hz, 1 s and 2 Hz. |
| RESS | A trial blanked outside the analysis window entered the covariances. | The covariances came back NaN and the component went missing without a message. |

*Each is covered by a test; for the first three the test was run against the old code and seen to fail. Nodes computed before a fix keep their old result until they are recalculated. Three display defects were fixed alongside: missing values drawn as the lowest colour in the ERP image and the time-frequency and coherence maps, and an ICA activation preview one sample long.*

Two readings of this. The worrying one is that core steps like Average had been wrong under rejection, which every real analysis uses, while the comparison with ERPLAB (claim 8) passed. The reassuring one is that the project's habit of checking found them, wrote each down with its cause, and pinned each with a test. A tool is not trustworthy because it has no bugs; it is trustworthy when its bugs are found this way and said out loud.

## What it lacks

*In scope, ranked by consequence*

> **Closed since the fourth pass: single-trial regression and deconvolution**, which was ranked first. It was the one gap that changed what a transformation could mean, and it was closed by a plugin all the same: the regression lives in one folder, and its result is shaped so the rest of the tool reads it unchanged (claim 9). What remains of it is listed under gap 08.

### 01. Standard automated cleaning pipelines

*Capability*

> **Closed on 30 September**: PREP, ASR and AutoReject, and a flat-line detector in ArtefactDetect. See the addendum.

ICLabel eye correction and GEDAI are both present and both current. What is missing is the citable, standardised pipeline: PREP for robust referencing and bad-channel detection, ASR for burst repair, autoreject for principled per-channel rejection thresholds derived by cross-validation rather than chosen by eye. Flat-line detection, the simplest of the bad-channel checks, is missing too.

This matters disproportionately for a tool whose pitch is methodological rigour. "We used autoreject" is a stronger sentence in a methods section than "we used a threshold of ±100 µV", and reviewers increasingly know the difference. It is now the largest capability gap.

**Cost to close:** moderate; ASR and PREP exist as EEGLAB plugins, and the week showed how cheaply the architecture wraps one, pin and consent included. **Blocks:** nobody, costs you in review.

### 02. BIDS

*Capability*

No BIDS import or export. In a few years this has gone from a nicety to something funders, journals and data-sharing mandates assume. A tool whose distinctive strength is reproducibility not speaking the field's reproducibility interchange format is an uncomfortable position to hold.

Import is the more valuable half: it opens every public dataset to the tool, which is also the cheapest way to get people trying it.

**Cost to close:** moderate, and well-trodden. **Blocks:** depositing data, and reading anyone else's.

### 03. The plugin contract has no version and no dependencies

*Architectural*

The fourth pass called the contract a convention held in place by habit. That was wrong: since 29 August every call goes through `TransTools.invoke`, which checks the outputs (two of them, a dataset or a plot or nothing, an options struct, a consistent cancel) and reports a violation against the plugin by name, and `TransformContractTest` asserts that nothing bypasses it. The return half of the contract is enforced.

What is still missing is the half about time and environment. There is no API version, so a host change can break a third-party transformation with nothing to say which host it was written for. All 35 manifests carry the same six fields, so dependencies are declared nowhere. Deconvolve, EyeTracking, SourceEstimate and AutoGEDAI install their toolboxes on first use, pinned and with consent, which is good behaviour at run time and invisible to the ribbon; MATLAB's own toolboxes are not mentioned at all. And the rule that options must survive a JSON round trip, which templates and the script exporter depend on, is written down but checked only by the in-tree tests; `invoke` deliberately leaves it to a conformance check that does not exist yet.

**Cost to close:** small: a version field, a `Requires` array checked when the ribbon is built, and a conformance function an author runs, JSON round trip included.

### 04. Nowhere to put a plugin, and no way to find one

*Architectural*

EEGLAB has a plugin manager, MNE-Python has PyPI, Alakazam has a folder. Sharing a transformation means sending someone a directory and telling them where to drop it; discovering that one exists is not possible at all. The application updates itself from its GitHub releases, and toolboxes are fetched on demand; plugins have nothing equivalent. The model makes extensions cheap to write and provides no way to circulate them, which is the gap between the design claim and its payoff.

**Cost to close:** small to start: a list in the repository and install-from-zip would cover most of it, and the release updater and the toolbox installers are models for the rest.

### 05. The test suite runs on one machine

*Friction*

161 test classes with 1,932 tests, tagged by cost, run by hand before a push. The release workflow renders the manual and packages the tree, and runs no test. So the evidence behind claims 1 to 9 is a green run nobody else sees, and a contributor learns about a failure from the maintainer, if at all. For a project whose credibility rests on its checks, that evidence should be public: a run on every push that anyone can inspect.

**Cost to close:** moderate. MathWorks' GitHub actions run MATLAB tests in CI, with licensing that depends on whether the repository is public; EEGLAB and the pinned toolboxes have to be fetched there, and the tests that need R or Quarto can run as a separate job.

### 06. An authoring guide, but no scaffold

*Friction*

> **Closed on 30 September**: `newTransformation`, and the dataset contract in the developer guide. See the addendum.

Narrower than a week ago. `DEVELOPER.md` now states the contract with a worked example, the rules for dialogs and for recalculation, the JSON rule, and a six-step checklist for a new transformation whose last steps are enforced by tests (the script exporter's equivalence test, and a manual test that fails when a transformation has no section). What is still missing is a generator for the three files, and a written rule for what a transformation may do to the dataset it is given: which fields it must keep, and where its own provenance goes.

The checklist also shows the design claim's small print. An in-tree transformation is now three files plus a test class, a manual section and its pictures. That is the right standard for the project, and it is more than the "three files" a third-party author needs.

**Cost to close:** a small generator, and one page on the dataset contract.

### 07. The generated dialog caps out early

*Friction*

> **Closed on 30 September**: the field types below exist (`+DialogFields`), with previews and dependent fields. See the addendum.

Inferring field types from default values is the trick that removes the UI work, and it covers dropdowns, checkboxes, numbers and text. Anything richer (a channel picker, a waveform preview, a table of formulas, a field that depends on another) needs a hand-written dialog. Of the 32 transformations with settings, 14 use the generated dialog and 18 have their own, and each of the three added this week is among the 18. At that point the headline benefit is gone and the author is writing an app.

**Cost to close:** a library of reusable field types (channels, bins, a table, a plot), so the escape hatch comes later.

### 08. Decoding, signal regressors, and headless operation

*Lower*

No MVPA. Multivariate decoding is a legitimate scalp-EEG technique rather than an out-of-scope one, so it belongs on the list, but it is a research programme rather than a feature and MVPA-Light and MNE-Python are well established. Deconvolve regresses on events; a stimulus feature that is itself a signal (a speech envelope, a luminance trace) needs a temporal response function, which the mTRF toolbox and MNE-Python provide. And Alakazam is GUI-first: Apply to All now runs on several workers, but it is started from the window, and the script exporter is a one-way door out, so cluster use is reachable only through the exported script.

**Cost to close:** high for decoding; moderate for the others. None is on the critical path.

### 09. File formats

*Trivia*

> **Closed on 30 September**: every major format opens, from one registry. See the addendum.

Reads BrainVision, EEGLAB `.set` (including an already-epoched one, whose bins are adapted into Alakazam's own), ERPLAB `.erp` and the cache, and joins an EyeLink `.asc` (or an `.edf`, when SR Research's converter is installed) onto a recording; writes `.set`, `.erp` and an ERPLAB `EVENTLIST`. No BioSemi, Neuroscan, EGI or EDF. Listed for completeness rather than as a design finding: a loader is exactly the kind of thing this architecture makes cheap, and the EEGLAB importers already exist.

**Cost to close:** low, and it is the cheapest thing on this page that would widen adoption.

## What it is not trying to be

*Absent by design, and rightly*

### MRI-based individual anatomy

Not source estimation, which Alakazam does and which is assessed above, but the MRI side of it: segmenting a participant's structural scan, building a subject-specific head model, coregistering digitised electrode positions to it. That is a second imaging modality with its own file formats, its own preprocessing and its own expertise, and taking it on would change what the tool is. Template head models are the right trade for a scalp workbench, and FieldTrip, Brainstorm and MNE-Python are there for anyone who needs the individual version.

### MEG and intracranial recordings

Different sensor physics, different file formats, different preprocessing conventions, different community. FieldTrip and MNE-Python serve both; a scalp EEG workbench has no obligation to.

### Deep connectivity analysis

Coherence is present because it is useful alongside frequency-tagging work. Granger causality, phase-locking value, weighted phase-lag index and directed measures are a research programme with its own validity debates, and adding a thin version would be worse than not having one.

### Eye-movement analysis for its own sake

The eye track is joined so that it can supply events and covariates to the EEG. Fixation maps, scanpaths, reading measures and eye-tracker calibration belong to eye-tracking software; the tracker's own saccade and fixation detection is taken as it comes.

## Verdict by audience

*One paragraph each*

**A user who does not write code.** The strongest option of the six. FieldTrip and MNE-Python are unusable without scripting. EEGLAB and ERPLAB are usable but leave you assembling the record of what you did and writing up the statistics yourself. BrainVision Analyzer is comparable on usability and costs money. Alakazam is the only one that carries you from recordings to a written, statistically defensible result without leaving the application, and the only one where the QC and the reproducibility record are produced rather than assembled. It now has a manual that walks through published analyses step by step. Recalculate anything computed before 26 to 28 September that the defect list touches.

**An eye-movement, reading or fast-presentation lab.** New on this list, and a real option since this week. Join an EyeLink track, take its saccades and fixations as events with their measures, fit fixation-related potentials with a spline on saccade amplitude, and look at the overlap-corrected trials in a sorted ERP image, without writing code. The limits: EyeLink only, events rather than continuous regressors, and one published figure and one participant as the check so far.

**A lab that wants its own methods in the tool.** The cheapest of the six to extend, by a clear margin, and the only one where the plumbing is free rather than boilerplate; this week added three substantial methods without touching the host. The return contract is enforced and the developer guide says what the rest of it is. The qualification is that this still works best when the lab extending it is also the lab maintaining it: without a versioned contract, declared dependencies or a distribution channel, a plugin written elsewhere is a folder somebody emails you.

**A methods developer.** Not the right home, and it should not try to be. FieldTrip and MNE-Python have the depth, the source analysis, the connectivity and the ecosystem. Alakazam's contribution is upstream of that: making a rigorous, reproducible, well-documented scalp ERP analysis something an ordinary researcher can complete correctly, now including the overlap-corrected ones.

> **What is checked and what is recalled.** Everything asserted about Alakazam was read from the `Development` tree on 28 September 2026, at V0.4.4.3: the 35 manifests and their fields, the `invoke` seam and its test, the developer guide, which transformations use the generated dialog, the artefact detectors, the file readers, the toolbox pins, the test count, the release workflow, and the headers of Deconvolve, the Unfold package, EyeTracking and RESS. The validation figures are quoted from chapter 17 of the manual, the RESS audit, `Docs/luck.md` and `Docs/dimigen.md`, not re-run. The defect list comes from `issues.manual.md`, the changelog and the commits that fixed them.
>
> Two things the fourth pass said were wrong when it said them. Its gap on the plugin contract missed the `invoke` seam, which had been checking every call for three weeks. And its SME claim rested partly on Average's aSME, which was too small whenever rejection had left NaN trials in a bin. Both are corrected above.
>
> The other five packages are from training knowledge and are not verified. They move quickly, my information has a cutoff, and the commercial one is hardest to stay current on. Treat those columns as orientation and confirm any cell a decision rests on, particularly a ○ that would be awkward if it had since become a ●.

---

*Alakazam in-depth capability review · fifth pass, against the Development tree at V0.4.4.3, 28 September 2026.*
