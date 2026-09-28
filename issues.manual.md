# Issues found while writing the manual

A running list of problems found while documenting Alakazam for the manual
(`manual/`), started 2026-09-26. Each issue has a fixed ID, so it can be
referred to as "M3" in conversation, in a commit message or in a later
session. Close an issue by changing its status, not by deleting it.

Status: **fixed** (in the working tree, not committed), **fixed, untested**
(changed, but no test yet), **open** (not changed), **decide** (needs a
decision before anything changes), **won't fix** (decided to leave as is).

| ID | Status | Area | Summary |
|---|---|---|---|
| M1 | fixed | Average | Standard error, aSME and trial count included rejected trials |
| M2 | fixed | TimeFrequency | One rejected trial made the whole ERSP map NaN |
| M3 | fixed | Coherence Map | One rejected trial made a channel's coherence NaN |
| M4 | fixed, untested | ICA dialog | Activation preview was a single sample on continuous data |
| M5 | fixed, untested | TransformOptionsDialog | Long descriptions were clipped |
| M6 | fixed | ERP image | Rejected trials were drawn as the lowest colour |
| M7 | fixed | TimeFrequency, Coherence views | NaN cells were drawn as the lowest colour |
| M8 | fixed | ReRef | Reconstructed implicit reference was left out of an average reference |
| M9 | fixed | Fourier | "Other" resolution silently truncated segments |
| M10 | fixed | Deconvolve | lsmr "did not converge": time-locked events are now warned about |
| M11 | won't fix | Cache | Average nodes computed before M1 keep the old errors |
| M12 | fixed | Docs | ManualReject header said it was not recalculable |
| M13 | fixed | Docs | `measure.md` and `bin_language.md` were out of date |
| M14 | fixed | Docs | README still said ManualReject is not recalculable |
| M15 | fixed | Manual | Chapters 11 to 22 were draft stubs |
| M16 | fixed | Manual | Screenshots to retake |
| M17 | fixed | Manual | Remaining plan items (README, Help, tests, release) |
| M18 | open | Manual | Screenshots that show a non-default or weak example |
| M19 | fixed | Rejection breakdown | Was a uialert, which the capture tool cannot photograph; now a dialog |
| M20 | fixed | Manual | Captions that did not match their pictures |
| M21 | fixed | DefineBins | `epoch` is now a statement; other text before the first statement is refused |
| M22 | fixed | Grand Average | Recordings taken out of the study are marked "(not in study)" |
| M23 | fixed | Cluster dialog | Said "Home tab" where the ribbon tab is "Alakazam" |
| M24 | fixed | Data quality | Rectification is now reported |
| M25 | fixed | Spectral view | Now keeps the bin as well as the channel |

---

## Fixed in the working tree

### M1. Average: standard error, aSME and trial count included rejected trials

*Status: fixed. `src/Transformations/Average/Average.m` (`keptTrials`,
`standardError`, `windowedSME`), test
`tests/AverageTest.m` `standardErrorCountsOnlyTheTrialsKept`.*

Rejection (ArtefactDetect, ManualReject) writes NaN and leaves the trial in
its bin. Average took the mean and standard deviation with `'omitnan'` but
divided by the square root of **every** trial in the bin, so:

- the standard error, the plotted confidence band, was too narrow by
  sqrt(kept/total): 13% at a quarter of the trials rejected;
- the aSME was too small by the same factor;
- `bindesc(b).n`, the count in the legend, the ERPLAB "accepted" count
  (`averagedToErpset`) and the weight of a weighted grand average, counted
  rejected trials.

The fix divides by the trials kept per channel and sample, and counts as
kept a trial not rejected as a whole epoch. The data-quality SME
(`erpScoreSME`) already counted this way. The test fails on the old code and
passes on the new (checked 2026-09-26). Combination bins inherit the fix
through their constituent bins. Grand Average is not affected in the same
way: it takes the standard deviation across subjects without `'omitnan'`,
so a missing subject gives NaN rather than a smaller error.

### M2. TimeFrequency: one rejected trial made the whole map NaN

*Status: fixed. `src/Transformations/TimeFrequency/ComputeErsp.m`
around line 110; test `tests/TimeFrequencyTest.m`
`aRejectedTrialIsLeftOutNotSpreadAsNaN` (fails on the old code, passes on
the new, checked 2026-09-27). The retaken screenshot shows real maps.*

The wavelet power was summed over all of a bin's trials, and one NaN sample
makes a trial's convolution NaN, so after artefact rejection (the normal
order) every map of that channel and bin was NaN. The manual's screenshot
`timefrequency-result.jpg` shows it: every bin uniformly at the bottom of
the scale. The fix leaves out, per channel, every trial that is not wholly
finite, and divides by the number kept. **To do:** a test in
`tests/TimeFrequencyTest.m` (a bin with one NaN trial gives the same ERSP as
the bin without it), run it against the old code, and retake the screenshot
(M16).

### M3. Coherence Map: one rejected trial made a channel's coherence NaN

*Status: fixed. `src/Transformations/CoherenceMap/ComputeCoherenceMap.m`,
`coherenceOverBins`, around line 278; tests `tests/CoherenceMapTest.m`
`aRejectedTrialIsLeftOut` and `aChannelRejectedInOneTrialKeepsItsOtherTrials`
(both fail on the old code, pass on the new, checked 2026-09-27).*

Same cause as M2, in the cross and auto spectra. The fix skips a trial for a
channel unless both the channel and the reference are intact in it, and
accumulates the reference power in each channel's denominator over the same
trials as its cross spectrum, so the ratio stays a coherence. The
reference's own power (`refPower`) averages over the trials where the
reference is intact. **To do:** a test in `tests/CoherenceMapTest.m`, run
against the old code. Check whether CoherenceTopography and the
`newcrossf` path of Spectral Measure need the same (Spectral Measure's own
paths already use `'omitnan'`; `FrameCoherence` handles NaN).

### M4. ICA dialog: activation preview was a single sample

*Status: fixed, untested.
`src/Transformations/RemoveComponents/RemoveComponentsDialog.m` line 145.*

`squeeze(icaact(ic, :, :))` of a continuous 1 x N x 1 slice stays a 1 x N
row, so `act(:, 1)` was one sample and the "Activation (first 10 s)" plot
was empty with a time axis of 10^-16^ s. Now `reshape` to samples x trials;
the retaken `removecomponents-dialog.png` shows the time course.
**To do:** a test, and retake `removecomponents-dialog.png` (M16).

### M5. TransformOptionsDialog: long descriptions were clipped

*Status: fixed, untested. `src/Dialogs/TransformOptionsDialog.m` lines 67
and 179 (`descriptionLines`).*

The description area had a fixed height, so the DC-Detrend and Rectify
descriptions were cut off. Its height now follows the number of wrapped
lines. The dialogs were retaken with the fix. **To do:** a test.

### M6. ERP image: rejected trials drawn as the lowest colour

*Status: fixed 2026-09-28, with a test (`tests/NaNCellsAreBlankTest.m`).
`src/Views/showImageData.m`.*

NaN rows were drawn in the colour map's lowest colour, so a rejected trial
looked like a strongly negative one. `AlphaData` now makes them blank.
`artefactdetect-result.jpg` was retaken with the fix. EpochView now draws
through `showImageData`, shared with M7.

---

## Open

### M7. TimeFrequency and Coherence views draw NaN as the lowest colour

*Status: fixed 2026-09-28: both draw through `src/Views/showImageData.m`,
which makes NaN cells transparent, as EpochView does (M6). Tested in
`tests/NaNCellsAreBlankTest.m`.*

The same drawing problem as M6: both set `CData` with `imagesc` and no
`AlphaData`, so a NaN cell (a bin whose trials were all rejected, a
frequency outside a method's band) is drawn as a real minimum. After M2 and
M3 this is rarer, but it should get the same treatment as EpochView.

### M8. ReRef: the reconstructed implicit reference is left out of an average reference

*Status: fixed 2026-09-28, as EEGLAB advises: the channel is added as a flat
zero before `pop_reref`, so an Average reference is over all N+1 sites and
the channels sum to zero. Tested in `tests/ReRefTest.m`. The manual's
two-step workaround is replaced by a description of the new behaviour. Nodes
computed before the fix keep the old result until recalculated; left as is,
like M11, and said in the CHANGELOG.*

With **Average** and **Reconstruct implicit reference channel**, `pop_reref`
averages over the recorded channels only, and the reconstructed channel is
then placed relative to that average. The result is not a true average
reference over all N+1 sites: the channels no longer sum to zero, and the
subtracted average is N/(N+1) of what it should be (3% at 32 channels).
EEGLAB's advice is to add the reference channel back first and then average.
The manual documents a workaround (ReRef twice: first any reference with the
channel reconstructed, then Average). **Decision needed:** leave as is, or
reconstruct the channel before averaging when both options are set.

### M9. Fourier: "Other" resolution silently truncates segments

*Status: fixed 2026-09-28 by padding: NFFT is never below the segment's own
power of two, so a coarser spacing gives Max's spectrum and a finer one
zero-pads. Tested in `tests/FourierTest.m`; the manual says so.*

In **Other** mode, `NFFT = 2^nextpow2(srate/ResVal)`. When that is shorter
than the segment, `fft(x, NFFT)` uses only the first NFFT samples, silently:
at 200 Hz, a 1 s epoch and a 2 Hz spacing, only the first 128 of 200
samples are transformed. The manual warns about it. **Decision needed:**
refuse (or warn) when NFFT is shorter than the segment, or pad to at least
the segment length.

### M10. Deconvolve: lsmr "did not converge" diagnosis never confirmed

*Status: fixed 2026-09-28. `Unfold.timeLockedEvents` finds a
modelled event in no bin that keeps a near-constant lag to a bin or another
modelled code; the Deconvolve dialog lists it as a warning in the model and
raises an alert, and the fit names it as the likely cause when the solver
does not converge. Tested in `tests/UnfoldTimeLockedTest.m` and
`tests/DeconvolveDialogTest.m`. Closed without the confirming fit on the
reported data (your decision, 2026-09-28).*

You reported "did not converge for channel 9 after 400 iterations". The
Figure 11 template converges in 78 iterations. The likely cause is modelling
the events in no bin that follow a binned event at a near-constant lag:
`fixation` 12 ms after its saccade (SD 5.9 ms) and `S 99` about 1010 ms
before each stimulus (SD 5.9 ms), which makes the design nearly collinear.
The confirming fit (the same model with those events not modelled) was never
completed. The manual's Deconvolve section already advises modelling only
one of such a pair. **To do:** run the fit; if confirmed, consider a warning
in the dialog when an event in no bin is time-locked to a binned one.

### M11. Cached Average nodes keep the old errors

*Status: won't fix (decided 2026-09-28): kept as is. Recalculating the nodes,
or Clear WorkSpace and a replay, gives the corrected values.*

M1 changes what Average computes, but a node already in a cache keeps what
it was computed with (see the memory note on cached transform results).
Every workspace with rejection upstream of an Average needs those nodes
recalculated (or **Clear WorkSpace** and a replay) before the bands, aSME,
counts and weighted grand averages are right. Worth a line in the CHANGELOG
entry for the fix.

### M14. README still says ManualReject is not recalculable

*Status: fixed 2026-09-27: the README is now the landing page (M17), and the
manual describes ManualReject as recalculable. Checked again 2026-09-28:
`README.MD` no longer mentions ManualReject, and no file in the repository
says it is not recalculable.*

`WorkSpaceTree.RecalculableTransforms` includes ManualReject on purpose,
and its header now says so (M12). The README will be replaced by the landing
page (M17), which removes the line; if the README stays as it is for a while,
correct it.

### M15. Manual chapters 11 to 22 are draft stubs

*Status: fixed 2026-09-27: all twelve chapters written from the README, the
code and the pictures. The manual is 122 pages as PDF.*

Chapters 1 to 10 are written. Chapters 11 to 22 exist only as stubs with a
"Draft" callout, so that the manual renders and every cross-reference
resolves. To write: plots (Scalp, Brain 3D, TimeFrequency, Coherence Map,
CohTopo), grand averages, statistics, cluster statistics, data quality,
frequency tagging, the deconvolution walkthrough (the `deconvolve-*`
images are ready), source estimation, reproducibility, worked examples,
troubleshooting and glossary. The README holds most of the source text.

### M16. Screenshots to retake

*Status: fixed 2026-09-27: all retaken and looked at; captions updated.
Run with `CAPTURE_ONLY` and the runner in the scratchpad (`run_capture.m`,
scratch `C:\AlakazamManual`). Closed 2026-09-28 without a further retake
(your decision): `fourier-result`, `welch-result`, `spectralmeasure-result`
and `ress-result` still show the spectrum views' old step and pan buttons,
from before the channel and bin dropdowns; a capture run (`manualShots`)
makes them again.*

| Image | Why |
|---|---|
| `average-result.jpg` | M1: the bands were drawn too narrow |
| `collapse-result.jpg` | M1 |
| `deconvolve-waveforms.jpg` | M1 (the plain average is overlaid) |
| `timefrequency-result.jpg` | M2: every map was NaN |
| `removecomponents-dialog.png` | M4 |
| `spectralmeasure-result.jpg` | x axis now limited to 0 to 100 Hz (`xlim` added to the capture tool), and the 60 Hz bin (M20) |
| `ress-result.jpg` | the same, and the 60 Hz bin (M20) |
| `sourceestimate-result.jpg` | the shot asked for projection "MNE", which is not a menu label, so it drew the scalp projection; now "dSPM" |

After the retake, look at every image again before relying on its caption.

### M17. Remaining plan items

*Status: fixed 2026-09-27.*

- The README is a landing page: what Alakazam is for (education and
  reusability in research), what it does, getting started, and links to the
  manual (`manual/manual.pdf`, now committed), `DATA.md`, `DEVELOPER.md`,
  `CHANGELOG.md`, `dependencies.md` and the Luck templates. Every bin script
  in it and in the recipes was parsed by `DefineBinsEngine.parseSpec`.
- Help shows the manual: `src/Support/buildHelpPageInto.m` (copies
  `manual/manual.html`, rendering it with Quarto when it is missing or older
  than its sources, then inlines the `data:` resources and adds the link
  bridge), `Alakazam.buildHelpPage`, `onHelp`, and `offerManualInstead`
  (replacing `offerReadmeInstead`: prepare it now, the PDF, or the README).
  `tests/BuildHelpPageTest.m`, seven cases, Quarto replaced by a stand-in.
  The Node builder in `src/help` is gone; `src/help/README.md` now
  describes the Help page and the capture tool.
- The HTML manual draws its maths as MathML (`html-math-method: mathml`),
  so neither MathJax nor its polyfill is fetched from a CDN: the viewer
  needs nothing from outside the page.
- `tests/ManualTest.m`, six cases: every transformation has a
  `{#sec-tr-<folder>}` section; every picture shown exists, is in
  `manual/images` and is made by `manualShots` (except `statistics-report`);
  every picture in the folder is shown; no em dash and no " -- " in the
  manual or the README.
- `AboutDependenciesTest` checks the About box's papers against
  `manual/references.bib` instead of the README.
- `.github/workflows/release.yml` sets up Quarto, renders the HTML and the
  Typst PDF, ships both in the package, checks for them, and attaches the PDF
  to the release.
- `dependencies.md`, `PROJECT_STRUCTURE.md`, `.gitignore`, `DEVELOPER.md`,
  `alakazamDependencies.m` (the Quarto entry) and the links into the old
  README from `Docs/luck.md` and `measure.md` updated.

The plan as it was:

- `README.MD` rewritten as a short landing page linking the manual,
  `DEVELOPER.md` and `CHANGELOG.md`; move or reuse `Screenshots/`.
- In-app Help built from the Quarto manual: `Alakazam.buildHelpPage`,
  `buildHelpPageInto`, `offerReadmeInstead`, `src/help/README.md`,
  `tests/BuildHelpPageTest.m`, with the CSP inlining (the embedded viewer
  refuses `data:` styles and scripts). Quarto's self-contained HTML embeds
  its scripts and styles as `data:` URIs, so they must be rewritten inline;
  and the one resource it does not embed is MathJax's polyfill
  (`cdnjs.cloudflare.com/polyfill/...`, which the render could not fetch on
  2026-09-27). It is only needed by old browsers; drop it or check that the
  viewer's policy does not block the page because of it.
- `ManualTest`: every transformation folder has a `{#sec-tr-<folder>}`
  section; every image in `manual/images` is referenced and every reference
  exists; no em dashes and no " -- " in the docs.
- `.github/workflows/release.yml`: set up Quarto, render HTML and the PDF
  (`--to typst`; since 2026-09-27 the PDF is Typst, so no TinyTeX), ship
  both.
- `dependencies.md` (line 82 still says the help is built from the README
  with node) and `PROJECT_STRUCTURE.md` (`src/help/capture`, `manual/`).
- Lint every edited MATLAB file and run the quick suite.
- `DEVELOPER.md` already describes ManualTest, the Quarto Help build and the
  release step as if they existed; it becomes true when these are done. The
  manual does too: chapter 2 (a release ships the manual; a clone builds it
  on the first press of **Help**) and chapter 21 (the Help button's
  fallback).

### M18. Screenshots that show a non-default or weak example

*Status: open.*

- `ui-settings-*.png` show the settings of the machine that made them
  (jet colour map, a band of 2 SE, trials grouped by bin, reversed sort),
  not the defaults. The manual's caption and table say so; retaking on
  default settings would change the look of every other figure.
- ~~`photodiode-dialog.png` shows the step declining a RIFT recording (the
  diode follows a 60 Hz flicker, not a patch), because no recording with
  photodiode patches is available.~~ Fixed 2026-09-28: you took it by hand on
  a recording with a diode patch (205 onsets found). It is taken off the
  capture list (`manualShots`) so a capture run cannot overwrite it, and
  `ManualTest` names it as made by hand. It shows no delays: none of the
  onsets had a trigger within the 200 ms maximum lag.
- `eyetracking-result.jpg`: the gaze and pupil channels are drawn flat at
  the EEG's scale.

### M19. Rejection breakdown is a uialert, which cannot be photographed

*Status: fixed 2026-09-27, as you asked: `src/Dialogs/RejectionBreakdownDialog.m`,
opened by `src/@Alakazam/onRejectionBreakdown.m`; test
`tests/RejectionBreakdownDialogTest.m` (five cases). The manual shows the
dialog (`rejectionbreakdown-dialog.png`, captured by the new `call` shot
kind on a three-detector stage).*

You spotted it (2026-09-27): printed pages 44 and 45 of the PDF showed the
same picture. Figure 8.3 was meant to show the Rejection breakdown, but that
is drawn with `uialert` over the main window, and `exportapp` leaves an
alert out, so the capture tool saved the bare window, which showed the same
ERP image as Figure 8.2. It reported the shot as done because nothing
checked that the alert was in the picture.

Done: the picture is deleted, the manual now shows a real breakdown as a
table (computed headlessly with three detectors on the same N400 epochs:
93 of 231 epochs rejected; the step detector caught 82, none that the other
two missed), and the capture tool no longer has an `alert` kind, so this
cannot recur silently.

**Decision needed:** make the Rejection breakdown a small dialog with a
table instead of a `uialert`. The alert prints its columns with `sprintf`
padding, which only lines up in a fixed-width font, and `uialert` uses a
proportional one (likely misaligned; not verified on screen). A dialog would
also be capturable, like every other dialog in the manual.

### M20. Captions that did not match their pictures

*Status: fixed (captions); the pictures themselves are in M16.*

Found by looking at every retaken picture after M19:

- `derivechannels-result.jpg`: the caption described the derived channel on
  the continuous recording; the picture is the response-locked LRP average
  at `C34`. The dialog's caption said C3 and C4 the other way round from
  what the dialog defines (`C34 = C4 - C3`). Both captions now describe what
  is shown.
- `spectralmeasure-result.jpg` and `ress-result.jpg`: the view opened on the
  first bin (RIFT 64 Hz) while the RESS caption spoke of the 60 Hz bin; the
  shots now ask for the 60 Hz bin as well as the 0 to 100 Hz range.

### M21. DefineBins ignores text before the first statement

*Status: fixed 2026-09-27, as you decided: `epoch [lo,hi] ms` (or `samples`)
is a statement (`parseEpochStatement.m`), at most once, and wins over the
dialog's fields, with a note in the run's summary when they differ;
Deconvolve ignores it (`tagsOnly`). Anything else before the first
statement is refused with the parser's explanation. Tests in
`tests/DefineBinsTest.m` (anEpochStatementSegmentsTheData,
theScriptsEpochWinsOverAPassedOne, anEpochCanBeGivenInSamples,
tagsOnlyIgnoresTheEpoch, aSecondEpochIsRefused, anEpochInEventsIsRefused,
anEmptyEpochIsRefused, textAfterTheEpochWindowIsRefused,
textBeforeTheFirstStatementIsRefused,
commentsBeforeTheFirstStatementAreFine) and the new
`tests/TemplateBinScriptsTest.m` (every template's bin script parses).
`bin_language.md`, manual chapters 9, 20 and 21 updated; the recipes carry
their epoch in the script.*

*Was: decide. `src/Transformations/DefineBins/@DefineBinsEngine/parseSpecInner.m`
(statements start at `let` or `bin`); `README.MD` P300, LRP and MMN recipes.*

The parser splits the script at `let` and `bin <n> "<label>"` and drops
whatever comes before the first of them without a word. The README's three
recipes start their scripts with `epoch [-200,800] ms`, which is therefore
ignored: a reader who follows them and leaves the dialog's epoch fields blank
gets tagged continuous data, not epochs. The manual's recipes set the epoch in
the fields and say that text before the first statement is ignored.
**Decision needed:** refuse unrecognised text before the first statement
with the parser's usual explanation (or accept an `epoch` line as a real
statement), and correct the README recipes either way.

### M22. Define Grand offers recordings taken out of the study

*Status: fixed 2026-09-27, as you decided: they stay in the lists, marked
"(not in study)" (`findGrandAverageCandidates` now asks
`WorkSpace.includedFor`), and the two cluster dialogs preselect only the
recordings in the study. Test: `tests/ClusterStatsDialogSelectionTest.m`.
Manual chapters 12 and 14 updated.*

*Was: decide. `src/@Alakazam/findGrandAverageCandidates.m`.*

Unticking **In study** under Grouping is documented as taking a recording out
of every report, statistic and grand average. **Per Design Cell** respects it
(it builds from `deriveDesign`), but **Define Grand** lists every recording's
datasets, excluded ones included (`findGrandAverageCandidates` never calls
`WorkSpace.includedFor`). The manual describes the actual behaviour.
**Decision needed:** filter excluded recordings out of Define Grand's list,
or keep them and mark them.

### M23. The cluster dialog says "Home tab"

*Status: fixed 2026-09-27 (the string; no test).*

*Was: open. `src/Dialogs/ClusterStatsDialog.m` (the note under the subject
list: "Home tab, Design group, Grouping...").*

The ribbon's first tab is labelled **Alakazam**, not Home. Seen in
`ga-cluster.png`; other dialogs may carry the old name too.

### M24. Rectification is recorded but not reported

*Status: fixed 2026-09-27, as you asked: `dataQualityMetrics` reads it (from
the average, falling back to the epoched dataset) into a provenance row, and
the report has a "Channels rectified" table: mode, how many channels and
which, whether single trials or the average, and for the squared mode the
unit and total or evoked power. Tests in
`tests/DataQualityProvenanceTest.m`
(rectificationIsReportedWithItsModeAndOrder,
rectificationAfterAveragingIsReadOffTheAverage,
theReportHasARectificationTable). Manual chapters 4, 7 and 15 updated.*

*Was: open. `src/Transformations/Rectify/Rectify.m` writes
`EEG.etc.alz.rectified` and `rectifySquared`, "or the data-quality report
cannot see it"; `src/Reports/dataQualityMetrics.m` does not read either.*

The manual (chapters 1, 4, 7 and 15) now says what is true. Either add a
row to the data-quality report's provenance, or drop the promise from the
Rectify header.

### M25. The spectral view takes the channel from the focus but not the bin

*Status: fixed 2026-09-27, as you asked: `SpectralMeasureView.currentFocus`
and `applyFocus` carry the bin, by label. Tests in `tests/ViewFocusTest.m`
(aSpectralViewAdoptsARememberedBin, aBinTheSpectralViewLacksLeavesItAlone).
Chapter 5 now says every view that shows one bin at a time keeps it.*

*Was: open. `src/Views/SpectralMeasureView.m`, `applyFocus` and
`currentFocus`.*

Moving between nodes keeps the channel but resets the bin to the first,
unlike the waveform and ERP-image views. Found when the capture tool asked for
the 60 Hz bin and got the 64 Hz one; the tool now steps the bin with the arrow
key. The manual's chapter 5 says "the channel, and in most views the bin".

---

## Documentation fixed

### M12. ManualReject header said it was not recalculable

*Status: fixed. `src/Transformations/ManualReject/ManualReject.m`.*

The header now explains why Recalculate is offered (the trials and channels
are stable when the input is recomputed) and why RemoveComponents, by
contrast, is not.

### M13. `measure.md` and `bin_language.md` were out of date

*Status: fixed.*

- `measure.md` said Measure runs on averaged data only (it also measures
  epoched data, per trial), pointed to a "Measurements" tab for the export
  (it is **Export/Report > ERP & Report**), and said a peak has no local
  search (the **Local pts** column provides one).
- `bin_language.md` said combination coefficients must be integers; the
  parser accepts fractions (`0.5 bin 1 + 0.5 bin 2`).
