# Applied ERP Data Analysis, the Alakazam way

A chapter-by-chapter **companion** to Steven Luck's open-access textbook
**[Applied Event-Related Potential Data Analysis](https://socialsci.libretexts.org/Bookshelves/Psychology/Biological_Psychology/Applied_Event-Related_Potential_Data_Analysis_(Luck))**
(LibreTexts), which teaches the whole ERP pipeline on the **ERP CORE** datasets
using EEGLAB and ERPLAB. This guide follows Luck's chapters and works the same
steps in **Alakazam**, so you can read the two side by side. Professor Luck's book
is the authoritative source throughout: for the science, the datasets, the
analysis choices, and the reasoning behind them. Read his text first and keep it
open; this guide only shows how to carry out, in a different tool, the analyses he
teaches.

> **Please read this before relying on anything below.**
>
> **Alakazam is young**, especially next to EEGLAB and ERPLAB, which are mature,
> widely used and validated across many years and thousands of published
> studies. Alakazam's transformations wrap or re-implement the same algorithms.
>
> Several of them have now been **validated against Luck's own published output
> and against ERPLAB directly**, and where that has been done the agreement is
> exact or near-exact: see [Validation](#validation-against-lucks-own-stage-outputs) for the measurements,
> and the **Validated** column of the [coverage table](#coverage-of-the-book-chapter-by-chapter) for
> which steps they are. Filtering, ICA correction and the statistics have
> **not** been validated, and for those treat every value as **provisional**
> until you have checked it against EEGLAB/ERPLAB on the same data.
>
> For any analysis that matters, Luck's EEGLAB/ERPLAB workflow remains the
> reference. Where a chapter says a step is "covered" or "done", read it as
> *implemented*; whether it is also *verified to match* is what the coverage
> table answers, step by step.
>
> This document and Alakazam stand entirely on Steven Luck's work: the pedagogy,
> the ERP CORE data, and the analysis recipes are his. Any mistakes in translating
> them into Alakazam are ours, not his, and are far more likely than in the
> long-tested tools the book uses.

Like the book, each chapter first describes the **experiment** and the **data**,
then the analysis. It does not paraphrase Luck's text; it points you to it. The
repository ships the actual ERP CORE recordings and a ready-made workspace for
every chapter, so the walkthrough is concrete down to the event codes, epoch
windows, baseline limits, artifact thresholds and measurement windows, values all
taken from the book. Where Alakazam's chosen values differ from Luck's, both are
given, and Luck's should be treated as correct.

## What is already in the repository

- **Data:** [`Data/Luck/`](../Data/Luck), one folder per chapter that has its
  own recordings (`ch1`-`ch3`, `ch5`-`ch11`; chapter 4 is about filtering and
  reuses the N400 data, so there is no `ch4`), the ERP CORE recordings the book
  uses, one component per chapter (N400, P3b, MMN, N2pc, LRP, N170).
- **A workspace per chapter:** `Chapter1.wksp` ... `Chapter11.wksp` in the
  repository root. Each points its *Raw* folder at the matching `Data/Luck/chN`
  and preloads bin, baseline, ICA and time-frequency settings.
- **Two ready pipelines:**
  [`N400-complete.alztemplate`](../N400-complete.alztemplate), chapters 2 and 3
  end to end from the files `ch3` ships (filter through measurement and
  topography, see [Appendix 3](#the-fullest-chain-ready-to-run)), and
  [`N400.alztemplate`](../N400.alztemplate), the full N400
  recipe as a re-appliable template.
- ERPLAB source files sit next to the data (`BDF_*.txt` bin descriptor files,
  `*.binscript` saved bin scripts, `BinOps_*.txt` bin-operation files), so you
  can compare Alakazam's bin language with the ERPLAB originals directly.

To start a chapter: **File > Open WorkSpace**, choose `ChapterN.wksp`. Every
recording in that chapter's folder loads as a root node in the **Data &
Analyses** tree, and the ribbon dialogs are pre-seeded with that chapter's
settings.

## The ERP CORE dataset

All seven ERP CORE components come from the same 40 neurotypical adults, each of
whom completed every paradigm (Kappenman et al., 2021). Recordings use a
common montage of scalp electrodes plus horizontal and vertical EOG. The book
(and this guide) uses one component per chapter:

| Chapter | Component | Data folder | What it teaches |
|---|---|---|---|
| 1 | N400 | `ch1` | first steps: load a `.set` and an `.erp` |
| 2 | N400 | `ch2` | the single-participant pipeline end to end |
| 3 | N400 | `ch3` | many participants, grand average |
| 4 | (N400) | -- | filtering, in depth |
| 5 | N400 | `ch5` | referencing, montage editing, resampling |
| 6 | P3b | `ch6` | bins, averaging, baseline, data quality (aSME) |
| 7 | MMN | `ch7` | inspecting the EEG, interpolating bad channels |
| 8 | MMN, N2pc | `ch8` | artifact detection and rejection |
| 9 | MMN | `ch9` | artifact correction with ICA (automatic and manual) |
| 10 | LRP (Flankers) | `ch10` | scoring amplitudes and latencies, statistics |
| 11 | N170 | `ch11` | scripting and automation |

## Orientation, in one screen

- A **workspace is three folders**: *Raw* (recordings), *Cache*
  (`Data/Cache/`, where results and the tree live) and *Exports*
  (`Data/Exports/`). Saving a workspace writes them to a `.wksp` file you
  choose (plain JSON); the chapter workspaces in the repository root are
  exactly such files.
- You process by **building a tree**, not by running a script. A raw import is a
  root node; each ribbon transformation adds a child; a subject's whole analysis
  is a branch.
- The ribbon groups transformations like the book's pipeline:
  *1. Preprocessing* (SelectData, ReRef, Resample, Filter, Baseline, Interpolate,
  ChannelEditor, Average, Rectify, DC-Detrend, EventEditor, Photodiode,
  Derive Channels),
  *2. Artifact Rejection / Reduction* (ArtefactDetect, AutoICA, ICA,
  ManualReject, AutoGEDAI), *3. Segments* (DefineBins),
  *4. Frequency and Component Analysis* (Fourier, Welch PSD, Spectral Measure,
  ERP Measure, Covariance, Cross Correlation, Source Estimate),
  *5. Plots* (Scalp, TimeFrequency, Coherence Map, CohTopo, Brain (3D)). A
  **Grand Average** tab builds group results; a **Measurements** tab scores and
  exports. The eye-correction step is labelled **AutoICA** on the ribbon, while
  its function and its stored settings key are both `AutoEyeICA`, which is the
  name a template or a `.wksp` file shows.
- **Reproducibility is templates**, not `.m` files: any branch saves as a
  template and re-applies to other subjects, and any step's parameters can be
  edited and recomputed down the branch ("Recalculate", written back to disk so
  it survives a restart).

Import formats: BrainVision (`.vhdr`), EEGLAB (`.set`), MATLAB (`.mat`), ERPLAB
erpsets (`.erp`).

---

## Why the pipeline looks the way it does

Before the chapters, a short primer on *what* each stage is for. This is a brief,
non-authoritative summary of ideas Luck develops properly, and far more carefully,
in the book; it is here only to make the Alakazam steps legible, not to teach the
methodology, which is his book's job. Where this summary and Luck's text seem to
disagree, Luck is right and this is wrong.

**What an ERP is.** The scalp EEG is a continuous mixture of many overlapping
brain (and non-brain) sources. An event-related potential is the small,
time-locked response to a class of events (a stimulus, a response), recovered by
**averaging** many trials of the same type: activity that is consistently
time-locked to the event survives averaging, while activity that is not
time-locked averages towards zero. Two consequences drive the whole pipeline.
First, the ERP you measure is only as clean as the trials you average and the way
you align and score them, so most of the work is about protecting the average
from distortions (drift, blinks, bad channels, mislabelled events). Second,
because the raw waveform at any electrode is a *sum* of components, the effect you
care about is usually isolated with a **difference wave** between two conditions
that are matched on everything except the process of interest.

**Epochs, baselines, and the time axis.** Averaging requires cutting the
continuous record into fixed **epochs** locked to each event (for the ERP CORE
components, typically a couple of hundred milliseconds before the event to several
hundred after). The prestimulus interval is assumed to contain no event-related
signal, so subtracting its mean, **baseline correction**, removes slow offsets and
puts every epoch on a common zero. The choice of baseline window is a real
decision: too short and it is noisy; overlapping the response and it biases the
component. Alakazam keeps the epoch definition (in DefineBins) and the baseline
(a separate Baseline step) as distinct, editable nodes so you can revisit either.

**Filtering is a trade-off, not a clean-up.** A high-pass filter removes slow
drift (skin potentials, sweat, movement) that would otherwise ride under the ERP;
a low-pass removes high-frequency noise (muscle, line noise, amplifier noise). But
filters are not free: they redistribute energy in time, so an aggressive high-pass
can introduce artificial opposite-polarity lobes around a real component, and a
low-pass smears onsets and latencies. The standard cognitive-ERP compromise, and
the one the book uses for the N400, is a gentle **0.1 Hz** high-pass and a modest
low-pass, applied to the *continuous* data before epoching so edge effects fall
outside the analysis window.

**Referencing.** Voltage is only defined relative to a reference, so every ERP is
implicitly "channel minus reference". Changing the reference changes the shape and
scalp distribution of every waveform without changing the underlying data, which
is why the book ships the N400 under three references. Common choices are the
**average** of all scalp electrodes and a pair of **mastoids**; the right one
depends on the component and the montage.

**Artifacts: reject or correct.** Blinks, eye movements, muscle and a bad channel
add large voltages that are not brain activity. Two strategies exist. **Rejection**
throws away contaminated epochs; it is simple and safe but costs trials, and for
blink-heavy data can cost too many. **Correction** estimates the artifact and
subtracts it while keeping the trial, most commonly with **ICA**: decompose the
EEG into maximally independent components, identify the ocular ones (by their
frontal topography and time course, aided by **ICLabel**), and project them out.
The pipeline offers both, and they compose: correct the blinks with ICA, then
reject whatever gross artifacts remain.

**Bad channels and interpolation.** A single dead or noisy electrode corrupts any
measure that pools across channels (an average reference, ICA, a topography).
Rather than lose the site, its signal is reconstructed from its neighbours by
spherical-spline **interpolation**, which keeps the channel count identical across
subjects, a prerequisite for group statistics.

**Measurement.** Turning a waveform into a number is itself a design choice with
real consequences. **Peak amplitude** (the most extreme point in a window) is
intuitive but biased by noise and by the number of trials, and it is not additive
across the components that sum into the waveform. **Mean amplitude** (the average
over a window) is unbiased, additive, and far more robust, which is why it is the
default recommendation for most amplitude effects. For latency, the peak is again
fragile; **fractional area latency** (the time at which a set fraction of the
component's area has accumulated, e.g. 50%) is a stabler onset/timing measure, and
is the one the book uses for the LRP. Alakazam's ERP Measure implements all of
these so you can match the measure to the question.

**Data quality (aSME).** How much can you trust a single number? The
**standardized measurement error** answers this directly: it is the standard error
of your measurement, estimated from the single-trial values, so it is in the same
units as the score and comparable across conditions, subjects and labs. It makes
"how noisy, on how many trials" a reported quantity rather than a guess.

**Reproducibility.** Every one of these choices is a parameter, and a real study
applies the same choices to dozens of subjects and revisits them when a reviewer
asks. In a script that means re-running code; in Alakazam it means a **template**
(the branch of choices) applied across subjects, and **Recalculate** to change a
choice and let it flow downstream. The tree *is* the record of what you did.

---

## Chapter 1 -- First Steps

**In the book.** Install EEGLAB/ERPLAB, meet the N400 experiment, and open one
participant's data.

**The experiment (N400).** A word-pair semantic priming task. On each trial a
**prime word** (shown in red) is followed by a **target word** (shown in green),
and the participant presses one of two buttons to judge whether the target is
semantically **related** to the prime (e.g. CHAIR after TABLE) or **unrelated**
(e.g. SPIDER after RAKE); related and unrelated pairs are equally likely. The
**N400** is a broad negativity from roughly 200 to 600 ms, peaking near 400 ms,
**larger (more negative) for unrelated targets**, maximal at central-parietal
sites (CPz). It is isolated as the unrelated-minus-related difference wave on the
target words.

**The data.** `Chapter1.wksp` -> `Data/Luck/ch1`: one participant, two ways.
`1_N400_preprocessed.set` is the continuous, already-preprocessed EEG;
`1_N400_erp.erp` is a finished ERPLAB erpset holding **two** collapsed bins
("All Unrelated, Correct" and "All Related, Correct"). The four-bin erpsets,
one per prime/target x related/unrelated cell, are the `premade erp` files in
`ch3`.

**In Alakazam.**

1. Open `Chapter1.wksp`. Both files load as root nodes: the `.set` with a
   person-shaped "raw" badge, the `.erp` with an "averaged" badge (Alakazam
   reads ERPLAB erpsets directly, see [erpset support](../src/IO/erpsetToAveraged.m)).
2. Click `1_N400_preprocessed` for the scrolling **SignalView** (pan / zoom /
   magnify sliders, mouse-wheel scroll; the display scales off the EEG channels
   only, so a big EOG channel does not squash the trace).
3. Right-click -> **List events** to see the eight stimulus codes and the one
   response code (listed in Chapter 2).
4. Click `1_N400_erp` to see its two averaged bins immediately, no processing.

**Difference.** Nothing to install and nothing to keep in sync: a persistent
on-disk tree replaces EEGLAB's one-dataset-per-window model.

---

## Chapter 2 -- Processing one participant (the N400 pipeline)

**In the book.** Filter, create an EventList, assign events to bins with
BINLISTER, epoch and baseline-correct, detect artifacts, and average.

**Why the bin definitions are the crux.** Everything downstream depends on which
events go into which average. A **bin** is just "the set of events of one
experimental condition", and getting it right is a matter of reading the event
codes precisely and, often, of *conditioning on context*: an N400 target counts
only if the participant answered correctly and in time, so the bin is not "all
unrelated targets" but "unrelated targets followed by a correct response within a
window". This is why the definition language has anchors (the event to lock to),
relations (was it related or unrelated) and temporal constraints (was the response
in [200, 1500] ms). The **difference wave** that isolates the component
(unrelated minus related targets) is defined here too, as a bin computed from
other bins, because the whole point is to subtract away everything the two
conditions share and leave only the process of interest. Get the bins right and
the rest of the pipeline is bookkeeping; get them wrong and a perfect filter and a
clean average still measure the wrong thing.

**The experiment (N400).** As in Chapter 1. The **event-code scheme** is the key
to the bins: the first digit is stimulus type (**1** = prime, **2** = target),
the second is relatedness (**1** = related, **2** = unrelated), and **201** is a
correct behavioural response. So `111`/`112` are related primes, `121`/`122`
unrelated primes, `211`/`212` related targets, `221`/`222` unrelated targets;
a target counts only if a correct response (`201`) follows **200 to 1500 ms**
later. The book's worked bin descriptor file, `BDF_N400.txt` (shipped in `ch2`):

```
Bin 1
Prime word, related to subsequent target word
.{111;112}

Bin 2
Prime word, unrelated to subsequent target word
.{121;122}

Bin 3
Target word, related to previous prime, followed by correct response
.{211;212}{t<200-1500>201}

Bin 4
Target word, unrelated to previous prime, followed by correct response
.{221;222}{t<200-1500>201}
```

**The data.** `Chapter2.wksp` -> `Data/Luck/ch2`: the preprocessed N400 `.set`,
plus the ERPLAB `BDF_N400.txt`, its saved `BDF_N400.binscript`, and `n400.alm`.

**In Alakazam.** Select the `..._N400_preprocessed` node and apply, in order:

1. **Filter** (Preprocessing). Book setting: a **0.1 Hz** high-pass,
   half-amplitude cutoff, 12 dB/octave, on the continuous data (no low-pass, the
   recording is already low-passed). Tick High-pass, enter `0.1` Hz and a dB
   attenuation (e.g. 40). See Chapter 4.

2. **DefineBins** (Segments) does EventList + BINLISTER + epoching in one
   step. `Chapter2.wksp` preloads this script (the alias/wildcard form) with
   **Epoch start -200** and **stop 800**:

   ```
   let prime     = {111, 112, 121, 122}
   let target    = {211, 212, 221, 222}
   let related   = "?1?"
   let unrelated = "?2?"
   bin 1 "Prime, related"    (prime and related)
   bin 2 "Prime, unrelated"  (prime and unrelated)
   bin 3 "Target, related"   (target and related)   and next("201") within (200,1500] ms
   bin 4 "Target, unrelated" (target and unrelated) and next("201") within (200,1500] ms
   ```

   The wildcards read the code scheme directly: `"?1?"` matches any code whose
   middle digit is 1 (related), so `target and related` resolves to `211`/`212`.
   You can instead reproduce ERPLAB's file with **Import BDF...** on
   `BDF_N400.txt`; Alakazam translates the timing flag `t<200-1500>` into
   `within [200,1500] ms`. The shipped `BDF_N400.binscript` is that import plus
   two hand edits, a braced code set rewritten as `111|112` and the difference
   bin added, since the BDF itself defines only four bins:

   ```
   bin 1 "Prime word, related to subsequent target word" : 111|112
   bin 2 "Prime word, unrelated to subsequent target word" : 121|122
   bin 3 "Target word, related to previous prime, followed by correct response" : 211|212 and next(201) within [200,1500] ms
   bin 4 "Target word, unrelated to previous prime, followed by correct response" : 221|222 and next(201) within [200,1500] ms

   bin 5 "N400" = bin 4 - bin 3
   ```

   The last line is the **N400 difference wave** (unrelated minus related
   targets), a combination bin evaluated after averaging with propagated error.

3. **ArtefactDetect** (Artifact Rejection). Book setting for this chapter: a
   simple voltage threshold of **+/- 100 microvolts**. Tick **Absolute threshold**
   and enter Minimum `-100`, Maximum `100`. (ArtefactDetect also offers the step,
   moving-window and sample-to-sample detectors, and lets you tick several at
   once, see Chapter 8.)

4. **Baseline** (Preprocessing), **before** averaging. The book corrects on the
   whole prestimulus interval (**-200 to 0 ms**, ERPLAB "Pre"); `Chapter2.wksp`
   preloads a tighter **-100 to -10 ms**. Set Start/Stop to your preference.
   Baseline needs segmented data, so it belongs between DefineBins and Average;
   run it on an Average node and it will tell you it needs epochs.
   (`N400.alztemplate` and Appendix 3 use this order, and in the book the
   baseline is subtracted as the epochs are cut.)

5. **Average** (Preprocessing) produces the four per-bin ERPs (plus the bin 5
   difference wave), each with a standard error, an accepted trial count, and its
   **aSME** data-quality value (Chapter 6).

Plot the **Average** node for the waveforms with standard-error bands
(AverageView), and add a **Scalp** plot for the N400 topography.

**As a template.** `N400.alztemplate` in the root is this whole pipeline
pre-built (`AutoGEDAI -> DefineBins -> Baseline -> ArtefactDetect -> Average ->
ERP Measure`); apply it to any raw node (Chapter 3).

---

## Chapter 3 -- Processing multiple participants

**In the book.** Run the pipeline on every participant and make a grand average.

**The experiment (N400).** As in Chapter 2, now across many of the 40
participants.

**The data.** `Chapter3.wksp` -> `Data/Luck/ch3`: several participants'
preprocessed N400 `.set` files, plus a `premade erp` folder of finished erpsets
you can grand-average directly.

**In Alakazam.**

1. Build the Chapter 2 branch on the first participant.
2. Right-click its first transformation -> **Save Template...** (Alakazam walks
   the whole branch, forks and all, into a portable `.alztemplate`).
3. **Apply Template...** to each other participant, or **Apply to All Raw Files**
   to replay it across the folder in one action (or drop in `N400.alztemplate`).
4. **Grand Average** tab -> **Define Grand Average...**: pick the participants'
   Average results, name it, choose weighted or unweighted; it lands in the
   separate **Grand Averages** tree. To use the ready erpsets instead, put the
   `premade erp` files in *Raw* and grand-average those.
5. Measure the N400 and export (Chapter 10).

**Difference.** The template is the batch recipe and preserves forks, so
per-subject plots and measures are recreated for everyone; no scripting needed.

---

## Chapter 4 -- Filtering the EEG and ERPs

**In the book.** High-pass to remove drift, low-pass to remove high-frequency
noise; mind the filter artifacts. The N400 pipeline uses a **0.1 Hz** high-pass
(half-amplitude cutoff, 12 dB/octave) on the continuous EEG.

**Why it matters.** Filtering is the step most likely to quietly distort a result,
because a filter always trades frequency selectivity against temporal fidelity. A
high-pass with too high a cutoff (say above ~0.3 Hz for slow cognitive components)
does not merely remove drift: it subtracts a smoothed copy of the signal, which
can carve artificial opposite-polarity bumps on either side of a genuine
component and can shrink sustained potentials that live partly at low frequencies.
A low-pass with too low a cutoff rounds off sharp onsets and pushes peak latencies
later. The safe defaults are conservative for exactly this reason: a gentle
**0.1 Hz** high-pass removes drift while barely touching the ERP, and a low-pass
only as aggressive as the noise demands. Filtering the **continuous** record
(before epoching) keeps the filter's edge transients at the ends of the recording,
well outside any epoch, rather than at the edges of every epoch.

**In Alakazam.** The **Filter** transformation is an EEGLAB-grade FIR
windowed-sinc filter: it designs a Kaiser-windowed kernel with the firfilt
plugin's own helpers (`firwsord`, `kaiserbeta`, `firws`) and applies it
zero-phase with `firfilt`. That is a **linear-phase** design, so it delays
every frequency equally and does not smear component *shapes* the way a
minimum-phase IIR filter can. You give each filter a **frequency** and a **dB**
stopband attenuation; the filter order and transition bandwidth needed to reach
that attenuation are computed for you. High-pass, low-pass and notch are
independent toggles, with a **per-channel** mode. Filter the *continuous*
recording before DefineBins.

- N400 high-pass: High-pass, `0.1` Hz, e.g. 40 dB attenuation.
- A cognitive low-pass: Low-pass, `30` Hz (or `20` Hz for publication smoothing).
- Line noise: a notch at `50`/`60` Hz only if a low-pass has not already removed
  it (a low-pass below the line frequency makes the notch redundant).

Because Filter is a node, you can build two branches from the same raw import with
different cutoffs and overlay their Averages to *see* what the filter did to your
component before committing, the practical antidote to filter distortion.

**Difference.** You dial a cutoff and a dB attenuation rather than a filter
order and a window type, the more interpretable knob for the same FIR design.

---

## Chapter 5 -- Referencing and other channel operations

**In the book.** Re-reference (average, mastoid, etc.), edit the channel montage,
and resample.

**Why it matters.** A single electrode measures a *voltage difference* against
whatever the amplifier used as reference, so there is no such thing as the
absolute potential at a site. Re-referencing recomputes every channel against a
new baseline (a specific electrode, the average of a pair, or the mean of all
scalp channels), which can move a component's apparent peak, flip its sign at some
sites, and reshape its scalp map, all without adding or removing any information.
The choice interacts with the component: an **average reference** is even-handed
across the head but needs good, whole-head coverage and no bad channels dragging
the mean; **linked/averaged mastoids** are conventional for midline components
like the P3b but sit near the neck and can attenuate posterior activity. Because
the map you interpret and the number you measure both depend on this choice, the
book ships the same N400 under three references to make the effect concrete.

**The experiment (N400).** Same recording as Chapter 2, provided under three
references so you can see referencing change the waveforms.

**The data.** `Chapter5.wksp` -> `Data/Luck/ch5`: the same participant as
`..._N400_unreferenced.set`, `..._N400_CzRef.set` (referenced to Cz) and
`..._N400_LmRef.set` (left-mastoid reference).

**In Alakazam.**

- **ReRef** on `..._unreferenced`: choose **Average** reference, or **Specific
  channels** (e.g. the mean of the two mastoids), exclude non-scalp channels from
  the reference, and optionally keep the reference channel. Plot it next to the
  provided `CzRef` and `LmRef` versions to compare.
- **ChannelEditor** (Preprocessing) is the Alakazam counterpart of `pop_chanedit`:
  edit channel **labels**, **types** and **X/Y/Z coordinates** in a table.
  **Look up 10-5 locations** fills coordinates by matching labels to the standard
  template (and, at the same time, guesses each channel's **type** from its label,
  so EOG/ECG/... are marked and no longer treated as scalp EEG). **Load
  montage...** reads a channel-location file (`.ced`, `.locs`, `.elc`, `.sfp`,
  `.xyz`, ...). Only the geometry changes; the data is untouched.
- **Resample** (Preprocessing) changes the sampling rate of a continuous
  recording (`pop_resample`); enter the new rate in Hz.
- **SelectData** for channel/time/point/trial keep-or-remove: drop a dead
  channel, or crop to a window.

---

## Chapter 6 -- Bins, averaging, baseline, and data quality

**In the book.** The BINLISTER + averaging + baseline mechanics, plus data
quality, on the **P3b** experiment.

**The experiment (P3b).** An active visual oddball built on the "Hillyard
principle" (keep the stimuli constant, vary only the task). The letters
**A, B, C, D, E** appear in random order, each 20% probable. Across 5 blocks of
40 trials a **different letter is the target** in each block; the participant
presses one button for that block's target and another for the four non-targets.
The same physical letter is therefore in the **Rare** category (the target,
~20%) in one block and the **Frequent** category (a non-target, ~80%) in others.
The **P3b** is larger for the Rare than the Frequent category, ~300 to 600 ms,
maximal at **Pz** (referenced to the average of P9 and P10), and isolated as the
rare-minus-frequent difference wave.

**The data.** `Chapter6.wksp` -> `Data/Luck/ch6`: many participants'
`..._P3_corrected.set`.

**In Alakazam.**

- **DefineBins** replaces EventList + BINLISTER: write one line per bin with
  anchors and relations, and a **difference bin** for the effect, e.g.
  `bin 3 "P3b" = bin 1 - bin 2` (rare minus frequent). **Import BDF...** reads a
  P3b bin descriptor file. Epoch the P3b at, say, `-200` to `800`.
- **Baseline** does the prestimulus subtraction, on the segmented data, before
  averaging.
- **Average** gives each bin's ERP with a standard error and trial counts and
  evaluates the difference bins.

**Why data quality is its own step.** A grand-average waveform can look clean and
still rest on a handful of noisy trials. Two subjects, or two conditions, can
differ in a component simply because one had more usable trials or a quieter
recording, not because their brains differed. The **standardized measurement
error** makes that risk visible: rather than a vague "signal-to-noise", it reports,
in microvolts, how much your specific measurement would wobble if you re-ran the
session, estimated from the spread of the single-trial values divided by the
square root of the trial count. Because it is in the same units as the score and
on the same footing across conditions and people, you can compare data quality
directly, drop or down-weight subjects on a principled threshold, and report a
number instead of an impression. The standardized measurement error, and the case
for reporting it, is developed in Luck's book (and the work it builds on); the
summary here does it no justice.

**Data quality (aSME) in Alakazam.** **Average** computes the analytic aSME for
the mean amplitude, per bin and channel, from the single-trial amplitudes; it is
propagated correctly through **difference bins** (the errors add in quadrature),
shown in **AverageView** as a per-channel readout, and **pooled across subjects**
on the Grand Average (a root-mean-square over the count of contributing subjects).
It sits alongside the pointwise **standard-error band** (the shaded ribbon around
each waveform, which shows quality resolved across time) and the **trial counts**,
so "how noisy, on how many trials" is answered both as the formal aSME and
visually.

**The Data Quality Report.** The value above is computed over the whole epoch,
which is a summary rather than the quantity Luck argues for: SME describes the
error on a specific score, so it belongs to a measurement window. The
**Data Quality Report** (Export/Report tab) computes it per **Measure** window
across every subject in the workspace, analytically for mean amplitude and by
bootstrap for peak amplitude, peak latency, area and the fractional latencies,
which have no closed form. The same report covers rejection and truncation
counts per subject and per bin, per-trial noise, a per-channel noise map, and
the **number of trials flagged per channel per subject** as a count rather than
a proportion, which is what a decision to interpolate or drop a channel
actually rests on. Its organising concern is whether trial loss is even across
conditions, since uneven loss affects the validity of the contrast rather than
only its power. See [Data quality](../README.MD#data-quality).

**Dependability, where per-trial scores exist.** SME says what the loss cost in
the units of the measure. It does not say whether the measure is reliable
enough to correlate with anything, which is the question behind "how many
trials do I need". Where `Measure` has been run on the **epoched** node rather
than on the Average, the report decomposes single-trial variance into
between-person and within-person parts with a random-intercept model and
reports the **dependability** coefficient from generalizability theory
(Clayson & Miller, 2017), together with the trial count a dependability of .70
or .80 would need for that score, at that channel, in that condition. Read
those counts as design numbers rather than criteria: they assume the trials you
would add resemble the ones you have, which fatigue and drift make less true
towards the end of a session.

**Is there a "good" aSME?** There is no universal threshold: the value is in
microvolts and depends on the component, montage, reference, filter, measurement
window and trial count, so a number that is fine for a large slow component (P3b)
would be poor for a small fast one (N170). It is meant for *relative* comparison,
not a fixed pass/fail cutoff. Published **benchmarks** do exist to compare against:
the SME metric was introduced by Luck, Stewart, Simmons & Kappenman (2021), and the
ERP CORE paper (Kappenman et al., 2021) reports per-component data-quality figures
for exactly these datasets, the natural reference for this walkthrough. Use them
that way, against a published value for the same component and measurement, or
across your own conditions, subjects and labs, rather than as a hard cutoff. Two
cautions before comparing to a published number: match the **measurement window and
measure** (Alakazam reports the aSME of the mean amplitude over the analysis window;
a benchmark computed on a different window, or on a peak measure, is not comparable),
and note which part of the aSME has been checked: the analytic aSME of the mean
amplitude matches ERPLAB on every cell of a subject's erpset (see
[Validation](#validation-against-lucks-own-stage-outputs)), while its propagation through difference bins and
its pooling across subjects on the Grand Average have not been compared to
anything.

---

## Chapter 7 -- Inspecting the EEG and interpolating bad channels

**In the book.** Scroll the continuous EEG to find bad channels and intervals,
then interpolate bad channels from their neighbours, on the **MMN** data.

**The experiment (MMN).** A **passive** auditory oddball. Frequent **standard**
tones and rare **deviant** tones, differing only in intensity (the ERP CORE
version uses an 80 dB standard, ~80% of trials, and a softer 70 dB deviant,
~20%), are presented while the participant **watches a silent video and ignores
the sounds**. The **mismatch negativity** is the **deviant-minus-standard**
difference, a frontocentral negativity around 125 to 225 ms that arises without
attention.

**Why inspect, and why interpolate.** Automatic pipelines hide problems that a few
minutes of scrolling would catch: a channel that drifted or went flat halfway
through, a run of movement, a mislabelled event. Looking at the continuous EEG is
not optional polish, it is how you learn what your automatic steps will have to
cope with. When one electrode is genuinely bad, you face a choice: remove it, or
reconstruct it. Removal is safe but changes the channel set, which breaks an
average reference and makes cross-subject comparison awkward; **interpolation**
estimates the missing channel from its neighbours (weighting nearby electrodes
more), so the montage stays intact and every subject keeps the same channels. It
is a genuine estimate, not new data, so it is for the occasional bad channel, not
a way to rescue a recording where many electrodes failed.

**The data.** `Chapter7.wksp` -> `Data/Luck/ch7`: `..._MMN_preprocessed.set`.
`ch8` also ships pre-interpolated files (`..._MMN_preprocessed_interp.set`) so you
can compare.

**In Alakazam.**

- **Inspecting** is well covered: **SignalView** scrolls the continuous data
  (pan/zoom/magnify, mouse wheel), scales off the **EEG channels only**, and
  shows a **channel scrollbar** for dense montages. **EpochView** gives a
  per-channel ERP-image (trials x time) for spotting bad trials.
- **Interpolate** (Preprocessing) reconstructs a bad channel from its neighbours
  (`pop_interp`): pick the bad channel(s) from a multi-select list and a method
  (**spherical spline**, **inverse distance**, or **spacetime**). It needs channel
  positions, so run a montage lookup first (Chapter 5) if the dataset has none.
  Interpolating (rather than removing) keeps the channel set identical across
  subjects, which matters for a group analysis.

---

## Chapter 8 -- Artifact detection and rejection

**In the book.** Several detectors (absolute threshold, step function for blinks,
moving-window peak-to-peak, sample-to-sample, etc.), on the **MMN** and **N2pc**
data.

**The experiments.** **MMN** as in Chapter 7. **N2pc** is a lateralized visual
attention task: on each trial a bilateral array appears and the participant
attends to a target defined by a pre-cued colour in one hemifield (ignoring an
equivalent item in the other) and reports a feature of it. The **N2pc** indexes
the covert shift of attention and is isolated as the **contralateral-minus-
ipsilateral** difference (relative to the attended side), ~200 to 275 ms at
lateral posterior sites (PO7/PO8).

**The data.** `Chapter8.wksp` -> `Data/Luck/ch8`: `..._MMN_preprocessed.set` and
its `..._interp.set`, `..._N2pc_ICA_preprocessed.set` and its `..._epoched.set`,
plus the ERPLAB `BDF_MMN.txt` and `BDF_N2pc.txt`.

**Why several detectors.** No single rule catches every artifact, because
different artifacts look different in the signal. A blink is a large, slow
frontal deflection best caught by a **step**-like change; a saccade is a sharp
transition; muscle shows up as fast, low-amplitude jitter; a movement or a bad
segment as a large **peak-to-peak** swing; a single corrupted sample as a
one-sample jump. A plain absolute-voltage limit catches the biggest problems but
misses a fast blink that never crosses the threshold, and a threshold tuned tight
enough to catch it would reject good data. So the detectors are complementary, and
the right policy is usually to run a few together. Two further choices matter: the
**test window** (restrict detection to the interval you care about, so an artifact
in the far prestimulus period does not needlessly cost you a trial), and the
**scope** (reject the whole epoch, the conservative ERP default, versus flagging
just the offending channel). Rejection always costs trials, which is why the book
pairs it with correction (Chapter 9): correct the blinks, reject the rest.

**In Alakazam.** **ArtefactDetect** reproduces (and extends) ERPLAB's detector
set, with the thresholds and windows named the same. The trial-by-trial flags
have been checked against ERPLAB's own on Luck's chapter 10 data: the absolute
threshold agrees on all 346 trials, and the two detectors together reproduce
ERPLAB's rejection list exactly (see [Validation](#validation-against-lucks-own-stage-outputs), which also
records the one artefact Alakazam catches and ERPLAB misses). Tick **one or
more** of:

- **Absolute threshold** -- any sample outside [Minimum, Maximum] uV (default
  **+/- 100 uV**).
- **Step function** -- a moving window whose first-half vs second-half mean
  differs by more than a threshold (blinks, saccades).
- **Moving-window peak-to-peak** -- max-minus-min within a sliding window exceeds
  a threshold.
- **Sample-to-sample** -- any single-sample jump exceeds a threshold (transients).

Ticking **none** leaves the data untouched and reports that it did so. Earlier
versions silently fell back to the absolute threshold in that case, which meant
an empty selection quietly rejected on a default nobody had chosen; if you have
`ArtefactDetect` nodes built before this change with no detector selected, their
rejections came from that fallback and are worth recalculating.

A channel is flagged if **any** ticked detector trips. Detection runs over a
**test window** (blank = the whole epoch), and a hit either rejects the **whole
epoch** (all channels, the ERP-standard default), marks **just that channel**,
or **interpolates that channel** from its neighbours for that trial; rejected
data is set aside so averaging omits it.

**Which channels are tested** is a separate choice, and it matters more than it
looks. The default is every channel, which is what makes a blink on VEOG reject
the trial, the classic rejection this chapter is about. But an eye channel
exceeds any threshold chosen for the scalp on every blink, so under the other
two scopes it is flagged on a large fraction of trials by construction: the
result is an eye channel marked bad to no purpose, and a data-quality report
listing VEOG as a candidate for interpolation. Set **Channels to test** to
*Scalp EEG only* in that case, which uses the recorded channel types and leaves
an untyped dataset testing everything as before. A channel with no scalp
position is never interpolated whatever the scope, since a spherical spline has
nowhere to place it. **Import BDF...** brings the
MMN / N2pc bins over. For blink-heavy data you can instead **correct** the blinks
(Chapter 9) rather than reject every blink epoch.

---

## Chapter 9 -- Artifact correction with ICA

**In the book.** Run ICA, identify blink/eye components (with ICLabel), and
subtract them (automatically or by hand), on the **MMN** data.

**The experiment (MMN).** As in Chapter 7.

**Why ICA works, and what it assumes.** The scalp signal is a mixture: each
electrode picks up a weighted sum of many sources at once. Independent Component
Analysis undoes that mixing by finding a set of components whose time courses are
as statistically independent as possible, on the assumption that a blink and an
occipital rhythm and a cortical generator are driven by unrelated processes. Each
component has a fixed **scalp projection** (a topography) and a single time course;
a blink component is unmistakable, a large frontal projection near the eyes that
fires whenever the participant blinks. Because a component's projection is fixed,
you can **subtract just that component** from the data and leave everything else
intact, which is what makes correction preferable to rejection when blinks are
frequent: you keep the trial and lose only the ocular contribution.
**ICLabel** automates the recognition step by scoring each component's probability
of being brain, eye, muscle, heart, line noise or channel noise from its
topography and spectrum. Two practical requirements follow. ICA needs enough clean
data and real electrode positions to estimate the mixing, so channels must have
scalp coordinates; and it should decompose **brain** channels, not the ocular
electrodes themselves, or the eye activity you are trying to isolate contaminates
the decomposition and plots as a component sitting outside the head.

**The data.** `Chapter9.wksp` -> `Data/Luck/ch9`: `..._MMN_preprocessed.set`,
`BDF_MMN.txt`.

**In Alakazam.** Two routes, side by side in the ribbon.

- **AutoICA** does eye correction end to end and automatically: it runs ICA
  (FastICA if installed, else runica), classifies components with **ICLabel**, and
  prunes every component whose "Eye" probability exceeds a threshold.
  `Chapter9.wksp` preloads **EyeThreshold = 0.6**.
- **ICA** (manual component removal) is the hands-on counterpart: it runs (or
  reuses) the decomposition, classifies with **ICLabel**, and opens a component
  selector showing every component's ICLabel class probabilities with a live
  **scalp-topography preview**, so you tick exactly the components to subtract,
  the way to remove a specific non-ocular component (muscle, heart, line noise) by
  hand.

Both decompose the **scalp EEG channels only**: a channel needs a real 10-5 scalp
position **and** must not be a peripheral, so EOG/ECG channels (recognised by
type, guessed from the label) are excluded from the decomposition and spliced back
untouched. That keeps ocular electrodes from dominating the components or plotting
outside the head.

### GEDAI, a different way to denoise

**AutoGEDAI** offers a third route that is worth understanding on its own terms,
because it rests on a different idea from ICA. GEDAI (Ros et al., 2025; a separate
EEGLAB plugin) denoises by **generalized eigenvalue decomposition** of the data
against a **theoretical leadfield reference**. The leadfield is a head-model
prediction of how activity from cortical sources projects onto the electrodes,
so it encodes what *plausible brain signal* should look like given the geometry of
the montage. GEDAI compares the recording's own covariance to that reference
covariance and finds the directions (spatial filters) that best separate
signal-like from artifact-like variance; it then thresholds them automatically
(its **SENSAI** step) into a brain subspace to keep and an artifact subspace to
discard, and reconstructs the cleaned data from the brain subspace alone. It is
**broadband**: it targets whatever does not look like plausible brain activity,
rather than a named component such as "eye". In Alakazam it exposes a **Strength**
(`auto` / `auto+` / `auto-`), a **Leadfield** mode (`precomputed`, matching
channels to its bundled 343-electrode 10-5 template by label; or `interpolated`,
which uses each channel's X/Y/Z), a **low-cut** frequency, and optional automatic
**bad-epoch** and **bad-channel** rejection on ENOVA thresholds. Like the ICA
routes it works on real scalp channels only (matched against its own template),
splicing EOG/ECG back untouched. `Chapter9.wksp` preloads `Strength = auto`,
`Leadfield = precomputed`, `LowCut = 0.4`.

GEDAI is not bundled: it is licensed **PolyForm Noncommercial** (free for personal,
noncommercial research; a separate licence for commercial use). The first time you
run it, Alakazam asks permission and downloads it; declining leaves it uninstalled.

### ICA vs GEDAI, in one table

| | ICA (AutoICA / manual ICA) | GEDAI (AutoGEDAI) |
|---|---|---|
| **Principle** | unmix into maximally **independent** sources | contrast data covariance against a **leadfield** reference (a biophysical prior) |
| **What it removes** | specific components you identify (esp. the eye component) | a broadband **artifact subspace**, whatever is least brain-like |
| **How components are chosen** | ICLabel probabilities (auto), or by hand from a topography gallery | automatically, by SENSAI thresholding |
| **Best at** | ocular / blink correction and targeted, interpretable component removal | diffuse, broadband noise not captured by a few tidy components |
| **You inspect** | each component's map, spectrum and ICLabel class | aggregate diagnostics (SENSAI score, per-epoch / per-channel ENOVA) |
| **Repeatability** | ICA is **stochastic** (components differ run to run) | eigen-decomposition of covariances, more **deterministic** for the same data |
| **Availability** | built in (runica / FastICA + ICLabel) | optional plugin, noncommercial licence, consent download |

**Which to use.** For the classic ERP problem, blinks and eye movements, reach for
**AutoICA** (automatic, ICLabel-guided) or the **manual ICA** step when you want
to eye a specific component before removing it: ICA excels when the artifact is a
small number of well-defined, physiologically interpretable components. Reach for
**GEDAI** when the contamination is diffuse or broadband and does not resolve into
a handful of components, or when you want a montage-geometry-aware clean-up that
needs no manual labelling. They are not exclusive: you can run one and then the
other (for example ICA to take out the eye component, then GEDAI for residual
broadband noise), or neither. Whatever you choose is a node in the tree, so you can
branch, compare the resulting Averages side by side, and keep the cleaner one.

---

## Chapter 10 -- Scoring and statistical analysis

**In the book.** Score amplitudes and latencies (mean amplitude, peak amplitude
and latency, **fractional area latency**, onset latency) and run statistics, on
the **LRP** derived from a Flankers experiment.

**The experiment (Flankers -> LRP / ERN).** An Eriksen flankers task. A central
target arrow points **left or right** (equal probability), flanked by two arrows
on each side that are **compatible** (same direction, 50%) or **incompatible**
(opposite, 50%); each array is shown for 200 ms with a 1200 to 1400 ms
inter-stimulus interval. The participant makes a **speeded left/right
buttonpress** to the central arrow (staircased to keep error rates between 10%
and 20%). Two **response-locked** components: the **LRP**, a
contralateral-minus-ipsilateral difference relative to the responding hand that
starts heading negative ~120 ms **before** the response; and the **ERN**, an
error-minus-correct difference peaking just after an incorrect response. The
book's `BDF_LRP.txt` and its `BinOps_Diff.txt` (contra-minus-ipsi) are shipped:

```
Bin 01  Left-Pointing Target, Compatible Flankers, Left Response    .{11}{t<200-1000>111}
Bin 02  Right-Pointing Target, Compatible Flankers, Right Response  .{12}{t<200-1000>212}
Bin 03  Left-Pointing Target, Incompatible Flankers, Left Response  .{21}{t<200-1000>121}
Bin 04  Right-Pointing Target, Incompatible Flankers, Right Response .{22}{t<200-1000>222}
```
```
nb1 = b1 - b2   label "Contra-Ipsi, Compatible Flankers"
nb2 = b3 - b4   label "Contra-Ipsi, Incompatible Flankers"
```

**The data.** `Chapter10.wksp` -> `Data/Luck/ch10`: 40 participants'
`..._LRP_continuous.set` and `..._LRP_preprocessed.set`, plus `BDF_LRP.txt`,
`BDF_LRP_RT.txt`, `BinOps_Contra.txt`, `BinOps_Diff.txt`.

**Why the measure is a design decision.** The waveform is a curve; a statistic
needs a number, and how you reduce the curve changes the answer. **Peak amplitude**
(the single most extreme sample in a window) seems the obvious choice but has three
quiet flaws: it is biased upward by noise (more noise finds a bigger peak), it
depends on the trial count (a noisier average peaks higher), and it is not additive
across overlapping components, so the peak of a difference wave is not the
difference of the peaks. **Mean amplitude** over a fixed window has none of these:
it is unbiased, roughly trial-count independent, and additive, which is why it is
the default for amplitude effects, at the cost of needing a sensible window. For
timing, the peak **latency** is even more fragile than peak amplitude. **Fractional
area latency**, the time by which a set fraction (say 50%) of the component's area
has accumulated, is far stabler because it integrates over the whole component
rather than trusting one point, and it captures *onset*-like timing, which is
exactly what the LRP question needs. The lesson the chapter teaches is to pick the
measure that matches the claim, and Alakazam's ERP Measure gives you all of them
in one dialog so the choice is explicit. The case for mean amplitude and for
fractional-area latency is one of the central lessons of Luck's book, argued there
far more carefully and completely than this summary can; read his treatment before
committing to a measure.

**In Alakazam.**

- Reproduce the bins with **Import BDF...** on `BDF_LRP.txt`. The two
  `BinOps` files need more care than a single sentence, because they are not
  the same kind of operation:
  - `BinOps_Diff.txt` (`nb1 = b1 - b2`) is plain bin arithmetic and becomes a
    difference bin directly: `bin 5 "..." = bin 1 - bin 2`.
  - `BinOps_Contra.txt` is not. It collapses across the hemispheres
    conditioned on the response side (`contra = (b1@RH + b2@LH)/2`), mixing
    bin and channel selection in one expression, and Alakazam's difference
    bins take only coefficient-weighted whole bins, with no channel-subset
    operator.
- **The contra-ipsi difference wave is still available**, by composing a
  channel operation with a weighted bin operation. Since
  `contra - ipsi = (lat(b1) - lat(b2)) / 2` where `lat = RH - LH`, put the
  lateral difference in a **Derive Channels** node and the halving in the bin
  script:

  ```
  bin 1 "Left response"  : 11|21 and next(111|121) within [200,1000] ms timelock next(111|121)
  bin 2 "Right response" : 12|22 and next(212|222) within [200,1000] ms timelock next(212|222)

  bin 3 "LRP (contra-ipsi)" = 0.5 bin 1 - 0.5 bin 2
  ```

  with `let C34 = C4 - C3` in Derive Channels, and `timelock` making the
  epochs **response**-locked, which is what an LRP needs. Checked against
  ERPLAB's own definition on subject 1: the composed waveform and
  `(b1@RH + b2@LH)/2 - (b1@LH + b2@RH)/2` agree to **6.7e-15 uV**. And it
  behaves like an LRP should, flat early (-0.07 uV at -500 to -400 ms) and
  ramping negative into the response (-1.78 uV over the last 150 ms, -2.69 uV
  at the buttonpress).

  What this does *not* give you is **separate** Contra and Ipsi waveforms, or
  the collapse across all eleven lateral pairs in one action, which is what
  `BinOps_Contra.txt` produces.
- **ERP Measure** scores each bin. Per window it computes: **mean amplitude**;
  **peak** amplitude and latency (absolute or the most extreme **local** peak);
  **area** in four modes (signed / rectified / positive / negative), over the
  window or a width centred on the peak; **fractional peak** and **fractional
  area latency** (e.g. the 50% area latency, exactly the LRP onset measure the
  book uses); with optional **baseline** and **derived channels**. The N400
  template scores the N400 as: label `N400`, window **300 to 500 ms**, **Mean
  Amplitude**, polarity **Negative**, channel **Cz** (the book measures the N400
  at **CPz**; choose your electrode in the dialog).
- Export from the **Measurements** tab: a long, tidy, R-ready CSV (one row per
  measure x bin x channel) plus an HDF5 of the arrays.

**Statistics.** The Measurements export also renders a **Quarto report** beside
the CSV, and it is design-aware rather than one generic loop: each window and
measure is routed to the test its own bins support, a paired *t*-test for two
conditions, a repeated-measures ANOVA for three or more, a one-sample test
against zero for a difference bin, a mixed model where sessions or groups make
one appropriate. Every result is stated **estimate first**, which condition was
larger and by how much with a confidence interval, before any test decision.

Four things in it are worth knowing for this chapter:

- **The waveforms the numbers came from** are drawn with the measurement window
  shaded, read from the export itself so the shading cannot drift from the
  interval actually measured. A window over the wrong peak or a baseline never
  applied produces numbers that test perfectly well and mean nothing, and both
  are obvious on the wave.
- **The effect gets its own panel**, a bootstrap distribution of the mean
  difference with its interval and zero always drawn, next to raincloud plots of
  the conditions themselves.
- **Single-trial models.** Where `Measure` was run on the epoched node, the
  report also fits the measure to individual trials rather than to per-subject
  averages (`value ~ bin + trial_c + (1 + bin | person_id)`), which is the
  current standard for ERP inference and handles unequal trial counts properly.
  Trial order enters as a covariate, centred within person.
- **Primary and secondary families.** Planned condition comparisons are
  corrected together; difference-bin tests and single-trial re-analyses are
  reported as secondary with uncorrected *p*, because they re-express the same
  hypothesis rather than adding one.

An **R analysis script** is still written alongside for anyone who wants to take
the analysis over. Treat both as a **starting point**, not a finished analysis:
they make default choices that may not match your design or the book's
recommendations, so check them against Luck's guidance for this experiment
before reporting anything, or take the tidy CSV into JASP / SPSS instead. The
report says as much itself, including that windows and channels chosen after
seeing the data make the *p*-values optimistic in a way no correction repairs.

---

## Chapter 11 -- EEGLAB and ERPLAB Scripting

**In the book.** Automate the pipeline with EEGLAB/ERPLAB MATLAB scripts, on the
**N170** data.

**Why automation, and what it really buys you.** A study is the same pipeline run
on many subjects, and re-run whenever a decision changes. Doing that by hand does
not scale and is not reproducible; two subjects processed on different days drift
apart. The book's answer is scripting, so the recipe lives in code that can be
replayed. The deeper goal is not "write MATLAB" but "make the analysis a single,
inspectable, re-runnable object". Alakazam reaches the same goal a different way: a
**template** is the recipe (the branch of choices, forks included), applied across
every subject in one action, and **Recalculate** propagates a changed choice down
the branch and writes the result back to disk. The provenance is the tree itself,
which is both the record of what you did and the thing you re-run, so
reproducibility is the default rather than a discipline you have to maintain.

**The experiment (N170).** A face-perception task. Images of **faces** and
**cars** (with scrambled-image controls) are presented one at a time, and the
participant makes a simple discrimination response. The **N170** is a lateral
occipito-temporal negativity around 130 to 200 ms that is **larger for faces
than cars**, isolated as the face-minus-car difference at sites such as PO8.

**The data.** `Chapter11.wksp` -> `Data/Luck/ch11`: `..._N170.set`.

**In Alakazam.** The same automation goals, without writing MATLAB:

- **Templates** capture a whole processing branch (forks and all) and replay it
  onto any dataset, or every raw file at once. `N400.alztemplate` is a worked
  example.
- **Recalculate** edits any step's parameters (a filter cutoff, a bin line, a
  measurement window) and recomputes that node and everything below it, in place,
  written back to the cache so it survives a restart. A pipeline is a live,
  editable graph, not a one-shot script.
- The **bin language** (`.binscript`), the exported **R script**, and template
  files are all plain text you save, load, and version-control, the
  human-readable core of a "script".
- The **exported analysis script** is MATLAB, and where a step is a faithful
  translation it names **EEGLAB's own functions** rather than Alakazam's:
  `pop_resample`, `pop_reref`, `pop_interp`, and `pop_select` for a channel
  selection. That matters for readers of this book in particular, since the
  result is a script in the vocabulary Luck teaches, runnable without Alakazam
  and quotable in a methods section. Steps that cannot be translated faithfully
  keep their own call and carry a comment naming the library function that does
  the work: `Filter` designs its own Kaiser windowed-sinc kernel, and inlining
  that would copy the design logic into the script and diverge the day the
  transformation changed.

**Difference.** The unit of reuse is a template/tree, not a `.m` file: the same
recipe applies across subjects without any code. For a genuinely bespoke
statistical model, edit the generated R script.

---

## Appendix 1 -- A brief introduction to EEG and ERPs

Theory rather than software; the book's introductory appendix is the place for
it. Alakazam's own algorithm citations are in
[README.MD](../README.MD#references).

## Appendix 3 -- The example pipeline, as a template

`N400.alztemplate` in the repository root, applied on one subject and then
**Apply to All Raw Files**, finished on the **Grand Average** tab:

```
raw import (…_N400_preprocessed.set)
  -> AutoGEDAI        (Strength auto, precomputed leadfield, LowCut 0.4)
  -> DefineBins       (bins 1-4 + "N400"=bin4-bin3; epoch -200..800)
  -> Baseline         (-100..-10 ms)
  -> ArtefactDetect   (Absolute threshold, +/- 100 uV)
  -> Average
       -> ERP Measure (N400: mean amplitude 300..500 ms, Negative, Cz)
```

Swap `AutoGEDAI` for `AutoEyeICA` (the ribbon's **AutoICA**; EyeThreshold 0.6),
or add the manual `ICA`
step to prune a specific component; add a `Filter` (0.1 Hz high-pass) at the
front to match the book's exact recipe, and add a `Scalp` leaf under Average for
the topography.

### The fullest chain, ready to run

`N400-complete.alztemplate` in the repository root is the whole of chapters 2
and 3 as one template, starting from the unfiltered `.set` files `ch3` actually
ships and ending at the numbers the statistics read:

```
raw import (…_N400_preprocessed.set, ch3)
  -> Filter           (0.1 Hz high-pass, 40 dB)
  -> DefineBins       (the book's four BDF bins + "N400" = bin 4 - bin 3;
                       epoch -200..800)
  -> Baseline         (-200..0, the book's whole prestimulus interval)
  -> ArtefactDetect   (Absolute threshold +/- 100 uV, tested -200..795)
  -> Average
       -> ERP Measure (N400 amplitude: mean amplitude 300..500 ms at CPz;
                       N400 onset: 50% NEGATIVE-area latency, same window)
       -> Scalp       (the topography)
```

Apply it to one subject, then **Apply to All Raw Files** for the other nine,
then **Grand Average** and export from **Measurements** for the report. Four
notes on it:

- It **branches** under Average (a measurement leaf and a topography leaf), so
  it is a version-2 template. Version 1's flat `steps` list cannot express that.
- The measurement electrode is **CPz**, where the book measures the N400, not
  the `Cz` that `N400.alztemplate` uses.
- The onset window asks for the **negative** area rather than the signed area.
  That is deliberate and comes out of the validation work: on a window spanning
  both polarities the signed cumulative area can pass its own 50% point more
  than once, which makes the latency ambiguous, while a single-signed area is
  monotonic and its crossing unique.
- Grand averaging and the statistics report are **not** template steps; they
  are actions on the Grand Average and Measurements tabs, applied once the
  per-subject branches exist. A template stops at the last per-subject node.

Replayed on `ch3/1_N400_preprocessed.set`, all seven nodes run, the Average
carries the five bins, and the N400 difference bin measures **-5.9 uV** at CPz
with a 50%-area onset near 391 ms. Expect its artifact count to differ slightly
from the book's (70 of 230 epochs here against 67 with the book's own
Butterworth high-pass), because Alakazam's Filter is a Kaiser FIR by design;
see [Not validated](#not-validated-and-why).

---

## Validation against Luck's own stage outputs

The `Data/Luck` tree does not just hold raw recordings: for several chapters it
ships Luck's **own output at each stage**, and his ten published `.erp` files.
Those are a better reference than re-running EEGLAB locally would be, because
they are the exact files the book's figures and exercises are built on. Each
comparison below loads the earlier stage, runs the corresponding Alakazam step,
and reports the worst-case difference against Luck's published later stage.

One caveat on scope: a comparison is only meaningful where exactly one step
separates two files, so the table is shorter than the chapter list. Everything
below is measured against Luck's stored outputs rather than a local ERPLAB
run, which is the stronger reference anyway. Figures were produced under
EEGLAB 2026.1.0 with ERPLAB 13.10 available.

### What agrees, and to what precision

| Chapter | Step | Reference | Worst-case difference |
|---|---|---|---|
| 5 | ReRef to Cz, and to the left mastoid | `6_N400_unreferenced` to `6_N400_CzRef` / `6_N400_LmRef` | **0 uV**, bit-identical, 32 channels x 79 400 samples, both cases |
| 7 to 8 | Interpolate C5, spherical spline | `1_MMN_preprocessed` to `1_MMN_preprocessed_interp` (ERPLAB `pop_erplabInterpolateElectrodes`) | **0 uV**, bit-identical, all 33 channels x 155 648 samples |
| 8 | DefineBins, from Luck's own `BDF_N2pc.txt` via `erplabBdfToBinScript` | ERPLAB BINLISTER's stored `EVENTLIST` | **642 of 642 events** assigned to the same bins; trials per bin `[125 142]`, matching `trialsperbin` exactly |
| 8 | Epoch window and time axis | `pop_epochbin(EEG,[-200 800],'pre')` | identical to the sample: 256 points, -199.22 to 796.88 ms |
| 8 | Baseline correction | the same file | identical; see the note on `t = 0` below |
| 3, 1 | DefineBins + Baseline + ArtefactDetect + Average, end to end | `ch3/premade erp/1_N400.erp` | bins available `[60 60 57 53]` exactly; accepted `[47 44 37 34]` and rejected `[13 16 20 19]` exactly; waveforms to **0.0004 uV** worst case (relative RMS error 5e-6, correlation 1.0000000000) on all four bins |
| 10 | ArtefactDetect, absolute threshold +/-200 uV | ERPLAB `pop_artextval` flags in `1_LRP_preprocessed` | **346 of 346 trials** identical (the same 8 flagged) |
| 10 | ArtefactDetect, moving-window peak-to-peak | ERPLAB `pop_artmwppth` flags in the same file | 345 of 346; the one difference is Alakazam catching an artefact ERPLAB misses, below |
| 10 | Both detectors together | ERPLAB's `reject.rejmanual` | 9 rejected trials, matching exactly |
| 3, 4 | erpset bridge, all ten published N400 erpsets | `erpsetToAveraged` / `averagedToErpset` | **0 uV** both ways, bit-identical |
| 3, 4 | GrandAverage, equal-weight and trial-count-weighted | independently computed means of the ten erpsets | **3.6e-15 uV** (floating-point exact); the two weightings differ from each other by 1.67 uV, so the test is not vacuous |

Three of these deserve a note, because passing them easily would have been
suspicious. The interpolated C5 differs from the original bad channel by 230%
of its own RMS, so "bit-identical" there is a real reconstruction being
reproduced, not a near-no-op. The bipolar EOG channels carry no coordinates, so
Alakazam excludes them from the spline automatically and ERPLAB's explicit
`ignoreChannels [32 33]` turns out to be redundant. And ERPLAB's `'pre'`
baseline **includes the sample at t = 0** (52 samples at 256 Hz, not 51);
Alakazam's `Baseline(-200, 0)` already does the same, which is why the epochs
match rather than sitting a fraction of a microvolt apart.

### Two bugs this found, both fixed

**The moving-window detectors never examined the end of the epoch.**
`movingWindow` in `ArtefactDetect.m` stepped from sample 1 and stopped at the
last window that *fits*, leaving up to `window + step - 2` samples at the tail
that no window ever covered. At 256 Hz over -200 to 800 ms with ERPLAB's usual
200 ms window and 100 ms step, the windows stopped at sample 233 of 256: the
last **90 ms went unchecked**, which is inside the P3 and LRP measurement
windows. ERPLAB's `artmwppth` flagged a 311 uV swing there (trial 222, FC4,
602 to 797 ms) that Alakazam's detector walked past. The last window start is
now forced flush with the end of the signal. This affected the step-function
detector too, which shares the same helper.

Fixing it also revealed that **ERPLAB has the same blind spot**: trial 202
carries a 457 uV peak-to-peak swing on PO8 at 602 to 797 ms, far over the
300 uV threshold under every window geometry, and ERPLAB does not flag it. That
is the single "disagreement" left in the peak-to-peak row above, and it is
Alakazam being right. Reproducing ERPLAB's stored flags exactly requires both
its blind spot and its `floor`-based step length (`step 25, no flush` gives
346 of 346).

**`Interpolate` required Alakazam's own two fields to already exist.** It read
`input.DataType` and `input.DataFormat` bare to restore them after `pop_interp`
(which rebuilds the struct through `eeg_checkset` and drops them). A dataset
that never had them, such as one loaded straight with `pop_loadset` outside the
app, died on `Unrecognized field name "DataType"`. It now reads them through
`TransTools.FieldOr` like every other transformation, falling back to the data
shape for `DataFormat` rather than assuming continuous.

### Which sample is t = 0, and why it is floor

Event latencies are fractional once a recording has been resampled (Luck's
1024 to 256 Hz files carry latencies ending .00, .25, .50 and .75), so the
sample labelled `t = 0` in each epoch has to be chosen, and the two defensible
answers disagree. **EEGLAB and ERPLAB both truncate** (`epoch.m`:
`pos0 = floor(events(index)*srate)`), which puts the `t = 0` sample up to a
full sample *before* the event and gives every latency measure a systematic
half-sample bias, about 2 ms at 256 Hz. Rounding to the nearest sample would
remove that bias and halve the worst-case error.

**Alakazam truncates, matching EEGLAB and ERPLAB.** This validation is what
settled it. Alakazam originally rounded, and on the chapter 3 N400 chain that
choice alone moved one trial across the +/-100 uV rejection threshold (48
accepted in bin 1 against ERPLAB's 47) and shifted the averaged ERP by **15 to
30% relative RMS** (correlation 0.96 to 0.98). That is larger than a
one-sample shift sounds, and it is real: this data carries only a 0.1 Hz
high-pass and no low-pass, so it is broadband to 100 Hz and adjacent samples
genuinely differ.

The reasoning for preferring reproducibility over the smaller error: a uniform
half-sample bias shifts every condition equally, so it cancels in difference
waves and in condition contrasts, which is what ERP work actually measures.
Being unable to reproduce a published ERPLAB result does not cancel. With
`floor` every figure in the table above is exact: 267 of 267 chapter 8 trials
bit-identical to `pop_epochbin`, and chapter 3's four bins matching ERPLAB's
accepted and rejected counts exactly at `[47 44 37 34]` and `[13 16 20 19]`.

The choice is documented where it is made
(`@DefineBinsEngine/evaluateBins.m`) and in the transformation's own help
(`DefineBins.m`), in both cases spelling out that it is a choice, what the
alternative would buy, and what it would cost.

### Measurement and data quality, against ERPLAB directly

The comparisons above use Luck's stored files. Measurement needs something
else, because no scored output ships with the data: ERPLAB 13.10 is installed
as an EEGLAB plugin, so `geterpvalues` can be run as the reference on the very
same erpsets. Both sides were driven from one specification (the same 300 to
500 ms N400 window, bins 3 and 4, five channels, a -200 to 0 ms baseline,
negative peak polarity, 0.5 fraction), over all ten published N400 erpsets,
which is 100 measurement cells per measure.

| Measure | ERPLAB reference | Cells | Worst difference |
|---|---|---|---|
| Mean Amplitude | `meanbl` | 100 | **relative 6.2e-09** |
| Peak amplitude | `peakampbl` | 100 | **relative 7.4e-09** |
| Peak latency | `peaklatbl` | 100 | **0.000 ms, exact** |
| Area, signed | `ninteg` | 100 | **relative 3.9e-08** |
| Area, positive | `areap` | 100 | **relative 3.9e-08** |
| Area, negative | `arean` | 100 | same magnitude; sign convention differs, below |
| Fractional peak latency, 50% | `fpeaklat` | 36 | 4.93 ms worst, 2.34 ms median (under one sample) |
| Fractional area latency, rectified | `fareatlat` | 100 | **100 of 100 within one sample** |
| Fractional area latency, positive | `fareaplat` | 94 | **94 of 94 within one sample** |
| Fractional area latency, negative | `fareanlat` | 49 | **49 of 49 within one sample** |
| Fractional area latency, signed | `fninteglat` | 100 | 77 within one sample; 23 where ERPLAB is wrong, below |
| **aSME** | `ERP.dataquality`, computed by `pop_averager` | **1080** | **1.25e-05 uV** (range 0.23 to 4.18 uV), correlation 1.0000000000 |
| Baseline Measure - SD | `ERP.dataquality` | 120 | **1.78e-05 uV**, correlation 1.0000000000 |

The **aSME** row is the one worth dwelling on. ERPLAB computed those 1080
values inside `pop_averager` from the very trials that produced
`1_N400.erp`, and this comparison is only possible because the chain that
rebuilds those trials is already exact: 47, 44, 37 and 34 accepted trials per
bin, matching ERPLAB's own counts. So Alakazam's analytic standardized
measurement error agrees with ERPLAB's to single precision across every
channel, every one of the nine 100 ms windows, and every bin. The
Alakazam/ERPLAB ratio has a median of exactly 1.00000000, which also rules out
the obvious suspect: this is not an N versus N-1 normalisation that happens to
be close, the two formulas are the same formula.

`Baseline Measure - SD` has no Alakazam counterpart (it is the SD across the
baseline samples of the averaged waveform, not a measurement error), but it is
a fresh function of the average, so reproducing it to 1.8e-05 uV re-confirms
the averaging from an angle the earlier waveform comparison did not use.

#### Three differences, and what each one is

**Area is in uV.ms here and uV.s in ERPLAB.** Alakazam integrates over a time
axis in milliseconds and says so in `Measure`'s own help; ERPLAB's `areaerp`
uses `Ts*trapz(...)` with `Ts = 1/fs` in seconds. Both use the same
trapezoidal rule, so the values agree to 3.9e-08 relative once the factor of
1000 is applied. Nothing to fix, but anyone cross-checking an area against
ERPLAB needs to know which unit they are holding.

**Negative area is signed in Alakazam and a magnitude in ERPLAB.** The ratio
is exactly -1000: same number, opposite sign convention, on top of the unit
factor. Alakazam's `'negative'` mode integrates `min(y, 0)` and so reports a
negative area; ERPLAB's `arean` reports how much area there is below zero, as a
positive quantity.

**Fractional latencies: Alakazam interpolates, ERPLAB does not.** Where both
report a fractional peak latency the worst disagreement over all ten subjects
is 4.93 ms with a 2.34 ms median, and the sample period is 5 ms: every
difference is smaller than one sample, because ERPLAB's default `intfactor` of
1 pins its answer to a sample boundary while Alakazam interpolates between
samples. Three of the four fractional-area measures behave the same way, and
every one of their 243 cells agrees within a sample.

#### Where Alakazam returns NaN and ERPLAB returns a number

Alakazam returned NaN in 64 of 100 fractional-peak-latency cells, and in 51 of
those ERPLAB returned a number instead. What decides it is whether the
threshold is reachable at all, and that predicts the behaviour exactly:

| | Alakazam answered | Alakazam NaN |
|---|---|---|
| a downward crossing of `frac x peak` exists before the peak | **36** | 0 |
| no such crossing exists | 0 | **64** |

So Alakazam answers precisely when the measure is defined and declines
precisely when it is not. In **51 of 51** of the cells where ERPLAB answered
instead, its "fractional peak latency" is exactly its own peak latency: as
`localpeak.m` shows, ERPLAB walks back from the peak looking for the first
sample at or beyond `frac x peak` and tests the peak sample itself first, so
when that test passes immediately the walk stops and reports the peak's own
latency under a different name.

**Why the threshold can be unreachable, which is subtler than a sign test.**
It is tempting to say these are cells where the located peak "had the wrong
sign", and 51 of the 64 do have a positive-valued peak. But a negative peak is
a local *minimum*, and a minimum can legitimately sit at a positive voltage: a
waveform dipping from +10 to +5 and back is a real negative-going deflection
whose amplitude happens to be positive. **37 of the 64 NaN cells are exactly
that**, true interior local minima (36 of them positive-valued), not artefacts;
the remaining 27 are minima sitting on a window edge, where the waveform never
turned around inside the window at all.

What makes the measure inapplicable is not the peak, it is the
*baseline-relative* threshold both tools use. `frac x peak` is a fraction of
the distance from baseline to the peak, so for a minimum at +5 uV the threshold
is +2.5 uV; the signal reached that minimum from *above*, and +5 is the
smallest value in the window, so it never descends through +2.5. The threshold
lies on the far side of the peak from the approach. A fraction-of-peak
threshold is only reachable when the deflection actually moves away from
baseline in the polarity requested, and peak sign is merely a good proxy for
that: 13 cells with a properly negative peak are also NaN, because their
minimum is the window's first sample and there is nothing before it to cross
from.

This is a real limitation of fractional peak latency as defined, not of
Alakazam's peak detection: a negative deflection riding on a positive offset
has no baseline-relative half-amplitude point. NaN is the honest answer, and
silently substituting the peak latency is not.

#### The signed fractional area latency, where ERPLAB is wrong

`fninteglat` is the one measure where the two disagree by more than a sample:
23 of 100 cells, up to 196 ms apart. Every one of those was checked against a
hand computation of the crossings, independent of both tools:

- In **23 of 23**, ERPLAB's answer is at or after the earliest crossing of
  `frac * total`, often the window edge itself (500 ms of a 300 to 500 ms
  window).
- Alakazam's answer is the earliest crossing in every case.

The 23 are sign-mixed windows. Measuring how single-signed each window is as
`|total area| / sum of |segment areas|` (1 means the waveform never changes
sign, 0 means perfect cancellation), the 77 agreeing cells have a median of
exactly **1.000** while the 23 disagreeing ones have a median of **0.598**,
with 10 of them below 0.5. On such a window the signed cumulative area is not
monotonic: it passes its own 50% point, falls back, and may pass it again.
ERPLAB searches forward and lands on a later crossing or runs off the end.

Two honest qualifications. First, Alakazam reporting the earliest crossing is
the correct reading of "when did this component get halfway", and it is now
pinned by a test. Second, on a window whose positive and negative areas nearly
cancel the measure is **ill-conditioned whatever either tool reports**: two of
the 23 have signed totals of only -7.5 and 0.3 uV.ms, where 50% of the total is
near zero and the latency is arbitrary. That is precisely why ERPLAB offers the
three single-signed variants, whose cumulative area is monotonic and whose
crossing is unique, and why the fix below matters.

#### areaMode is now honoured for fractional area latency

This exercise turned up a real defect on Alakazam's side. A measurement
window's `areaMode` was accepted and then discarded for Fractional Area
Latency, which always integrated the signed area: asking for the rectified,
positive or negative variant silently returned the signed answer. `Measure`'s
help did say "signed", so it was documented rather than wrong, but three of
ERPLAB's four measures had no Alakazam equivalent and a stored template could
ask for one and be quietly given another.

`areaMode` is now applied exactly as `Area` itself applies it, giving all four
of ERPLAB's measures, and the agreement above (100 of 100, 94 of 94 and 49 of
49 within one sample) is what that fix buys. Two unit tests cover it: one
pinning each mode's hand-computed latency on a sign-changing fixture, and one
guarding the defect itself, that the four modes must not all return the same
number.

### Not validated, and why

- **Filter (Ch 4).** Luck uses a second-order Butterworth IIR
  (`pop_basicfilter`); Alakazam uses a Kaiser-windowed-sinc zero-phase FIR,
  which is EEGLAB's and Luck's own stated best practice for ERP work. These are
  deliberately different designs and cannot agree numerically, so there is no
  meaningful bit comparison to make. Validating Alakazam's filter means
  checking its realised magnitude response against its design specification,
  not against `pop_basicfilter`.
- **ICA correction (Ch 9), and Ch 6's `*_P3_corrected.set`.** The data ships
  only corrected outputs, with no matching uncorrected file, so there is no
  single-step pair to compare.
- **Inferential statistics (Ch 10).**

The harness that produced these numbers is not checked in: it depends on the
2.4 GB `Data/Luck` tree, which is gitignored. The two bugs it found are covered
by ordinary unit tests instead (`ArtefactDetectTest`,
`InterpolateTest`), written to fail against the pre-fix code.

---

## Coverage of the book, chapter by chapter

"Implemented" below means Alakazam has a step **intended** to do what the book's
step does. The "Validated" column says whether that step has been shown to agree
with Luck's own published output for it; see the section above for the exact
figures and for what could not be checked. Where a step is not yet validated,
use the EEGLAB/ERPLAB workflow Luck teaches as the reference and this as an
alternative to check against it.

| Book step | Alakazam | Validated | How |
|---|---|---|---|
| Filtering (Ch 4) | implemented | not comparable (FIR vs Luck's IIR by design) | Filter: FIR windowed-sinc / Kaiser, freq + dB |
| Referencing (Ch 5) | implemented | **yes, bit-identical** | ReRef: average / specific, exclude, keep-ref |
| Channel / coordinate editor (Ch 5) | implemented | no reference pair | ChannelEditor: labels, types, X/Y/Z, 10-5 lookup, montage load |
| Resampling (Ch 5) | implemented | wraps `pop_resample` | Resample (`pop_resample`), continuous |
| Bins + averaging + baseline (Ch 6) | implemented | **yes**: bins exact, averages to 0.0004 uV | bin language + BDF import + difference bins |
| Data quality / aSME (Ch 6) | implemented | **yes**: all 1080 aSME values match ERPLAB to 1.3e-05 uV | analytic aSME + standard-error band + trial counts; Data Quality Report adds per-window SME, flagged-trial counts per channel, and dependability where per-trial scores exist |
| EEG inspection (Ch 7) | implemented | n/a, a view | SignalView / EpochView |
| Bad-channel interpolation (Ch 7) | implemented | **yes, bit-identical** | Interpolate (`pop_interp`): spline / invdist / spacetime |
| Artifact detection (Ch 8) | implemented | **yes**, after fixing a tail blind spot; now catches one artefact ERPLAB misses | ArtefactDetect: absolute, step, moving-window p2p, sample-to-sample (multi-select); scope = whole epoch / this channel / interpolate, tested over all channels or scalp EEG only |
| ICA artifact correction (Ch 9) | implemented | no reference pair (only corrected files ship) | automatic (AutoICA) + manual component removal (ICA), both ICLabel |
| Amplitude / latency scoring (Ch 10) | implemented | **yes**: mean/peak amplitude, peak latency and area exact; fractional latencies within one sample, and where they differ Alakazam is the correct one | ERP Measure, incl. fractional-area latency |
| Inferential statistics (Ch 10) | implemented | not yet | design-aware Quarto report (waveforms, estimation panels, single-trial mixed models, primary/secondary correction) + auto-generated R script + tidy CSV |
| Reproducible pipeline (Ch 11) | implemented | n/a | templates + Recalculate |
| MATLAB scripting (Ch 11) | implemented | n/a | exported MATLAB script naming EEGLAB's own functions where faithful (`pop_resample`, `pop_reref`, `pop_interp`, `pop_select`), plus templates and Recalculate |

**The short version.** For the ERP CORE components the book teaches
(N400, P3b, MMN, N2pc, LRP, N170), Alakazam has a step for every stage of the
pipeline: import, filtering, referencing, montage editing and resampling,
bad-channel interpolation, bin definition, artifact detection, ICA correction
(automatic and manual), epoching, averaging, grand-averaging, data quality (aSME),
amplitude/latency scoring, and export, with a design-aware statistical report
and a generated script for the statistics, and every chapter has a ready
workspace over the real data.

"Has a step for" is not "gets the same answer as", and the section above is the
attempt to tell the two apart. Where Luck's data contains a single-step
reference, the answer is now encouraging: referencing and interpolation are
bit-identical, bin assignment matches BINLISTER on every one of 642 events, and
the whole bin-to-average chain reproduces a published `.erp` to 0.0004 uV. That
Measurement and data quality now check out against ERPLAB itself: mean and
peak amplitude, peak latency and area are exact, and all 1080 of a subject's
aSME values match to 1.3e-05 uV. That exercise also found two real bugs in
Alakazam, one of them a detector blind spot over the last 90 ms of every
epoch, settled the epoch time-locking convention in favour of matching EEGLAB
and ERPLAB, and turned up one case where Alakazam is right and ERPLAB is not.
Filtering, ICA correction and the statistics remain unvalidated, so this guide
is still best used **alongside** Luck's book and the tools it uses. The credit for the science, the teaching, and the data is
entirely Steven Luck's; the responsibility for any way Alakazam gets it wrong is
ours. We are grateful for his book, and for making it and the ERP CORE data openly
available.
