function [EEG, info] = fitBins(input, varargin)
%FITBINS  One overlap-corrected waveform per bin, from continuous data.
%   [EEG, INFO] = Unfold.fitBins(INPUT) fits the model Unfold.binModel builds
%   from DefineBins' bins and returns it in the shape Average returns:
%   DataFormat "Averaged", channels x samples x bins, the same EEG.bindesc,
%   so Measure, ScalpDistribution, GrandAverage and the reports read it
%   without knowing it came from a regression. INFO carries the model, the
%   notes and what was excluded.
%
%   THE ALTERNATIVE TO EPOCH-AND-AVERAGE, not a replacement for it. Averaging
%   assumes each epoch holds the response to its own event and nothing else.
%   Where events follow each other faster than the response decays, that
%   assumption is wrong and the average of a bin carries a smear of whatever
%   came before and after it. This fits all the bins at once against the
%   whole continuous recording, so a sample explained by two events is
%   attributed to both, and what comes out is the response to each bin with
%   the others' overlap removed (Ehinger & Dimigen, 2019; Dimigen & Ehinger,
%   2021, J Vis 21(1):3).
%
%   IT NEEDS DATA WITHOUT A DC OFFSET, and refuses data that has one. A
%   time-expanded design has no constant term, so whatever mean voltage a
%   channel carries has to be explained by the event responses, and the
%   betas come back in the thousands of microvolts. Epoch-and-average never
%   shows this because Baseline subtracts the offset epoch by epoch, so a
%   DC-coupled recording (BioSemi and the like, tens of millivolts of
%   electrode offset) averages perfectly and deconvolves into nonsense. The
%   remedy belongs upstream, in DCDetrend or a high-pass Filter, not here:
%   silently de-meaning someone's data would hide the one fact that decides
%   whether the numbers mean anything.
%
%   Options, all with paper-grounded defaults:
%     WindowMs           [-200 800], the response window per event. It should
%                        cover the whole response, including anything that
%                        precedes the event (a saccade's own motor activity
%                        precedes the fixation it produces).
%     BaselineMs         the window the fitted waveforms are baseline-
%                        corrected over, by default the pre-event part of
%                        WindowMs. A beta is a regression coefficient, so its
%                        zero is wherever the model put it, and comparing one
%                        with an average (which Baseline has corrected) means
%                        correcting this the same way. [] leaves the betas
%                        exactly as the solver returned them.
%     OtherEvents        which event codes in no bin to fit as nuisance and
%                        drop from the result: 'all' (default), a cellstr of
%                        codes, or {} for none. See Unfold.binModel for why
%                        this is a choice per code. The older
%                        ModelOtherEvents true/false still works.
%     Covariates         event fields to fit alongside each bin, mean-centred
%                        (see Unfold.binModel): their slopes are fitted and
%                        dropped, so the result is still one waveform per bin,
%                        but one from which the covariate's variance has been
%                        taken out. Unfold.eventCovariates lists what a
%                        dataset offers.
%     ArtifactThresholdUv, ArtifactWindowMs, ArtifactStepMs
%                        150 uV in a 2000 ms window stepped by 100 ms, which
%                        are the toolbox's own defaults and the paper's
%                        larger dataset. Bad intervals are EXCLUDED BY
%                        ZEROING the design matrix there, not by cutting
%                        epochs: the surrounding data still contributes, and
%                        an event near a bad stretch does not lose its whole
%                        epoch. Set the threshold to 0 to skip detection;
%                        the recording's own boundaries (cuts) are left out
%                        either way, since a window spanning one is fitted
%                        across a join between moments that were never
%                        adjacent.
%                        The threshold is PEAK-TO-PEAK within each moving
%                        window: uf_continuousArtifactDetect hands it to
%                        ERPLAB's basicrap without a threshold type, whose
%                        default is 'peak-to-peak'. Its own header says
%                        "[-lim +lim] is marked", which reads like an
%                        absolute limit and is not what the code does
%                        (checked in basicrap.m, unfold 1.3.1). So a standing
%                        offset does not trip it; drifts, blinks and, in
%                        free viewing, eye movements within a window do.
%     Channels           which channels the artifact scan looks at. The
%                        default is the scalp EEG (eegChannelMask), not every
%                        channel: an EOG channel's range is several times the
%                        EEG's, so scanning it marks most of the recording bad
%                        and takes the bins' data with it.
%
%   WHAT THE RESULT DOES NOT CARRY is a standard error of its own. Average's
%   .stErr is the spread of the trials that went into a mean, and a
%   regression coefficient has no trials to spread; it has a standard error
%   from the model's residuals, which the lsmr solver used here does not
%   return. Rather than leave the field out, which AverageView indexes
%   unguarded, it is filled with zeros, exactly as that view does for any
%   series with no error available, and the provenance in EEG.etc.alz.unfold
%   records that there is none. Across-subject error bars in the reports are
%   unaffected: those come from the grand average, not from this.
%
%   See also UNFOLD.BINMODEL, UNFOLD.ENSURE, AVERAGE, DEFINEBINS.
    parsed = inputParser();
    parsed.addParameter('WindowMs', [-200 800], @(v) isnumeric(v) && numel(v) == 2 && v(1) < v(2));
    parsed.addParameter('BaselineMs', 'pre-event', ...
        @(v) isempty(v) || (ischar(v) || isstring(v)) || (isnumeric(v) && numel(v) == 2 && v(1) < v(2)));
    parsed.addParameter('ModelOtherEvents', true, @(v) islogical(v) && isscalar(v));
    parsed.addParameter('OtherEvents', 'all', @(v) isempty(v) || ischar(v) || iscellstr(v) || isstring(v));
    parsed.addParameter('Covariates', {}, @(v) isempty(v) || iscellstr(v) || isstring(v));
    parsed.addParameter('ArtifactThresholdUv', 150, @(v) isnumeric(v) && isscalar(v) && v >= 0);
    parsed.addParameter('ArtifactWindowMs', 2000, @(v) isnumeric(v) && isscalar(v) && v > 0);
    parsed.addParameter('ArtifactStepMs', 100, @(v) isnumeric(v) && isscalar(v) && v > 0);
    parsed.addParameter('Channels', [], @(v) isnumeric(v));
    parsed.parse(varargin{:});
    opts = parsed.Results;
    opts.BaselineMs = resolveBaseline(opts.BaselineMs, opts.WindowMs);

    requireCentredData(input);
    % OtherEvents is passed only when it was given, so the older
    % ModelOtherEvents switch keeps meaning what it meant for a caller that
    % still uses it (binModel lets OtherEvents win when both arrive).
    modelArgs = {'ModelOtherEvents', opts.ModelOtherEvents, 'Covariates', opts.Covariates};
    if ~ismember('OtherEvents', parsed.UsingDefaults)
        modelArgs = [modelArgs, {'OtherEvents', opts.OtherEvents}];
    end
    plan = Unfold.binModel(input, modelArgs{:});
    if isempty(plan.eventTypes)
        throw(MException('Alakazam:Unfold:NothingToFit', ...
            ['None of this dataset''s bins hold any events, so there is no model to fit. ' ...
             'Check the bin definitions against the events the recording actually has.']));
    end
    Unfold.ensure('Deconvolution (rERP)');

    work = input;
    work.event = plan.events;
    srate = double(input.srate);

    % 1. The design: one intercept per event type (see Unfold.binModel).
    work = uf_designmat(work, 'eventtypes', cellfun(@(t) {t}, plan.eventTypes, 'UniformOutput', false), ...
        'formula', plan.formulas);

    % 2. Time expansion: the design matrix gains one column per predictor per
    %    time point in the window, which is what makes the fit a
    %    deconvolution rather than a regression on epochs.
    work = uf_timeexpandDesignmat(work, 'timelimits', opts.WindowMs / 1000);

    % 3. What not to model: artifacts by the paper's method, and the
    %    recording's own cuts. A boundary is a join, so the samples around it
    %    are two different moments stitched together and an event window that
    %    spans one is being fitted across a discontinuity. The toolbox drops
    %    boundary events from the design (Unfold.binModel) but knows nothing
    %    about the data around them, which is why the interval is added here,
    %    through the toolbox's own combiner.
    channels = opts.Channels;
    if isempty(channels)
        channels = scalpChannels(input);
    end
    excluded = boundaryIntervals(input, opts.WindowMs, srate);
    if opts.ArtifactThresholdUv > 0
        detected = uf_continuousArtifactDetect(forArtefactScan(work), ...
            'amplitudeThreshold', opts.ArtifactThresholdUv, ...
            'windowsize', opts.ArtifactWindowMs, ...
            'stepsize', opts.ArtifactStepMs, ...
            'channels', channels);
        excluded = combineIntervals(excluded, detected);
    end
    if ~isempty(excluded)
        % Checked before the fit, not after: a design with most of its rows
        % zeroed takes minutes to not converge, and the answer it then
        % gives is unusable anyway. Refusing here costs the user the wait
        % and tells them which knob to turn.
        requireEnoughDataLeft(excluded, size(input.data, 2), opts, numel(channels));
        work = uf_continuousArtifactExclude(work, 'winrej', excluded);
    end

    % 4. The fit, and the condensed per-predictor time courses. The solver
    %    warns rather than fails when it runs out of iterations, and an
    %    under-converged fit looks like a result, so the warning is caught and
    %    carried into the notes instead of scrolling past in the log.
    lastwarn('');
    work = uf_glmfit(work);
    [solverWarning, ~] = lastwarn();
    if contains(lower(solverWarning), 'did not converge')
        plan.notes{end + 1} = ['The solver ran out of iterations before it converged, for at ' ...
            'least one channel, so these waveforms are an unfinished estimate. That usually ' ...
            'means the design is close to collinear (bins whose events keep a near-constant ' ...
            'lag) or that a lot of the data was excluded as artefact.'];
    end
    result = uf_condense(work);

    [EEG, info] = package(input, plan, result, opts, excluded, srate);
end

% ======================================================================= %
function [EEG, info] = package(input, plan, result, opts, excluded, srate)
%PACKAGE  The fitted betas in Average's own output shape.
    times = reshape(double(result.times) * 1000, 1, []);   % uf_condense reports seconds
    nchan = size(result.beta, 1);
    nbin = numel(input.bindesc);
    data = nan(nchan, numel(times), nbin);

    ordinary = find(~comboMask(input.bindesc));
    fitted = false(1, nbin);
    for k = 1:numel(plan.binTypes)
        column = interceptColumn(result, plan.binTypes{k});
        if isempty(column)
            continue;   % a bin with no events: left as NaN, and noted by binModel
        end
        data(:, :, ordinary(k)) = result.beta(:, :, column);
        fitted(ordinary(k)) = true;
    end
    requireFiniteBetas(data, fitted, input.bindesc, opts);
    data = applyBaseline(data, fitted, times, opts.BaselineMs);
    data = resolveComboBins(data, input.bindesc);

    EEG = input;
    EEG.data = data;
    EEG.times = times;
    EEG.pnts = numel(times);
    EEG.trials = 1;
    EEG.xmin = times(1) / 1000;
    EEG.xmax = times(end) / 1000;
    EEG.DataFormat = "Averaged";
    EEG.ntrials = sum(plan.binCounts);
    EEG.stErr = zeros(size(data));      % see this file's header: there is none
    EEG.aSME = nan(nchan, nbin);
    for k = 1:numel(ordinary)
        EEG.bindesc(ordinary(k)).n = plan.binCounts(k);
    end

    info = struct('window', opts.WindowMs, 'baseline', opts.BaselineMs, ...
        'binLabels', {plan.binLabels}, ...
        'binTypes', {plan.binTypes}, 'binCounts', plan.binCounts, ...
        'nuisanceTypes', {plan.nuisanceTypes}, 'covariates', {plan.covariates}, ...
        'notes', {plan.notes}, ...
        'excludedIntervals', excluded, ...
        'excludedSeconds', sum(diff(excluded, 1, 2)) / srate, ...
        'recordingSeconds', size(input.data, 2) / srate, ...
        'artifact', struct('thresholdUv', opts.ArtifactThresholdUv, ...
                           'windowMs', opts.ArtifactWindowMs, 'stepMs', opts.ArtifactStepMs), ...
        'hasStandardError', false);
    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc)
        EEG.etc = struct();
    end
    if ~isfield(EEG.etc, 'alz') || ~isstruct(EEG.etc.alz)
        EEG.etc.alz = struct();
    end
    EEG.etc.alz.unfold = info;

    for k = 1:numel(plan.notes)
        warning('Alakazam:Unfold:design', '%s', plan.notes{k});
    end
end

function window = resolveBaseline(requested, responseWindow)
%RESOLVEBASELINE  The baseline window, defaulting to the pre-event part of the
%   response window. A response window that starts at or after the event has
%   no pre-event part, so there is nothing to default to and the correction is
%   left off rather than invented.
    if isempty(requested)
        window = [];
        return;
    end
    if ischar(requested) || isstring(requested)
        if responseWindow(1) >= 0
            window = [];
        else
            window = [responseWindow(1) 0];
        end
        return;
    end
    window = reshape(double(requested), 1, 2);
    if window(1) < responseWindow(1) || window(2) > responseWindow(2)
        throw(MException('Alakazam:Unfold:Baseline', '%s', sprintf([ ...
            'The baseline window (%g to %g ms) reaches outside the response window (%g to ' ...
            '%g ms), so part of it was never fitted and there is nothing there to average. ' ...
            'Would you either move the baseline inside the response window or widen the ' ...
            'response window to cover it?'], window(1), window(2), ...
            responseWindow(1), responseWindow(2))));
    end
end

function data = applyBaseline(data, fitted, times, window)
%APPLYBASELINE  Each fitted waveform, shifted so its baseline window averages
%   zero. Combination bins are resolved afterwards, and a difference of two
%   corrected waveforms is the correction of their difference, so they inherit
%   it rather than needing their own.
    if isempty(window)
        return;
    end
    inWindow = times >= window(1) & times <= window(2);
    for b = find(fitted)
        slice = data(:, :, b);
        data(:, :, b) = slice - mean(slice(:, inWindow), 2);
    end
end

function intervals = boundaryIntervals(EEG, windowMs, srate)
%BOUNDARYINTERVALS  The samples around each cut in the recording, as a winrej
%   array. A response window reaching across a boundary is fitted across the
%   join between two moments that were never adjacent, so the window's worth
%   of samples on each side of the cut is left out of the model.
    intervals = zeros(0, 2);
    if ~isfield(EEG, 'event') || isempty(EEG.event) || ~isfield(EEG.event, 'type')
        return;
    end
    types = arrayfun(@(e) char(string(e.type)), EEG.event, 'UniformOutput', false);
    cuts = double([EEG.event(strcmpi(types, 'boundary')).latency]);
    if isempty(cuts)
        return;
    end
    reach = ceil(max(abs(windowMs)) * srate / 1000);
    npnts = size(EEG.data, 2);
    intervals = [max(1, round(cuts(:)) - reach), min(npnts, round(cuts(:)) + reach)];
    intervals = intervals(intervals(:, 1) < intervals(:, 2), :);
end

function intervals = combineIntervals(a, b)
%COMBINEINTERVALS  Two winrej arrays as one, with overlaps merged, so the
%   share of the recording left out is counted once rather than twice.
    if isempty(a); intervals = b; return; end
    if isempty(b); intervals = a; return; end
    intervals = uf_combineWinrej(a, b);
end

function EEG = forArtefactScan(EEG)
%FORARTEFACTSCAN  A copy shaped the way the ERPLAB scan expects a dataset.
%   The scan is ERPLAB's crap.m, and it reads two fields that EEGLAB always
%   writes but an Alakazam dataset need not carry: {chanlocs.type}, to warn
%   about EYE-EEG channels, and .epoch, to check the data is continuous. Both
%   are absent rather than empty on a dataset whose importer never wrote them,
%   and the scan then fails with a bare "Unrecognized field name" that says
%   nothing about what went wrong. Filled in on the copy handed to the scan, so
%   nothing is written into the dataset the user keeps.
    if ~isempty(EEG.chanlocs) && ~isfield(EEG.chanlocs, 'type')
        [EEG.chanlocs.type] = deal('');
    end
    if ~isfield(EEG, 'epoch')
        EEG.epoch = [];
    end
end

function channels = scalpChannels(EEG)
%SCALPCHANNELS  Which channels the artefact scan looks at by default: the
%   scalp EEG. An EOG channel swings several times as far as the EEG, so
%   including it means the scan reports the eyes rather than the data.
    channels = 1:size(EEG.data, 1);
    if ~isfield(EEG, 'chanlocs') || numel(EEG.chanlocs) ~= numel(channels)
        return;
    end
    mask = eegChannelMask(EEG.chanlocs);
    if any(mask)
        channels = find(mask);
    end
end

function requireCentredData(EEG)
%REQUIRECENTREDDATA  Refuse a recording whose channels carry a DC offset.
%   The test is scale-free on purpose: a channel whose mean is further from
%   zero than its own variation is dominated by its offset, whatever the
%   units or the gain. Judged on the median channel, so one dead or saturated
%   electrode does not decide it.
    data = double(EEG.data);
    if isempty(data)
        return;
    end
    mu = mean(data, 2);
    sd = std(data, 0, 2);
    ratio = abs(mu) ./ max(sd, eps);
    if median(ratio) <= 1
        return;
    end
    [~, worst] = max(abs(mu));
    label = sprintf('channel %d', worst);
    if isfield(EEG, 'chanlocs') && numel(EEG.chanlocs) >= worst
        label = char(string(EEG.chanlocs(worst).labels));
    end
    throw(MException('Alakazam:Unfold:DcOffset', '%s', sprintf([ ...
        'This recording carries a DC offset that deconvolution cannot work with: the median ' ...
        'channel sits %.1f times its own standard deviation away from zero, and %s averages ' ...
        '%.0f uV. Would you run DCDetrend (order 0 removes the mean, order 1 a linear drift) ' ...
        'or a high-pass Filter on the continuous data first, and deconvolve that?\n\nThe ' ...
        'reason it matters here and not in an average: this fits one waveform per bin against ' ...
        'the whole recording, with no constant term to absorb a standing voltage, so that ' ...
        'offset has to come out of the event responses and the result is thousands of ' ...
        'microvolts of nothing. Epoch-and-average hides it because Baseline subtracts the ' ...
        'offset epoch by epoch, which is why the same file averages perfectly well.'], ...
        median(ratio), label, mu(worst))));
end

function requireEnoughDataLeft(excluded, npnts, opts, nchannels)
%REQUIREENOUGHDATALEFT  Refuse when the artefact scan has taken most of the
%   recording. The threshold is peak-to-peak within a window that is marked
%   whole, so frequent large swings (a drift, blinks, or the eye movements a
%   reading or free-viewing task is made of) can mark nearly everything, and
%   the fit that follows is a slow way of producing NaN.
    marked = sum(diff(excluded, 1, 2));
    fraction = marked / max(npnts, 1);
    if fraction <= 0.5
        return;
    end
    throw(MException('Alakazam:Unfold:TooMuchExcluded', '%s', sprintf([ ...
        'The artefact scan marked %.0f%% of this recording as bad (%d segments, at %g uV ' ...
        'peak-to-peak over %d channel(s)), which leaves too little for the model to be ' ...
        'fitted against. The limit is peak-to-peak within each moving window, and the ' ...
        'whole window is marked, so frequent large swings (a drift, blinks, or the eye ' ...
        'movements a reading or free-viewing task consists of) trip it almost everywhere. ' ...
        'Would you either high-pass or detrend the data first, raise the threshold, or set ' ...
        'it to 0 to leave artefact rejection out of this step?'], ...
        100 * fraction, size(excluded, 1), opts.ArtifactThresholdUv, nchannels)));
end

function requireFiniteBetas(data, fitted, bindesc, opts)
%REQUIREFINITEBETAS  Never hand back a waveform of NaNs. The solver returns
%   them without complaint when the system it was given has no answer, and a
%   plot of NaN looks like a bug in the app rather than a fact about the fit,
%   so the fit says so itself.
    bad = false(1, numel(fitted));
    for b = find(fitted)
        bad(b) = ~all(isfinite(data(:, :, b)), 'all');
    end
    if ~any(bad)
        return;
    end
    labels = arrayfun(@(d) char(string(d.label)), bindesc(bad), 'UniformOutput', false);
    throw(MException('Alakazam:Unfold:NotFinite', '%s', sprintf([ ...
        'The fit returned no usable numbers for %s, I''m afraid: the solver produced NaN ' ...
        'rather than a waveform. That happens when the system it was given has no answer ' ...
        'to give, which in practice means one of three things: too much of the data was ' ...
        'excluded as artefact (the threshold here was %g uV), the recording carries an ' ...
        'offset or drift the model cannot absorb (try DCDetrend or a high-pass Filter), or ' ...
        'two bins hold events whose timing never varies relative to each other, which no ' ...
        'amount of deconvolution can separate.'], strjoin(labels, ', '), ...
        opts.ArtifactThresholdUv)));
end

function mask = comboMask(bindesc)
    mask = false(1, numel(bindesc));
    if isfield(bindesc, 'combo')
        mask = ~cellfun(@isempty, {bindesc.combo});
    end
end

function column = interceptColumn(result, eventType)
%INTERCEPTCOLUMN  Which of uf_condense's parameters is this event's intercept.
%   With one formula of y ~ 1 per event type, each type contributes exactly
%   one parameter, so the event name identifies it; the name is matched too
%   rather than assumed, so a later formula with covariates cannot silently
%   pick up the wrong column here.
    events = arrayfun(@(p) char(string(p.event)), result.param, 'UniformOutput', false);
    names = arrayfun(@(p) char(string(p.name)), result.param, 'UniformOutput', false);
    column = find(strcmp(events, eventType) & contains(lower(names), 'intercept'), 1);
    if isempty(column)
        column = find(strcmp(events, eventType), 1);
    end
end

function data = resolveComboBins(data, bindesc)
%RESOLVECOMBOBINS  Difference bins, as Average computes them: the signed sum
%   of the bins they reference, resolved in dependency order so a difference
%   of differences works too. They are not predictors (see Unfold.binModel);
%   subtracting two fitted waveforms is the same operation subtracting two
%   averages is.
    isCombo = comboMask(bindesc);
    if ~any(isCombo)
        return;
    end
    position = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for b = 1:numel(bindesc)
        position(bindesc(b).index) = b;
    end

    resolved = ~isCombo;
    progress = true;
    while progress && ~all(resolved)
        progress = false;
        for b = find(~resolved)
            combo = bindesc(b).combo;
            if ~all(isKey(position, num2cell([combo.bin])))
                continue;   % references a bin this dataset does not have
            end
            parts = arrayfun(@(t) position(t.bin), combo);
            if ~all(resolved(parts))
                continue;   % a dependency is itself an unresolved difference
            end
            acc = zeros(size(data, 1), size(data, 2));
            for t = 1:numel(combo)
                acc = acc + combo(t).coeff * data(:, :, parts(t));
            end
            data(:, :, b) = acc;
            resolved(b) = true;
            progress = true;
        end
    end
end
