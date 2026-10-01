# Where each transformation's work is done

Which of Alakazam's transformations wrap another toolkit, and which implement
their method here. Useful when citing the software, when judging what a
dependency's absence would actually cost, and when deciding whether a bug
belongs upstream.

Verified against the source rather than recalled. The commands that produced
it are at the foot of this page, so they can be re-run rather than trusted.

*Last verified: 28 September 2026, 35 transformations, at V0.4.4.3; PREP,
ASR and AutoReject added 30 September, 38 in all. The
previous full pass (30 August, 22 transformations) is superseded: since then
SourceEstimate has come to call FieldTrip's inverse solutions, RemoveComponents
fits dipoles with dipfit, and RESS, Photodiode, EventEditor, DeriveChannels,
CollapseHemispheres, Deconvolve and EyeTracking were added. The pattern now
also matches EEGLAB's `newcrossf`, which has no `pop_` prefix and was missed
before.*

## Wrappers: the toolkit does the work

Thirteen transformations.

| Transformation | Wraps |
|---|---|
| `ReRef` | `pop_reref` (EEGLAB); `readlocs` and `pop_chanedit` place a reconstructed implicit reference |
| `Resample` | `pop_resample` (EEGLAB) |
| `SelectData` | `pop_select` (EEGLAB) |
| `Interpolate` | `pop_interp` (EEGLAB) |
| `Filter` | `firfilt` (EEGLAB firfilt plugin) |
| `AutoEyeICA` | `pop_runica` / `fastica`, `iclabel`, `pop_subcomp`, `pop_select`; `pop_chanedit` fills positions |
| `RemoveComponents` | the same ICA stack, plus `eeg_checkset`; dipfit's `pop_dipfit_settings` and `pop_multifit` for the component dipoles; `topoplot` through `TransTools.DrawScalpMap` for the maps |
| `AutoGEDAI` | `GEDAI` (GEDAI plugin), `pop_select`, `readlocs`; `pop_chanedit` fills positions |
| `SourceEstimate` | FieldTrip: `ft_prepare_leadfield` and the template head, electrode and cortex files for the forward model (`TransTools.BuildSourceForwardModel`), and `ft_inverse_mne`, `ft_inverse_sloreta`, `ft_inverse_eloreta` for the spatial filter (`TransTools.InverseSolution`) |
| `Deconvolve` | `uf_designmat`, `uf_timeexpandDesignmat`, `uf_continuousArtifactDetect`, `uf_continuousArtifactExclude`, `uf_combineWinrej`, `uf_glmfit`, `uf_condense`, `uf_predictContinuous`, `uf_addmarginal` (Unfold), through `Unfold.fitBins` and `Unfold.designMatrix` |
| `EyeTracking` | `parseeyelink`, `pop_importeyetracker` (EYE-EEG) |
| `PREP` | `prepPipeline` (the PREP pipeline, v0.56.0): line noise, bad channels, the robust average reference and the interpolation; `pop_chanedit` fills positions |
| `ASR` | `clean_flatlines`, `clean_channels`, `clean_asr`, `clean_windows` (EEGLAB's clean_rawdata), `eeg_interp` puts the removed channels back; `pop_select`, `pop_chanedit` |

`Deconvolve` has the most of its own around the toolkit: turning DefineBins'
bins into Unfold's event types, each with its formula, and checking every
field a formula names against the bin's own events (`Unfold.binModel`);
finding event types the fit cannot tell apart, identical bins, bins at a
fixed lag and modelled events at a near-constant lag
(`Unfold.timeLockedEvents`); evaluating each bin's waveform at the same values
of its terms, from the toolbox's own design matrix, betas and spline
functions; leaving out the stretches around cuts; the baseline; the difference
bins; and the overlap-corrected trials, which are Alakazam's arithmetic on
Unfold's own time-expanded design and betas (`Unfold.overlapCorrectedTrials`).
The terms output is the toolbox's own (`uf_predictContinuous`, then
`uf_addmarginal`). `EyeTracking` adds finding the eye file beside the
recording, choosing the anchor triggers, and refusing a poor synchronisation,
judged from EYE-EEG's own table of per-trigger offsets.

`SourceEstimate` asks FieldTrip for the forward model and for each method's
spatial filter only (`keepfilter`); resolving the scalp distribution to the
template's electrodes, applying the filter, the time window and the
decimation are Alakazam's.

`ReRef` does more of its own since 28 September: a reconstructed implicit
reference is inserted as a flat zero channel, next to its nearest neighbour
on the 10-5 template, before `pop_reref` runs, so an average reference
includes it.

`ASR` calls clean_rawdata's stages one by one rather than `clean_artifacts`,
for two reasons: its high-pass is left to Filter, and a rejected burst is
marked `NaN` rather than cut out. Which samples a rejection removes is
clean_rawdata's own rule, reproduced in `asrRejectedSamples`. `PREP` passes
its channel sets (the scalp for the reference, the scalp and EOG for the line
noise and the re-referencing) and reads its record; a stage that fails inside
`prepPipeline` is turned into an error rather than passed on.

`Filter` is the one worth a note: the filtering is `firfilt`, but the
parameter design is Alakazam's. You give a frequency and a stopband
attenuation in dB, and the order, transition band and window are derived
from those rather than asked for. The impulse and frequency responses the
dialog plots come from the same kernels.

## Own algorithm, another toolkit for support only

Six transformations.

| Transformation | Its own | Borrowed |
|---|---|---|
| `ArtefactDetect` | the five detectors and the per-detector record, 518 lines | `eeg_interp`, through `TransTools.InterpolateFlaggedCells`, to repair flagged cells |
| `AutoReject` | local autoreject (Jas et al., 2017): the cross-validated thresholds, the consensus and the repair plan, 400 lines | `eeg_interp`, the same |
| `ManualReject` | the rejection view, 382 lines | `eeg_interp`, the same |
| `ChannelEditor` | the editor, 312 lines | `readlocs` and the 10-5 template file (`TransTools.Template1005File`) |
| `CoherenceTopography` | the coherence, 333 lines | `readlocs` and the template file, for electrode positions |
| `SpectralMeasure` | every quantity, and the frame-averaged coherence that is the default estimator, 956 lines | `newcrossf` (EEGLAB), when the older estimator is chosen |

## Written for Alakazam

Nineteen transformations. Sizes are the lines of MATLAB in the transformation's
own folder, comments included, and comments are often half of them.

| Transformation | Lines |
|---|---|
| `Measure` | 1509 |
| `Photodiode` | 1504 |
| `DefineBins` | 536, plus a 1506-line language engine (`@DefineBinsEngine`) |
| `CollapseHemispheres` | 768 |
| `RESS` | 724 |
| `EventEditor` | 721 |
| `CoherenceMap` | 505, with `ComputeCoherenceMap`; plus `TransTools.ReferenceSpectrum` |
| `CrossCorrelation` | 353 |
| `Fourier` | 299 |
| `Covariance` | 289 |
| `TimeFrequency` | 264, with `ComputeErsp` |
| `DCDetrend` | 252 |
| `Rectify` | 243 |
| `Average` | 179 |
| `DeriveChannels` | 172 |
| `Welch` | 165 |
| `Baseline` | 77 |
| `ScalpDistribution` | 42; the drawing is in `ScalpDistributionView` |
| `Brain3D` | 27; scalp-position resolution, the drawing is in `Brain3DView` |

With the thirteen wrappers and the six that borrow a helper, that accounts for
all 38.

## Five things worth knowing

**`AutoReject` is a port, not a wrapper.** autoreject is a Python package on
MNE, with no MATLAB counterpart, so its algorithm is implemented here and
checked against a literal evaluation of its criterion (`AutoRejectTest`). Two
details differ from the package on purpose: each channel's threshold is the
exact minimum over every candidate rather than a Bayesian-optimisation
sample, and each candidate number of channels to interpolate is scored from
the thresholded labels rather than from the previous candidate's.

**`TimeFrequency` is not a `newtimef` wrapper.** `ComputeErsp` builds its own
Morlet wavelets, `exp(2i*pi*f*t) * exp(-t^2 / 2*sigma^2)`, unit-energy
normalised and convolved by FFT. `newtimef` appears in its folder only inside
comments, naming the time-frequency trade-off the two share. Since 30
September its conventions are theirs: samples within half a wavelet of an
edge are left out, as FieldTrip leaves them, and the baseline is the dB of
the mean power, as in `newtimef` and `ft_freqbaseline`. Before, it computed
its baseline over the edge (M26; see [`toolbox-audit.md`](toolbox-audit.md),
which asks this question of every hand-written transformation).

**The source estimates are FieldTrip's filters, applied here.** Until 3
September the minimum norm was Alakazam's own closed form
(`TransTools.ComputeSourceEstimate`, which names `ft_sourceanalysis` only to
record why it does not call it). SourceEstimate now asks FieldTrip for every
method's spatial filter, because eLORETA's weighting is an iterative solve
that is easier to audit in the reference implementation than rewritten. The
closed form is still in the tree, used by the tests as an independent check on
FieldTrip's minimum norm.

**`topoplot` is called in one place.** `TransTools.DrawScalpMap` calls it, for
`ScalpDistributionView`, `CoherenceTopographyView` and
`RemoveComponentsDialog`. The transformations compute; EEGLAB draws. That
separation means a transformation's result does not depend on EEGLAB's
plotting.

**FieldTrip is reached from one transformation, and from the statistics.**
`SourceEstimate`, through `TransTools.BuildSourceForwardModel` and
`TransTools.InverseSolution`, installed on first use by
`TransTools.ensureFieldTrip`; the cluster statistics (`ClusterStats`,
`+ClusterStats/runMontecarlo`) and the source cluster statistics with their
atlas labels (`TransTools.AtlasVertexLabels`), which are a separate mechanism
rather than transformations (see `PROJECT_STRUCTURE.md`).

## How this was verified, and how to redo it

Whole-line comments are stripped before matching, and only whole-line ones.
Stripping from the first `%` to end of line looks equivalent and is not: it
truncates format strings such as `'%s'`, which is how an earlier pass lost a
real `topoplot` call in `TransTools.DrawScalpMap`. Indirect dependencies are
resolved one hop, through the package helper a transformation calls
(`+TransTools`, `+Unfold`, `+EyeEeg`). A helper only one transformation uses
lives in that transformation's own folder (`CoherenceMap/ComputeCoherenceMap.m`,
and so on), so it is already counted under "direct": the glob below reads
every `.m` in the folder.

Run from `src/Transformations`:

```python
import io, os, re, glob
PAT = re.compile(r'\b(pop_[a-zA-Z0-9_]+|eeg_[a-zA-Z0-9_]+|ft_[a-zA-Z0-9_]+'
                 r'|GEDAI|iclabel|fastica|runica|firfilt|newtimef|newcrossf'
                 r'|spectopo|topoplot|readlocs|dipfitdefs|uf_[a-zA-Z0-9_]+'
                 r'|parseeyelink)\b')
PACKAGES = ('TransTools', 'Unfold', 'EyeEeg')

def code(path):
    return "\n".join(l for l in io.open(path, encoding='utf-8',
                                        errors='replace').read().split('\n')
                     if not l.lstrip().startswith('%'))

helper = {p: {os.path.basename(f)[:-2]: sorted(set(PAT.findall(code(f))))
              for f in glob.glob('+' + p + '/*.m')} for p in PACKAGES}

for d in sorted(os.listdir('.')):
    if not os.path.isdir(d) or d.startswith('+'):
        continue
    src = "\n".join(code(f) for f in glob.glob(os.path.join(d, '*.m')))
    print(d, "direct:", sorted(set(PAT.findall(src))) or "-")
    for p in PACKAGES:
        for h in sorted(set(re.findall(p + r'\.([A-Za-z0-9_]+)', src))):
            if helper[p].get(h):
                print("   via", p + "." + h + ":", helper[p][h])
```

And the sizes, from the repository root:

```bash
for d in src/Transformations/*/; do
    echo "$(basename $d) $(cat $d*.m | wc -l)"
done
```

### Matches that are not calls

Three helpers match the pattern without calling the toolkit for any work.
`TransTools.Template1005File` asks `which('ft_defaults')` to find FieldTrip's
copy of the 10-5 electrode template, and falls back to dipfit's; the two are
numerically identical. `EyeEeg.ensure` and `Unfold.isAvailable` name
`pop_importeyetracker` and `uf_designmat` to check that the toolbox is
installed. Those matches are left out of the tables above.

### What this does not prove

The pattern matches the naming conventions of EEGLAB, FieldTrip, GEDAI,
ICLabel, FastICA, Unfold and EYE-EEG, and `newcrossf` by name. A dependency
named unconventionally would be missed, as `newcrossf` was until this pass.
A search for EEGLAB's other unprefixed analysis functions (`timefreq`,
`erpimage`, `binica`, `spectopo`) found no call; that is an absence of
evidence rather than a proof.

It also says nothing about MATLAB's own toolboxes. `fft`, `filtfilt`,
`pwelch` (in the RemoveComponents dialog's spectra) and friends are treated as
part of the language here, not as dependencies; see `dependencies.md` for what
an installation actually requires.
