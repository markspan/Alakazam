# Where each transformation's work is done

Which of Alakazam's transformations wrap another toolkit, and which implement
their method here. Useful when citing the software, when judging what a
dependency's absence would actually cost, and when deciding whether a bug
belongs upstream.

Verified against the source rather than recalled. The command that produced
it is at the foot of this page, so it can be re-run rather than trusted.

*Last verified: 30 August 2026, 22 transformations.*

## Wrappers: the toolkit does the work

| Transformation | Wraps |
|---|---|
| `ReRef` | `pop_reref` (EEGLAB) |
| `Resample` | `pop_resample` (EEGLAB) |
| `SelectData` | `pop_select` (EEGLAB) |
| `Interpolate` | `pop_interp` (EEGLAB) |
| `Filter` | `firfilt` (EEGLAB firfilt plugin) |
| `AutoEyeICA` | `pop_runica` / `fastica`, `iclabel`, `pop_subcomp` |
| `RemoveComponents` | the same ICA stack, plus `eeg_checkset` |
| `AutoGEDAI` | `GEDAI` (GEDAI plugin), `pop_select` |

`Filter` is the one worth a note: the filtering is `firfilt`, but the
parameter design is Alakazam's. You give a frequency and a stopband
attenuation in dB, and the order, transition band and window are derived
from those rather than asked for.

## Own algorithm, another toolkit for support only

| Transformation | Its own | Borrowed |
|---|---|---|
| `ArtefactDetect` | the detection, 282 lines | `eeg_interp`, to repair flagged cells |
| `ManualReject` | the rejection UI | `eeg_interp`, the same |
| `ChannelEditor` | the editor | dipfit's `standard_1005.elc`, a data file rather than a function |
| `CoherenceTopography` | the coherence, 110 lines | `readlocs` and the dipfit file, for electrode positions |

## Written for Alakazam

| Transformation | Size |
|---|---|
| `Measure` | 1116 lines |
| `DefineBins` | 251, plus a 1363-line language engine |
| `SpectralMeasure` | 295 lines |
| `Fourier` | 207 lines |
| `Average` | 182 lines |
| `TimeFrequency` | 101, plus 175 in `TransTools.ComputeErsp` |
| `CoherenceMap` | 97, plus 179 in `TransTools.ComputeCoherenceMap` |
| `Baseline` | 65 lines |
| `Brain3D` | scalp-position resolution; the drawing is in `Brain3DView` |
| `ScalpDistribution` | the distribution; the drawing is in `ScalpDistributionView` |

Ten of the twenty-two, and they are the substantial ones by volume.

## Two things worth knowing

**`TimeFrequency` is not a `newtimef` wrapper.** `TransTools.ComputeErsp`
builds its own Morlet wavelets, `exp(2i*pi*f*t) * exp(-t^2 / 2*sigma^2)`,
unit-energy normalised and convolved by FFT. `newtimef` appears in that file
only inside a comment. The same is true of `TransTools.ComputeSourceEstimate`,
which names `ft_sourceanalysis` only to record why it does not call it.

**`topoplot` is not in the transformation layer at all.** It is called by
`ScalpDistributionView`, `Brain3DView`, `CoherenceTopographyView` and
`RemoveComponentsDialog`. The transformations compute; EEGLAB draws. That
separation is cleaner than a folder listing suggests, and it means a
transformation's result does not depend on EEGLAB's plotting.

**FieldTrip appears in no transformation.** Only in
`TransTools.BuildSourceForwardModel` and `TransTools.ensureFieldTrip`, reached
from `Brain3DView`, and in the cluster statistics, which is a separate
mechanism rather than a transformation (see `PROJECT_STRUCTURE.md`).

## How this was verified, and how to redo it

Whole-line comments are stripped before matching, and only whole-line ones.
Stripping from the first `%` to end of line looks equivalent and is not: it
truncates format strings such as `'%s'`, which is how an earlier pass lost a
real `topoplot` call in `TransTools.DrawScalpMap`. Indirect dependencies are
resolved one hop, through the `+TransTools` helper a transformation calls.

Run from `src/Transformations`:

```python
import io, os, re, glob
PAT = re.compile(r'\b(pop_[a-zA-Z0-9_]+|eeg_[a-zA-Z0-9_]+|ft_[a-zA-Z0-9_]+'
                 r'|GEDAI|iclabel|fastica|runica|firfilt|newtimef|spectopo'
                 r'|topoplot|readlocs|dipfitdefs)\b')

def code(path):
    return "\n".join(l for l in io.open(path, encoding='utf-8',
                                        errors='replace').read().split('\n')
                     if not l.lstrip().startswith('%'))

helper = {os.path.basename(f)[:-2]: sorted(set(PAT.findall(code(f))))
          for f in glob.glob('+TransTools/*.m')}

for d in sorted(os.listdir('.')):
    if not os.path.isdir(d) or d == '+TransTools':
        continue
    src = "\n".join(code(f) for f in glob.glob(os.path.join(d, '*.m')))
    print(d, "direct:", sorted(set(PAT.findall(src))) or "-")
    for h in sorted(set(re.findall(r'TransTools\.([A-Za-z0-9_]+)', src))):
        if helper.get(h):
            print("   via", h + ":", helper[h])
```

### What this does not prove

The pattern matches the naming conventions of EEGLAB, FieldTrip, GEDAI,
ICLabel and FastICA. A dependency named unconventionally would be missed.
Nothing in the current source suggests one, but that is an absence of
evidence rather than a proof.

It also says nothing about MATLAB's own toolboxes. `fft`, `filtfilt` and
friends are treated as part of the language here, not as dependencies; see
`dependencies.md` for what an installation actually requires.
