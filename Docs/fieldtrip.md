# Checked against FieldTrip's own tutorials

FieldTrip publishes tutorials with their data. This note records three of
them carried out in Alakazam and compared with FieldTrip run on the same
recording: the ERP preprocessing tutorial, done end to end as a library
template, and the dipole fitting and beamforming tutorials, which check the
FieldTrip calls behind Alakazam's Dipole Fit and Beamformer.

*Checked on 8 October 2026, FieldTrip 20260812, EEGLAB 2026.1.0.*

## ERP preprocessing: the same analysis, to rounding

FieldTrip's tutorial (`tutorial/sensor/preprocessing_erp`) analyses one
participant judging words in two tasks, affective (positive or negative) and
ontological (animal or human), recorded with a 64-channel BrainVision cap
against the left mastoid. It is a complete small ERP analysis: trials around
each word, a low-pass, linked mastoids, two bipolar EOG channels, eight
trials rejected by eye, and an average per task. The template
`library/templates/fieldtrip/preprocessing-erp.alztemplate` does the same.

**To follow it:** put the recording (`s04.vhdr`, `s04.vmrk`, `s04.eeg`, 143
MB, from `https://download.fieldtriptoolbox.org/tutorial/preprocessing_erp/`)
in a workspace's raw folder, open it, and **Apply Template** with that file.
The rejected trials are stored for this recording (192 trials, 59 channels);
on another recording, run ManualReject by hand instead.

| FieldTrip | Alakazam | Notes |
|---|---|---|
| `ft_definetrial` with `trialfun_affcog`: every word (S141), its task from the marker that follows (S131 affective, S132 ontological), from -0.2 to 1 s | **DefineBins**: `bin 1 "Affective" : "S141" and adjacent("S131")`, the same for S132, epoch -200 to 1000 ms | Alakazam's epoch stops one sample before 1000 ms, as EEGLAB cuts one: 600 samples against FieldTrip's 601 |
| `implicitref = 'LM'`, `reref` to `{'LM' 'RM'}` | **ReRef**: specific channels LM and RM, implicit reference LM, keep the reference channels | |
| `lpfilter`, 100 Hz | **Filter**: low-pass at 100 Hz | the one real difference, below |
| `demean`, `baselinewindow = [-0.2 0]` | **Baseline**, -200 to 0 ms | the same samples: Baseline follows FieldTrip's window rule |
| `eogv` = LEOG against 53; `eogh` = 25 against 57 | **DeriveChannels**: `let eogv = LEOG - "53"`, `let eogh = "25" - "57"` | channels named by number go in double quotes |
| `ft_selectdata`, channels 1 to 60 but 25, 53 and 57; `ft_appenddata` the two EOG channels | **SelectData**: remove 25, 53, 57, LEOG, 62, 63, 64 and LM | the same 59 channels, in the same order |
| `ft_rejectvisual`, summary: trials 22, 42, 89, 90, 92, 126, 136 and 150 | **ManualReject**, whole epoch: the same eight | 92 trials left in each task |
| `ft_timelockanalysis` per task; `ft_math` subtract | **Average**; bin 3 = bin 1 - bin 2 | |

Alakazam re-references, derives, selects and filters the continuous
recording and then cuts the trials; FieldTrip cuts first and does the rest
within each trial. Every one of these steps is linear, so the order alone
changes nothing, as the first comparison below shows.

**How close.** The averages were compared on every channel, both tasks and
their difference, on the 600 samples both have. The averages themselves
have an RMS of about 5 µV.

| Comparison | Largest difference | RMS difference |
|---|---|---|
| No low-pass on either side | 0.000003 µV | 0.0000002 µV |
| FieldTrip's Butterworth on both, on the whole recording | 0.000003 µV | 0.0000001 µV |
| As shipped: Alakazam's FIR against the tutorial as published | 1.09 µV, at the first sample | 0.026 µV |
| Alakazam's FIR against FieldTrip's Butterworth on the whole recording | 0.18 µV | 0.020 µV |

All 192 words are locked to the same samples in both. What is left, 3e-6 µV,
is EEGLAB reading the recording in single precision and FieldTrip in double.

**The difference is the filter, twice over.** The tutorial's low-pass is
FieldTrip's default, a sixth-order Butterworth run forward and backward, and
it runs on each 1.2 s trial alone. Alakazam's is a Kaiser windowed-sinc FIR
on the whole recording. The design accounts for the 0.02 µV RMS (the last
row). Filtering each trial alone accounts for the largest differences: at
the trial's first and last samples the filter has no data beyond the edge,
and the tutorial's averages there differ by about 1 µV from the same filter
run on the whole recording. Where Alakazam is given the tutorial's own
Butterworth as a designed filter (Filter Designer), the two agree to
rounding again (the second row). Filtering the continuous recording before
the trials are cut avoids those edges; in FieldTrip it takes `cfg.padding`,
or `ft_preprocessing` on the whole recording before `ft_redefinetrial`.

`FieldTripTutorialErpTest` (tagged `Slow`, about a minute) replays the
template and runs FieldTrip's tutorial beside it, and repeats these three
comparisons. It fails when a numbered channel in quotes is read as a number,
when the implicit reference is ignored, when the rejected trials are kept,
when the epochs are cut one sample late, and when the template's baseline
stops 20 ms early.

**What the tutorial changed in Alakazam.**

- *Channels named by number.* DeriveChannels read `LEOG - 53` as LEOG minus
  the number 53, silently, which gives a channel that looks like an EOG and
  is not. A channel name in double quotes is now always a channel (`"53"`, or
  a name with a hyphen or a space), and a bare number that is also a
  channel's name is refused rather than guessed. The same holds in ERP
  Measure's `let` field.
- *The epoch's last sample.* The bin language reference and the manual said
  an epoch keeps both of its ends. It does not, and should not: DefineBins
  cuts as EEGLAB's `epoch.m` does, stopping one sample before the upper
  bound, which is what keeps its epochs identical to ERPLAB's. The text now
  says so.

**Not covered.** This recording's channels are named by number, and the
tutorial places them with its own layout file
(`mpi_customized_acticap64.mat`), which Alakazam does not read. Its scalp
maps and source tools place channels by their 10-5 name, so they cannot be
used on it.

## Export as FieldTrip: the same averages from FieldTrip alone

**Export as FieldTrip** (Export/Report tab, `exportFieldTripScript`) writes
an analysis as a FieldTrip script. Applied to the ERP template's result on
`s04`, every step comes out exact or a decision read back:

| Step | Status | As FieldTrip |
|---|---|---|
| ReRef | exact | `ft_preprocessing` with `reref`, `refchannel`, `implicitref` |
| DeriveChannels | exact | a weighted sum of channels (`addChannel`, carried in the script) |
| SelectData | exact | `ft_selectdata` |
| Filter | exact | `ft_preprocessing` with `lpfilttype = 'firws'`, Alakazam's order (46), cutoff and Kaiser deviation (0.01) |
| DefineBins | decision | `ft_redefinetrial`, with the trials read from `s04_trials.tsv` |
| Baseline | exact | `ft_preprocessing` with `demean` and `baselinewindow` |
| ManualReject | decision | `ft_selectdata`, leaving out the trials the table marks |
| Average | exact | `ft_timelockanalysis` per bin; `ft_math` for the difference |

Run with FieldTrip alone, the script gives Alakazam's averages to 2.7e-6 µV
on every channel and sample, the same rounding as above, and its trials
have Alakazam's 600 samples. The low-pass is exact, unlike the tutorial's
own: FieldTrip's `firws` builds its kernel with the same `firws`, `windows`
and `kaiserbeta` that EEGLAB's firfilt uses, and both pad the edges with the
first and last sample, so given Alakazam's design it computes Alakazam's
filter. `FieldTripTutorialErpTest` exports and runs the script, for this recording
twice over under two names, so that it also runs the loop the export writes
for recordings processed alike and a weighted grand average of the two.

### Two modes, and ICA

The export asks whether to **reproduce** Alakazam's results, every choice
FieldTrip cannot make read back, or to **re-run** in FieldTrip, which makes
the choices it has a method for itself with the settings closest to
Alakazam's. The difference is in ICA:

- *Reproduced*, AutoEyeICA's (or Remove Components') decomposition is applied
  with `ft_componentanalysis` and its components removed with
  `ft_rejectcomponent`, with that function's own demeaning switched off and
  the channels it leaves out put back in place, two things EEGLAB's
  `pop_subcomp` does not do. The export checks on the data that subtracting
  the components gives Alakazam's result; where the decomposition does not
  span the data, `pop_subcomp`'s rebuilding from the kept components
  differs from it, and the step is marked approximate.
- *Re-run*, FieldTrip decomposes the data itself with the same algorithm
  (FastICA, the same package; or extended Infomax with EEGLAB's learning
  rate, 0.00065/log(channels), where FieldTrip would use 0.001), the same
  channels and as many components, and removes the components whose
  topographies correlate with the ones Alakazam removed at |r| ≥ 0.9.

On Luck's chapter 9 recording 1 (MMN, AutoEyeICA at 0.6, 2 of 28 components
removed, then DefineBins, Baseline, ArtefactDetect and Average), the
reproducing script gives Alakazam's averages to 1.6e-6 µV. The re-running
one found FieldTrip components matching both of Alakazam's at |r| = 1.000,
and gave the averages to 1.5e-6 µV: removing the same two topographies
removes the same subspace, whatever the other components are. Measure and
the scalp map are marked not translated in both.

`FieldTripExportEquivalenceTest` checks each exact translation on its own
(five filter designs, three ICA decompositions, equal and weighted grand
averages) and the re-run on synthetic data with a known blink source;
`ExportFieldTripScriptTest` the header, both modes, the table of trials,
the loop, the refusals and the app's collector.

## The NatMEG recordings

Alakazam's dipole fit and beamformer are FieldTrip's (`ft_dipolefitting`,
`ft_sourceanalysis`), called on FieldTrip's template head. Their own tests
simulate a source in that head and find it again, which checks the pipeline
but not whether it is called the way FieldTrip's authors call it. The
sections below compare them with FieldTrip's tutorials, on the
tutorials' own data: the combined MEG/EEG oddball recording of the NatMEG
2014 workshop. Only the EEG is used.

### The data

From `https://download.fieldtriptoolbox.org/workshop/natmeg2014/`:

| File | Size | Used for |
|---|---|---|
| `dipolefitting/timelock_eeg.mat` | 1.2 MB | the average the dipole tutorial fits |
| `dipolefitting/headmodel_eeg.mat` | 47 MB | the subject's three-shell BEM (`bemcp`, in mm) |
| `timefrequency/data_clean_EEG_responselocked.mat` | 86 MB | the trials the beamforming tutorial uses |
| `oddball1_mc_downsampled.fif` | 458 MB | the raw recording (not needed for either check) |

They live under `FieldTrip/natmeg2014` in the data folder (on the machine this
was written on, `D:\data`). `FieldTripTutorialDipoleTest` finds them through
the `ALAKAZAM_DATA` environment variable, the repository's `Data` folder or
`D:\data`, and skips without them; it never downloads anything.

**Why Alakazam's transformations cannot be run on this recording as they
are.** The EEG channels are named `EEG001` to `EEG128`. Alakazam's source
transformations place electrodes by their 10-5 name on FieldTrip's template
head (`TransTools.ResolveScalpDistribution`), so a recording whose channels
have other names (Neuromag's, EGI's `E1`..., BioSemi's `A1`..., or plain
numbers) is refused, even when it carries digitised positions. Both checks
below therefore run Alakazam's own code on the tutorial's head model and
electrodes, which is also the only way to compare with the tutorial at all:
the tutorials use the subject's own MRI, Alakazam a template.

### Dipole fit: identical

FieldTrip's tutorial (`tutorial/source/dipolefitting`) fits a pair of dipoles
mirrored across the midline to the N100 from 80 to 110 ms. The recipe was run
as published, except for two things that no longer work as written, and
`dipoleFitWindow` (what DipoleFit does for each bin) was run on the same
average, electrodes and head model:

| | Pair (mm, subject's head coordinates) | Residual variance |
|---|---|---|
| FieldTrip's recipe | [±32.57 -11.86 51.58] | 0.31345 |
| Alakazam | [±32.57 -11.86 51.58] | 0.31345 |
| The tutorial's second step, symmetry released | [21.8 -21.0 36.8; -31.5 -19.5 48.8] | 0.241 |

The two agree to the last digit. `FieldTripTutorialDipoleTest` (tagged `Slow`,
about 30 s) repeats the comparison, to 0.5 mm and 1e-4. It fails when the
window is shifted by 20 ms, when the residual variance is taken as the mean of
FieldTrip's per-sample values, when the model is 'moving' instead of
'regional', or when the pair is mirrored across y instead of x.

**The recipe as published does not do what it says.** Two FieldTrip
behaviours, both of which DipoleFit already avoids:

- **The grid's unit is ignored.** The recipe asks for `cfg.resolution = 1`
  with `cfg.unit = 'cm'`. `ft_dipolefitting` says that `cfg.unit` is moved to
  `cfg.sourcemodel.unit`, but `ft_checkconfig`'s list of fields it moves
  there has no `unit`, so the spacing is read in the head model's
  millimetres: a 1 mm grid of about 1.7 million pairs, some hours of scanning
  before the fit starts. (A 3 cm request gave 61,553 points on a 3 mm
  lattice.) The tutorial's 1 cm grid is `resolution = 10` with this head
  model; DipoleFit gives its spacing in the head model's unit for this
  reason. `ft_prepare_sourcemodel` called directly does honour `cfg.unit`.
- **The default optimiser can fail silently.** `fminunc` (the Optimization
  Toolbox) fails on this machine, and FieldTrip then returns the grid
  search's starting point, [±35 -15 55] mm, with no residual variance and no
  error. DipoleFit uses `fminsearch`, and refuses a fit without one.

### Beamformer: the same code path, the expected source

FieldTrip's tutorial (`tutorial/source/beamforming`) computes DICS at 18 Hz,
±4 Hz, from 350 to 850 ms after the response, with one filter from all
trials, and maps (left - right) / (left + right) between the left-hand (49)
and right-hand (50) responses, on a 5 mm grid in the subject's head
(13,331 points inside), with 15% regularisation.

Alakazam's Beamformer contrasts two windows rather than two bins, so its own
functions (`fieldtripTrials`, `spectrumOf`, `sourcePower`, `dicsContrast`, called
from a verbatim copy of `Beamformer.m`) were run on the same trials, head
model and grid, with a baseline of -1500 to -1000 ms:

| Map | At the left hand area, [-2 -1.5 7] cm |
|---|---|
| FieldTrip's tutorial, (L - R) / (L + R) | -0.140, among its lowest 0.5% |
| Alakazam's filter, the same contrast | -0.232, its minimum |
| Alakazam's output, right-hand bin, (active - baseline) / baseline | +0.618, its maximum |
| Alakazam's output, left-hand bin | +0.067 |

The beta rebound after right-hand responses, over the left hand area, is
where both put it; the left-hand responses show no clear rebound over the
right hand area in either. Over the whole brain the two contrast maps
correlate at r = 0.907. The difference is the filter: Alakazam computes it
from both of its windows, as a contrast between windows needs, the tutorial
from the active window alone. With the tutorial's filter and Alakazam's other
setting (`fixedori`), the map correlates with the tutorial's at 0.988.
Rebuilding Alakazam's values from its own steps reproduced `dicsContrast`
exactly. This was checked once and is not a test: it needs 133 MB of data.

## Not checked

- Source Estimate and Source Regions: FieldTrip's minimum-norm tutorial is
  MEG only.
- LCMV: the tutorial's beamformer is DICS.
- Anything against the subject's anatomy, which Alakazam's template head
  cannot match by design.
