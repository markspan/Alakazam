function [EEG, opts] = ScalpDistribution(input, varargin)
%% ScalpDistribution  Resolve scalp positions for a scrubbable topography.
%
%   A normal, persisted transformation (Alakazam.onTransformation): gets a
%   tree node under the averaged dataset it was run on, and opens in its
%   own tab, drawn by ScalpDistributionView -- the same way Average/
%   Fourier/TimeFrequency results do. Was a "pure plot" (see
%   Alakazam.onTransformation's "if ishandle(result.EEG)") until EEGLAB's
%   topoplot() was ported to TransTools.DrawScalpMap (a uiaxes-compatible
%   version -- topoplot() itself only ever drew via gca/gcf-implicit
%   state, and was confirmed to silently draw nothing at all when targeted
%   at a uiaxes hosted in a uitab; see migration.md), which made it
%   possible for ScalpDistribution to become a real tab like every other
%   transformation instead of its own separate classic-figure window.
%
%   All this function does is resolve channel scalp positions once (a
%   template lookup, not cheap enough to redo on every redraw) and compute
%   a shared, symmetric colour scale across the WHOLE dataset (every
%   channel, every bin, every instant) so a low-amplitude moment never
%   looks just as saturated as a high-amplitude one while scrubbing -- see
%   TransTools.ResolveScalpDistribution, which does the actual resolving
%   (shared with Brain3D.m: same resolution, only the drawing differs).
%   ScalpDistributionView does the actual per-instant interpolation/draw
%   (via TransTools.DrawScalpMap) and owns the time-scrubbing uislider;
%   see its own header comment for the live-scrubbing design and for how
%   it decides which bins to draw (it looks at this dataset's own
%   AverageView tickboxes, if that tab happens to be open -- a concern
%   that also moved from here into the view, since only the view has
%   access to sibling tabs).
%
%   Works on either a per-subject Average or a Grand Average: both are
%   channels x time x bins with DataFormat = "Averaged", so nothing here
%   needs to tell them apart.
%
%   Signature (Alakazam transformation contract, matching Average.m):
%   ScalpDistribution has no real options, so OPTS is accepted and
%   returned unchanged, purely to satisfy the two-output/replay contract.
%     [EEG, opts] = ScalpDistribution(input, opts)

opts = TransTools.InitGuard(nargin, 'Alakazam:ScalpDistribution', varargin{:});

EEG = TransTools.ResolveScalpDistribution(input, 'Alakazam:ScalpDistribution');
