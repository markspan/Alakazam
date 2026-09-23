# Electrodes

Electrode position templates, vendored so they travel with the repository.

## Why these are here

`TransTools.Template1005File` resolves the 10-5 template out of whichever
toolbox happens to be installed: FieldTrip's copy when FieldTrip is on the
path, dipfit's otherwise. That works, and `Template1005Test` asserts the two
are numerically identical (same 346 labels in the same order, 0 mm maximum
displacement), so which one is read cannot change a result.

What it does not survive is a toolbox update. FieldTrip installs into a
version-stamped folder (`fieldtrip-20260812/`), so the next release is a new
directory and anything placed beside its templates does not follow. A
montage an analysis depends on should not live somewhere that a routine
update silently removes.

**`Template1005File` itself is unchanged** and still prefers the installed
toolbox copies, so nothing about ICA eligibility, GEDAI, or the four
`TemplateScalpLocs` callers (scalp maps, coherence topography, the manual
ICA selector's component maps, cluster stats) depends on this folder --
see "If the accessor is ever pointed here" at the bottom for what changing
that would mean.

**One caller does read this folder directly**: Channel Editor's "Look up
locations" offers every template here in a dropdown (10-5 first, the rest
alphabetically), via `AvailableElectrodeTemplates`. That is a
deliberate, user-facing choice made once per edit, not a change to what
any transformation resolves positions from automatically -- it is the
reason this folder exists in the first place: an equidistant montage's
labels carry no anatomy, so a user filling in its locations needs to
pick THIS file rather than the 10-5 system a 10-5-only lookup would have
silently failed to match.

## `standard_1005.elc`

The 10-5 system, 346 electrodes plus fiducials.

- **Source:** FieldTrip, `template/electrode/standard_1005.elc`
  (<https://github.com/fieldtrip/fieldtrip>), from the
  `fieldtrip-20260812` release installed under `Documents/MATLAB`. Copied
  byte-for-byte, verified with `cmp`, 2026-09-13.
- **Licence:** GPLv3 (FieldTrip's own `COPYING`), the same licence as
  Alakazam itself -- see the repository root `LICENSE`.
- **Also shipped by:** dipfit, as
  `plugins/dipfit/standard_BEM/elec/standard_1005.elc`, and by GEDAI as
  `auxiliaries/standard_1005.elc`. The dipfit and FieldTrip copies differ
  only by a few dozen bytes of header whitespace; `Template1005Test`
  measures their positions as identical.

## `standard_waveguard64_equidistant.elc`

ANT Neuro's 64-channel equidistant waveguard montage: 64 scalp electrodes
plus one `EOG`, 65 positions in all.

- **Source:** supplied by the maintainer, 2026-09-13, as ANT's own
  `standard_waveguard64_equidistant.elc`.
- **Licence:** not stated by the supplier. It is a table of electrode
  coordinates rather than code; treat its redistribution terms as unsettled
  until confirmed with ANT.
- **Labels carry no anatomy**, which is the point of an equidistant
  montage: electrodes are named by position in the array (`0Z`, `1L`, `1R`,
  `1LB`, `10L`, `4RC`), not by the underlying cortex. So nothing that reads
  a 10-20 label can interpret this montage, and anything inferring
  laterality must do it from the coordinates or from the `L`/`R` letter.
- **Verified on import** (2026-09-13), through `readlocs`, the same reader
  `TransTools.TemplateScalpLocs` uses: 65 channels, all with finite X/Y/Z
  **and** theta/radius, and `LateralPairs` finds 27 lateral
  pairs, 10 midline electrodes and 1 unpaired (`EOG`) from the geometry and
  the labels **independently, in exact agreement**.
- **Coordinates:** mm, `ReferenceLabel avg`, and the axis convention
  matches EEGLAB's (+X toward the nose, +Y toward the LEFT ear, +Z up):
  `1L` sits at Y = +27.6597 and `1R` at Y = -27.6597 with identical X and Z.
- **No fiducials.** The file carries `Positions` and `Labels` only, with no
  Nz/LPA/RPA, so there is nothing for a head model to coregister against.
  Scalp maps and laterality need no fiducials and work from this file;
  dipole fitting and source estimation do need them, and cannot be done
  from this file alone.
- **One pair is listed inverted.** Every pair appears left-then-right
  except `3RD`, which precedes `3LD`. Anything pairing adjacent rows would
  swap contralateral for ipsilateral on exactly that pair, in a montage
  where no label would let a reader notice. See
  `LateralPairs`, which pairs by mirrored position or by label
  and never by channel order, and the test that names this case.

## If `Template1005File` itself is ever pointed here

That is a different, larger change from Channel Editor's picker above: it
would move where AutoEyeICA, RemoveComponents' decomposition, GEDAI's
channel matching and every `TemplateScalpLocs` caller resolve the 10-5
system from, not just what one dialog offers. Two consequences worth
knowing before making it:

1. For `standard_1005.elc` it is numerically a no-op, because this copy is
   byte-identical to FieldTrip's and `Template1005Test` already measures
   FieldTrip's and dipfit's as identical. The gain is only that filling
   channel locations and drawing a scalp map would stop depending on a
   toolbox being installed at all. That is not urgent: dipfit ships with
   EEGLAB and its copy is present here
   (`eeglab2026.1.0/plugins/dipfit/standard_BEM/elec/standard_1005.elc`),
   so the existing fallback works.
2. `Template1005Test` compares the installed copies to each other. Adding a
   third, preferred copy means that test should compare this one too, or it
   stops guarding the thing it was written to guard.

Using the waveguard file is a larger change than a default: the four
callers of `TemplateScalpLocs` (`ResolveScalpDistribution`,
`CoherenceTopography`, `RemoveComponents`, `ClusterStats`) each hard-code
`Template1005File`, so a montage choice would have to reach them.
