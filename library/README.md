# Library

Ready-made files to start an analysis from: templates, bin scripts and
measurement windows. They live in the repository, so they are versioned with
the code that reads them and ship in every release.

The dialogs that load these files open here the first time in a session:
**Apply Template** in `templates/`, DefineBins' **Load...** in `binscripts/`
and ERP Measure's **Load...** in `measures/`. After that, each opens wherever
a file of its kind was last loaded from.

## The rules every file here follows

1. **It loads as shipped.** `tests/LibraryTest.m` reads every file the way
   the application does: every template names only transformations that
   exist, every bin script parses, every measurement file reads.
2. **A measurement window says where it comes from.** A window taken from
   a library is an a priori choice only if its source is known; one chosen
   after looking at the data makes the statistics optimistic in a way no
   correction repairs. Every `.alm` file carries a `source` block: the
   reference, its DOI, a one-word `agreement` with it and a sentence saying
   how. `agreement` is `matches`, `partly`, `differs`, `not compared` (a
   source exists, the comparison has not been made) or `no source` (none
   is recorded, so check the window against the literature for your
   paradigm before using it).
3. **Its assumptions are stated.** A template's bins name one dataset's
   event codes, and a measurement file names channels by 10-20 label. The
   tables below say which data each file was written for.

## templates/

| File | What it builds | Written for |
|---|---|---|
| `N400.alztemplate` | N400, one recording: AutoGEDAI, bins, baseline, artefacts, average, N400 at Cz | ERP CORE N400 (Luck ch. 2) |
| `N400-complete.alztemplate` | Chapters 2 and 3 of Luck's book end to end: filter to measurement and scalp map, N400 at CPz | ERP CORE N400 (Luck ch. 3) |
| `AutoEyeICA.alztemplate` | The N400 pipeline with ICA eye correction first: AutoEyeICA, bins, baseline, artefacts, average, measure | ERP CORE N400 |
| `dimigen-rift.alztemplate` | The RIFT study's pipeline, coherence with the photodiode through Spectral Measure | Dimigen et al. (2025) |
| `dimigen-rift-simplified.alztemplate` | The same without resampling and ICA | Dimigen et al. (2025) |
| `FaceSaccadesDeconvolution.alztemplate` | Figure 11 of Ehinger & Dimigen (2019): faces, saccades and button presses, deconvolved and plainly averaged | the authors' OSF recording |
| `ReadingDeconvolution.alztemplate` | Fixation-related potentials in natural reading: EyeTracking, then Deconvolve | EYE-EEG test data 3 |
| `luck/ch02-N400-one-participant.alztemplate` | Luck chapter 2: N400, one participant | ERP CORE N400 |
| `luck/ch03-N400-many-participants.alztemplate` | Luck chapter 3: N400, for Apply to All | ERP CORE N400 |
| `luck/ch06-P3b.alztemplate` | Luck chapter 6: P3b | ERP CORE P3 |
| `luck/ch07-MMN.alztemplate` | Luck chapter 7: MMN | ERP CORE MMN |
| `luck/ch08-N2pc.alztemplate` | Luck chapter 8: N2pc, with a derived PO8 - PO7 channel | ERP CORE N2pc |
| `luck/ch09-MMN-with-ICA.alztemplate` | Luck chapter 9: MMN after ICA correction | ERP CORE MMN |
| `luck/ch10-LRP.alztemplate` | Luck chapter 10: response-locked LRP, with a derived C4 - C3 channel | ERP CORE flankers |

The Luck templates were each replayed end to end on their chapter's data
before they were shipped; see [`luck/README.md`](templates/luck/README.md)
and `Docs/luck.md`. The data is not in the repository: `downloadLuckData.m`
fetches it (see `DATA.md`).

## binscripts/

| File | Bins |
|---|---|
| `bdf_n400.binscript` | N400: primes and targets, related and unrelated, targets followed by a correct response within 200 to 1500 ms (ERP CORE codes) |
| `bdf_n400_plus.binscript` | The same, plus the N400 difference bin (unrelated minus related targets) |
| `bdf_P300_plus.binscript` | P3b: rare and frequent letters, correct, split by what the previous trial was (sequential effects; ERP CORE codes) |

## measures/

Load one into ERP Measure and adjust the channels to your montage; Load adds
to the table, so a battery is built by loading several. The windows are the
ones Alakazam has always shipped; the `agreement` column says how each
compares with its source, and the file's `source` block says in what way.

| File | Windows | Agreement |
|---|---|---|
| `ern.alm` | ERN: mean amplitude 0 to 100 ms at FCz | not compared |
| `erp_components_mean_amplitude.alm` | P2: mean amplitude 150 to 250 ms at Cz; P300: mean amplitude 300 to 600 ms at Pz; N400: mean amplitude 300 to 500 ms at Cz; MMN: mean amplitude 150 to 250 ms at Fz | partly |
| `erp_components_mean_and_area_latency.alm` | P2: mean amplitude 150 to 250 ms at Cz; P2 50%: fractional area latency 150 to 250 ms at Cz; P300: mean amplitude 300 to 600 ms at Pz; P300 50%: fractional area latency 300 to 600 ms at Pz; N400: mean amplitude 300 to 500 ms at Cz; N400 50%: fractional area latency 300 to 500 ms at Cz; MMN: mean amplitude 150 to 250 ms at Fz; MMN 50%: fractional area latency 150 to 250 ms at Fz | partly |
| `erp_components_peak_amplitude_latency.alm` | P2: peak 150 to 250 ms at Cz; P300: peak 300 to 600 ms at Pz; N400: peak 300 to 500 ms at Cz; MMN: peak 150 to 250 ms at Fz | partly |
| `lpp.alm` | LPP: mean amplitude 400 to 800 ms at Pz | no source |
| `lrp.alm` | LRP: mean amplitude -100 to 0 ms at C3, C4 | matches |
| `mmn.alm` | MMN: mean amplitude 150 to 250 ms at Fz | differs |
| `n170.alm` | N170: peak 130 to 200 ms at PO8 | not compared |
| `n2.alm` | N2: mean amplitude 200 to 350 ms at FCz | no source |
| `n400.alm` | N400: mean amplitude 300 to 500 ms at Cz | partly |
| `p1.alm` | P1: peak 80 to 130 ms at Oz | no source |
| `p2.alm` | P2: mean amplitude 150 to 250 ms at Cz | no source |
| `p300.alm` | P300: mean amplitude 300 to 600 ms at Pz | matches |
| `vmmn.alm` | vMMN_early: mean amplitude 100 to 200 ms at {PO7 PO8}; vMMN_late: mean amplitude 200 to 300 ms at {PO7 PO8} | no source |

ERP CORE is Kappenman, Farrens, Zhang, Stewart & Luck (2021), *NeuroImage*
225, 117465, [doi:10.1016/j.neuroimage.2020.117465](https://doi.org/10.1016/j.neuroimage.2020.117465),
whose windows and sites the paper recommends as a priori choices for these
tasks. Luck's *Applied Event-Related Potential Data Analysis* uses its data,
and the Luck templates above carry its windows.

## Adding to the library

- Put the file in the folder for its kind, and add a row to this README;
  `LibraryTest` fails when a file is not listed here.
- Give a measurement file a `source` block. Use `no source` rather than a
  reference that does not say what the file does.
- Say in its row which data it was written for.
- A template or bin script should have been run on that data before it is
  added.
