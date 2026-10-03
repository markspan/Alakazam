# Compiled TFCE kernel

`alakazam_tfce.c` scores a statistic map by threshold-free cluster
enhancement (TFCE). It is not a method of Alakazam's own: it is a C port of
FieldTrip's exact TFCE, written only to make source-level cluster tests
faster. The answer is FieldTrip's; only the speed differs.

- **Ported from:** `local_etfce` in `private/tfcestat.m` of FieldTrip
  20260812, the build Alakazam pins (see `dependencies.md`). The same file's
  `local_build_edges` is ported to MATLAB as `TransTools.TfceEdges`, and its
  handling of the two tails (`tfce_exact`) as `TransTools.TfceScore`.
- **Algorithm:** exact TFCE (eTFCE) by Chen, Weeda, Nichols and Goeman
  (2026), arXiv:2603.03004, implemented in FieldTrip by Devon Yanitski.
  TFCE itself is Smith and Nichols (2009).
- **Licence:** FieldTrip is free software under the GNU General Public
  License, version 3 or later. This port is distributed under the same
  terms, as part of Alakazam (see `LICENSE` at the repository root).

## Where it is used

Only by the source-level Cluster Test (`SourceClusterStats`), when its
correction is TFCE, the default. FieldTrip still runs the permutations and
the correction: `ClusterStats.tfceStatfun` hands it the already enhanced
map under `correctm = 'max'`, which is the same test as `correctm = 'tfce'`
(that file's header explains why). The scalp-level Cluster Test
(`ClusterStats`) does not use the kernel; FieldTrip computes TFCE there
itself.

The kernel is about 98% of a source run's time. The dialog's run-time
estimate assumes a run takes about 2.7 times as long without it.

## Built on first use

`TransTools.EnsureTfceMex` compiles it into `bin/` with MATLAB's `mex` the
first time it is needed. The binary is not in the repository (`.gitignore`
excludes `*.mex*`). Where it cannot be built, for want of a compiler,
`EnsureTfceMex` returns false and FieldTrip's own TFCE runs instead: the
same result, slower.

## What it reproduces

FieldTrip's `tfcestat` with:

- `tfce_method = 'exact'`, FieldTrip's default;
- `tfce_E` and `tfce_H` as passed (Alakazam passes FieldTrip's defaults,
  0.5 and 2);
- `tfce_h0 = 0`, the default (FieldTrip subtracts h0 before scoring; the
  kernel never does);
- a space by time map with an explicit neighbour matrix, channels or source
  vertices.

Not covered: the `'discrete'` method, a non-zero `tfce_h0`, further
dimensions such as frequency, and FieldTrip's 3-D grid case.
`SourceClusterStats` asks for none of these.

Tied values are visited in the order MATLAB's stable sort gives them, so
ties give FieldTrip's answer too; the C file's header explains how.

## How the equivalence is checked

`tests/SourceClusterMexTest.m`:

- `theAcceleratedRouteGivesIdenticalProbabilities` runs FieldTrip's own
  `correctm = 'tfce'` and the kernel's route on the same data with the same
  random seed. The p-values must be identical, the raw statistic equal to
  within 1e-12, and the TFCE maps equal to within a relative 1e-9.
- `anIsolatedPointScoresWhatTheFormulaSays` checks one point against the
  closed form of the integral.
- `theEdgeListJoinsSpaceAndTimeAndNothingElse` checks the lattice.

The cases that need the kernel are skipped where it cannot be built, and
the first also where FieldTrip is not installed. A skip is not a pass: run
them on a machine with a compiler and FieldTrip.

## When FieldTrip is updated

Run `SourceClusterMexTest` against the new build before changing the pin.
If `tfcestat.m` has changed, compare its `local_etfce` and
`local_build_edges` with this port, and either port the change or remove
the kernel. The two must not drift apart: results would differ from
FieldTrip's without anything a reader could see.
