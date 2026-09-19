# Rapid Invisible Frequency Tagging (RIFT), in Alakazam

A companion to **Dimigen, Badea, Simon & Span (2025), "Rapid Invisible Frequency
Tagging (RIFT) with a consumer monitor: A proof-of-concept"**
([bioRxiv 2025.08.14.670287](https://doi.org/10.1101/2025.08.14.670287), CC-BY
4.0), showing how the paper's EEG analysis maps onto Alakazam. The paper itself,
and its EEGLAB scripts, are the authoritative record; this note only describes how
to carry out the same steps here.

> **Read this before relying on it.** Alakazam is young and lightly tested. The
> paper's analysis was done with **EEGLAB** (`newcrossf`, `pop_eegfiltnew`,
> `runica`, ICLabel), which is mature and validated. Alakazam re-implements the
> same maths, and [one comparison with the paper's own
> statistics](#checked-against-the-paper) agrees closely at electrode Oz. That is
> a comparison with the numbers printed in the preprint, not a run of `newcrossf`
> on identical input, so before trusting any other Alakazam number, run one
> subject through both and compare (in particular, the coherence spectrum at Oz
> against `newcrossf('coher')`).

## The analysis, step by step

The paper's pipeline (deliberately minimal): downsample, high-pass, epoch, ICA-clean,
then quantify the tagging response as **cross-coherence between each EEG channel and
the photodiode** that recorded the flicker.

| Paper step | Alakazam | Notes |
|---|---|---|
| Photodiode recorded on the amplifier's external input | it is just a channel in the dataset | pick it as the *reference* everywhere below |
| Recorded against an online average reference; analysed average-referenced | **ReRef**, mode *Average*, photodiode excluded | not optional: a Cz reference lowers the Oz coherence by about 13%, see [Checked against the paper](#checked-against-the-paper) |
| Downsample 2000 -> 1000 Hz | **Resample** (continuous) | `pop_resample`; not the paper's exact call but the same operation. The template resamples to 960 Hz, a multiple of the display's 480 Hz, rather than 1000 Hz |
| High-pass 1 Hz FIR (`pop_eegfiltnew`, -6 dB, 2 Hz transition) | **Filter** (FIR, `pop_firws`/Kaiser) | a linear-phase high-pass, but **not** the identical `eegfiltnew` design; cutoff/transition will not match to the sample |
| Epoch -2 to +11 s at the fade-in trigger; one bin per condition (60c / 64c / 60periph) | **DefineBins** (epoch statement + one bin per trigger) | |
| ICA + ICLabel, remove **Eye and Muscle** >= 90% | **AutoEyeICA** (Eye, auto) or manual **ICA** (pick any class by hand) | partial, see caveat 1 |
| No baseline correction | omit the Baseline step | |
| **Cross-coherence EEG x photodiode**, STFT 510 ms, pad 4, 52-68 Hz @ ~0.49 Hz, magnitude-squared, trial-averaged | **Coherence Map** (STFT: `WindowMs` 510, `PadRatio` 4, band 52-68) | implements the paper's Eq. 1 exactly (trial-averaged cross-spectrum / autospectra) |
| Mean coherence topography during the steady-state interval (Fig 1C) | **Coherence Topography** (one scalp head-map per bin) | frequency auto-detected from the photodiode per bin (60 vs 64), or fixed; restrict to the steady-state window with its Start/Stop (ms) fields |
| Per-condition scalar coherence at Oz at the target frequency | **Spectral Measure** (coherence to reference at named frequencies, per channel/bin) -> tidy CSV | one value per subject/condition, ready for stats |
| Paired one-tailed t-tests + 5000-permutation | tidy CSV (+ auto-generated R: RM-ANOVA / pairwise-t) | the exact one-tailed / permutation tests are a few lines of your own R, see caveat 3 |
| Dropped-frame / stimulation-fidelity check | -- | out of scope: a photodiode/camera timing analysis, not EEG |

### The steady-state window

The paper averages coherence over the central **500-cycle steady-state period**
(the constant-amplitude middle of each trial, after the raised-cosine fade-in and
before the fade-out). Both **Coherence Topography** and **Spectral Measure** take a
time window: set their **Start / Stop (ms)** to that steady-state interval so the
onset/offset transients are excluded, matching the paper. Leaving the window at
`0 to 0` uses the whole epoch instead.

## Two caveats worth your attention

1. **ICA differs in two ways.** (a) Alakazam's automatic route (`AutoEyeICA`)
   prunes *Eye* components only; the paper also auto-removed *Muscle* >= 90%. Do
   Muscle by hand in the manual **ICA** step (which shows every component's ICLabel
   class probabilities and a topography preview), or that specific two-class,
   thresholded auto-rule would need adding. (b) The paper treated the ocular
   electrodes (IO1/2, LO1/2) as ordinary EEG and had them in the montage, whereas
   Alakazam now **excludes EOG/peripheral channels from ICA** by type. To match the
   paper you would keep those four channels untyped so they count as scalp EEG.

2. **The exact inferential tests are yours to write.** The per-subject/condition
   coherence values export cleanly (a tidy CSV, one row per measure x bin x
   channel), but the paper's one-tailed paired t-test and 5000-permutation test are
   not what the generated R report runs (it picks a paired t-test or a Wilcoxon
   signed-rank test by a normality check, and fits a mixed model for three or more
   conditions). Adapt the generated script, or take the CSV into your own R / JASP.

## Checked against the paper

The preprint reports the cross-coherence at electrode Oz, averaged over the
500-cycle steady state, for ten participants (seven for the peripheral condition),
and tests the target frequency against the same frequency in the other condition's
trials. The same quantities from this template applied to the raw recordings (a
960 Hz resample, 1 Hz high-pass, `AutoEyeICA`, then an Alakazam `CoherenceMap` with
STFT 510 ms, padding 4, 52 to 68 Hz) are, mean (SD) across participants, next to the
same chain with the template's earlier Cz reference:

| Oz coherence | Paper | Alakazam template, average reference | Same chain, Cz reference |
|---|---|---|---|
| 60 Hz, in 60 Hz trials | 0.280 (0.202) | 0.274 (0.199) | 0.242 (0.202) |
| 64 Hz, in 64 Hz trials | 0.241 (0.171) | 0.230 (0.165) | 0.216 (0.167) |
| 60 Hz, in 64 Hz trials (control) | 0.030 (0.004) | 0.031 (0.006) | 0.029 (0.004) |
| 64 Hz, in 60 Hz trials (control) | 0.031 (0.005) | 0.030 (0.005) | 0.030 (0.005) |
| 60 Hz target against control | t(9) = 3.906, d = 1.235 | t(9) = 3.897, d = 1.232 | t(9) = 3.34, d = 1.06 |
| 64 Hz target against control | t(9) = 3.833, d = 1.212 | t(9) = 3.810, d = 1.205 | t(9) = 3.47, d = 1.10 |
| Peripheral 60 Hz (n = 7) | 0.036 against 0.028, t(6) = 2.43 | 0.033 against 0.029, t(6) = 1.19 | 0.043 against 0.028, t(6) = 3.7 |

What this supports:

- **`CoherenceMap` reproduces the two central results.** With the paper's average
  reference the t values agree to within 0.03 and the d values to within 0.01, and
  the off-frequency floor (about 1/33 for 33 trials, as expected from the bias of
  the estimator) to three decimals.
- **The reference is the one preprocessing choice that visibly matters.** Under a
  Cz reference the Oz coherence at the tag is about 13% lower, and the weak
  peripheral condition looks significant when the paper's is barely so. The
  template therefore re-references to the average.
- **Removing the eye components made no visible difference to the central
  conditions.** The template's own chain (a 1 Hz high-pass and `AutoEyeICA`) and
  epochs with no component removed (their filter was not recorded) gave the same Oz
  mean to within 0.002 (0.242 against 0.244, both Cz-referenced).

What it does not show:

- **It compares with the numbers printed in the preprint, not with a run of
  `newcrossf` on identical input.** The preprint's own preprocessing files were not
  used, and the template's chain differs from the paper's in the ICA (eye components
  only, where the paper also removed muscle components), the filter design and the
  960 Hz resampling rate.
- **The peripheral condition does not replicate under either reference.** It is the
  weakest effect in the paper and the most sensitive to small differences.
- **Only Oz was checked**, and only the tagged frequencies.

To repeat it: export the coherence for Oz alone with
`exportCoherenceCSVs(entries, stem, struct('Channels', {{'Oz'}}))`, average each
participant's map over the steady-state frames at the target frequency and at the
other condition's frequency, and compare the two with a paired test.

## In short

The **core** of the paper -- minimal preprocessing, epoching, ICA cleaning, and the
EEG x photodiode magnitude-squared cross-coherence, read out both as per-channel
time x frequency maps (**Coherence Map**) and as per-bin scalp topographies at the
auto-detected tagging frequency (**Coherence Topography**) -- is directly available
in Alakazam, which was in part designed around exactly this analysis. What you
still handle outside or adapt: the exact `eegfiltnew` filter, the Muscle-removal and
EOG-in-ICA montage choices, and the specific statistics -- plus a like-for-like
check against the original EEGLAB scripts before reporting anything (the comparison
above used only the numbers printed in the preprint).
