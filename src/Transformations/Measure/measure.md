# Defining measures

`Measure` turns a window on an averaged waveform into a number. You give it a
short table of **measurement windows**: each row names a time window and says
how to reduce the samples inside it to a single value (or, for peaks, two
values). Every window is then evaluated for every bin and every selected
channel, and the results are stored on the dataset (`EEG.measurements`) ready
to be written out as one tidy CSV for statistics (see [What you get
out](#what-you-get-out)).

There are three kinds of measure: **mean amplitude**, **peak** (amplitude and
latency), and **peak area** (the signed area of a band centred on the peak).

`Measure` runs on an **averaged** dataset only: a subject `Average` or a
`Grand Average`. Run `Average` (or Grand Average, for a group waveform) first;
on anything else `Measure` reports that it needs an averaged ERP and stops.

This document builds the window table up one column at a time, with examples,
then covers what comes out and how to reuse a set of windows. For a one-screen
summary, jump to the [reference](#reference) at the end.

---

## 1. The window table

Each row of the dialog's table is one window:

| Label | Start (ms) | Stop (ms) | Measure | Polarity | Width (ms) | Reference channel | Channels |
|---|---|---|---|---|---|---|---|
| P3 | 300 | 600 | Mean Amplitude | Positive | 100 | | Pz |

Use **Add Window** / **Remove Selected** to grow and shrink the table. The
columns are:

- **Label**: the window's name, carried through to the output so you can tell
  rows apart (e.g. `P3`, `N170`, `LPP late`). Required, and best kept unique.
- **Start (ms)**, **Stop (ms)**: the window bounds, in the same millisecond
  axis the waveform is plotted on (`EEG.times`). Start must not be after Stop.
- **Measure**: `Mean Amplitude`, `Peak`, or `Peak Area` (see
  [§3](#3-mean-amplitude), [§4](#4-peak-amplitude-and-latency), and
  [§5](#5-peak-area)).
- **Polarity**: `Positive` or `Negative`. Used by `Peak` and `Peak Area`;
  ignored for `Mean Amplitude`.
- **Width (ms)**: the width of the integration band for `Peak Area`; ignored
  by the other measures (see [§5](#5-peak-area)).
- **Reference channel**: optional; used by `Peak` and `Peak Area` (see
  [§6](#6-reference-channel-locking-the-latency)).
- **Channels**: which channels to measure (see [§7](#7-channels)).

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

## 5. Peak Area

```
Label   Start  Stop  Measure    Polarity  Width  Reference channel  Channels
P3 area 250    600   Peak Area  Positive  150    Pz                 Pz, POz
```

`Peak Area` locates the peak exactly as `Peak` does (the extreme sample in the
Start–Stop **search range**, chosen by Polarity), then reports the **signed
area** of a band **`Width` ms wide, centred on that peak**
(`peak_latency − Width/2` to `peak_latency + Width/2`), together with the peak's
own **amplitude and latency** (so a Peak Area window gives you the integral and
the peak value and time in one measure). The area is a trapezoidal integral
against the real millisecond axis, so its units are **µV·ms**; a positive-going
component gives a positive area, a negative-going one a negative area.

For the row above, on a P3 peaking at, say, 372 ms, the area is integrated over
322–422 ms (150 ms centred on 372), on both `Pz` and `POz`.

The Start–Stop range is only where the **peak is searched**; the band that is
actually integrated is the `Width`-ms window that follows the peak. A couple of
worked placements:

```
peak at 360 ms, Width 100  ->  integrate 310–410 ms
peak at 150 ms, Width  60  ->  integrate 120–180 ms
```

Notes:

- **Width is required** for a Peak Area row and must be positive; the dialog
  will not accept the row otherwise. It is ignored for the other measures.
- If the band runs off the edge of the epoch it clamps to the nearest edge
  sample (the same nearest-sample rule as the search window).
- `NaN` samples inside the band are dropped and the remaining real samples
  integrated at their own times, so a few artefact-blanked points shrink the
  support rather than voiding the area. A band left with fewer than two real
  samples has no area (`NaN`).
- Because the band is *placed by the peak*, it inherits some of peak latency's
  noise. A **reference channel** ([§6](#6-reference-channel-locking-the-latency))
  fixes the band across channels and is often what you want here.

## 6. Reference channel: locking the latency

Peak latency is noisy, and a component often peaks at slightly different times
on different channels even when it is really one component. Setting a
**Reference channel** (for `Peak` or `Peak Area`) locates the peak **once**, on
that channel, and then reads every selected channel at that shared point: for
`Peak`, each channel's amplitude at the reference latency; for `Peak Area`,
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
- Reference channel is ignored for `Mean Amplitude` windows.
- The peak is found separately **per bin**, so two conditions may lock to
  different time points. Each bin's read-out is taken at that bin's own
  reference-channel latency.

## 7. Channels

The **Channels** cell is a list of channel labels, separated by commas and/or
spaces. Matching is case-insensitive.

```
Pz                 % one channel
Pz, Cz, POz        % a few, comma-separated
P7 P8              % spaces work too
cz,pz              % case does not matter
```

**Leave it blank to measure every channel** in the dataset. There is no `all`
keyword; blank *is* "all". A label that is not in the dataset is an error,
reported with the offending name, so a typo is caught at once rather than
silently dropped.

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
  which channel happened to win locally.
- **Peak area** is a peak-locked integrated amplitude: over a fixed `Width` it
  is just the mean amplitude of the band times its width, so it shares mean
  amplitude's robustness to noise, but with the band **following the component**
  rather than sitting at fixed times. That is useful when a component's timing
  moves across conditions or subjects, but note that placing the band by the
  peak reintroduces a little of peak latency's own noise; a reference channel
  is the usual remedy.
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
- **Peak Area** — the integrated band shaded under the curve (down to the
  0 µV baseline), labelled at the peak.
- **Mean Amplitude** — a level line at the mean, spanning the measurement
  window, labelled at its start.

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
s01,subject,Rare,Pz,P3 area,peak_area,250,600,540.5
s01,subject,Rare,Pz,P3 area,peak_latency,250,600,372
s01,subject,Frequent,Pz,P3 mean,mean_amplitude,300,600,1.05
GA all,grand_average,Rare,Pz,P3 mean,mean_amplitude,300,600,3.88
...
```

Points worth knowing:

- Each window contributes one measure-type row per value it produces, so the
  single `value` column stays uniformly numeric:
  - `Mean Amplitude` → one row, `mean_amplitude`.
  - `Peak` → two rows, `peak_amplitude` and `peak_latency`.
  - `Peak Area` → two rows, `peak_area` (µV·ms) and `peak_latency`.
- `window_start_ms` / `window_stop_ms` are the window's own **search range**
  for every measure. For `Peak Area` the integrated band is not these bounds
  but `Width` ms centred on `peak_latency` (which is exported, so the band is
  recoverable if you know the window's Width).
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
`.alzmeasures` file (small JSON); **Load...** reads one back in. This is
independent of any one dataset: use it to keep a lab-standard set of windows,
reuse the same battery in a new workspace, or share it with a colleague. Save
stores the table as-is (it does not require the rows to be valid first), so you
can also use it to park a work-in-progress.

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

| Column | Values | Used by |
|---|---|---|
| Label | any text (unique is best) | all |
| Start (ms), Stop (ms) | numbers; Start ≤ Stop | all |
| Measure | `Mean Amplitude`, `Peak`, `Peak Area` | all |
| Polarity | `Positive` (max), `Negative` (min) | `Peak`, `Peak Area` |
| Width (ms) | positive number (band width) | `Peak Area` |
| Reference channel | a channel label, or blank | `Peak`, `Peak Area` |
| Channels | labels (comma/space separated); blank = all | all |

### Measures

| Measure | Reports | Polarity | Latency | Band |
|---|---|---|---|---|
| Mean Amplitude | mean over the window | ignored | none | search window |
| Peak | extreme sample + its time | picks max/min | reported (ms) | one sample |
| Peak Area | signed area (µV·ms) + peak time | picks max/min | reported (ms) | `Width` ms centred on peak |

### Output rows (Export Measurements...)

| Window's Measure | `measure_type` value(s) |
|---|---|
| Mean Amplitude | `mean_amplitude` |
| Peak | `peak_amplitude` **and** `peak_latency` |
| Peak Area | `peak_area` **and** `peak_latency` |

CSV columns:
`dataset, dataset_type, bin, channel, window, measure_type, window_start_ms,
window_stop_ms, value` (missing `value` → `NA`).

### Behaviour notes

- Windows and integration bands snap to the nearest real sample; an edge just
  outside the epoch clamps to the nearest edge sample.
- Every bin is measured, including `DefineBins` difference/contrast bins.
- An all-`NaN` bin yields `NaN` (→ `NA` in the CSV), not a false first-sample
  reading.
- Peak is the single most extreme sample (no interpolation, no local-maximum
  search); peak area is a trapezoidal integral, NaN-tolerant within the band.

---

## Full worked example

A visual-oddball study: rare vs. frequent stimuli, and their difference,
scored for the classic components. Assume `DefineBins`/`Average` have produced
bins `Rare`, `Frequent`, and `Rare-Frequent` (a difference bin).

| Label | Start | Stop | Measure | Polarity | Width | Reference channel | Channels |
|---|---|---|---|---|---|---|---|
| P1 | 80 | 130 | Peak | Positive | | | O1, O2, Oz |
| N1 | 130 | 200 | Peak | Negative | | Oz | O1, O2, Oz |
| P2 | 150 | 250 | Mean Amplitude | | | | FCz, Cz |
| N2 | 200 | 350 | Mean Amplitude | | | | FCz, Cz |
| P3 | 300 | 600 | Mean Amplitude | | | | Pz, POz, CPz |
| P3 area | 250 | 600 | Peak Area | Positive | 150 | Pz | Pz, POz, CPz |
| P3 latency | 250 | 550 | Peak | Positive | | Pz | Pz |
| LPP | 500 | 800 | Mean Amplitude | | | | Pz, POz |

Reading this table:

- **P1**: posterior positive peak (amplitude + latency), each occipital
  channel searched independently.
- **N1**: posterior negative peak; latency **locked to Oz**, so O1/O2/Oz all
  report their amplitude at Oz's negative peak, sharing one latency.
- **P2, N2, P3, LPP**: mean amplitudes over fixed windows, the robust default;
  polarity, width and reference channel left unset because they don't apply.
- **P3 area**: the P3 as a peak-locked integrated amplitude — find the positive
  peak on `Pz`, integrate a 150 ms band centred on it, and read the same band
  on Pz/POz/CPz (reference channel keeps the band identical across the three).
- **P3 latency**: a separate `Peak` row purely to get the P3's **latency** on
  Pz (its amplitude comes out too; ignore it if you only wanted the timing).

Every one of these is computed for `Rare`, `Frequent` **and** `Rare-Frequent`.
The difference-bin rows give you, for free, the mean/peak/area of the
difference wave: the P3 mean of `Rare-Frequent`, for instance, is the oddball
P3 effect at each of Pz/POz/CPz. Export once, and the whole battery for every
subject and the grand average lands in a single CSV.
