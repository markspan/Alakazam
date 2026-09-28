# Changelog

What changed in each release, newest first. Releases are tagged on the
Development branch; the version running is shown in the main window's title
bar. Dates are those of the tag.

## Unreleased

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
- **Log scale** in the spectrum view draws the magnitude on a logarithmic
  axis, six decades deep; it is off by default. On a log scale the y zoom
  keeps the bottom of the axis and brings its top down.
- Fourier and Welch record what their spectrum holds (`EEG.SpectrumUnit`,
  Fourier's Output, or PSD for Welch), which Average keeps. The spectrum
  view labels its axis with it and takes the right factor for a ratio in
  dB; a spectrum computed before this has no label and no ratio until it is
  recalculated.

### Changed

- **The spectrum view picks the channel with a dropdown above the plot**, as
  the other views do, instead of a row of step and pan buttons below it. On
  single-trial spectra a second dropdown picks the trial and names its bin;
  an averaged spectrum's bins are tickboxes instead (above). The keys and
  the mouse wheel still step, and the dropdowns follow them. The zoom
  sliders stay; the plot's toolbar pans.
- The spectrum view shades the frequency bands as pale stripes behind the
  spectra, instead of filling the area under the one curve, which several
  curves or a log axis would not allow.
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
