function [EEG, opts] = SourceRegions(input, varargin)
%SOURCEREGIONS  The time course of each brain region, from a source estimate:
%   a dataset whose channels are the regions of an atlas.
%
%   Every bin of an averaged dataset is inverted onto the template cortical
%   sheet (by SourceEstimate, so with its noise covariance, its key and its
%   stored estimate), and the vertices are then combined region by region
%   by FieldTrip's own ft_sourceparcellate, over an atlas FieldTrip ships
%   (AAL, or Brainnetome). The result is an ordinary averaged dataset with
%   one "channel" per region, so everything that reads channels reads it:
%   the ERP plot, Measure and its windows, grand averages, the statistics
%   reports, and TimeFrequency, which then gives time-frequency power in
%   source space.
%
%   TWO WAYS TO COMBINE A REGION'S VERTICES:
%     'Mean magnitude'   the mean of the vertices' magnitudes (the free
%                        orientation's length): always positive, never
%                        cancelling. FieldTrip's 'mean' over power-like
%                        values.
%     'Signed mean'      the mean of the vertices' signed values along the
%                        cortical normal, each first flipped to agree with
%                        the region's dominant normal direction (the first
%                        right singular vector of its normals). Without the
%                        flip, the two banks of a sulcus, whose normals
%                        point at each other, cancel in the mean; with it,
%                        the polarity of an ERP survives. This is MNE's
%                        'mean_flip'; the mean itself is FieldTrip's.
%
%   A REGION IS AS GOOD AS THE ESTIMATE UNDER IT. With template anatomy and
%   a few dozen electrodes, neighbouring regions share much of their signal
%   (see the point-spread functions in chapter 18 of the manual), so a
%   difference between two adjacent regions is weak evidence that the
%   effect is in one and not the other.
%
%   Signature (Alakazam transformation contract):
%     [EEG, opts] = SourceRegions(input)        % settings dialog
%     [EEG, opts] = SourceRegions(input, opts)  % replay stored settings
%   OPTS: Atlas ('AAL' | 'Brainnetome'), Value ('Mean magnitude' |
%   'Signed mean'), Method ('dSPM' | 'sLORETA'), SourceSpace (20484, 8196 or
%   5124), NoiseCovariance ('auto' | 'baseline' | 'identity'), SNR, RegParam.
%
%   See also SOURCEESTIMATE, TRANSTOOLS.ATLASVERTEXLABELS, FT_SOURCEPARCELLATE.
ATLASES = {'AAL', 'Brainnetome'};
VALUES  = {'Mean magnitude', 'Signed mean'};
METHODS = {'dSPM', 'sLORETA'};
SPACES  = {'20484', '8196', '5124'};
NOISE   = {'auto', 'baseline', 'identity'};

[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:SourceRegions', varargin{:});
if ~isfield(input, 'bindesc') || isempty(input.bindesc) || ~isfield(input, 'data') || isempty(input.data)
    throw(MException('Alakazam:SourceRegions', '%s', ...
        ['I am afraid this dataset has no bins, so there is nothing to invert. Run ' ...
         'DefineBins and Average first: region time courses are computed per bin of an ' ...
         'averaged dataset.']));
end

if interactive
    stored = TransformSettings.get('SourceRegions');
    opts = TransformOptionsDialog( ...
        'Description', ['Inverts every bin onto the template cortex and averages the ' ...
            'vertices of each region of an atlas, giving a dataset whose channels are ' ...
            'regions. Mean magnitude never cancels; signed mean keeps the polarity, with ' ...
            'each vertex flipped to its region''s dominant orientation. The estimate is ' ...
            'Source Estimate''s, with the same settings.'], ...
        'title', 'Source Regions options', ...
        'separator', 'Regions:', ...
        {'Atlas'; 'Atlas'}, TransTools.PutFirst(ATLASES, TransTools.FieldOr(stored, 'Atlas', ATLASES{1})), ...
        {'Region value'; 'Value'}, TransTools.PutFirst(VALUES, TransTools.FieldOr(stored, 'Value', VALUES{1})), ...
        'separator', 'Source estimate:', ...
        {'Inverse method'; 'Method'}, TransTools.PutFirst(METHODS, TransTools.FieldOr(stored, 'Method', METHODS{1})), ...
        {'Source space (vertices)'; 'SourceSpace'}, TransTools.PutFirst(SPACES, ...
            char(string(TransTools.FieldOr(stored, 'SourceSpace', SPACES{1})))), ...
        {'Noise covariance'; 'NoiseCovariance'}, TransTools.PutFirst(NOISE, ...
            TransTools.FieldOr(stored, 'NoiseCovariance', NOISE{1})), ...
        {'Signal-to-noise ratio'; 'SNR'}, TransTools.FieldOr(stored, 'SNR', 3), ...
        {'Regularisation (white noise)'; 'RegParam'}, TransTools.FieldOr(stored, 'RegParam', 0.05));
    if isempty(opts)
        EEG = [];       % cancelled: no node, no compute
        opts = [];      % the contract is two outputs; both must be assigned
        return;
    end
    TransformSettings.set('SourceRegions', opts);
end
opts = withDefaults(opts);

% THE ESTIMATE IS SOURCE ESTIMATE'S, over the whole epoch at the data's own
% rate, so the regions keep the input's time axis, and a stored estimate made
% with the same settings is the one used.
signed = strcmpi(opts.Value, 'Signed mean');
orientation = 'magnitude';
if signed
    orientation = 'normal';
end
method = lower(char(string(opts.Method)));
if strcmp(method, 'dspm')
    method = 'mne';
end
space = double(str2double(string(opts.SourceSpace)));
estimateOpts = struct('Method', method, 'Orientation', orientation, 'SourceSpace', space, ...
    'TimeWindow', [], 'ResampleHz', [], 'RegParam', opts.RegParam, ...
    'NoiseCovariance', opts.NoiseCovariance, 'SNR', opts.SNR);
withEstimate = SourceEstimate(input, estimateOpts);
estimate = withEstimate.sourceEstimate(end);

labels = {withEstimate.ScalpChanlocs.labels};
[~, sourcemodel] = TransTools.BuildSourceForwardModel(labels, space);
[vertexRegion, regionNames] = TransTools.AtlasVertexLabels(sourcemodel, lower(opts.Atlas));
values = estimate.values;                        % vertices x time x bin

% A vertex the estimate has no value for (outside the head model) takes no
% part, and a region with no vertex left is not a channel.
vertexRegion(all(all(~isfinite(values), 2), 3)) = 0;
present = unique(vertexRegion(vertexRegion > 0));
[~, compact] = ismember(vertexRegion, present);  % 0 stays 0
regionNames = regionNames(present);
counts = accumarray(compact(compact > 0), 1, [numel(present) 1])';

if signed
    values = values .* regionFlips(TransTools.SurfaceNormals(sourcemodel), compact);
end

% FIELDTRIP DOES THE COMBINING: the estimate as a FieldTrip source, the atlas
% as a FieldTrip parcellation on the same vertices, and ft_sourceparcellate's
% own mean.
source = struct('pos', sourcemodel.pos, 'unit', 'mm', 'time', reshape(estimate.times, 1, []) / 1000, ...
    'dimord', 'pos_time');
parcellation = struct('pos', sourcemodel.pos, 'unit', 'mm', 'region', compact(:), ...
    'regionlabel', {regionNames(:)});
cfg = struct('method', 'mean', 'parcellation', 'region', 'parameter', 'pow', 'feedback', 'no');
nBins = size(values, 3);
data = nan(numel(regionNames), numel(estimate.times), nBins);
for b = 1:nBins
    source.pow = values(:, :, b);
    parcel = ft_sourceparcellate(cfg, source, parcellation);
    [found, rows] = ismember(regionNames, parcel.label);
    data(found, :, b) = parcel.pow(rows(found), :);
end

EEG = regionDataset(input, data, estimate, regionNames, counts, opts, orientation);
end

% ======================================================================= %
function opts = withDefaults(opts)
    defaults = struct('Atlas', 'AAL', 'Value', 'Mean magnitude', 'Method', 'dSPM', ...
        'SourceSpace', '20484', 'NoiseCovariance', 'auto', 'SNR', 3, 'RegParam', 0.05);
    if ~isstruct(opts)
        opts = struct();
    end
    for field = fieldnames(defaults)'
        if ~isfield(opts, field{1}) || isempty(opts.(field{1}))
            opts.(field{1}) = defaults.(field{1});
        end
    end
end

function flips = regionFlips(normals, region)
%REGIONFLIPS  +1 or -1 per vertex: the sign that turns its normal towards its
%   region's dominant direction (MNE's label_sign_flip). Vertices in no region
%   keep +1; they take no part in any mean.
    flips = ones(size(region, 1), 1);
    for r = 1:max(region)
        here = find(region == r);
        if isempty(here)
            continue;
        end
        [~, ~, V] = svd(normals(here, :), 'econ');
        s = sign(normals(here, :) * V(:, 1));
        if sum(s) < 0
            s = -s;      % the majority keeps its sign: a convention, not a choice of polarity
        end
        s(s == 0) = 1;
        flips(here) = s;
    end
end

function EEG = regionDataset(input, data, estimate, regionNames, counts, opts, orientation)
%REGIONDATASET  The averaged dataset whose channels are the regions.
    EEG = input;
    EEG.data   = data;
    EEG.times  = reshape(estimate.times, 1, []);
    EEG.pnts   = numel(EEG.times);
    EEG.nbchan = numel(regionNames);
    EEG.chanlocs = struct('labels', cellstr(string(regionNames(:)))', 'type', 'source region');
    EEG.chanlocs = EEG.chanlocs(:)';
    if isfield(EEG, 'xmin') && ~isempty(EEG.times)
        EEG.xmin = EEG.times(1) / 1000;
        EEG.xmax = EEG.times(end) / 1000;
    end
    % Nothing per-electrode survives: the error band and SME belong to the
    % electrodes, the noise covariance too, and the vertex estimate is where
    % this came from, not what it is.
    EEG.stErr = nan(size(data));
    EEG.aSME  = nan(size(data, 1), size(data, 3));
    for field = {'noiseCov', 'noiseCovInfo', 'sourceEstimate', 'ScalpChanlocs', 'ScalpHasPos', ...
            'icaweights', 'icasphere', 'icawinv', 'icaact', 'icachansind', 'chaninfo'}
        if isfield(EEG, field{1})
            EEG = rmfield(EEG, field{1});
        end
    end
    EEG.ref = 'source regions';
    info = estimate.info(1);
    EEG.etc.alz.sourceRegions = struct( ...
        'atlas', opts.Atlas, 'value', opts.Value, 'orientation', orientation, ...
        'method', estimate.key.method, 'noiseModel', estimate.key.noiseModel, ...
        'sourceSpace', estimate.key.sourceSpace, 'scaleLabel', info.scaleLabel, ...
        'scaleNote', info.scaleNote, 'regions', {cellstr(string(regionNames(:)))'}, ...
        'nVertices', counts, 'combine', 'ft_sourceparcellate, method mean');
end
