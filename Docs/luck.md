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
> **Alakazam is young and has had very little testing**, especially next to EEGLAB
> and ERPLAB, which are mature, widely used and validated across many years and
> thousands of published studies. Alakazam's transformations wrap or
> re-implement the same algorithms, but they have been only lightly tested and
> have **not** been validated against reference results. Treat every value
> Alakazam produces as **provisional** until you have checked it against
> EEGLAB/ERPLAB on the same data. For any analysis that matters, Luck's
> EEGLAB/ERPLAB workflow, not this one, is the reference. Where a chapter says a
> step is "covered" or "done", read it as *implemented and intended to behave the
> same way*, not *verified to match*.
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

- **Data:** [`Data/Luck/`](../Data/Luck) with one folder per chapter
  (`ch1` ... `ch11`), the ERP CORE recordings the book uses, one component per
  chapter (N400, P3b, MMN, N2pc, LRP, N170).
- **A workspace per chapter:** `Chapter1.wksp` ... `Chapter11.wksp` in the
  repository root. Each points its *Raw* folder at the matching `Data/Luck/chN`
  and preloads bin, baseline, ICA and time-frequency settings.
- **A ready pipeline:** [`N400.alztemplate`](../N400.alztemplate), the full N400
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
  (`Data/Exports/`). Ctrl+S saves them into `~/workspace.json`.
- You process by **building a tree**, not by running a script. A raw import is a
  root node; each ribbon transformation adds a child; a subject's whole analysis
  is a branch.
- The ribbon groups transformations like the book's pipeline:
  *1. Preprocessing* (SelectData, ReRef, Resample, Filter, Baseline, Interpolate,
  ChannelEditor, Average),
  *2. Artifact Rejection / Reduction* (ArtefactDetect, AutoEyeICA, ICA,
  AutoGEDAI), *3. Segment Analysis* (DefineBins),
  *4. Frequency and Component Analysis* (Fourier, Spectral Measure, ERP Measure),
  *5. Plots* (Scalp, TimeFrequency, Coherence Map, Coherence Topography). A
  **Grand Average** tab builds
  group results; a **Measurements** tab scores and exports.
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
`1_N400_erp.erp` is the finished ERPLAB erpset (the four averaged bins).

**In Alakazam.**

1. Open `Chapter1.wksp`. Both files load as root nodes: the `.set` with a
   person-shaped "raw" badge, the `.erp` with an "averaged" badge (Alakazam
   reads ERPLAB erpsets directly, see [erpset support](../src/erpsetToAveraged.m)).
2. Click `1_N400_preprocessed` for the scrolling **SignalView** (pan / zoom /
   magnify sliders, mouse-wheel scroll; the display scales off the EEG channels
   only, so a big EOG channel does not squash the trace).
3. Right-click -> **List events** to see the eight stimulus codes and the one
   response code (listed in Chapter 2).
4. Click `1_N400_erp` to see its four averaged bins immediately, no processing.

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

2. **DefineBins** (Segment Analysis) does EventList + BINLISTER + epoching in one
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
   You can instead reproduce ERPLAB's file verbatim with **Import BDF...** on
   `BDF_N400.txt`; Alakazam translates the timing flag `t<200-1500>` into
   `within [200,1500] ms`, giving the shipped `BDF_N400.binscript`:

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

4. **Average** (Preprocessing) produces the four per-bin ERPs (plus the bin 5
   difference wave), each with a standard error, an accepted trial count, and its
   **aSME** data-quality value (Chapter 6).

5. **Baseline** (Preprocessing). The book corrects on the whole prestimulus
   interval (**-200 to 0 ms**, ERPLAB "Pre"); `Chapter2.wksp` preloads a tighter
   **-100 to -10 ms**. Set Start/Stop to your preference.

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
windowed-sinc filter (`pop_firws`/Kaiser), a **linear-phase** design, so it delays
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
- **Average** gives each bin's ERP with a standard error and trial counts and
  evaluates the difference bins.
- **Baseline** does the prestimulus subtraction.

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

**In Alakazam.** **ArtefactDetect** aims to reproduce (and extend) ERPLAB's
detector set; the thresholds and windows are named the same, but the exact
trial-by-trial flags have not been checked against ERPLAB, so cross-check on a
recording you know. Tick **one or more** of:

- **Absolute threshold** -- any sample outside [Minimum, Maximum] uV (default
  **+/- 100 uV**).
- **Step function** -- a moving window whose first-half vs second-half mean
  differs by more than a threshold (blinks, saccades).
- **Moving-window peak-to-peak** -- max-minus-min within a sliding window exceeds
  a threshold.
- **Sample-to-sample** -- any single-sample jump exceeds a threshold (transients).

A channel is flagged if **any** ticked detector trips. Detection runs over a
**test window** (blank = the whole epoch), and a hit rejects either the **whole
epoch** (all channels, the ERP-standard default) or **just that channel**;
rejected data is set aside so averaging omits it. **Import BDF...** brings the
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

- **AutoEyeICA** does eye correction end to end and automatically: it runs ICA
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

| | ICA (AutoEyeICA / manual ICA) | GEDAI (AutoGEDAI) |
|---|---|---|
| **Principle** | unmix into maximally **independent** sources | contrast data covariance against a **leadfield** reference (a biophysical prior) |
| **What it removes** | specific components you identify (esp. the eye component) | a broadband **artifact subspace**, whatever is least brain-like |
| **How components are chosen** | ICLabel probabilities (auto), or by hand from a topography gallery | automatically, by SENSAI thresholding |
| **Best at** | ocular / blink correction and targeted, interpretable component removal | diffuse, broadband noise not captured by a few tidy components |
| **You inspect** | each component's map, spectrum and ICLabel class | aggregate diagnostics (SENSAI score, per-epoch / per-channel ENOVA) |
| **Repeatability** | ICA is **stochastic** (components differ run to run) | eigen-decomposition of covariances, more **deterministic** for the same data |
| **Availability** | built in (runica / FastICA + ICLabel) | optional plugin, noncommercial licence, consent download |

**Which to use.** For the classic ERP problem, blinks and eye movements, reach for
**AutoEyeICA** (automatic, ICLabel-guided) or the **manual ICA** step when you want
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

- Reproduce the bins with **Import BDF...** on `BDF_LRP.txt`; the contra-ipsi
  difference waves are `bin N "..." = bin A - bin B` lines (Alakazam's difference
  bins are the `BinOps` equivalent).
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

**Statistics.** The Measurements export also writes an **R analysis script** next
to the CSV. It loads the tidy CSV with the **tidyverse**, and per
measure / window / channel runs a **repeated-measures ANOVA** and **pairwise
t-tests** (Holm-corrected, via `rstatix`), then draws publication figures with
**ggplot** (per-subject lines plus condition means with standard-error bars and
significance brackets, `theme_pubr`) and saves them to PDF. Missing R packages are
installed on first run. So both halves of the chapter are addressed: the *scoring*
in Alakazam, and a first *statistical* pass as a ready-to-run, editable R script.
Treat the generated script as a **starting point**, not a finished analysis: it
makes reasonable default choices (which factors, which corrections) that may not
match your design or the book's recommendations, so read it, check it against
Luck's guidance on the statistics for this experiment, and adapt it before
reporting anything (or take the tidy CSV into JASP / SPSS instead).

---

## Chapter 11 -- Scripting and automation

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

**Difference.** The unit of reuse is a template/tree, not a `.m` file: the same
recipe applies across subjects without any code. For a genuinely bespoke
statistical model, edit the generated R script.

---

## Appendix 1 -- A brief introduction to EEG and ERPs

Theory rather than software; the book's introductory appendix is the place for
it. Alakazam's own algorithm citations are in
[readme.MD](../readme.MD#references).

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

Swap `AutoGEDAI` for `AutoEyeICA` (EyeThreshold 0.6), or add the manual `ICA`
step to prune a specific component; add a `Filter` (0.1 Hz high-pass) at the
front to match the book's exact recipe, and add a `Scalp` leaf under Average for
the topography.

---

## Coverage of the book, chapter by chapter

"Implemented" below means Alakazam has a step **intended** to do what the book's
step does. It does **not** mean the two have been shown to agree: that comparison
is exactly the validation work still to be done. Until it is, use the EEGLAB/ERPLAB
workflow Luck teaches as the reference and this as an experimental alternative to
check against it.

| Book step | Alakazam (implemented, not yet validated) | How |
|---|---|---|
| Filtering (Ch 4) | implemented | Filter: FIR windowed-sinc / Kaiser, freq + dB |
| Referencing (Ch 5) | implemented | ReRef: average / specific, exclude, keep-ref |
| Channel / coordinate editor (Ch 5) | implemented | ChannelEditor: labels, types, X/Y/Z, 10-5 lookup, montage load |
| Resampling (Ch 5) | implemented | Resample (`pop_resample`), continuous |
| Bins + averaging + baseline (Ch 6) | implemented | bin language + BDF import + difference bins |
| Data quality / aSME (Ch 6) | implemented | analytic aSME + standard-error band + trial counts |
| EEG inspection (Ch 7) | implemented | SignalView / EpochView |
| Bad-channel interpolation (Ch 7) | implemented | Interpolate (`pop_interp`): spline / invdist / spacetime |
| Artifact detection (Ch 8) | implemented | ArtefactDetect: absolute, step, moving-window p2p, sample-to-sample (multi-select) |
| ICA artifact correction (Ch 9) | implemented | automatic (AutoEyeICA) + manual component removal (ICA), both ICLabel |
| Amplitude / latency scoring (Ch 10) | implemented | ERP Measure, incl. fractional-area latency |
| Inferential statistics (Ch 10) | implemented | auto-generated R script (tidyverse / rstatix / ggplot) + tidy CSV |
| Reproducible pipeline (Ch 11) | implemented | templates + Recalculate |
| MATLAB scripting (Ch 11) | different by design | GUI + templates + generated R, instead of `.m` files |

**The short version.** For the ERP CORE components the book teaches
(N400, P3b, MMN, N2pc, LRP, N170), Alakazam has a step for every stage of the
pipeline: import, filtering, referencing, montage editing and resampling,
bad-channel interpolation, bin definition, artifact detection, ICA correction
(automatic and manual), epoching, averaging, grand-averaging, data quality (aSME),
amplitude/latency scoring, and export, with a generated R script for the
statistics, and every chapter has a ready workspace over the real data. But
"has a step for" is not "gets the same answer as": Alakazam is new and lightly
tested, and none of these steps has yet been validated against EEGLAB/ERPLAB. So
this guide is best used **alongside** Luck's book and the tools it uses, as a way
to learn the pipeline and to try an alternative, not as a replacement for a
validated workflow. The credit for the science, the teaching, and the data is
entirely Steven Luck's; the responsibility for any way Alakazam gets it wrong is
ours. We are grateful for his book, and for making it and the ERP CORE data openly
available.
