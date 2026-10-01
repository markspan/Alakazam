# Hand-written science, and where a toolbox could do it

The question: in the transformations, where is a scientifically relevant
calculation done in Alakazam's own code when EEGLAB, FieldTrip, ERPLAB or
MATLAB could do it instead?

*Audited 30 September 2026 on `Development`, 38 transformations. The list of
what is wrapped and what is written here is
[`transformation-provenance.md`](transformation-provenance.md); this page
reads the numerical core of each hand-written one and asks whether it matches
the reference implementation, and whether anything checks that it does.*

## The short answer

Most of the hand-written code is either something no toolbox offers (the bin
language, the photodiode check, RESS as its authors wrote it, autoreject in
MATLAB) or a small computation already checked against the toolbox it
replaces (Average and Measure against ERPLAB on Luck's data, Welch against
`pwelch`, CrossCorrelation against `xcorr`, DCDetrend against `detrend`,
the frame coherence against `newcrossf`). Replacing those would add a
dependency and lose what the own code does that the toolbox does not: leave
rejected trials out per channel (the `NaN` convention), resolve combination
bins, and record what it did.

One computation was wrong, and the audit fixed it (M26 in
`issues.manual.md`): **TimeFrequency computed its baseline over the edge of
the epoch**, where the wavelet reaches past the data, and so reported power
that was not there. Two others are worth changing, and three are worth a test
against the toolbox that does the same thing.

## Found and fixed: the time-frequency edge (M26)

`ComputeErsp` convolves each zero-padded trial with a Morlet wavelet and used
every sample of the result. Within half a wavelet of either end of the epoch,
part of the wavelet lies over no data, so the power there is too low. The
default baseline runs from the epoch start, which is exactly that zone: for a
-200 ms epoch start, no baseline sample was clear of it at any frequency below
about 20 Hz. The baseline was therefore too low, and everything after it too
high.

Measured on stationary white noise, whose ERSP is 0 dB everywhere, in a -200
to 800 ms epoch with a -200 to 0 ms baseline:

| Frequency | Half-wavelet | ERSP, 100 to 500 ms, before | Baseline samples clear of the edge |
|---|---|---|---|
| 4 Hz, 3 cycles | 360 ms | +1.40 dB | 0 of 51 |
| 6 Hz, 3.4 cycles | 272 ms | +1.51 dB | 0 of 51 |
| 10 Hz, 4.2 cycles | 200 ms | +0.64 dB | 1 of 51 |
| 20 Hz, 6.1 cycles | 148 ms | +0.41 dB | 14 of 51 |

The baseline was also the mean of the dB values, where `newtimef` and
FieldTrip's `ft_freqbaseline('db')` both take the dB of the mean power; the
mean of logs is the lower of the two, by about 0.1 dB in the same test.

Now: samples within half a wavelet of an edge are `NaN`, as FieldTrip leaves
them; a frequency with no baseline sample clear of the edge is blank, recorded
in `etc.alz.timeFrequency.noBaseline` and named in the view; and the baseline
is the dB of the mean. On the same noise, averaged over twenty channels, every
frequency that has a baseline is within 0.13 dB of zero. The cost is honest:
on short epochs the lowest frequencies are now blank, and the remedy is a
longer epoch, as it is in either toolbox.

## Every hand-written computation

| Transformation | What it computes itself | The toolbox that does the same | Checked against it | Verdict |
|---|---|---|---|---|
| TimeFrequency | Morlet ERSP, dB baseline | `newtimef`; `ft_freqanalysis('wavelet')` with `ft_freqbaseline('db')` | No; conventions now match both (M26) | Keep, add a reference test |
| CoherenceMap | wavelet, STFT and filter-Hilbert coherence over time | `newcrossf`; `ft_freqanalysis` with `ft_connectivityanalysis('coh')` | Its estimator family, through SpectralMeasure's, against `newcrossf` | Apply the edge rule, add a reference test |
| SpectralMeasure | power, amplitude, SNR, ITC, phase, coherence at named frequencies | `ft_freqanalysis('mtmfft')`; `newcrossf` (already an option) | Frame coherence against `newcrossf` to about 0.001; group means against Dimigen et al. | Keep |
| CoherenceTopography | the same frame coherence, one frequency per bin | as SpectralMeasure | Through `LibraryReplayTest`'s RIFT means | Keep |
| Fourier | calibrated FFT spectra (amplitude, power, PSD, complex) | `spectopo`; `ft_freqanalysis('mtmfft')` | Closed-form cases in `FourierTest` | Keep, add a PSD test against FieldTrip |
| Welch | averaged periodogram, skipping segments with rejected samples | `pwelch` (cannot skip them) | Against `pwelch` in `WelchTest` | Keep |
| CrossCorrelation | FFT-based normalised cross-correlation | `xcorr` | Against `xcorr` | Keep |
| Covariance | channel covariance per bin | `cov` | Against `cov` | Keep |
| DCDetrend | least-squares polynomial drift, fitted on a chosen range | `detrend`, `polyfit` | Against `detrend` | Keep |
| Baseline | mean subtraction | `pop_rmbase` | Trivial | Keep |
| Average | mean of the kept trials, standard error, aSME | `pop_averager` (ERPLAB) | Against Luck's `1_N400.erp` to 0.0004 uV, with its trial counts | Keep |
| Measure | mean and peak amplitude, area and fractional-area latencies, SME | `pop_geterpvalues` (ERPLAB) | Against ERPLAB 13.10 (`Docs/luck.md`) | Keep |
| CollapseHemispheres | contralateral and ipsilateral waveforms with their errors | ERPLAB's channel and bin operations, by hand | Against ERPLAB in its test | Keep |
| RESS | generalised eigendecomposition spatial filters | Cohen and Gulbinaite's own script (no toolbox) | Their filters to ten decimals | Keep |
| ArtefactDetect | ERPLAB's detectors, and flat lines | `pop_artmwppth` and the rest (ERPLAB) | Against ERPLAB on Luck's data | Keep |
| AutoReject | local autoreject | none in MATLAB (a Python package) | Against a literal evaluation of its criterion | Keep |
| Photodiode, DefineBins, EventEditor, DeriveChannels, Rectify | timing, bins, events, channel arithmetic, rectification | none equivalent, or ERPLAB's `pop_eegchanoperator` for the arithmetic | Their own tests | Keep |
| ScalpDistribution, Brain3D | positions; the maps are EEGLAB's `topoplot` | | | Keep |

Outside the transformations, the same question has three answers. The
cluster statistics are FieldTrip's and the mixed models are R's `lme4`, so
nothing to change. The grand average is Alakazam's own weighted mean (see
below). `TransTools.ComputeSourceEstimate`, the old closed-form minimum norm,
is kept only as an independent check on FieldTrip's in the tests.

## Recommendations, in order

1. **Done: the time-frequency edge and baseline** (M26, above).

2. **Apply the same edge rule to CoherenceMap's wavelet method.** It has no
   baseline, so the M26 bias does not arise, but near the ends of the epoch
   the wavelet is effectively shorter, so each coherence value there mixes in
   neighbouring frequencies: a 60 Hz response bleeds into the 64 Hz row
   exactly where the reader looks for the onset. FieldTrip returns `NaN` there.
   The change is the same few lines as in `ComputeErsp`.

3. **Test against the toolbox where one exists and nothing compares yet**,
   skipped cleanly when it is not installed, as `RawFormatsTest` does with
   BIOSIG: TimeFrequency against `ft_freqanalysis('wavelet')` and
   `ft_freqbaseline('db')` (same `sigma_t = c / (2 pi f)`, same three-sigma
   support); CoherenceMap against `ft_connectivityanalysis('coh')`; Fourier's
   PSD against `ft_freqanalysis('mtmfft')` with a Hann taper. FieldTrip is
   already pinned and installed on demand for the source estimates. These are
   the tests that would have caught M26.

4. **Check the grand average's error band when subjects are weighted.** With
   weighting on, the line is the trial-weighted mean of the subjects, but the
   band is the unweighted standard error across them
   (`GrandAverage.combineSubjects`). The two describe different estimators;
   either the band should use the weighted variance, or the report and the
   manual should say which it is.

5. **Do not replace the rest.** Each swap would trade a checked computation
   for a dependency and lose per-channel rejection, combination bins and the
   provenance record, for no change in the numbers. The pattern that works
   here is the one Average, Measure and Welch already follow: the own
   implementation, held to the reference by a test.

## How this was read

The numerical core of each hand-written transformation was read in full
(`ComputeErsp`, `ComputeCoherenceMap`, `Welch`, `Fourier`, `SpectralMeasure`'s
`computeRow`, `GrandAverage.combineSubjects`, and the others' main
functions), the calls it makes were tallied with

```
grep -ohE "\b(fft|ifft|pwelch|xcorr|cov|detrend|conv|filtfilt|hann|dpss|newtimef|newcrossf|ft_[a-z_]+|pop_[a-z_]+|eig|trapz|median|mean|std)\(" src/Transformations/<Name>/*.m
```

and each test file was searched for the toolbox function it names. The M26
figures come from the same formulas as `ComputeErsp` run on white noise, 200
trials at 250 Hz, and are pinned in `TimeFrequencyTest`
(`stationaryNoiseShowsNoEventRelatedPower`).
