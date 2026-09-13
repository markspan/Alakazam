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

**Nothing reads these files yet.** `Template1005File` still prefers the
installed toolbox copies, unchanged. These are a tracked, durable reference;
wiring the accessor to prefer them is a separate decision, noted at the
bottom.

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
  **and** theta/radius, and `TransTools.LateralPairs` finds 27 lateral
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
  `TransTools.LateralPairs`, which pairs by mirrored position or by label
  and never by channel order, and the test that names this case.

## If the accessor is ever pointed here

Two consequences worth knowing before making that change:

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
