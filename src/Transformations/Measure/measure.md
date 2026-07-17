# Defining measures

`Measure` turns a window on an averaged waveform into a number. You give it a
short table of **measurement windows**: each row names a time window and says
how to reduce the samples inside it to a single value (or, for peaks, two
values). Every window is then evaluated for every bin and every selected
channel, and the results are stored on the dataset (`EEG.measurements`) ready
to be written out as one tidy CSV for statistics (see [What you get
out](#what-you-get-out)).

There are five measures: **mean amplitude**, **peak** (amplitude and latency),
**area** (signed / rectified / positive / negative, over the whole window or a
band centred on the peak), **fractional peak latency**, and **fractional area
latency**. The dialog greys the parameter cells a row's chosen measure does not
use, so each row shows only what applies to it.

Any window can also carry an optional **baseline**: a pre-window interval whose
mean is subtracted from the waveform before the measure is taken.

`Measure` runs on an **averaged** dataset only: a subject `Average` or a
`Grand Average`. Run `Average` (or Grand Average, for a group waveform) first;
on anything else `Measure` reports that it needs an averaged ERP and stops.

This document builds the window table up one column at a time, with examples,
then covers what comes out and how to reuse a set of windows. For a one-screen
summary, jump to the [reference](#reference) at the end.

---

## 1. The window table

Each row of the dialog's table is one window:

| Label | Start | Stop | Measure | Polarity | Width | Local pts | Fraction | Area mode | Baseline | Ref | Channels |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P3 | 300 | 600 | Mean Amplitude | Positive | 100 | 0 | 0.5 | Signed | | | Pz |

Use **Add Window** / **Remove Selected** to grow and shrink the table. The
columns are:

- **Label**: the window's name, carried through to the output so you can tell
  rows apart (e.g. `P3`, `N170`, `LPP late`). Required, and best kept unique.
- **Start (ms)**, **Stop (ms)**: the window bounds, in the same millisecond
  axis the waveform is plotted on (`EEG.times`). Start must not be after Stop.
- **Measure**: one of the five (see [§3](#3-mean-amplitude),
  [§4](#4-peak-amplitude-and-latency), [§5](#5-area), and
  [More measures](#more-measures) for the fractional latencies).
- **Polarity**: `Positive` or `Negative`. Used by the peak-locating measures.
- **Width (ms)**: for `Area`, the scope switch: `0` (or blank) measures the
  whole window, a positive value measures a band that wide centred on the peak
  (see [§5](#5-area)).
- **Local pts**: `0` = absolute peak; `N` = local peak (more extreme than `N`
  neighbours each side). Used by the peak-locating measures (see
  [More measures](#more-measures)).
- **Fraction**: a number in (0,1) (e.g. `0.5`) for the two fractional-latency
  measures.
- **Area mode**: `Signed` / `Rectified` / `Positive` / `Negative`, how `Area`
  treats the sign of the waveform (see [§5](#5-area)).
- **Baseline (ms)**: optional; a `start stop` interval (e.g. `-100 0`) whose
  mean is subtracted before measuring. Blank = none. Applies to every measure
  (see [§8](#8-baseline-correction)).
- **Reference channel**: optional; used by `Peak` and band `Area` (see
  [§6](#6-reference-channel-locking-the-latency)).
- **Channels**: which channels to measure (see [§7](#7-channels)).

Irrelevant cells are greyed for the measure you pick, so you never have to
wonder which columns a row uses.

## 2. The window and the time axis

The Start/Stop times are matched to the **nearest available sample** of the
average, not interpolated. If your window edge falls between two samples it
snaps to the closer one; if it lands a little outside the epoch it snaps to the
nearest edge sample rather than failing. So for a 500 Hz average (one sample
every 2 ms) a window written as `300`–`600 ms` is measured over the samples
nearest 300 ms and 600 ms inclusive.

This means you can define your windows in round numbers without worrying about
whether `300` is exactly on a sample boundary. It always resolves to a real,
existing sample.

## 3. Mean Amplitude

```
Label  Start  Stop  Measure          Polarity  Width  Reference channel  Channels
P3     300    600   Mean Amplitude   -          -      -                  Pz
```

The value is the **average of the waveform over the window**, one number per
bin and channel. Polarity, width and reference channel play no part. Missing
samples (`NaN`) inside the window are ignored, so a partially-blanked bin still
yields a mean from whatever remains.

Mean amplitude is the workhorse ERP measure: it is unbiased by noise and does
not depend on how many samples the window contains, which is why it is the
default recommendation for most component analyses (see [Choosing a
measure](#choosing-a-measure)).

More examples:

```
Label     Start  Stop  Measure          Channels
N400      300    500   Mean Amplitude   Cz, Pz, CPz
LPP       400    800   Mean Amplitude
P2        150    250   Mean Amplitude   FCz
```

The second row leaves **Channels blank**, so it measures every channel in the
dataset (see [§7](#7-channels)).

## 4. Peak amplitude and latency

```
Label   Start  Stop  Measure  Polarity  Width  Reference channel  Channels
N170    130    200   Peak     Negative  -      -                  P7, P8
```

`Peak` finds the single most extreme sample inside the window and reports
**two** numbers: its amplitude and its **latency** (the time, in ms, at which
it occurred). **Polarity** picks which extreme:

- `Positive`: the maximum (most positive) sample. Use for P1, P2, P3, LPP, …
- `Negative`: the minimum (most negative) sample. Use for N1, N170, N2, …

So the `N170` row above measures, on P7 and P8, the most negative point
between 130 and 200 ms and the time it fell.

```
Label   Start  Stop  Measure  Polarity  Channels
P1      80     130   Peak     Positive  O1, O2, Oz
P3 peak 250    500   Peak     Positive  Pz
N2      200    350   Peak     Negative  FCz, Cz
```

The peak is the **single most extreme sample** in the window: there is no
local-maximum or centroid search. Keep the window tight enough that its
extreme really is the component you mean, not the shoulder of an adjacent one.

## 5. Area

`Area` integrates the waveform to a **µV·ms** value (a trapezoidal integral
against the real millisecond axis). Two columns shape it: **Area mode** (how the
sign of the waveform is treated) and **Width** (whether it covers the whole
window or a band on the peak).

**Area mode** — four ways to handle sign:

- `Signed`: the plain integral. Positive and negative excursions cancel; a
  positive-going component gives a positive area, a negative-going one a
  negative area. (ERPLAB's "numerical integration", Analyzer's signed *Area*.)
- `Rectified`: the integral of `|waveform|`. Every excursion adds, so it never
  cancels, a robust "total activity" measure.
- `Positive`: the integral of the positive part only (`max(waveform, 0)`).
- `Negative`: the integral of the negative part only (`min(waveform, 0)`).

**Width** — the scope of the integration:

*Whole window* (`Width` = 0 or blank) integrates the entire Start–Stop range:

```
Label   Start  Stop  Measure  Area mode  Channels
LPP     500    800   Area     Signed     Pz, POz
```

*Peak-locked band* (`Width` > 0) locates the peak exactly as `Peak` does (the
extreme sample in the Start–Stop **search range**, chosen by Polarity), then
integrates a band **`Width` ms wide, centred on that peak**
(`peak_latency − Width/2` to `peak_latency + Width/2`), and also reports the
peak's own **amplitude and latency** (so a band Area gives you the integral and
the peak value and time in one measure):

```
Label   Start  Stop  Measure  Polarity  Width  Area mode  Reference channel  Channels
P3 area 250    600   Area     Positive  150    Signed     Pz                 Pz, POz
```

For that row, on a P3 peaking at, say, 372 ms, the area is integrated over
322–422 ms (150 ms centred on 372), on both `Pz` and `POz`. The Start–Stop range
is only where the **peak is searched**; the band that is actually integrated is
the `Width`-ms window centred on the peak:

```
peak at 360 ms, Width 100  ->  integrate 310–410 ms
peak at 150 ms, Width  60  ->  integrate 120–180 ms
```

Notes:

- Whole-window and band areas both snap to the nearest real sample; a band (or
  window) running off the epoch edge clamps to the nearest edge sample.
- `NaN` samples are dropped and the remaining real samples integrated at their
  own times, so a few artefact-blanked points shrink the support rather than
  voiding the area. Fewer than two real samples yields no area (`NaN`).
- A **band** Area is *placed by the peak*, so it inherits some of peak latency's
  noise. A **reference channel** ([§6](#6-reference-channel-locking-the-latency))
  fixes the band across channels and is often what you want there. A
  whole-window Area has no peak and ignores polarity/reference channel.

## More measures

Two more measures share the same window/channel columns and add one parameter
each.

**Fractional Peak Latency** — the latency at which the waveform rises through
`Fraction` × its peak amplitude on the onset side (searching back from the
peak), interpolated between samples. More robust than raw peak latency.

```
Label      Start  Stop  Measure                  Polarity  Fraction  Channels
P3 onset   250    600   Fractional Peak Latency  Positive  0.5       Pz
```

**Fractional Area Latency** — the latency that divides the window's cumulative
signed area at `Fraction` (e.g. `0.5` = the **50% area latency**, the robust
onset/timing measure recommended over peak latency for many analyses),
interpolated between samples.

```
Label      Start  Stop  Measure                  Fraction  Channels
P3 50%     250    600   Fractional Area Latency  0.5       Pz
```

**Local pts** applies to every peak-locating measure (`Peak`, band `Area`,
`Fractional Peak Latency`): `0` finds the absolute extreme in the window; `N ≥
1` finds the most extreme *local* peak — a sample more extreme than its `N`
neighbours on each side — and falls back to the absolute extreme only if the
window has no local peak. Use it (e.g. `2`–`5`) to stop a rising edge or a lone
noise spike from being picked as "the peak".

Notes for the fractional latencies:

- **Fraction** must be strictly between 0 and 1; the dialog will not accept the
  row otherwise.
- Both are per-channel (no reference-channel locking): each channel's latency
  is measured against its own waveform.
- A Fractional Peak Latency returns `NaN` if the waveform never drops below the
  threshold within the window before the peak (open the window's Start
  earlier). A Fractional Area Latency returns `NaN` if the window's positive
  and negative areas cancel to ~zero (use a tighter, single-signed window).

## 6. Reference channel: locking the latency

Peak latency is noisy, and a component often peaks at slightly different times
on different channels even when it is really one component. Setting a
**Reference channel** (for `Peak` or a band `Area`) locates the peak **once**, on
that channel, and then reads every selected channel at that shared point: for
`Peak`, each channel's amplitude at the reference latency; for a band `Area`,
each channel's area over the one band centred on the reference peak. Every
channel then shares one latency instead of each drifting to its own local peak.

```
Label   Start  Stop  Measure  Polarity  Width  Reference channel  Channels
P3      250    500   Peak     Positive  -      Pz                 Fz, Cz, Pz, POz
```

Here the P3 peak latency is found on `Pz`; the reported amplitude for `Fz`,
`Cz`, `Pz` and `POz` is each channel's own value at that Pz-defined latency,
and all four rows carry the same latency. Leave the field blank to search each
channel independently instead.

Notes:

- The reference channel need **not** be one of the measured Channels; it is
  only the place the peak is found. (If you also want its own value, list it in
  Channels too, as above.)
- Reference channel is ignored for `Mean Amplitude` and whole-window `Area`
  windows.
- The peak is found separately **per bin**, so two conditions may lock to
  different time points. Each bin's read-out is taken at that bin's own
  reference-channel latency.

## 7. Channels

The **Channels** cell lists the channels to measure, separated by commas and/or
spaces. Matching is case-insensitive.

```
Pz                 % one channel
Pz, Cz, POz        % a few, each measured separately
P7 P8              % spaces work too
cz,pz              % case does not matter
```

**Leave it blank to measure every channel** in the dataset. There is no `all`
keyword; blank *is* "all". A label that is not in the dataset is an error,
reported with the offending name, so a typo is caught at once rather than
silently dropped.

### Pooling channels into an ROI

Wrap channels in **braces** to pool them into one virtual channel — the
NaN-tolerant mean of the members — instead of measuring each separately. This
is the standard "measure over a region of interest" (BrainVision's *Pooling*,
ERPLAB's channel operations).

```
{Pz POz CPz}          % one ROI = mean(Pz, POz, CPz)
{Pz POz CPz}, Fz      % the parietal ROI AND Fz -> two outputs
{P7 PO7}, {P8 PO8}    % a left ROI and a right ROI
```

A pooled channel appears in the output (and the CSV `channel` column) as
`{Pz+POz+CPz}`. Members inside the braces are comma/space separated; every
member must exist in the dataset. The measure is computed on the pooled
waveform exactly as it would be on a single electrode, so pooling works with
every measure (mean, peak, area, fractional latency, …) and with a reference
channel.

## 8. Baseline correction

The optional **Baseline (ms)** cell names a `start stop` interval whose mean is
subtracted from the waveform **before** the measure is taken, per channel and
per bin. Leave it blank for none.

```
Label   Start  Stop  Measure         Baseline  Channels
P3      300    600   Mean Amplitude  -100 0    Pz
```

Here each channel's mean over −100–0 ms is subtracted, then the P3 mean is read
over 300–600 ms. Write the interval as two numbers separated by a space or
comma (`-100 0`, `-200, -50`); the order is normalised, so `0 -100` also works.

This is a **local** re-baseline for the measurement only: it re-references each
window to a pre-interval of your choice without altering the stored waveform or
touching the earlier `Baseline` transform (ERPLAB's per-measurement baseline).
It applies to **every** measure, so a peak, an area or a fractional latency can
each be read against its own baseline. A baseline whose interval falls entirely
outside the epoch (no samples) is treated as no baseline.

## Choosing a measure

A short methodological note, since this is where measures are easy to get
wrong (see Luck, *Applied Event-Related Potential Data Analysis*, in the
project [references](../../../README.MD#references)):

- **Prefer mean amplitude over peak amplitude** when you can. Peak amplitude is
  biased by noise (noisier waveforms have larger peaks) and by window length
  (a wider window can only ever find a larger peak), so peak amplitudes are not
  comparable across conditions or subjects unless those are held constant. Mean
  amplitude over a fixed window has neither bias.
- **Peak latency** is the reason to use `Peak` at all. When you report it,
  consider a **reference channel** ([§6](#6-reference-channel-locking-the-latency))
  so a condition or group difference reflects a real timing shift rather than
  which channel happened to win locally, and consider **Local pts** so the peak
  is a genuine local maximum, not a window-edge sample.
- **Prefer fractional area latency over peak latency** for timing. The 50% area
  latency (`Fractional Area Latency`, Fraction 0.5) is far less biased by noise
  than the single-sample peak latency, and is the standard robust onset/timing
  measure. `Fractional Peak Latency` is a middle ground (interpolated, but still
  anchored to the peak).
- **Band Area** is a peak-locked integrated amplitude: over a fixed `Width` it
  is just the mean amplitude of the band times its width, so it shares mean
  amplitude's robustness to noise, but with the band **following the component**
  rather than sitting at fixed times. That is useful when a component's timing
  moves across conditions or subjects, but note that placing the band by the
  peak reintroduces a little of peak latency's own noise; a reference channel
  is the usual remedy. For a total-activity measure that never cancels, use a
  `Rectified` whole-window Area instead.
- Keep the **same windows across conditions and subjects**. Define them once
  and reuse them, which is exactly what [Save.../Load...](#saveload) and
  [running across a study](#running-a-measure-across-a-study) are for.

## Bins

Every bin in the average is measured, uniformly: you do not select bins here,
the output simply has one value per bin per channel per window. This includes
**difference / contrast bins** defined in `DefineBins` (`bin 3 = bin 1 - bin
2`). By the time `Average` has run they hold a real difference waveform, so
`Measure` treats them like any other bin, and the mean, peak or area of a
difference wave is exactly the difference measure you would expect.

If a bin is entirely missing (all `NaN`, e.g. a contrast bin that could not be
resolved), its values come out as `NaN` for that bin rather than as a false
reading at the window's first sample.

## Seeing the measures on the plot

A `Measure` result opens as an ordinary averaged-ERP plot, with the measures
drawn on top of the waveform, in each bin's own colour:

- **Peak** — a dot at the peak, labelled with the window name.
- **Area** — the integrated region shaded under the curve (down to the 0 µV
  baseline): a peak-locked band or the whole window, clipped to the Area mode's
  polarity (`Positive` shades only the part above 0, `Negative` only below),
  labelled at the peak or window centre.
- **Mean Amplitude** — a level line at the mean, spanning the measurement
  window, labelled at its start.
- **Fractional Peak / Area Latency** — a dashed drop line and a dot at the
  located latency on the curve, labelled with the window name.

The annotations are drawn for the **channel currently shown**, so stepping
through electrodes (up/down arrows or the mouse wheel) moves them with the
data; a window measured only on `Pz` appears only while `Pz` is displayed.
Un-ticking a bin (the checkboxes to the right of the plot) hides its lines and
its annotations together. The annotations never appear in the legend, which
lists the bin waveforms only.

## What you get out

`Measure` adds `EEG.measurements` to the result and, like every other
transformation, lands as a new node in the tree. Nothing about the waveform
itself is changed; it is a read-only quantification step.

To get the numbers into a statistics package, use **Export Measurements...**
on the ribbon's **Measurements** tab. It walks the whole workspace, every
subject branch and every Grand Average that carries a `Measure` result, and
writes one long-format, R-friendly CSV: one row per
dataset × window × bin × channel × measure type.

```
dataset,dataset_type,bin,channel,window,measure_type,window_start_ms,window_stop_ms,value
s01,subject,Rare,Pz,P3 mean,mean_amplitude,300,600,4.21
s01,subject,Rare,Pz,P3 peak,peak_amplitude,250,500,6.83
s01,subject,Rare,Pz,P3 peak,peak_latency,250,500,372
s01,subject,Rare,Pz,P3 area,area_signed,250,600,540.5
s01,subject,Rare,Pz,P3 area,peak_amplitude,250,600,6.12
s01,subject,Rare,Pz,P3 area,peak_latency,250,600,372
s01,subject,Rare,Pz,P3 int,area_signed,300,600,1263
s01,subject,Rare,Pz,P3 50%,fractional_area_latency,250,600,388
s01,subject,Frequent,Pz,P3 mean,mean_amplitude,300,600,1.05
GA all,grand_average,Rare,Pz,P3 mean,mean_amplitude,300,600,3.88
...
```

Points worth knowing:

- Each window contributes one measure-type row per value it produces, so the
  single `value` column stays uniformly numeric:
  - `Mean Amplitude` → `mean_amplitude`.
  - `Peak` → `peak_amplitude` and `peak_latency`.
  - `Area` → `area_<mode>` (µV·ms), where `<mode>` is `signed` / `rectified` /
    `positive` / `negative`; a **band** Area (Width > 0) adds `peak_amplitude`
    and `peak_latency`.
  - `Fractional Peak Latency` → `fractional_peak_latency` (ms).
  - `Fractional Area Latency` → `fractional_area_latency` (ms).
- `window_start_ms` / `window_stop_ms` are the window's own **search range**
  for every measure. For a band `Area` the integrated span is `Width` ms centred
  on `peak_latency`; a fractional latency's fraction is the window's own
  `Fraction`. Both are recoverable from the window definition (they are not
  extra CSV columns), so give windows distinct labels (e.g. `P3 50%`).
- `dataset_type` is `subject` or `grand_average`. For a subject, `dataset` is
  the **originating raw recording's** name (resolved from the branch's root),
  not the `Measure` node's own generic name; for a grand average it is the
  grand average's own name.
- A missing value (an all-`NaN` bin, as above) is written as `NA`, R's own
  missing-value token.

An example R read is then just:

```r
m <- read.csv("measurements.csv")
library(dplyr)
m |>
  filter(window == "P3 mean", channel == "Pz") |>
  group_by(bin) |>
  summarise(mean_uV = mean(value))
```

## Save.../Load...

The dialog's **Save...** button writes the current table to a portable
`.alm` file (small JSON); **Load...** reads one back in. This is
independent of any one dataset: use it to keep a lab-standard set of windows,
reuse the same battery in a new workspace, or share it with a colleague. Save
stores the table as-is (it does not require the rows to be valid first), so you
can also use it to park a work-in-progress.

Ready-made starting points live in
[`presets/`](presets) (Load one, then adjust the channels/windows to your
montage and design). Multi-component **batteries**:

- `erp_components_mean_amplitude` — P2, P300, N400, MMN as mean amplitude at
  their canonical sites (Cz, Pz, Cz, Fz).
- `erp_components_peak_amplitude_latency` — the same four as Peak (amplitude +
  latency), with a local-peak neighbourhood.
- `erp_components_mean_and_area_latency` — the same four with mean amplitude
  **and** 50% area latency (the robust modern amplitude + timing pair).

Single-component files (a growing library; Load the one you need, or combine
several by Load-ing one and copying rows in). Each holds that component's
sensible default measure at its canonical site:

- `p1` — Oz, 80–130 ms, Peak (positive, local peak).
- `n170` — PO8, 130–200 ms, Peak (negative, local peak).
- `p2` — Cz, 150–250 ms, mean amplitude (positive).
- `mmn` — Fz, 150–250 ms, mean amplitude (negative).
- `n2` — FCz, 200–350 ms, mean amplitude (negative).
- `p300` — Pz, 300–600 ms, mean amplitude (positive).
- `n400` — Cz, 300–500 ms, mean amplitude (negative).
- `lpp` — Pz, 400–800 ms, mean amplitude (positive).

## Running a Measure across a study

Because `Measure` is an ordinary transformation, its window set travels with
the usual replay mechanisms. You define the windows once and apply them to
everyone:

- **Drag** a measured branch onto another dataset to re-measure it with the
  same windows.
- **Apply to All Raw Files...** (a branch's right-click menu) replays a whole
  pipeline (`filter → epoch → baseline → artefact-reject → average → measure`)
  onto every other raw recording in the workspace at once.
- **Save Template... / Apply Template...** store that pipeline (windows and
  all) as a file to run in another session or workspace.
- **Recalculate** (right-click a `Measure` node) reopens the window table
  pre-filled with that node's own windows, so you can revise them and have the
  node, and anything downstream, recomputed in place.

## Reference

### Columns

The dialog greys the cells a row's chosen Measure does not use, so each row
shows only the parameters that apply to it.

| Column | Values | Used by |
|---|---|---|
| Label | any text (unique is best) | all |
| Start (ms), Stop (ms) | numbers; Start ≤ Stop | all |
| Measure | `Mean Amplitude`, `Peak`, `Area`, `Fractional Peak Latency`, `Fractional Area Latency` | all |
| Polarity | `Positive` (max), `Negative` (min) | `Peak`, band `Area`, `Fractional Peak Latency` |
| Width (ms) | `0`/blank = whole window; `N` > 0 = peak band `N` ms wide | `Area` |
| Local pts | whole number ≥ 0 (0 = absolute peak; N = local peak) | `Peak`, band `Area`, `Fractional Peak Latency` |
| Fraction | number in (0,1), e.g. 0.5 | `Fractional Peak Latency`, `Fractional Area Latency` |
| Area mode | `Signed`, `Rectified`, `Positive`, `Negative` | `Area` |
| Baseline (ms) | `start stop` interval (e.g. `-100 0`), or blank | all |
| Reference channel | a channel label, or blank | `Peak`, band `Area` |
| Channels | labels (comma/space separated); `{..}` pools an ROI; blank = all | all |

### Measures

| Measure | Reports | uV·ms / ms | Uses |
|---|---|---|---|
| Mean Amplitude | mean over the window | µV | window, channels |
| Peak | extreme sample amplitude + its time | µV, ms | polarity, local pts, ref |
| Area (whole window) | area over the window in the chosen mode | µV·ms | area mode, window, channels |
| Area (peak band) | area of a `Width` band on the peak + peak value + time | µV·ms, µV, ms | polarity, width, area mode, local pts, ref |
| Fractional Peak Latency | time rising through `Fraction`×peak (onset side) | ms | polarity, local pts, fraction |
| Fractional Area Latency | time dividing cumulative area at `Fraction` | ms | fraction |

Every measure also honours the optional **Baseline (ms)** interval.

**Local pts** (`Peak` / band `Area` / `Fractional Peak Latency`): `0` = the
absolute extreme in the window; `N ≥ 1` = the most extreme *local* peak (more
extreme than its `N` neighbours each side), falling back to the absolute
extreme if the window has none. Guards against picking a window-edge sample or
a lone noise spike.

### Output rows (Export Measurements...)

| Window's Measure | `measure_type` value(s) |
|---|---|
| Mean Amplitude | `mean_amplitude` |
| Peak | `peak_amplitude` **and** `peak_latency` |
| Area (whole window) | `area_signed` / `area_rectified` / `area_positive` / `area_negative` |
| Area (peak band) | `area_<mode>`, `peak_amplitude` **and** `peak_latency` |
| Fractional Peak Latency | `fractional_peak_latency` |
| Fractional Area Latency | `fractional_area_latency` |

CSV columns:
`dataset, dataset_type, bin, channel, window, measure_type, window_start_ms,
window_stop_ms, value` (missing `value` → `NA`).

### Behaviour notes

- Windows and integration bands snap to the nearest real sample; an edge just
  outside the epoch clamps to the nearest edge sample.
- Every bin is measured, including `DefineBins` difference/contrast bins.
- An all-`NaN` bin yields `NaN` (→ `NA` in the CSV), not a false first-sample
  reading.
- Peaks are single samples with an optional local-peak neighbourhood; areas
  and fractional latencies are trapezoidal, NaN-tolerant, and interpolate the
  crossing point between samples for the fractional latencies.

---

## Full worked example

A visual-oddball study: rare vs. frequent stimuli, and their difference,
scored for the classic components. Assume `DefineBins`/`Average` have produced
bins `Rare`, `Frequent`, and `Rare-Frequent` (a difference bin).

| Label | Start | Stop | Measure | Polarity | Width | Area mode | Reference channel | Channels |
|---|---|---|---|---|---|---|---|---|
| P1 | 80 | 130 | Peak | Positive | | | | O1, O2, Oz |
| N1 | 130 | 200 | Peak | Negative | | | Oz | O1, O2, Oz |
| P2 | 150 | 250 | Mean Amplitude | | | | | FCz, Cz |
| N2 | 200 | 350 | Mean Amplitude | | | | | FCz, Cz |
| P3 | 300 | 600 | Mean Amplitude | | | | | Pz, POz, CPz |
| P3 area | 250 | 600 | Area | Positive | 150 | Signed | Pz | Pz, POz, CPz |
| P3 latency | 250 | 550 | Peak | Positive | | | Pz | Pz |
| LPP | 500 | 800 | Mean Amplitude | | | | | Pz, POz |

Reading this table:

- **P1**: posterior positive peak (amplitude + latency), each occipital
  channel searched independently.
- **N1**: posterior negative peak; latency **locked to Oz**, so O1/O2/Oz all
  report their amplitude at Oz's negative peak, sharing one latency.
- **P2, N2, P3, LPP**: mean amplitudes over fixed windows, the robust default;
  polarity, width and reference channel left unset because they don't apply.
- **P3 area**: the P3 as a peak-locked integrated amplitude — find the positive
  peak on `Pz`, integrate a 150 ms `Signed` band centred on it, and read the
  same band on Pz/POz/CPz (reference channel keeps the band identical across the
  three).
- **P3 latency**: a separate `Peak` row purely to get the P3's **latency** on
  Pz (its amplitude comes out too; ignore it if you only wanted the timing).

Every one of these is computed for `Rare`, `Frequent` **and** `Rare-Frequent`.
The difference-bin rows give you, for free, the mean/peak/area of the
difference wave: the P3 mean of `Rare-Frequent`, for instance, is the oddball
P3 effect at each of Pz/POz/CPz. Export once, and the whole battery for every
subject and the grand average lands in a single CSV.
