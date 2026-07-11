function [pfigure, ropts] = ScalpDistribution(input, ~)
%% ScalpDistribution  Scrub through an averaged ERP's scalp topography.
%
%   A pure-plot transformation (see Alakazam.onTransformation, around
%   "if ishandle(result.EEG)"): returns a figure handle, not a modified
%   dataset, so nothing is persisted to the tree -- only the plot is shown.
%
%   A slider spans the dataset's whole time range; moving it redraws one
%   topographic map per bin -- the instantaneous amplitude per channel, at
%   whatever moment the slider is on -- using EEGLAB's topoplot. Works on
%   either a per-subject Average or a Grand Average: both are
%   channels x time x bins with DataFormat = "Averaged", so nothing here
%   needs to tell them apart.
%
%   Only draws the bins currently ticked on in this dataset's own Average
%   plot (its AverageView tickboxes), if that plot happens to be open --
%   the parent node this is drawn from. Falls back to every bin if that
%   plot is not open.
%
%   topoplot draws with legacy low-level graphics (gca/gcf, direct patch
%   calls), so this uses a classic figure with a classic uicontrol slider,
%   rather than a uifigure/uislider -- deliberately different from
%   PoinCare's uifigure style, because topoplot needs the classic one.
%
%   Signature (Alakazam transformation contract): the second argument is
%   accepted but unused, matching PoinCare -- a pure-plot transformation is
%   never replayed by dragging a branch (only persisted results are), so
%   there is no stored-options form to support.
%     [pfigure, ropts] = ScalpDistribution(input)

ropts = 'graph';

%% Check for the EEG dataset input:
if nargin < 1
    throw(MException('Alakazam:ScalpDistribution', ...
        'ScalpDistribution needs a dataset to plot, and none was given.'));
end

if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'Averaged')
    throw(MException('Alakazam:ScalpDistribution', sprintf([ ...
        'ScalpDistribution only plots an averaged ERP (a subject Average or a ' ...
        'Grand Average), not this dataset (DataFormat = "%s"). Run Average -- ' ...
        'or Grand Average, for a group result -- on it first.'], input.DataFormat)));
end

% A scalp map only makes sense for channels with a real scalp position:
% look each one up, by label, directly in a standard template (most
% datasets also carry a few non-scalp channels, e.g. EOG/ECG, which a
% template has no position for -- plot only the ones that resolve).
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
        ['None of this dataset''s channels match a standard scalp position, ' ...
         'so there is nothing to plot. Rename channels to match 10-5 ' ...
         'nomenclature, or set their locations manually first.']));
end
posChanlocs = chanlocs(hasPos);

isBinned = ndims(EEG.data) == 3 && isfield(EEG, 'bindesc') && ~isempty(EEG.bindesc);
if isBinned
    nBins = size(EEG.data, 3);
    labels = {EEG.bindesc.label};
else
    nBins = 1;
    labels = {char(string(EEG.id))};
end

% Only draw the bins currently ticked on in this dataset's own AverageView
% (see AverageView.m's tickboxes), if that plot happens to be open right
% now -- the parent node this is drawn from. Falls back to every bin if no
% such plot is open, or its bin count no longer matches this dataset (e.g.
% it was recomputed since the plot was last drawn).
selected = true(1, nBins);
parentFig = findobj("Type", "Figure", "Tag", EEG.File);
if ~isempty(parentFig)
    parentView = getappdata(parentFig, "AverageView");
    if ~isempty(parentView) && isvalid(parentView)
        ownSeries = cellfun(@(s) strcmp(s.file, EEG.File), parentView.Series);
        if sum(ownSeries) == nBins
            selected = parentView.Visible(ownSeries);
        end
    end
end
if ~any(selected)
    throw(MException('Alakazam:ScalpDistribution', ...
        ['Every bin in this dataset''s Average plot is currently unticked, so ' ...
         'there is nothing to draw a scalp map for. Tick at least one bin ' ...
         'there first.']));
end
binIndices = find(selected); % original EEG.data bin index for each kept slot
nBins  = numel(binIndices);
labels = labels(binIndices);

% One shared, symmetric colour scale for the whole scrubbing session (every
% selected bin, every moment in time), so a low-amplitude instant does not
% look just as saturated as a high-amplitude one -- topoplot otherwise
% auto-scales each call to its own min/max.
mapLimit = max(abs(EEG.data(hasPos, :, binIndices)), [], 'all');
if mapLimit == 0
    mapLimit = 1; % an all-zero dataset would otherwise give topoplot [0 0]
end

%% Build the figure: a subplot grid on top, a time slider along the bottom.
[~, name, ~] = fileparts(EEG.File);
pfigure = figure('Name', ['Scalp distribution: ' name], 'Visible', 'off', ...
    'Color', [1 1 1]);
nCols = min(3, nBins); % up to 3 bins side by side, then wrap to a new row
nRows = ceil(nBins / nCols);

sliderStripHeight = 0.12;
plotAreaBottom    = sliderStripHeight + 0.05;
plotAreaHeight    = 1 - plotAreaBottom - 0.05;
% A modest margin at the right -- not for anything we draw ourselves, but
% so that if the user adds a colorbar to the rightmost head via MATLAB's
% own axes toolbar (see the positionGuard timer below for why that needs
% handling at all), there is somewhere for it to land without being
% clipped at the figure edge.
plotAreaWidth = 0.95;
cellW = plotAreaWidth / nCols;
cellH = plotAreaHeight / nRows;

ax = gobjects(1, nBins);
layoutPositions = cell(1, nBins);
for b = 1:nBins
    row = ceil(b / nCols);
    col = mod(b - 1, nCols) + 1;
    left   = (col - 1) * cellW + 0.02;
    bottom = plotAreaBottom + (nRows - row) * cellH + 0.02;
    ax(b) = subplot('Position', [left, bottom, cellW - 0.04, cellH - 0.04]);
    layoutPositions{b} = ax(b).Position;
end

% topoplot's own axes shrink their actual Position (not just an outer
% margin) when a colorbar is added, to make room for it -- confirmed
% directly: the head itself is not redrawn smaller (its data extent is
% unchanged), its containing box just gets squeezed, which is what made a
% head with a user-added colorbar (via MATLAB's own axes toolbar --
% right-click > Insert Colorbar) look visibly smaller than its siblings.
% Setting PositionConstraint to 'innerposition' does not prevent this for
% a topoplot/subplot axes (confirmed; MATLAB's subplot-grid position
% manager overrides it regardless). Nor does an addlistener(ax, 'Position',
% 'PostSet', ...) catch it -- also confirmed directly: colorbar changes
% Position through some internal path that does not fire a PostSet
% notification at all. What does work (confirmed) is a plain restore
% after the fact, and it sticks (colorbar does not fight back a second
% time) -- so a lightweight timer periodically checks every head's
% Position against its original layout slot and restores it if something
% (typically a user-added colorbar) has changed it. This does not clip the
% colorbar itself -- confirmed it lands in the small gap already left
% between cells (or the reserved right margin above, for the rightmost
% column) rather than overlapping a neighbour. Stopped and deleted via the
% figure's DeleteFcn so it does not keep running after the plot is closed.
positionGuard = timer('ExecutionMode', 'fixedRate', 'Period', 0.5, ...
    'TimerFcn', @(~, ~) restoreHeadPositions());
start(positionGuard);
pfigure.DeleteFcn = @(~, ~) stopPositionGuard();

timeLabel = uicontrol(pfigure, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.35, 0.065, 0.3, 0.045], 'FontSize', 10, 'FontWeight', 'bold');

% Static labels for the slider's own start/end, flanking it, so the whole
% range is visible at a glance rather than only the current instant.
uicontrol(pfigure, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.0, 0.02, 0.07, 0.04], 'FontSize', 9, ...
    'String', sprintf('%.0f ms', EEG.times(1)), 'HorizontalAlignment', 'right');
uicontrol(pfigure, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.92, 0.02, 0.08, 0.04], 'FontSize', 9, ...
    'String', sprintf('%.0f ms', EEG.times(end)), 'HorizontalAlignment', 'left');

startTime = 0;
if startTime < EEG.times(1) || startTime > EEG.times(end)
    startTime = EEG.times(1); % 0 is not inside this epoch's window
end
slider = uicontrol(pfigure, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.08, 0.02, 0.84, 0.04], ...
    'Min', EEG.times(1), 'Max', EEG.times(end), 'Value', startTime);
% Classic uicontrol sliders only fire Callback on mouse-up; the underlying
% Value property, however, does update continuously while being dragged
% (confirmed directly), so a PostSet listener is the standard way to react
% live during the drag itself, with no Java/findjobj involved. Wired to
% the full redraw (label + every bin's topoplot), so the heads themselves
% update while dragging, not just the label -- Callback is therefore
% redundant (PostSet already fires for the final value on release too) and
% not set. The listener handle must be kept alive for the life of the
% figure; it is, via the same closure that already keeps ax/timeLabel/etc.
% alive (this whole function's workspace stays alive as long as the
% listener's callback, itself a nested-function handle, does).
sliderListener = addlistener(slider, 'Value', 'PostSet', @(~, ~) redraw(slider.Value)); %#ok<NASGU>

redraw(startTime);

pfigure.Visible = 'on';

    function redraw(t)
    %REDRAW  Show the scalp topography at the instant nearest T (ms).
    %   Wired to the slider's Value (see the PostSet listener above), so
    %   this runs continuously while dragging, not just on release.
        [~, idx] = min(abs(EEG.times - t));
        timeLabel.String = sprintf('t = %.0f ms', EEG.times(idx));
        for bb = 1:nBins
            axes(ax(bb)); %#ok<LAXES>
            cla(ax(bb)); % topoplot draws on top of whatever is already there otherwise
            topoplot(EEG.data(hasPos, idx, binIndices(bb)), posChanlocs, 'electrodes', 'on', ...
                'maplimits', [-mapLimit, mapLimit]);
            title(ax(bb), labels{bb}, 'Interpreter', 'none');
        end
    end

    function restoreHeadPositions()
    %RESTOREHEADPOSITIONS  Undo any external resize of any head's axes
    %   (see the positionGuard timer above -- typically MATLAB shrinking
    %   one to make room for a user-added colorbar), so every head stays
    %   the same size regardless.
        for bb = 1:nBins
            if isvalid(ax(bb)) && ~isequal(ax(bb).Position, layoutPositions{bb})
                ax(bb).Position = layoutPositions{bb};
            end
        end
    end

    function stopPositionGuard()
    %STOPPOSITIONGUARD  Figure DeleteFcn: stop and delete the positionGuard
    %   timer so it does not keep firing after this plot is closed.
        if isvalid(positionGuard)
            stop(positionGuard);
            delete(positionGuard);
        end
    end
end
