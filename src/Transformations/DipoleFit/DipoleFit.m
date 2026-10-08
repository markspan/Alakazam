function [EEG, opts] = DipoleFit(input, varargin)
%DIPOLEFIT  An equivalent current dipole, or a mirrored pair, fitted to an ERP
%   over a time window: where a single focal generator would have to be to
%   produce the scalp distribution, and how much of it that explains.
%
%   FieldTrip's ft_dipolefitting, on the same template forward model the
%   source estimates use (FieldTrip's template BEM and 10-5 electrodes): a
%   grid search over the brain compartment for the starting point, then a
%   nonlinear fit. The model is FieldTrip's 'regional' one: one position
%   (or one mirrored pair) for the whole window, with a moment that may
%   change over it. A pair is mirrored across the midline (FieldTrip's
%   symmetry 'x'), for a response from both hemispheres at once, such as an
%   early auditory or visual one.
%
%   NOT A DISTRIBUTED ESTIMATE. Source Estimate spreads the scalp map over
%   the whole cortex; this asks which one (or two) points explain it best,
%   which is only meaningful when one focal generator is a fair assumption.
%   The residual variance is the check: the share of the scalp data in the
%   window the dipoles do not reproduce. A low value says the model can
%   explain the map, not that the generator is there: with template anatomy
%   and template electrodes, a position is good to a centimetre or two.
%
%   Stored on the dataset as EEG.dipoleFit, one element per bin fitted:
%   .bin, .window (ms), .model, .pos (dipoles x 3, MNI mm), .region (the AAL
%   region at or near each dipole, by FieldTrip's ft_volumelookup), .mom
%   (3*dipoles x samples), .time (ms), .rv (over the whole window) and .gof
%   (1 - rv), and .rvTime (FieldTrip's own, per sample). The data are not
%   changed.
%
%   Signature (Alakazam transformation contract):
%     [EEG, opts] = DipoleFit(input)        % settings dialog
%     [EEG, opts] = DipoleFit(input, opts)  % replay stored settings
%   OPTS: Bins (labels), WindowStart and WindowStop (ms), Model ('One dipole'
%   | 'Mirrored pair'), GridResolution (mm).
%
%   See also DIPOLEFITWINDOW, FT_DIPOLEFITTING, SOURCEESTIMATE,
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL.
MODELS = {'One dipole', 'Mirrored pair'};

[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:DipoleFit', varargin{:});
if ~isfield(input, 'bindesc') || isempty(input.bindesc) || ~isfield(input, 'data') || isempty(input.data)
    throw(MException('Alakazam:DipoleFit', '%s', ...
        ['I am afraid this dataset has no bins, so there is no ERP to fit. Run DefineBins ' ...
         'and Average first: a dipole is fitted to a bin of an averaged dataset.']));
end

if interactive
    stored = TransformSettings.get('DipoleFit');
    peak = gfpPeak(input);
    opts = TransformOptionsDialog( ...
        'Description', ['Fits one dipole, or a pair mirrored across the midline, to the ' ...
            'scalp distribution of each chosen bin over the window, by FieldTrip on the ' ...
            'template head model. Meaningful when one focal generator is a fair ' ...
            'assumption; the residual variance says how much of the data it leaves ' ...
            'unexplained.'], ...
        'title', 'Dipole Fit options', ...
        'separator', 'Bins to fit:', ...
        {'Bins'; 'Bins'}, DialogFields.Bins(input, TransTools.FieldOr(stored, 'Bins', {input.bindesc(1).label})), ...
        'separator', 'Window and model:', ...
        {'From (ms)'; 'WindowStart'}, TransTools.FieldOr(stored, 'WindowStart', peak - 20), ...
        {'To (ms)'; 'WindowStop'}, TransTools.FieldOr(stored, 'WindowStop', peak + 20), ...
        {'Model'; 'Model'}, TransTools.PutFirst(MODELS, TransTools.FieldOr(stored, 'Model', MODELS{1})), ...
        {'Grid search spacing (mm)'; 'GridResolution'}, TransTools.FieldOr(stored, 'GridResolution', 10));
    if isempty(opts)
        EEG = [];       % cancelled: no node, no compute
        opts = [];      % the contract is two outputs; both must be assigned
        return;
    end
    TransformSettings.set('DipoleFit', opts);
end
opts = withDefaults(opts, input);
if opts.WindowStop <= opts.WindowStart
    throw(MException('Alakazam:DipoleFit', 'I am afraid the window ends before it starts.'));
end

TransTools.ensureFieldTrip('Dipole fits');
EEG = TransTools.ResolveScalpDistribution(input, 'Alakazam:DipoleFit');
labels = {EEG.ScalpChanlocs.labels};
% The 5124-vertex sheet only because building a forward model returns one:
% the dipole fit uses the head model and the electrodes, not the sheet.
[~, ~, resolvedLabels, elec, headmodel] = TransTools.BuildSourceForwardModel(labels, 5124);
[~, reorder] = ismember(lower(resolvedLabels), lower(labels));

binLabels = {EEG.bindesc.label};
wanted = cellstr(string(opts.Bins));
fits = struct('bin', {}, 'window', {}, 'model', {}, 'pos', {}, 'region', {}, ...
    'mom', {}, 'time', {}, 'rv', {}, 'gof', {}, 'rvTime', {});
for k = 1:numel(wanted)
    b = find(strcmp(binLabels, wanted{k}), 1);
    if isempty(b)
        throw(MException('Alakazam:DipoleFit', ...
            'I am afraid this dataset has no bin called "%s".', wanted{k}));
    end
    scalp = EEG.data(EEG.ScalpHasPos, :, b);
    % Not average-referenced here: ft_dipolefitting average-references EEG
    % data itself, as its leadfield is.
    values = double(scalp(reorder, :));
    fits(end + 1) = dipoleFitWindow(values, EEG.times, resolvedLabels, elec, headmodel, opts, wanted{k}); %#ok<AGROW>
end
EEG.dipoleFit = fits;
end

% ======================================================================= %
function opts = withDefaults(opts, input)
    if ~isstruct(opts)
        opts = struct();
    end
    peak = gfpPeak(input);
    defaults = struct('Bins', {{input.bindesc(1).label}}, 'WindowStart', peak - 20, ...
        'WindowStop', peak + 20, 'Model', 'One dipole', 'GridResolution', 10);
    for field = fieldnames(defaults)'
        if ~isfield(opts, field{1}) || isempty(opts.(field{1}))
            opts.(field{1}) = defaults.(field{1});
        end
    end
end

function t = gfpPeak(input)
%GFPPEAK  The latency (ms) of the first bin's largest global field power after
%   the event: where a window is suggested, not where one has to be.
    times = reshape(input.times, 1, []);
    gfp = std(double(input.data(:, :, 1)), 0, 1, 'omitnan');
    gfp(times <= 0) = -Inf;
    [~, at] = max(gfp);
    t = round(times(at));
end
