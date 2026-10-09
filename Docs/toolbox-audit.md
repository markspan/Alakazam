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
| TimeFrequency | Morlet ERSP, dB baseline | `newtimef`; `ft_freqanalysis('wavelet')` with `ft_freqbaseline('db')` | Against FieldTrip in `FieldTripReferenceTest`, to 0.027 dB | Keep |
| CoherenceMap | wavelet, STFT and filter-Hilbert coherence over time | `newcrossf`; `ft_freqanalysis` with `ft_connectivityanalysis('coh')` | Its estimator family, through SpectralMeasure's, against `newcrossf`; the wavelet against FieldTrip, to 0.006 | Keep; edge rule applied |
| SpectralMeasure | amplitude, SNR, ITC and the coherence normalisation on exact-frequency coefficients; the transform and tapers are the Signal Processing Toolbox's (`goertzel`, `hann`, `dpss`) | `ft_freqanalysis('mtmfft'/'mtmconvol')`, `ft_connectivityanalysis('coh')`; `newcrossf` (an option) | Against FieldTrip in `FieldTripReferenceTest`, to rounding; frame coherence against `newcrossf` to about 0.001 on RIFT data; group means against Dimigen et al. | Toolbox transform; keep the rest (below) |
| CoherenceTopography | the same frame coherence, one frequency per bin | as SpectralMeasure | Its frame coherence against FieldTrip, through SpectralMeasure's case; the RIFT means in `LibraryReplayTest` | Keep |
| Fourier | calibrated FFT spectra (amplitude, power, PSD, complex) | `spectopo`; `ft_freqanalysis('mtmfft')` | Closed-form cases in `FourierTest`; the PSD against FieldTrip, to 1e-15 | Keep |
| Welch | averaged periodogram, skipping segments with rejected samples | `pwelch` (cannot skip them) | Against `pwelch` in `WelchTest` | Keep |
| CrossCorrelation | FFT-based per-lag Pearson r, averaged in Fisher-z | `xcorr` (a different normalisation) | Against an independent per-lag loop; `xcorr`'s normalised form divides by the whole signals' energies, a different quantity | Keep |
| Covariance | channel covariance per bin | `cov` | Against `cov` | Keep |
| DCDetrend | the fitting range and the report; the fits are `polyfit` and `robustfit` | `ft_preproc_polyremoval`, `detrend` | Against `ft_preprocessing` and `ft_preproc_polyremoval` on epochs, `detrend` over the whole epoch, and known drifts | Toolbox fits (below) |
| Baseline | mean subtraction, on FieldTrip's window rule | `ft_preprocessing` demean, `ft_timelockbaseline`; `pop_rmbase`; ERPLAB's `blvalue2` | Against `ft_preprocessing` in `FieldTripReferenceTest`; identical to ERPLAB on Luck's data | Keep (below) |
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

2. **Done: the same edge rule in CoherenceMap's wavelet method.** It has no
   baseline, so the M26 bias does not arise, but near the ends of the epoch
   the wavelet is effectively shorter, so each coherence value there mixes in
   neighbouring frequencies: a 60 Hz response bleeds into the 64 Hz row
   exactly where the reader looks for the onset. FieldTrip returns `NaN` there,
   and now so does `ComputeCoherenceMap`, for the coherence and the reference
   power alike; the half-wavelets and the frequencies blank throughout are
   recorded in `etc.alz.coherenceMap`, and the view names them.

3. **Done: tests against the toolbox where one exists and nothing compared
   yet**, in `FieldTripReferenceTest`, skipped cleanly when FieldTrip is not
   installed: TimeFrequency against `ft_freqanalysis('wavelet')` and
   `ft_freqbaseline('db')`, CoherenceMap's wavelet against
   `ft_connectivityanalysis('coh')`, Fourier's PSD against
   `ft_freqanalysis('mtmfft')` with a Hann taper. The PSD agrees to 1e-15.
   The wavelet comparisons needed one convention matched first: FieldTrip
   cuts its wavelet to a whole number of samples counted from -3 sigma, and
   with ordinary cycle counts that alone moved the ERSP by up to 0.13 dB,
   more than M26's mean-of-dB baseline (0.04 to 0.08 dB here). With cycles
   that put 3 sigma just past a whole sample, the ERSPs agree to 0.027 dB and
   their means per channel and frequency to 0.002 dB, and the coherences to
   0.006. Each check was seen to fail on the error it guards: the mean-of-dB
   baseline, power or coherence computed over the edges, and a PSD that
   doubles 0 Hz and Nyquist.

4. **Done: the grand average's error band when subjects are weighted.** With
   weighting on, the line was the trial-weighted mean of the subjects, but the
   band was the unweighted standard error across them
   (`GrandAverage.combineSubjects`): two different estimators. The band is now
   the standard error of the weighted mean, the square root of
   `V * sum(w.^2)` with `V = sum(w .* (x - mean).^2) / (1 - sum(w.^2))`, which
   is the plain standard error when the weights are equal, and the pooled
   aSME is `sqrt(sum(w.^2 .* SME.^2))`. ERPLAB 13.10 is no reference here:
   its `gaverager` sums the squares weighted by the raw trial counts but
   subtracts the squared mean and divides as if they were unweighted. With
   every subject on `n` trials, the variance it reports is `n` times the
   right one plus `(n - 1) N / (N - 1)` times the squared grand mean, so its
   weighted band is several times too wide (read from its source, not run).

5. **Do not replace the rest.** Each swap would trade a checked computation
   for a dependency and lose per-channel rejection, combination bins and the
   provenance record, for no change in the numbers. The pattern that works
   here is the one Average, Measure and Welch already follow: the own
   implementation, held to the reference by a test.

## SpectralMeasure, examined again (1 October)

Asked to use toolbox computations wherever they fit, SpectralMeasure was read
quantity by quantity against FieldTrip and EEGLAB, FieldTrip counting as
available like any optional toolbox.

- **The transform** is now the Signal Processing Toolbox's `goertzel`, which
  evaluates the DFT at a fractional index and so at any frequency, with its
  `hann` and `dpss` tapers. FieldTrip's spectral estimators round each
  requested frequency to the padded epoch's grid (`ft_specest_mtmfft` and
  `ft_specest_mtmconvol`, `freqoi = (freqboi - 1) ./ endtime`), so they read a
  harmonic or intermodulation row at the nearest bin, not at its frequency.
  At a frequency on the grid the coefficients are the same.
- **Amplitude, SNR and ITC** stay as their definitions: FieldTrip and EEGLAB
  have no function for any of them at one exact frequency.
- **The coherence** is FieldTrip's estimator, which averages the cross-spectra
  over trials ignoring NaN and normalises by the averaged powers
  (`ft_connectivity_corr`), on the exact-frequency coefficients. One
  difference is kept on purpose: FieldTrip averages each power over every
  trial that channel has, so under per-channel rejection the reference power
  in its denominator covers trials the cross-spectrum does not.
- **The phase** was measured from the epoch's first sample; it is now measured
  from time zero, as FieldTrip measures it.
- **A bug found on the way**: with `newcrossf` as the estimator, one rejected
  (NaN) trial made the whole coherence image NaN. Rejected trials are now left
  out first.

`FieldTripReferenceTest` holds amplitude, phase, ITC and SNR to `mtmfft`, and
the frame coherence to `mtmconvol` with `ft_connectivityanalysis`, frame by
frame, both with rejected trials, to rounding. With an even frame length
FieldTrip centres each frame one sample earlier than `TransTools.FrameStarts`,
which moves the average coherence by about 0.002; the test uses an odd length.

## Decisions taken (1 October)

Writing the reasons for keeping each computation into its code turned up two
places where the reason did not hold. Both were decided the same day, with a
general rule: where EEGLAB or FieldTrip has a convention for an operation,
Alakazam adopts it.

- **Time windows.** When a window's ends fall between samples, `pop_rmbase`
  takes the samples inside it, FieldTrip (`nearest`, as `ft_preprocessing`,
  `ft_timelockbaseline` and `ft_selectdata` use it) and ERPLAB (`closest`)
  the sample nearest each end, earlier on a tie, and Baseline took the sample
  at or before each end; most other steps took the samples inside. All now
  use FieldTrip's rule through `TransTools.WindowSamples`, which also refuses
  a window wholly outside the epoch, as `ft_selectdata` does. Baseline also
  leaves rejected samples out of its mean, as `ft_preproc_baselinecorrect`
  does. The exceptions follow their own toolbox: TimeFrequency's baseline
  takes the samples inside, as `ft_freqbaseline` and `newtimef` do, and
  Deconvolve's takes those from its start up to, but not including, its
  stop, as Unfold's `uf_plotParam` does. (Until 2026-10-09 Deconvolve took
  the stop sample too, while this note said it followed Unfold; see
  `Docs/unfold-technical-note.md`.) `FieldTripReferenceTest` holds Baseline
  to `ft_preprocessing`'s demean.
- **DC-Detrend's fits.** The robust fit is now `robustfit` with Huber weights.
  Least squares was meant to become FieldTrip's `ft_preproc_polyremoval`,
  which does exactly this job, but as FieldTrip calls it (without its
  standardising flag, which needs a function private to another FieldTrip
  folder) it fits the raw sample index: an order-2 trend on a recording of
  300 000 samples or more comes out 50 uV wrong, the whole trend lost, where
  orders 0 and 1 and every epoch length up to 5000 samples agree to 3e-6 uV
  or better. Least squares is therefore MATLAB's `polyfit`, centred and
  scaled, and `FieldTripReferenceTest` holds it to `ft_preprocessing` and
  `ft_preproc_polyremoval` on epochs.

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
