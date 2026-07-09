function [pfigure, ropts] = ScalpDistribution(input, opts)
%% ScalpDistribution  Plot scalp topographies of an averaged ERP.
%
%   A pure-plot transformation (see Alakazam.onTransformation, around
%   "if ishandle(result.EEG)"): returns a figure handle, not a modified
%   dataset, so nothing is persisted to the tree -- only the plot is shown.
%   Modelled on the same pattern as the (now removed from development, still
%   on main) PoinCare transformation.
%
%   Plots one topographic map per bin -- the mean amplitude across a chosen
%   time window, per channel -- using EEGLAB's topoplot. Works on either a
%   per-subject Average or a Grand Average: both are channels x time x bins
%   with DataFormat = "Averaged", so nothing here needs to tell them apart.
%
%   topoplot draws with legacy low-level graphics (gca/gcf, direct patch
%   calls), so this uses a classic figure + subplot grid rather than a
%   uifigure/uiaxes -- deliberately different from PoinCare's uifigure
%   style, because topoplot needs the classic one.
%
%   Signature (Alakazam transformation contract):
%     [pfigure, ropts] = ScalpDistribution(input)        % interactive
%     [pfigure, ropts] = ScalpDistribution(input, opts)  % replay

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

if nargin < 2 || (ischar(opts) && strcmpi(opts, 'Init'))
    opts = uiextras.settingsdlg( ...
        'Description', 'Plot the mean scalp topography of this ERP over a time window.', ...
        'title', 'Scalp Distribution options', ...
        'separator', 'Time window (ms):', ...
        {'Start'; 'Start'}, 300, ...
        {'Stop'; 'Stop'}, 500);
end
if opts.Stop <= opts.Start
    throw(MException('Alakazam:ScalpDistribution', sprintf([ ...
        'The Stop field (%g ms) needs to come after Start (%g ms), so there is ' ...
        'a real window to average over.'], opts.Stop, opts.Start)));
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
EEG.chanlocs = chanlocs;

if ~any(hasPos)
    throw(MException('Alakazam:ScalpDistribution', ...
        ['None of this dataset''s channels match a standard scalp position, ' ...
         'so there is nothing to plot. Rename channels to match 10-5 ' ...
         'nomenclature, or set their locations manually first.']));
end

[~, startIdx] = min(abs(EEG.times - opts.Start));
[~, stopIdx]  = min(abs(EEG.times - opts.Stop));

isBinned = ndims(EEG.data) == 3 && isfield(EEG, 'bindesc') && ~isempty(EEG.bindesc);
if isBinned
    nBins = size(EEG.data, 3);
    labels = {EEG.bindesc.label};
else
    nBins = 1;
    labels = {char(string(EEG.id))};
end

% Mean amplitude per positioned channel, per bin, across the window.
chanlocs = EEG.chanlocs(hasPos);
values = zeros(sum(hasPos), nBins);
for b = 1:nBins
    values(:, b) = mean(EEG.data(hasPos, startIdx:stopIdx, b), 2);
end

% One shared, symmetric colour scale across every bin, so the maps are
% actually comparable to each other -- topoplot otherwise auto-scales each
% one to its own min/max, which would make a real amplitude difference
% between bins look identical.
mapLimit = max(abs(values(:)));
if mapLimit == 0
    mapLimit = 1; % a flat-zero window would otherwise give topoplot [0 0]
end

[~, name, ~] = fileparts(EEG.File);
pfigure = figure('Name', ['Scalp distribution: ' name], 'Visible', 'off', ...
    'Color', [1 1 1]);
nCols = ceil(sqrt(nBins));
nRows = ceil(nBins / nCols);

for b = 1:nBins
    subplot(nRows, nCols, b);
    topoplot(values(:, b), chanlocs, 'electrodes', 'on', ...
        'maplimits', [-mapLimit, mapLimit]);
    title(labels{b}, 'Interpreter', 'none');
end

cb = colorbar('Position', [0.93 0.1 0.02 0.8]);
cb.Label.String = sprintf('Amplitude (\\muV), mean %g-%g ms', opts.Start, opts.Stop);

pfigure.Visible = 'on';
end
