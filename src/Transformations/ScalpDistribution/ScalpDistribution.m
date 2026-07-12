function [EEG, opts] = ScalpDistribution(input, opts)
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
%   looks just as saturated as a high-amplitude one while scrubbing.
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

%% Check for the EEG dataset input:
if nargin < 1
    throw(MException('Alakazam:ScalpDistribution', ...
        'Problem in ScalpDistribution: needs a dataset to run on, and none was given.'));
end
if nargin < 2
    opts = 'Init';
end

if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'Averaged')
    throw(MException('Alakazam:ScalpDistribution', sprintf([ ...
        'Problem in ScalpDistribution: only works on an averaged ERP (a subject ' ...
        'Average or a Grand Average), not this dataset (DataFormat = "%s"). Run ' ...
        'Average -- or Grand Average, for a group result -- on it first.'], input.DataFormat)));
end

% A scalp map only makes sense for channels with a real scalp position:
% look each one up, by label, directly in a standard template (most
% datasets also carry a few non-scalp channels, e.g. EOG/ECG, which a
% template has no position for -- keep only the ones that resolve).
%
% This deliberately does not use TransTools.FillChanlocs (which resolves
% positions via pop_chanedit): pop_chanedit runs eeg_checkset on the whole
% EEG struct, which expects native per-trial EEG.event(i).epoch bookkeeping
% that our bin-based Session model never populates (DefineBins/Average tag
% events with .bini, not EEGLAB's own .epoch) -- on a real Averaged dataset
% (as opposed to a fresh eeg_emptyset(), which papers over this) that
% mismatch makes eeg_checkset abort outright ("the event info structure
% does not contain an 'epoch' field"). A direct template lookup by label
% only ever touches a plain chanlocs array, never eeg_checkset, and is the
% same approach AutoGEDAI already uses for its own template matching.
EEG = input;
elcFile  = TransTools.Dipfit1005File('Alakazam:ScalpDistribution');
template = readlocs(elcFile);
templateLabels = lower(string({template.labels}));

chanlocs = EEG.chanlocs;
hasPos = false(1, numel(chanlocs));
for c = 1:numel(chanlocs)
    match = find(templateLabels == lower(string(chanlocs(c).labels)), 1);
    if isempty(match)
        continue;
    end
    chanlocs(c).X      = template(match).X;
    chanlocs(c).Y      = template(match).Y;
    chanlocs(c).Z      = template(match).Z;
    chanlocs(c).theta  = template(match).theta;
    chanlocs(c).radius = template(match).radius;
    hasPos(c) = true;
end

if ~any(hasPos)
    throw(MException('Alakazam:ScalpDistribution', ...
        ['Problem in ScalpDistribution: none of this dataset''s channels match a ' ...
         'standard scalp position, so there is nothing to plot. Rename channels ' ...
         'to match 10-5 nomenclature, or set their locations manually first.']));
end

% One shared, symmetric colour scale for the whole scrubbing session (every
% bin, every moment in time -- ScalpDistributionView may only end up
% drawing a subset of bins, based on the sibling AverageView's tickboxes,
% but the scale itself stays fixed regardless of that selection), so a
% low-amplitude instant does not look just as saturated as a high-amplitude
% one -- DrawScalpMap otherwise has no natural scale of its own to fall
% back on.
mapLimit = max(abs(EEG.data(hasPos, :, :)), [], 'all');
if mapLimit == 0 || isnan(mapLimit)
    mapLimit = 1; % an all-zero (or all-NaN) dataset would otherwise give an empty [0 0] scale
end

EEG.ScalpChanlocs = chanlocs(hasPos);
EEG.ScalpHasPos   = hasPos;
EEG.ScalpMapLimit = mapLimit;

% Alakazam.persistResultNode overwrites EEG.File with this result's own
% new cache path immediately after this function returns, so by the time
% ScalpDistributionView runs (it draws the persisted result, not this
% transformation's live workspace), EEG.File no longer identifies the
% parent Average dataset this was run on -- stash it now, under this
% function's own input.File, while it still does, since that is exactly
% what a sibling AverageView tab is tagged with (see
% ScalpDistributionView.tickedBins).
EEG.ScalpSourceFile = input.File;
