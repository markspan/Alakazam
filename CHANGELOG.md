# Changelog

What changed in each release, newest first. Releases are tagged on the
Development branch; the version running is shown in the main window's title
bar. Dates are those of the tag.

## Unreleased

### Added

- **PREP, ASR and AutoReject**, the standardised automated cleaning methods
  the field cites (Tools > 2. Artifact Rejection / Reduction). **PREP** runs
  the PREP pipeline (Bigdely-Shamlo et al., 2015): line noise at the mains
  frequency and its harmonics, bad channels found by robust statistics and
  RANSAC and interpolated, and a robust average reference; the line
  frequency defaults to 50 Hz where PREP's own is 60. **ASR** runs
  clean_rawdata's bad-channel and burst stages (Artifact Subspace
  Reconstruction), interpolates the removed channels back in their places,
  and repairs bursts, or marks them rejected rather than cutting them out;
  its criterion defaults to 20 SD. **AutoReject** implements local
  autoreject (Jas et al., 2017): a peak-to-peak threshold per channel chosen
  by cross-validation, and a consensus that rejects an epoch or interpolates
  its worst channels, deterministic and checked against a literal
  evaluation of autoreject's criterion. All three work on the scalp channels
  with a position and leave the peripherals alone, record what they did, and
  have their own table in the data-quality report's provenance section. PREP
  is downloaded on first use, after consent, pinned to v0.56.0;
  clean_rawdata ships with EEGLAB and is now on the startup plugin list.
- **A generator for new transformations**: `newTransformation('Name', ...)`
  writes the entry function (the contract, a generated dialog from the fields
  given, replay, an input check and a record in `etc.alz`), the manifest, a
  placeholder icon and its SVG source, a test class whose cases pass as
  generated, a manual section with an options table, and the entry on the
  Recalculate list. DEVELOPER.md now also states what a transformation may
  do to the dataset it is given.
- **Every major recording format opens**: European Data Format (.edf,
  EDF+), BioSemi (.bdf), GDF, Neuroscan and ANT Neuro (.cnt), EGI (.mff and
  simple binary .raw), Lab Streaming Layer (.xdf), Micromed (.trc), Nicolet
  (.e) and MNE-Python's .fif, alongside .set, .vhdr, .erp and .mat. Each is
  read by its dedicated EEGLAB reader, installed through EEGLAB's plugin
  manager the first time it is needed, with EEGLAB's File-IO route
  (FieldTrip's readers) as the fall-back. An EyeLink .edf beside a
  recording is recognised by its header and left for EyeTracking. The list
  is one registry (`rawFormats`), so a format is one entry.
- **A recording that cannot be read no longer stops the workspace from
  opening**: it is left out, and one message lists every such file and why.
- **ArtefactDetect has a flat-line detector**: a channel whose voltage stays
  within a set range (1 uV by default) for at least a set time (200 ms), at
  any offset. A channel that is exactly zero throughout is the reference and
  is not tested.

- **A library of ready-made files**, in `library/` at the root: templates
  (`library/templates`), bin scripts (`library/binscripts`) and measurement
  windows (`library/measures`), gathered from `templates/`, `binscripts/` and
  the Measure presets, which moved there. Every measurement file now says
  where its windows come from: the reference, and whether it matches it,
  partly matches, differs, has not been compared yet, or has no published
  source (the P300 and LRP sets match ERP CORE; the N400 set takes its window
  but uses Cz for CPz; the MMN set uses 150 to 250 ms for ERP CORE's 125 to
  225 ms). `library/README.md` indexes every file and the data it was written
  for, and `LibraryTest` checks that each loads, has its source and is
  indexed. `LibraryReplayTest` replays the templates on their own data, where
  it is present, and compares with the results recorded when each was
  checked (Docs/luck.md, Docs/dimigen.md, chapters 17 and 20 of the manual).
  `AutoEyeICA.alztemplate`, which was never checked against its data, is not
  in the library.
- **Reference tests against FieldTrip** (`FieldTripReferenceTest`, skipped
  when FieldTrip is not installed): the TimeFrequency ERSP against
  `ft_freqanalysis` and `ft_freqbaseline('db')`, the Coherence Map's wavelet
  coherence against `ft_connectivityanalysis('coh')`, Fourier's PSD
  against `ft_freqanalysis('mtmfft')`, and Spectral Measure's amplitude,
  phase, ITC, SNR and frame-averaged coherence against `ft_freqanalysis`
  (`mtmfft`, `mtmconvol`) and `ft_connectivityanalysis`. They agree to 0.027
  dB, 0.006, 1e-15 and, for Spectral Measure, to rounding, rejected trials
  included, and each fails on the error it is there to catch, including both
  halves of the time-frequency baseline bug fixed below.

### Changed

- The Filter dialog plots only the frequency response of the ticked filters
  now; the impulse response above it is gone.
- **Time windows follow FieldTrip's rule.** Baseline, DC-Detrend's fitting
  range, ArtefactDetect's test window, Covariance, Cross Correlation, CohTopo,
  RESS, Source Estimate (and the source cluster statistics) and Spectral
  Measure's coherence window take the nearest sample at each end of a window
  in ms, the earlier one on an exact tie, as FieldTrip selects a latency
  range and ERPLAB a baseline. They took the samples inside the window, and
  Baseline the sample at or before each end. A window lying wholly outside
  the epoch is now refused, where it silently became the whole epoch (or, in
  ERP Measure, the edge sample). Where a window's ends fall between samples
  the result moves by at most one sample at each end; recalculate to bring
  older nodes in line. TimeFrequency's baseline and Deconvolve's keep the
  samples inside the window, as `ft_freqbaseline`, `newtimef` and Unfold do.
- **Baseline leaves rejected samples out of the mean**, as FieldTrip does: one
  rejected sample inside the window used to make that channel of the trial
  entirely missing.
- **DC-Detrend's fits are MATLAB's**: `polyfit` for least squares (the same
  numbers) and `robustfit` for the robust fit, which moves slightly, since
  `robustfit` adjusts for leverage and iterates to convergence where the
  hand-written fit stopped after five iterations.
- **Spectral Measure's phase is measured from the event** (time zero), as
  FieldTrip measures it. It was measured from the epoch's first sample, so
  the same response read a different phase depending on how long before the
  event the epoch started. Recalculate Spectral Measure nodes whose phase you
  report; amplitude, power, SNR, ITC, coherence and phase lag are unchanged.
- **Spectral Measure's transform and tapers are the Signal Processing
  Toolbox's** (`goertzel` at the exact frequency, `hann`, `dpss`), and so is
  the transform of the frame-averaged coherence. The numbers agree with the
  previous code to about 1e-13. Why these and not FieldTrip's `ft_freqanalysis`,
  which rounds every frequency to the epoch's grid, is set out in the manual
  and in the code.
- **CohTopo shows every bin's map in one plot**, side by side on one colour
  scale, with a tickbox per bin in a column on the right (as the ERP view has
  for its lines), instead of one map at a time behind a dropdown.

- **The generated settings dialog can hold much more**, so fewer
  transformations need a dialog of their own. A field can now be a channel
  picker (by label, with All, None and Scalp EEG), a bin picker (with
  Differences), an editable table of rows, a block of text checked when OK
  is pressed, a drop-down whose shown and stored values differ, a number with
  limits, or a live preview; and any field can be greyed out while other
  values say it does not apply. OK now asks every field whether its value can
  be used and stays open, saying why, when one cannot. Interpolate and Derive
  Channels lose their hand-written dialogs to it; Baseline gains a preview of
  its window over every channel's average; ArtefactDetect greys out the
  settings of detectors that are not ticked; the channel lists of Rectify,
  DC-Detrend, Covariance and Cross Correlation gain All, None and Scalp EEG.
- **Interpolating flagged channel-epochs is faster**: trials that share a set
  of bad channels are interpolated in one call, which gives the same result
  (the spline weights depend only on the set) at a fraction of the calls.
  ArtefactDetect's and ManualReject's interpolation benefit; AutoReject's
  cross-validation depends on it.

- **Apply Template, and DefineBins' and ERP Measure's Load..., open in the
  library** the first time in a session, and after that in whichever folder
  a file of that kind was last loaded from. They used to share one folder
  with each other and with EEGLAB, and Apply Template started in the
  workspace's Exports folder.

### Fixed

- **DC-Detrend read a continuous recording's fitting range in seconds.** The
  range is entered in ms, but a continuous recording keeps its time axis in
  seconds, so a 0 to 1000 ms range covered the first 1000 seconds. It is now
  converted first.

- **Spectral Measure's newcrossf coherence went missing after artefact
  rejection.** A rejected trial is NaN, and handed to `newcrossf` it made the
  whole coherence image NaN, so every row's coherence and phase lag were
  missing. Rejected trials are now left out first, as the other two
  estimators leave them out.

- **TimeFrequency reported power that was not there** at low frequencies. It
  computed the baseline over the start of the epoch, where the wavelet
  reaches past the data and the power comes out too low, so everything after
  it came out too high: on stationary noise, +1.3 to +1.5 dB after the
  stimulus at 4 to 6 Hz in a -200 to 800 ms epoch. Samples within half a
  wavelet of either end are now left blank, as FieldTrip leaves them, a
  frequency with no baseline clear of the edge is blank and the view says
  below which frequency, and the baseline is the dB of the mean power, as in
  `newtimef` and `ft_freqbaseline`. On short epochs the lowest frequencies are
  now blank: epoch longer for them. Recalculate time-frequency nodes made
  before this. Found by an audit of every hand-written computation against
  the toolboxes (`Docs/toolbox-audit.md`).

- **The Coherence Map's wavelet method computed coherence at the very ends
  of the epoch**, where the wavelet reaches past the data and is in effect
  shorter, so each value there mixed in neighbouring frequencies. Those
  samples are now blank by the same rule as TimeFrequency, recorded in
  `etc.alz.coherenceMap`, and a frequency whose wavelet is longer than the
  epoch is blank throughout, with the view saying below which frequency. The
  STFT and filter-Hilbert methods are unchanged. Recalculate wavelet
  coherence maps made before this.

- **A weighted grand average drew the wrong error band.** The line was the
  trial-count-weighted mean, but the band around it was the unweighted
  standard error, which belongs to a different mean. It is now the standard
  error of the weighted mean, and the pooled aSME uses the same weights.
  Unweighted grand averages, and weighted ones whose subjects kept equal
  trial counts, are unchanged. Recalculate weighted grand averages made
  before this.

- **A bin script could define the same bin number twice**, and both were
  accepted without a word, although a bin's number is how events and
  combination bins refer to it. It is now refused with a message naming the
  number. A shipped P3b bin script did this; it is removed, with two other
  drafts from the old `binscripts/` folder.

- **Export as Code wrote a ReRef that reconstructs an implicit reference as a
  plain `pop_reref`**, which drops the reconstructed channel and, under an
  average reference, subtracts a different average. Such a step now keeps
  ReRef's own call in the script, as Filter does.

- **The continuous view sometimes drew a sawtooth** that went away at the
  next zoom. Its min/max envelope was decimated for the axes' width as last
  measured, which before layout is a placeholder and after a window resize,
  a move into the tile grid or an undock is out of date; and between 2 and 8
  samples per pixel it used 8-sample buckets, up to 4 pixels wide. A line
  through buckets wider than a pixel zigzags. The envelope is now decimated
  for at least the widest screen, and no bucket is wider than a column: the
  samples are reduced directly where the pyramid's finest level is too
  coarse, and its buckets are merged to one per column elsewhere, which also
  draws fewer vertices than before.
- **The Reports tree listed the reports of every workspace** sharing the
  same Exports folder. A report now records the workspace that rendered it
  (its Raw folder), and each workspace lists its own; a report made before
  that is judged by the recordings its tables name. Grand averages were
  already scoped this way.
- **Recalculate on a step under a grand average recalculated the grand
  average.** A Filter run on a grand average keeps the grand average's record
  in its data, and that record was read as "this node is a grand average", so
  Recalculate reopened the subject list instead of the filter's settings. The
  grand average is now told by its place in the tree (the top-level node),
  and a step under it recalculates as that step. An Average under a grand
  average no longer offers Recalculate at all.
- **Steps under a grand average came back after reopening the workspace.**
  They were saved in a folder named after the grand average, like every
  node's children, but only the grand averages themselves were read back.
- **Derive Channels on an average could not be shown**: the step added the
  channel to the data but not to the average's standard error and aSME, and
  the waveform view failed with "Arrays have incompatible sizes". Every
  transformation's result now has those arrays (and the interpolation mask)
  brought in step with its channels as it returns (`TransTools.
  AlignChannelCompanions`, run by `TransTools.invoke`), so the same holds
  for Select Data, Channel Editor and any plugin, and a node saved before
  the fix draws too. A derived channel's error on an average is unknown and
  drawn without a band; derived before Average, it gets its own.
- **A failed step no longer leaves a node behind.** A result is saved as a
  node before it is drawn; when the drawing (or the saving) failed, the node
  stayed, looking like an unchanged copy of its parent. It is now taken out
  again, and the step either completes or leaves no trace.
- **The error dialog says what failed.** It used to read "could not run on
  this dataset" and suggest the data was of the wrong kind whatever
  happened. It now tells a failed step from a failed drawing of its result
  (and says the fault is then the view's), names the kind and shape of the
  dataset concerned, keeps the "wrong kind of data" hint for the errors
  data of the wrong shape produces, and calls any other unanticipated error
  a defect rather than the user's data.
- **The cluster statistics report printed its significance level as
  `\(\alpha\)`**, and the data-quality report its chi-square the same way.
  They were written as TeX math, which is drawn by MathJax, and MathJax does
  not run in the app's report viewer (nor offline). The reports now print
  the letters themselves (α, χ²), from one place (`ReportDoc.symbol`), and a
  test fails on TeX math in any report source. Reports are also written and
  read explicitly as UTF-8.

### Documentation

- The documents in `Docs/` are brought up to date: the transformation
  provenance re-verified for all 35 transformations, the RIFT companion with
  RESS and the current templates, and the Luck companion with the current
  ribbon, report and data download. The fifth pass of the capability review
  is added as `Docs/where-alakazam-stands.md`.
- **Why each computation is Alakazam's own, or a toolbox's.** Every
  transformation that computes something a toolbox also computes now says,
  in its code (a TOOLBOX OR OWN CODE paragraph in its header) and in its
  manual section, which toolbox that is, why the computation is kept or
  handed over, and what holds it to the toolbox. Writing them down corrected
  two claims (Cross Correlation is checked against a per-lag calculation, not
  `xcorr`, which normalises differently; DC-Detrend is now also checked
  against `detrend`) and raised two decisions, since taken: Baseline's window
  rule and DC-Detrend's fits (under Changed).

## V0.4.4.3 (2026-09-28)

### Documentation

- The manual and the README cite Pütz, Span & Lorist (2025) again, the
  protocol whose workflow Alakazam follows; it had been lost when the
  README became a landing page. The manual now also cites de Cheveigné &
  Nelken (2019) on reporting filters, Dimigen (2020) on ICA for free
  viewing, and Dandekar et al. (2012) on overlapping saccade responses.

### Added

- The Filter dialog plots the impulse response of the ticked filters
  together under the three filters, with its length, from the same kernels
  the step applies, and redraws it as the settings change.
- Below it, at the bottom of the dialog, the Filter dialog plots the
  frequency response of the ticked filters together: the gain in dB from
  0 Hz to the Nyquist frequency, with a dotted line at -6 dB where each
  cutoff sits. It is the gain of the same kernels, and is shown in global
  mode only, like the impulse response.
- The continuous view marks every sample with a small filled circle once it
  is zoomed in far enough that each sample has two pixels or more to itself;
  an overlaid recording is marked by its own sampling rate.
- **An averaged spectrum overlays its bins**, as the ERP plot does: a
  tickbox per bin beside the plot, each ticked bin a line in the colour it
  has in the ERP plot, with its standard-error band (the ERP plot's own
  confidence-interval settings). With two bins ticked, **Difference** draws
  the first minus the second, **Swap** reverses it, and **Ratio in dB** draws
  their ratio in decibels (10·log10 for a power, 20·log10 for an
  amplitude); with the phase shown, the difference is the phase of one
  relative to the other.
- **Overlay on plot works on spectra**, as on ERPs: right-click an averaged
  spectrum, or a Welch spectrum of a continuous recording, and choose
  Overlay on plot, or drop one averaged spectrum onto another. Channels are
  matched by name and each spectrum keeps its own frequencies; overlaid
  lines are named by what sets their datasets apart, drawn underneath and
  paler (Overlay opacity), and taken off with Remove overlay. Difference
  and Ratio in dB compare any two ticked lines, of one dataset or two, the
  second interpolated onto the first's frequencies. A spectrum in another
  unit, or single-trial spectra, are refused with the reason.
- **Log scale** in the spectrum view draws the magnitude on a logarithmic
  axis, six decades deep; it is off by default. On a log scale the y zoom
  keeps the bottom of the axis and brings its top down.
- Fourier and Welch record what their spectrum holds (`EEG.SpectrumUnit`,
  Fourier's Output, or PSD for Welch), which Average keeps. The spectrum
  view labels its axis with it and takes the right factor for a ratio in
  dB; a spectrum computed before this has no label and no ratio until it is
  recalculated.

- **Deconvolve warns about events locked together.** When an event in no
  bin is modelled and keeps a nearly constant lag to a bin or to another
  modelled event (a fixation 12 ms after its saccade), the dialog lists a
  warning in the model and raises an alert naming the pair and the lag, and
  the fit notes it; if the solver then does not converge, its note names
  the pair as the likely cause. Such a pair makes the design nearly
  collinear, which was the likely reason for a reported "did not converge".
  Unticking the event clears the warning.

### Changed

- **The spectrum view picks the channel with a dropdown above the plot**, as
  the other views do, instead of a row of step and pan buttons below it. On
  single-trial spectra a second dropdown picks the trial and names its bin;
  an averaged spectrum's bins are tickboxes instead (above). The keys and
  the mouse wheel still step, and the dropdowns follow them. The zoom
  sliders stay; the plot's toolbar pans.
- **The Spectral Measure view picks the channel and the bin with dropdowns
  above the plot**, as the spectrum view and the other views do, instead of
  a row of step and pan buttons below it; the bin dropdown is left out when
  there is one bin. The keys, the mouse wheel and a focus shared from
  another view still step, and the dropdowns follow them. The zoom sliders
  stay; the plot's toolbar pans, and the x zoom keeps a pan made with it.
- The spectrum view still fills the frequency bands under the curve when
  one spectrum is drawn (from the bottom of the axis on a log scale), and
  shades them as pale stripes behind the lines when there are several, or
  a difference, where there is no one curve to fill under.
- `src/help/node_modules/` and `src/help/dist/`, left behind by the old help
  builder, are removed from the repository (a clone that had built the old
  help page had committed them) and ignored again, so they do not show up
  as new files after a pull.
- The Photodiode picture in the manual shows a recording with a diode
  patch; it is taken by hand, so the capture tool no longer makes it.
- **Fourier, Welch, TimeFrequency and Coherence Map show their progress in
  the app's own busy dialog**, as a bar that fills with the percentage done
  and the time left, instead of in a separate small window. The dialog
  turns back into its spinner when the computation is done. Run from a
  script or a test, with no app, they show nothing. The old window
  (`TransTools.progressbar`, from 2004) is removed.

### Fixed

- Dropping one averaged spectrum onto another replayed Average onto an
  average, which could only fail; it now overlays the two, as dropping one
  ERP onto another does.
- **Fourier's Complex output had the phase of every coefficient the wrong
  way round**: it stored the complex conjugate of each spectrum, because
  the transform was transposed with `'`, which conjugates. A cosine starting
  at phase φ read -φ. The magnitudes (Volt, Power, the densities, PSD) were
  never affected. Complex nodes computed before this fix keep the old sign
  until they are recalculated.
- **The Fourier view's phase (the P key) is wrapped to -π to π and drawn as
  points.** It was unwrapped across frequency, which piled up the ramp that
  comes from measuring phase from the segment's first sample: on a long
  recording, a straight line reaching 10^4 to 10^5 radians by 100 Hz. It was
  also drawn on an axis that started at 0, and its label stayed on the axis
  after switching back to the magnitude.
- The Filter dialog did not open for settings that stored a filter which is
  off with a frequency or attenuation of 0, as a script does; it now falls
  back to the defaults for those fields.
- **ReRef with an Average reference and a reconstructed implicit reference
  left the reference site out of its own average.** The channel is now added
  as a flat zero before re-referencing, as EEGLAB advises, so N recorded
  channels and the reference are averaged as N + 1 sites and the channels
  sum to zero. Before, the subtracted average was (N + 1)/N of what it
  should be (3% too large at 32 channels). Specific-channel references are
  unchanged.
  Nodes computed before this fix keep the old result until recalculated.
- **Fourier's Other resolution no longer drops samples.** A spacing coarser
  than the segment's own made the transform shorter than the segment, which
  used only its first samples, silently: at 200 Hz, a 1 s segment and 2 Hz,
  the first 128 of 200. The transform is now padded to at least the
  segment's length, so such a spacing gives the same spectrum as Max.
- The time-frequency and coherence views leave a cell with no value blank,
  as the ERP image already did for a rejected trial, instead of drawing it
  as the strongest decrease or as no coherence.

## V0.4.4.2 (2026-09-28)

### Added

- **Overlay on plot**, in a node's right-click menu: draws an average's
  waveforms on the ERP plot in view, from either tree, to compare two
  subjects, two conditions, or the same average before and after a step; or
  a continuous recording under the continuous recording in view, each
  channel in the lane of the channel with the same name, as a grey ghost.
  Its **Difference** draws, in each lane, the recording minus the overlaid
  one: what a filter or a cleaning step removed.
- **Difference**: with exactly two lines ticked, the ERP plot draws the
  first minus the second (**Swap** reverses it), interpolating when the two
  were sampled differently.
- **Overlay opacity**: overlaid datasets are drawn underneath the plot's own
  and paler, by a slider below the tick boxes. **Remove overlay** takes them
  off again.
- The ERP plot keeps a zoom or pan made with its toolbar while channels are
  stepped and lines ticked; **Restore view** returns to automatic scaling.

### Changed

- Overlaid ERPs are matched by channel name and drawn on their own time
  axes, so a resampled or re-referenced average overlays the original; two
  datasets with no channel or time in common are refused with the reason.
  Their lines are named by what sets the datasets apart in the tree.

### Fixed

- A right-click on a tree node also clicked it, so the node was plotted and
  its plot brought to the front before the menu opened. Only the left button
  clicks now; the right-click still selects the node for its menu.
- Overlaying two averages whose channels were in different orders drew
  different electrodes on one plot, since channels were matched by position.
- Dropping an average onto an average of another shape replayed Average
  onto it, which could only fail, instead of saying why they cannot be
  overlaid.

## V0.4.4.1 (2026-09-27)

### Documentation

- **Three documents instead of one.** The README is now a short landing
  page; the user manual moved into a Quarto book (`manual/manual.qmd`),
  rendered as a self-contained HTML page (which the Help button shows) and as
  a PDF; the architecture, plugin contract, testing and release notes moved
  into `DEVELOPER.md`; and this changelog took the history that had
  accumulated in the README.
- **Every transformation has a section in the manual**, with its method and
  the literature behind it, every option and its default, a picture of its
  dialog and, where it produces one, of its result.
- **The manual's pictures are regenerated from the running application** by
  `src/help/capture/captureManualImages.m`, on the datasets in `DATA.md`, in
  scratch workspaces that leave every real workspace untouched.
- The bibliography is a BibTeX file (`manual/references.bib`) and the manual
  cites it throughout.
- **Help shows the manual.** The in-app help page is the rendered manual,
  prepared on the first press of Help (a release ships it ready-made; a clone
  renders it with Quarto). Without Quarto, Help offers the PDF manual or the
  README. The Node.js help builder is gone. The manual's maths is MathML, so
  the page needs nothing from the internet.
- The PDF manual (`manual/manual.pdf`) is committed, and attached to each
  release.

### Added

- **An `epoch` statement in the bin language**: `epoch [-200,800] ms` in a
  script sets the epoch, so a script, a `.binscript` or a template carries
  its own. It wins over the dialog's epoch fields, and the run's summary
  says so when they differ. Deconvolve ignores it.
- **The data-quality report shows rectification**: the mode, which channels,
  and whether single trials or the average were rectified.
- **Rejection breakdown** is a small dialog with a table, instead of an
  alert.

### Changed

- `onApplyTemplate` takes an optional template file, so a script can apply a
  template without the file picker.
- Text before the first statement of a bin script, other than comments, is
  refused with an explanation, where it used to be dropped without a word.
- Recordings taken out of the study under **Grouping** are marked
  "(not in study)" in Define Grand and the cluster dialogs, and the cluster
  dialogs no longer select them.
- The Spectral Measure view keeps the selected bin, as well as the channel,
  when another node is opened.

### Fixed

- **Average**: the standard error, the aSME and the trial count included
  rejected trials. Averages computed before this fix keep the old values
  until they are recalculated.
- **TimeFrequency**: one rejected trial made the whole ERSP map NaN.
- **Coherence Map**: one rejected trial made a channel's coherence NaN.

## V0.4.4 (2026-09-25)

### Added

- **Deconvolve**: regression-based, overlap-corrected ERPs through the Unfold
  toolbox (Ehinger & Dimigen, 2019). Bins in `DefineBins`' language, a
  formula per bin in Unfold's notation (linear terms, factors, splines,
  circular splines, interactions), and three results: one waveform per bin,
  overlap-corrected single trials, or the model's terms at chosen values.
  Every bin is evaluated at the same values of a term, so a covariate that
  differs between bins does not show up as a difference between them.
- **EyeTracking**: joins an EyeLink recording onto the EEG through EYE-EEG
  (Dimigen et al., 2011), refusing a join whose synchronisation is poor and
  reporting its quality.
- **ERP images sort** by the latency of the next or previous event of any
  type, by reaction time, or by any numeric event field, with the sort value
  drawn across the image; a bin selector and a colour range control.
- **RESS**: rhythmic entrainment source separation (Cohen & Gulbinaite,
  2017), one spatial-filter component per tagging frequency, with its null in
  the spectral report; checked against the authors' own code.
- The frame-averaged coherence estimator, now the default for Spectral
  Measure, Coherence Topography and the Coherence Map, agreeing with EEGLAB's
  `newcrossf`.
- **Apply to All Raw Files** runs several recordings at once with the Parallel
  Computing Toolbox.
- Templates for Ehinger & Dimigen's Figure 11 (face task) and for reading
  data.

### Changed

- The statistical report runs one test per comparison rather than a battery,
  with Bayes factors for mixed models.
- **Clear WorkSpace** asks for a normal clear or a deep clean.
- The reports' R code moved out of MATLAB string literals into template
  files.
- Caches are written uncompressed, with the MAT version chosen by size.

### Fixed

- Coherence frequency is read from the reference channel, not from the EEG
  average.
- Deconvolve reads a covariate from its own event, not from another event at
  the same sample.

## V0.4.3.12 (2026-09-14)

### Added

- **Derive Channels**: channel arithmetic (`let LRP = C3 - C4`) as a
  transformation of its own.
- **Collapse Hemispheres**: contralateral and ipsilateral waveforms for an
  N2pc or LRP across every lateral pair at once.
- A template per chapter of Luck's *Applied ERP Data Analysis*.
- **Rejection breakdown**: which artefact detector rejected which trials,
  on right-click and in the data-quality report.
- The manual component selector shows ICLabel's verdict per component.

### Changed

- Epoch time-locking truncates the latency, as EEGLAB and ERPLAB do; with
  that, the N400 chain reproduces Luck's published erpset to 0.0004 µV.
- Channel Editor looks positions up in any electrode template, not only 10-5.
- Recalculate is offered for six more transformations.

### Fixed

- Two bugs found by validating against Luck's published stage outputs, and
  `areaMode` is honoured in fractional area latency.

## V0.4.3.9 (2026-09-11)

### Added

- An **Update** button that checks GitHub for a newer release and applies it
  on the next start.
- Photodiode: falling edges, trigger ranges, onsets timed to the foot of the
  edge, and a preview drawn as a signal view.
- The running version in the title bar.

## V0.4.3.6 (2026-09-10)

### Added

- A Getting started chapter.
- **Undock** a plot into a window of its own; **Close others** on the tab menu.
- **Open in Word** in the report view.
- A quick test suite alongside the full one.
- The channel and bin a user is looking at follow them between views.

### Changed

- The Help button builds its own page instead of printing build commands.

## V0.4.3.5 (2026-09-08)

### Added

- **Source-space cluster statistics** (dSPM or sLORETA on a template cortical
  sheet, TFCE, a compiled kernel), with a report written to the COBIDAS MEEG
  checklist.
- **Source Estimate**: the inversion as a stored, reusable node.
- **EventEditor** and **Photodiode**.
- `Docs/transformation-provenance.md`.

### Changed

- Fourier gained a Complex output.
- Artefact detection no longer tests, or interpolates, the eye channels.
- Every window opens where its title bar can be reached.

## V0.4.3.3 (2026-08-29)

- `TransTools.invoke`, the single checked entry point for every
  transformation.
- ERPLAB bin-descriptor import for DefineBins.

## V0.4.3 (2026-08-29)

- **Export as Code**: the whole workspace as a runnable MATLAB script.
- The design editor (groups, persons, sessions) and a report refactor.

## V0.4.2 (2026-08-28)

- An About dialog; safer cache handling; grand-average candidate selection.

## V0.4.1 (2026-08-27)

- Interpolated channel loss is tracked into the data-quality report.

## V0.4.0 (2026-08-27)

- **Data Quality Report** and the in-app help page.
- A release workflow and a Quarto report test suite.

## V0.3.1 (2026-08-24)

- EEGLAB `.set` export, the DefineBins editor, ManualReject improvements, and
  the Luck example data download.

## V0.3.0 (2026-08-21)

- **Cluster Statistics** (FieldTrip-based cluster permutation testing).
- **Quarto statistical reports**, design-aware, with mixed models and Bayes
  factors; person and session metadata.
- **Measure**: areas, fractional latencies, per-window baselines, derived
  channels. **Spectral Measure**, **Coherence Map**, **Coherence Topography**,
  **TimeFrequency**.
- Templates: **Save Template** and **Apply Template**, and batch replay.
- ERPLAB erpset import and export; the **Filter** transformation; the
  ribbon's overflow groups.

## V0.2.0 and earlier

The application's first versions (2022 to 2024): the tree of datasets with
replayable transformations, built on EEGLAB, in a Java-based window shell
that later MATLAB releases retired (see `migration.md`).
