# Rapid Invisible Frequency Tagging (RIFT), in Alakazam

A companion to **Dimigen, Badea, Simon & Span (2025), "Rapid Invisible Frequency
Tagging (RIFT) with a consumer monitor: A proof-of-concept"**
([bioRxiv 2025.08.14.670287](https://doi.org/10.1101/2025.08.14.670287), CC-BY
4.0), showing how the paper's EEG analysis maps onto Alakazam. The paper itself,
and its EEGLAB scripts, are the authoritative record; this note only describes how
to carry out the same steps here.

> **Read this before relying on it.** Alakazam is young and lightly tested. The
> paper's analysis was done with **EEGLAB** (`newcrossf`, `pop_eegfiltnew`,
> `runica`, ICLabel), which is mature and validated; Alakazam re-implements the
> same maths but has **not** been checked against those results. Before trusting
> any Alakazam number, run one subject through both and compare (in particular,
> compare the coherence spectrum at Oz against `newcrossf('coher')`). The
> `CoherenceMap` / `CoherenceTopography` / `SpectralMeasure` transformations were
> written with this paper as their reference and cite it, but "written for it" is
> not "validated against it".

## The analysis, step by step

The paper's pipeline (deliberately minimal): downsample, high-pass, epoch, ICA-clean,
then quantify the tagging response as **cross-coherence between each EEG channel and
the photodiode** that recorded the flicker.

| Paper step | Alakazam | Notes |
|---|---|---|
| Photodiode recorded on the amplifier's external input | it is just a channel in the dataset | pick it as the *reference* everywhere below |
| Downsample 2000 -> 1000 Hz | **Resample** (continuous) | `pop_resample`; not the paper's exact call but the same operation |
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

## Three caveats worth your attention

1. **ICA differs in two ways.** (a) Alakazam's automatic route (`AutoEyeICA`)
   prunes *Eye* components only; the paper also auto-removed *Muscle* >= 90%. Do
   Muscle by hand in the manual **ICA** step (which shows every component's ICLabel
   class probabilities and a topography preview), or that specific two-class,
   thresholded auto-rule would need adding. (b) The paper treated the ocular
   electrodes (IO1/2, LO1/2) as ordinary EEG and had them in the montage, whereas
   Alakazam now **excludes EOG/peripheral channels from ICA** by type. To match the
   paper you would keep those four channels untyped so they count as scalp EEG.

2. **"Built for it" is not "validated against it."** `CoherenceMap` and
   `CoherenceTopography` implement Eq. 1 and an STFT that mirrors `newcrossf`, but
   have not been checked numerically against the EEGLAB output. Validate on one
   subject first; `newcrossf`'s tapering, normalisation and frame-centre
   bookkeeping are the likely places to diverge.

3. **The exact inferential tests are yours to write.** The per-subject/condition
   coherence values export cleanly (a tidy CSV, one row per measure x bin x
   channel), but the paper's one-tailed paired t-test and 5000-permutation test are
   not what the generated R script produces (it does RM-ANOVA + pairwise t). Adapt
   the generated script, or take the CSV into your own R / JASP.

## In short

The **core** of the paper -- minimal preprocessing, epoching, ICA cleaning, and the
EEG x photodiode magnitude-squared cross-coherence, read out both as per-channel
time x frequency maps (**Coherence Map**) and as per-bin scalp topographies at the
auto-detected tagging frequency (**Coherence Topography**) -- is directly available
in Alakazam, which was in part designed around exactly this analysis. What you
still handle outside or adapt: the exact `eegfiltnew` filter, the Muscle-removal and
EOG-in-ICA montage choices, and the specific statistics -- plus a validation pass
against the original EEGLAB scripts before reporting anything.
