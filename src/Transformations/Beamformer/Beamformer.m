function [EEG, opts] = Beamformer(input, varargin)
%BEAMFORMER  Where power changes between a baseline and an active window, by
%   FieldTrip's beamformers: LCMV in the time domain, DICS at a frequency.
%
%   An adaptive spatial filter is computed for every location of a source
%   model from the trials themselves (their covariance, or their
%   cross-spectral density), and the power each filter passes is compared
%   between an active window and a baseline window of the same length:
%   (active - baseline) / baseline, FieldTrip's relative change. Both are
%   FieldTrip's own: ft_timelockanalysis and ft_freqanalysis estimate the
%   covariance and the cross-spectra, and ft_sourceanalysis computes the
%   filters ('lcmv', 'dics') and the power.
%
%   ONE FILTER FOR EVERY BIN AND BOTH WINDOWS, as FieldTrip recommends for a
%   contrast: computed once from the covariance (or cross-spectra) of both
%   windows over every chosen bin's trials, then applied to each bin and
%   window. A difference between bins or windows is then a difference in the
%   data, not in the filters.
%
%   TWO SOURCE MODELS. The template cortical sheet the other source
%   estimates use, drawn in the view on the cortex; or a regular volume
%   grid inside the template brain (FieldTrip's ft_prepare_sourcemodel),
%   which is what beamformers are usually computed on, drawn in the view on
%   slices of FieldTrip's template MRI (ft_sourceinterpolate).
%
%   NEEDS TRIALS, not an average: the filters are made from the variability
%   across them. Trials rejected anywhere in the two windows are left out.
%   The output is the average of the input (as Average makes it), with the
%   maps stored beside it as EEG.beamformer: .method, .sourceModel, .pos,
%   .inside, .dim (grid) or .tri (sheet), .bins, .values (sources x bins),
%   .peakPos and .peakRegion per bin, the windows, the frequency and the
%   regularisation.
%
%   Signature (Alakazam transformation contract):
%     [EEG, opts] = Beamformer(input)        % settings dialog
%     [EEG, opts] = Beamformer(input, opts)  % replay stored settings
%   OPTS: Bins, Method ('LCMV (time domain)' | 'DICS (frequency)'),
%   Frequency and Smoothing (Hz, DICS), ActiveStart/ActiveStop and
%   BaselineStart/BaselineStop (ms), SourceModel ('Cortical sheet' |
%   'Volume grid'), SourceSpace (sheet vertices), GridResolution (mm),
%   Lambda (%, of the mean sensor power).
%
%   See also FT_SOURCEANALYSIS, SOURCEESTIMATE, BEAMFORMERVIEW.
METHODS = {'LCMV (time domain)', 'DICS (frequency)'};
MODELS  = {'Cortical sheet', 'Volume grid'};
SPACES  = {'5124', '8196', '20484'};

[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Beamformer', varargin{:});
if ~isfield(input, 'bindesc') || isempty(input.bindesc) || ~isfield(input, 'trials') || input.trials < 2
    throw(MException('Alakazam:Beamformer', '%s', ...
        ['I am afraid a beamformer needs the single trials of an epoched dataset with bins: ' ...
         'its filters are made from the variability across trials. Run it before Average.']));
end

if interactive
    stored = TransformSettings.get('Beamformer');
    opts = TransformOptionsDialog( ...
        'Description', ['Compares the power that adaptive spatial filters pass in an active ' ...
            'window with a baseline window of the same length, at every location of the ' ...
            'source model: LCMV for power in the time domain, DICS for power at one ' ...
            'frequency. One filter, from both windows of every chosen bin, is applied to ' ...
            'each bin. Computed by FieldTrip.'], ...
        'title', 'Beamformer options', ...
        'separator', 'Bins:', ...
        {'Bins'; 'Bins'}, DialogFields.Bins(input, TransTools.FieldOr(stored, 'Bins', ...
            {input.bindesc(arrayfun(@(d) isempty(d.combo), input.bindesc)).label}), 'Differences', false), ...
        'separator', 'Method:', ...
        {'Method'; 'Method'}, TransTools.PutFirst(METHODS, TransTools.FieldOr(stored, 'Method', METHODS{1})), ...
        {'Frequency (Hz, DICS)'; 'Frequency'}, TransTools.FieldOr(stored, 'Frequency', 10), ...
        {'Smoothing (Hz, DICS)'; 'Smoothing'}, TransTools.FieldOr(stored, 'Smoothing', 4), ...
        'separator', 'Windows (ms):', ...
        {'Active from'; 'ActiveStart'}, TransTools.FieldOr(stored, 'ActiveStart', 300), ...
        {'Active to'; 'ActiveStop'}, TransTools.FieldOr(stored, 'ActiveStop', 500), ...
        {'Baseline from'; 'BaselineStart'}, TransTools.FieldOr(stored, 'BaselineStart', -200), ...
        {'Baseline to'; 'BaselineStop'}, TransTools.FieldOr(stored, 'BaselineStop', 0), ...
        'separator', 'Source model:', ...
        {'Source model'; 'SourceModel'}, TransTools.PutFirst(MODELS, TransTools.FieldOr(stored, 'SourceModel', MODELS{1})), ...
        {'Sheet vertices'; 'SourceSpace'}, TransTools.PutFirst(SPACES, ...
            char(string(TransTools.FieldOr(stored, 'SourceSpace', SPACES{1})))), ...
        {'Grid spacing (mm)'; 'GridResolution'}, TransTools.FieldOr(stored, 'GridResolution', 10), ...
        {'Regularisation (%)'; 'Lambda'}, TransTools.FieldOr(stored, 'Lambda', 5));
    if isempty(opts)
        EEG = [];       % cancelled: no node, no compute
        opts = [];      % the contract is two outputs; both must be assigned
        return;
    end
    TransformSettings.set('Beamformer', opts);
end
opts = withDefaults(opts, input);
checkWindows(opts, input.times);

TransTools.ensureFieldTrip('Beamformers');
% THE CHANNELS EVERY SOURCE VIEW RESOLVES (those with a template position),
% found on a one-trial stand-in, since that resolution is made for averaged
% data and only the channel list is wanted from it.
proxy = input;
proxy.data = input.data(:, :, 1);
proxy.trials = 1;
proxy.DataFormat = 'AVERAGED';
resolved = TransTools.ResolveScalpDistribution(proxy, 'Alakazam:Beamformer');
scalpView = input;
scalpView.ScalpHasPos = resolved.ScalpHasPos;
labels = {resolved.ScalpChanlocs.labels};
[model, resolvedLabels, elec, headmodel] = sourceModel(labels, opts);
[~, reorder] = ismember(lower(resolvedLabels), lower(labels));

% The chosen bins' trials, on the forward model's channels in its order,
% average-referenced as the leadfield is; a trial rejected anywhere in the
% two windows takes no part, since FieldTrip cannot take a NaN.
binLabels = {input.bindesc.label};
wanted = cellstr(string(opts.Bins));
[raw, trialBin] = fieldtripTrials(scalpView, reorder, resolvedLabels, elec, wanted, binLabels, opts);

isDics = startsWith(opts.Method, 'DICS');
if isDics
    [values, nTrials] = dicsContrast(raw, trialBin, numel(wanted), model, headmodel, elec, opts);
else
    [values, nTrials] = lcmvContrast(raw, trialBin, numel(wanted), model, headmodel, elec, opts);
end

% The average of the input, as Average makes it, with the maps beside it.
EEG = Average(input, struct());
EEG.beamformer = describe(values, nTrials, wanted, model, opts, isDics);
end

% ======================================================================= %
function opts = withDefaults(opts, input)
    if ~isstruct(opts)
        opts = struct();
    end
    ordinary = input.bindesc(arrayfun(@(d) ~isfield(d, 'combo') || isempty(d.combo), input.bindesc));
    defaults = struct('Bins', {{ordinary.label}}, 'Method', 'LCMV (time domain)', ...
        'Frequency', 10, 'Smoothing', 4, 'ActiveStart', 300, 'ActiveStop', 500, ...
        'BaselineStart', -200, 'BaselineStop', 0, 'SourceModel', 'Cortical sheet', ...
        'SourceSpace', '5124', 'GridResolution', 10, 'Lambda', 5);
    for field = fieldnames(defaults)'
        if ~isfield(opts, field{1}) || isempty(opts.(field{1}))
            opts.(field{1}) = defaults.(field{1});
        end
    end
end

function checkWindows(opts, times)
%CHECKWINDOWS  Two windows inside the epoch, of the same length, as
%   FieldTrip asks of a contrast between them: a covariance or a spectrum
%   from more samples is a better estimate, and would differ for that alone.
    active = [opts.ActiveStart, opts.ActiveStop];
    base   = [opts.BaselineStart, opts.BaselineStop];
    if diff(active) <= 0 || diff(base) <= 0
        throw(MException('Alakazam:Beamformer', 'I am afraid a window ends before it starts.'));
    end
    if min([active, base]) < min(times) || max([active, base]) > max(times)
        throw(MException('Alakazam:Beamformer', ...
            'I am afraid a window reaches outside the epoch (%g to %g ms).', min(times), max(times)));
    end
    step = median(diff(times));
    if abs(diff(active) - diff(base)) > step
        throw(MException('Alakazam:Beamformer', ['I am afraid the two windows are of ' ...
            'different lengths (%g and %g ms). Their power is compared, and a covariance or a ' ...
            'spectrum from more samples differs for that reason alone, so FieldTrip asks for ' ...
            'equal windows.'], diff(active), diff(base)));
    end
end

function [model, resolvedLabels, elec, headmodel] = sourceModel(labels, opts)
%SOURCEMODEL  The leadfield to scan: the template cortical sheet, or a
%   regular grid inside the template brain.
    if strcmpi(opts.SourceModel, 'Volume grid')
        [~, ~, resolvedLabels, elec, headmodel] = TransTools.BuildSourceForwardModel(labels, 5124);
        model = gridLeadfield(resolvedLabels, elec, headmodel, opts.GridResolution);
        model.kind = 'grid';
    else
        space = str2double(string(opts.SourceSpace));
        [model, sheet, resolvedLabels, elec, headmodel] = TransTools.BuildSourceForwardModel(labels, space);
        model.tri  = sheet.tri;
        model.kind = 'cortex';
    end
end

function leadfield = gridLeadfield(labels, elec, headmodel, resolution)
%GRIDLEADFIELD  FieldTrip's regular grid inside the template brain, and its
%   leadfield. Kept for the session, since it depends only on the channels
%   and the spacing.
    persistent cache
    key = sprintf('%s|%g', strjoin(lower(labels), ','), resolution);
    if ~isempty(cache) && isKey(cache, key)
        leadfield = cache(key);
        return;
    end
    cfg = struct('headmodel', headmodel, 'elec', elec, 'resolution', resolution, ...
        'unit', 'mm', 'feedback', 'no'); %#ok<NASGU> used in evalc
    [~, grid] = evalc('ft_prepare_sourcemodel(cfg);');
    cfg = struct('sourcemodel', grid, 'headmodel', headmodel, 'elec', elec, ...
        'channel', {labels}, 'feedback', 'no'); %#ok<NASGU> used in evalc
    [~, leadfield] = evalc('ft_prepare_leadfield(cfg);');
    if isempty(cache)
        cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end
    cache(key) = leadfield;
end

function [raw, trialBin] = fieldtripTrials(EEG, reorder, labels, elec, wanted, binLabels, opts)
%FIELDTRIPTRIALS  The chosen bins' clean trials as FieldTrip raw data, and
%   the bin each trial belongs to.
    times = reshape(EEG.times, 1, []);
    inWindows = (times >= opts.BaselineStart & times <= opts.BaselineStop) | ...
                (times >= opts.ActiveStart & times <= opts.ActiveStop);
    raw = struct('label', {labels(:)}, 'trial', {{}}, 'time', {{}}, 'elec', elec, ...
        'fsample', EEG.srate);
    trialBin = [];
    scalp = EEG.data(EEG.ScalpHasPos, :, :);
    for b = 1:numel(wanted)
        index = find(strcmp(binLabels, wanted{b}), 1);
        if isempty(index)
            throw(MException('Alakazam:Beamformer', ...
                'I am afraid this dataset has no bin called "%s".', wanted{b}));
        end
        for t = reshape(TransTools.BinTrials(EEG, index), 1, [])
            x = double(scalp(reorder, :, t));
            if any(~isfinite(x(:, inWindows)), 'all')
                continue;    % rejected somewhere in the windows
            end
            raw.trial{end + 1} = x - mean(x, 1);
            raw.time{end + 1}  = times / 1000;
            trialBin(end + 1)  = b; %#ok<AGROW>
        end
    end
    for b = 1:numel(wanted)
        if nnz(trialBin == b) < 2
            throw(MException('Alakazam:Beamformer', ['I am afraid bin "%s" has fewer than ' ...
                'two clean trials in these windows, so its covariance cannot be estimated.'], wanted{b}));
        end
    end
end

function [values, nTrials] = lcmvContrast(raw, trialBin, nBins, model, headmodel, elec, opts)
%LCMVCONTRAST  FieldTrip's LCMV: covariances by ft_timelockanalysis, one
%   filter from both windows of every trial, then each bin's power in each
%   window through it.
    base   = [opts.BaselineStart, opts.BaselineStop] / 1000;
    active = [opts.ActiveStart, opts.ActiveStop] / 1000;
    allTrials = 1:numel(raw.trial);
    pre  = covarianceOf(raw, allTrials, base);
    post = covarianceOf(raw, allTrials, active);
    common = post;
    common.cov = (pre.cov + post.cov) / 2;
    filter = sourcePower(common, model, headmodel, elec, 'lcmv', opts, []);

    values  = nan(numel(model.inside), nBins);
    nTrials = zeros(1, nBins);
    for b = 1:nBins
        trials = find(trialBin == b);
        nTrials(b) = numel(trials);
        [~, powPre]  = sourcePower(covarianceOf(raw, trials, base), model, headmodel, elec, 'lcmv', opts, filter);
        [~, powPost] = sourcePower(covarianceOf(raw, trials, active), model, headmodel, elec, 'lcmv', opts, filter);
        values(:, b) = (powPost - powPre) ./ powPre;
    end
end

function [values, nTrials] = dicsContrast(raw, trialBin, nBins, model, headmodel, elec, opts)
%DICSCONTRAST  FieldTrip's DICS: cross-spectra at the frequency by
%   ft_freqanalysis (multitaper), one filter from both windows of every
%   trial, then each bin's power in each window through it.
    base   = [opts.BaselineStart, opts.BaselineStop] / 1000;
    active = [opts.ActiveStart, opts.ActiveStop] / 1000;
    allTrials = 1:numel(raw.trial);
    pre  = spectrumOf(raw, allTrials, base, opts);
    post = spectrumOf(raw, allTrials, active, opts);
    common = post;
    common.crsspctrm = (pre.crsspctrm + post.crsspctrm) / 2;
    common.powspctrm = (pre.powspctrm + post.powspctrm) / 2;
    filter = sourcePower(common, model, headmodel, elec, 'dics', opts, []);

    values  = nan(numel(model.inside), nBins);
    nTrials = zeros(1, nBins);
    for b = 1:nBins
        trials = find(trialBin == b);
        nTrials(b) = numel(trials);
        [~, powPre]  = sourcePower(spectrumOf(raw, trials, base, opts), model, headmodel, elec, 'dics', opts, filter);
        [~, powPost] = sourcePower(spectrumOf(raw, trials, active, opts), model, headmodel, elec, 'dics', opts, filter);
        values(:, b) = (powPost - powPre) ./ powPre;
    end
end

function tl = covarianceOf(raw, trials, window) %#ok<INUSD> raw is used in evalc
    cfg = struct('trials', trials, 'covariance', 'yes', 'covariancewindow', window, ...
        'feedback', 'no'); %#ok<NASGU> used in evalc
    [~, tl] = evalc('ft_timelockanalysis(cfg, raw);');
end

function freq = spectrumOf(raw, trials, window, opts) %#ok<INUSD> raw is used in evalc
    cfg = struct('trials', trials, 'toilim', window, 'feedback', 'no'); %#ok<NASGU> used in evalc
    [~, segment] = evalc('ft_redefinetrial(cfg, raw);'); %#ok<ASGLU> used in evalc
    cfg = struct('method', 'mtmfft', 'output', 'powandcsd', 'taper', 'dpss', ...
        'tapsmofrq', opts.Smoothing, 'foilim', [opts.Frequency opts.Frequency], ...
        'keeptrials', 'no', 'feedback', 'no'); %#ok<NASGU> used in evalc
    [~, freq] = evalc('ft_freqanalysis(cfg, segment);');
end

function [filter, power] = sourcePower(data, model, headmodel, elec, method, opts, filter) %#ok<INUSD> data is used in evalc
%SOURCEPOWER  ft_sourceanalysis with METHOD: computing the filter when
%   FILTER is empty, applying it when not.
    cfg = struct('method', method, 'headmodel', headmodel, 'elec', elec, 'feedback', 'no');
    cfg.sourcemodel = rmfield(model, intersect(fieldnames(model), {'kind', 'tri'}));
    cfg.(method) = struct('keepfilter', 'yes', 'lambda', sprintf('%g%%', opts.Lambda), ...
        'fixedori', 'yes', 'projectnoise', 'no');
    if strcmp(method, 'dics')
        cfg.frequency = opts.Frequency;
    end
    if ~isempty(filter)
        cfg.sourcemodel.filter = filter; %#ok<STRNU> used in evalc
    end
    [~, source] = evalc('ft_sourceanalysis(cfg, data);');
    filter = source.avg.filter;
    power = source.avg.pow(:);
end

function bf = describe(values, nTrials, bins, model, opts, isDics)
%DESCRIBE  The maps, with everything a view or a report needs to say what
%   they are.
    bf = struct();
    bf.method      = lower(strtok(opts.Method));
    bf.sourceModel = model.kind;
    bf.pos         = model.pos;
    bf.inside      = model.inside(:);
    if strcmp(model.kind, 'grid')
        bf.dim = model.dim;
        bf.tri = [];
    else
        bf.dim = [];
        bf.tri = model.tri;
    end
    bf.bins     = bins;
    bf.values   = values;
    bf.nTrials  = nTrials;
    bf.active   = [opts.ActiveStart, opts.ActiveStop];
    bf.baseline = [opts.BaselineStart, opts.BaselineStop];
    bf.frequency = NaN;
    bf.smoothing = NaN;
    if isDics
        bf.frequency = opts.Frequency;
        bf.smoothing = opts.Smoothing;
    end
    bf.lambda   = opts.Lambda;
    bf.contrast = '(active - baseline) / baseline';
    bf.peakPos  = nan(numel(bins), 3);
    for b = 1:numel(bins)
        [~, at] = max(abs(values(:, b)));
        bf.peakPos(b, :) = model.pos(at, :);
    end
    bf.peakRegion = TransTools.AtlasRegionsAt(bf.peakPos);
end
