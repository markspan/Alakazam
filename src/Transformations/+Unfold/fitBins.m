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
%                        this is a choice per code.
%     Formulas           each bin's formula in Unfold's notation, as a struct
%                        array of .bin (label) and .formula; 'y ~ 1' for a
%                        bin without one (see Unfold.binModel).
%     Covariates         the older option: event fields added as linear
%                        terms to every bin without a formula of its own.
%                        Unfold.eventCovariates lists what a dataset offers.
%     EvaluateAt         for Output 'terms': where each continuous or spline
%                        term is evaluated, as text, "sac_amplitude = 0.5 1 2;
%                        rating = 1 5". A term not named is evaluated at five
%                        quantiles of its own values, which differ from one
%                        recording to the next, so name the values when the
%                        terms are to be combined across subjects.
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
%                        THE TOOLBOX IS CALLED AS A SCRIPT CALLS IT, and its
%                        results are kept as they are (1.3.1, unchanged in
%                        its current version). The scan is handed the
%                        dataset's own events, boundaries included, so
%                        ERPLAB's scan looks at each stretch between cuts on
%                        its own (forArtefactScan). Its windows start one
%                        sample in and stop when the next would run off the
%                        end, so the first sample and less than one step at
%                        the end of a stretch are not looked at. The scan's
%                        marks and the zones around cuts are then joined by
%                        uf_combineWinrej, which ends a joined stretch where
%                        the later-starting one ends; where one lies wholly
%                        inside another, the joined stretch ends with the
%                        inner one. With the scan between cuts a marked
%                        window never spans a cut, so the one case left is a
%                        marked stretch lying wholly inside a cut's zone,
%                        on one side of it: the zone then ends where that
%                        stretch does. It needs an artefact window shorter
%                        than the longer side of the response window (the
%                        zone reaches that far either side of a cut), so
%                        with the defaults, 2000 ms against 800 ms, it
%                        cannot happen.
%     SolverIterations   400, the toolbox's own limit on the lsmr solver's
%                        iterations (uf_glmfit's lsmriterations). A fit that
%                        reaches it says so in the notes; raising it lets a
%                        slow but sound fit finish, while a nearly collinear
%                        design needs a different model instead.
%     Channels           which channels the artifact scan looks at. The
%                        default is the scalp EEG (eegChannelMask), not every
%                        channel: an EOG channel's range is several times the
%                        EEG's, so scanning it marks most of the recording bad
%                        and takes the bins' data with it.
%     Output             'average' (the default): one waveform per bin, as
%                        described above. 'trials': one OVERLAP-CORRECTED
%                        TRIAL per binned event instead, in the epoched shape
%                        DefineBins cuts (DataFormat 'EPOCHED', EEG.epoch with
%                        each trial's .bini, bindesc.trials), so EpochView,
%                        Average and the data-quality report take it like any
%                        epoch node. Each trial is the recording around its
%                        event with every other event's fitted response
%                        subtracted (Unfold.overlapCorrectedTrials, which
%                        also says why averaging them gives back the fitted
%                        waveform). A trial whose window touches a stretch
%                        the model left out, or runs off the recording, is
%                        dropped, since nothing was subtracted there; the
%                        count is in the provenance. 'terms': one waveform
%                        per model term instead (see below).
%
%   A BIN'S WAVEFORM is the model's prediction with every continuous and
%   spline term at its average over ALL the modelled events that carry it
%   (Unfold.binModel's plan.pooled), the same for every bin, and every factor
%   at the bin's own mix of levels. With y ~ 1 that is the intercept, as it
%   always was. With a covariate it is each bin's response at the same value
%   of it, so a covariate whose values differ between bins (a bigger saccade
%   in one condition, a slower response in another) is held constant rather
%   than showing up as a difference between them. That is what makes it a
%   control. For a spline the average is taken over its basis, which is
%   Unfold's own average marginal effect and is right for a circular one
%   too, where a mean angle would not be. The spline bases are evaluated by
%   the toolbox's own function (EEG.unfold.splines{s}.splinefunction with its
%   knots and removedSplineIdx). A spline that is not circular is only
%   averaged over the values every bin using it shares (plan.pooled's
%   .common), since outside a bin's own values its spline is extrapolating;
%   bins that share none are each averaged over their own, and the notes say
%   which of the two happened. A 2D spline (2dspl) is averaged the same way
%   over the pooled pairs of its two fields. An interaction with a
%   continuous term (cat(side) * rt) has that term at the pooled mean too,
%   like the term's own column. Where every bin carries the same values, as
%   with y ~ 1 or a covariate one bin alone uses, this is also exactly what
%   the bin's overlap-corrected trials average to.
%
%   BINS THAT SHARE EVENTS: each set of bins the events can be in is one
%   event type of the model (Unfold.binModel), and a bin's waveform is the
%   average of those types' waveforms weighted by how many of its events
%   each holds. That is Average's own rule, an event counting in every bin it
%   is in, so "Rare" nested in "All stimuli" is the rare events' response,
%   not its difference from the others.
%
%   THE TERMS OUTPUT is Unfold's own view of the model: uf_condense, then
%   uf_predictContinuous (each continuous and spline term at the EvaluateAt
%   values, or five quantiles), then uf_addmarginal with 'type' 'AME', which
%   makes every term a whole waveform with the others as their average
%   marginal effects: a spline averaged over its events' values, as a bin's
%   waveform has it, and not evaluated at the mean value (the toolbox's
%   default, 'MEM'), which for an angle is a direction no event need have
%   had. So the intercept is the response at each factor's reference level,
%   a factor level is the response at that level, and a spline at a value is
%   the response at that value. One "bin" per term of every modelled set of
%   bins, labelled "<bin>: <term>" ("<bin>: x = 1, z = 2" for a 2D spline),
%   in Average's shape, so Measure, GrandAverage and the reports read them.
%   A TOOLBOX BEHAVIOUR KEPT AS IT IS, by design, and the toolbox's own
%   warning says so: uf_predictContinuous takes a continuous term's
%   quantiles, and uf_addmarginal its mean, over the events whose value is
%   not exactly zero, since zero is what the other event types' rows of X
%   hold. A covariate whose own values include zero (a rating of 0) is
%   summarised without them; name the values in EvaluateAt where that
%   matters.
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
    parsed.addParameter('OtherEvents', 'all', @(v) isempty(v) || ischar(v) || iscellstr(v) || isstring(v));
    parsed.addParameter('Covariates', {}, @(v) isempty(v) || iscellstr(v) || isstring(v));
    parsed.addParameter('Formulas', [], @(v) isempty(v) || isstruct(v));
    parsed.addParameter('EvaluateAt', '', @(v) ischar(v) || isstring(v));
    parsed.addParameter('ArtifactThresholdUv', 150, @(v) isnumeric(v) && isscalar(v) && v >= 0);
    parsed.addParameter('ArtifactWindowMs', 2000, @(v) isnumeric(v) && isscalar(v) && v > 0);
    parsed.addParameter('ArtifactStepMs', 100, @(v) isnumeric(v) && isscalar(v) && v > 0);
    parsed.addParameter('Channels', [], @(v) isnumeric(v));
    parsed.addParameter('SolverIterations', 400, @(v) isnumeric(v) && isscalar(v) && v >= 1 && v == round(v));
    parsed.addParameter('Output', 'average', ...
        @(v) (ischar(v) || isstring(v)) && any(strcmpi(char(string(v)), {'average', 'trials', 'terms'})));
    parsed.parse(varargin{:});
    opts = parsed.Results;
    opts.BaselineMs = resolveBaseline(opts.BaselineMs, opts.WindowMs);

    requireCentredData(input);
    plan = Unfold.binModel(input, 'OtherEvents', opts.OtherEvents, 'Covariates', opts.Covariates, ...
        'Formulas', opts.Formulas);
    if isempty(plan.eventTypes)
        throw(MException('Alakazam:Unfold:NothingToFit', ...
            ['None of this dataset''s bins hold any events, so there is no model to fit. ' ...
             'Check the bin definitions against the events the recording actually has.']));
    end
    Unfold.ensure('Deconvolution (rERP)');

    srate = double(input.srate);

    % Events in no bin that keep a near-constant lag to another modelled type
    % make the design nearly collinear, the usual reason the solver does not
    % converge; they are named in the notes before the fit, not only after it.
    locked = Unfold.timeLockedEvents(plan, srate, opts.WindowMs);
    plan.notes = [plan.notes, {locked.note}];

    % 1. The design: one event type per bin, each with its own formula (see
    %    Unfold.binModel).
    work = Unfold.designMatrix(input, plan);

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
        detected = uf_continuousArtifactDetect(forArtefactScan(work, input.event), ...
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

    % 4. The fit, by the toolbox's default solver (lsmr) with its iteration
    %    limit as a setting. The solver warns rather than fails when it runs
    %    out of iterations, and an under-converged fit looks like a result,
    %    so the warning is caught and carried into the notes instead of
    %    scrolling past in the log.
    lastwarn('');
    work = uf_glmfit(work, 'lsmriterations', opts.SolverIterations);
    [solverWarning, ~] = lastwarn();
    if contains(lower(solverWarning), 'did not converge')
        plan.notes{end + 1} = sprintf(['The solver ran out of iterations (Solver iterations, %d) ' ...
            'before it converged, for at least one channel, so these waveforms are an unfinished ' ...
            'estimate. That usually means the design is close to collinear (bins whose events ' ...
            'keep a near-constant lag) or that a lot of the data was excluded as artefact; ' ...
            'where it is neither, raising Solver iterations lets it finish.'], opts.SolverIterations);
        if ~isempty(locked)
            plan.notes{end} = sprintf('%s The likely cause here: %s.', plan.notes{end}, ...
                strjoin(arrayfun(@(p) sprintf('"%s" locked to "%s"', p.code, p.other), ...
                locked, 'UniformOutput', false), ', '));
        end
    end

    % The waveforms are checked in every case: a fit that produced no
    % numbers produces no trials or terms either, and says so the same way.
    [waveforms, times, evaluationNotes] = fittedWaveforms(input, plan, work.unfold, opts);
    plan.notes = [plan.notes, evaluationNotes];
    info = modelInfo(input, plan, opts, excluded, srate);
    switch lower(char(string(opts.Output)))
        case 'trials'
            [EEG, info] = packageTrials(input, plan, work, info, opts, excluded, srate, times);
        case 'terms'
            [EEG, info] = packageTerms(input, plan, work, info, opts, times);
        otherwise
            EEG = package(input, plan, waveforms, times);
    end
    EEG = recordInfo(EEG, info, plan);
end

% ======================================================================= %
function [data, times, notes] = fittedWaveforms(input, plan, unfold, opts)
%FITTEDWAVEFORMS  One fitted waveform per bin, baseline-corrected, with the
%   combination bins computed from them. Each is the model's prediction at
%   the pooled values of its continuous and spline terms (see this file's
%   header), read from the documented EEG.unfold fields: X, colnames,
%   cols2eventtypes, cols2variablenames, variablenames, variabletypes,
%   splines, eventtypes and beta_dc, whose third dimension runs over X's
%   columns. NOTES say where a spline could not be averaged over every
%   pooled value (see referencePrediction).
%
%   A BIN IS THE EVENT-WEIGHTED MEAN OF ITS SETS: the waveform of each event
%   type (a set of bins its events share, Unfold.binModel's plan.cellTypes)
%   weighted by how many of the bin's events it holds. For bins that share
%   no events each bin is one set and this is its own waveform; for nested
%   bins it is what Average gives, each event counted in every bin it is in.
    times = reshape(double(unfold.times) * 1000, 1, []);   % Unfold keeps seconds
    nchan = size(unfold.beta_dc, 1);
    nbin = numel(input.bindesc);
    data = nan(nchan, numel(times), nbin);
    notes = {};

    perCell = cell(1, numel(plan.cellTypes));
    for c = 1:numel(plan.cellTypes)
        [perCell{c}, cellNotes] = referencePrediction(unfold, plan, c);
        if ~isempty(cellNotes)   % one note per spline, not one per type
            notes = reshape(unique([notes, cellNotes], 'stable'), 1, []);
        end
    end

    ordinary = find(~comboMask(input.bindesc));
    fitted = false(1, nbin);
    for k = 1:numel(plan.binLabels)
        cells = plan.binCells{k};
        if isempty(cells) || any(cellfun(@isempty, perCell(cells)))
            continue;   % a bin with no events: left as NaN, and noted by binModel
        end
        waveform = zeros(nchan, numel(times));
        for c = reshape(cells, 1, [])
            waveform = waveform + plan.cellCounts(c) / plan.binCounts(k) * perCell{c};
        end
        data(:, :, ordinary(k)) = waveform;
        fitted(ordinary(k)) = true;
    end
    requireFiniteBetas(data, fitted, input.bindesc, opts);
    data = applyBaseline(data, fitted, times, opts.BaselineMs);
    data = resolveComboBins(data, input.bindesc);
end

function EEG = package(input, plan, data, times)
%PACKAGE  The fitted waveforms in Average's own output shape.
    nchan = size(data, 1);
    nbin = size(data, 3);
    EEG = input;
    EEG.data = data;
    EEG.times = times;
    EEG.pnts = numel(times);
    EEG.trials = 1;
    EEG.xmin = times(1) / 1000;
    EEG.xmax = times(end) / 1000;
    EEG.DataFormat = "Averaged";
    EEG.ntrials = sum(plan.cellCounts);  % each event once, as Average counts epochs
    EEG.stErr = zeros(size(data));      % see this file's header: there is none
    EEG.aSME = nan(nchan, nbin);
    ordinary = find(~comboMask(input.bindesc));
    for k = 1:numel(ordinary)
        EEG.bindesc(ordinary(k)).n = plan.binCounts(k);
    end
end

function [EEG, info] = packageTrials(input, plan, work, info, opts, excluded, srate, times)
%PACKAGETRIALS  Overlap-corrected trials, laid out by DefineBins' own
%   cutEpochs, so the result is a DefineBins epoch node in every field but
%   its data: one trial per binned event (an event in two bins is one trial
%   carrying both tags), EEG.epoch, the anchor events' .epoch and latencies,
%   bindesc.trials, and the neighbour table EpochView sorts by. Average,
%   EpochView and the data-quality report then read it without knowing it
%   came from a model, and there is one definition of an epoched dataset
%   rather than two to keep in step.
    events = unique([plan.membership{:}]);           % one trial per binned event
    trialOf = zeros(1, numel(input.event));
    trialOf(events) = 1:numel(events);
    owner = trialOf(plan.eventSource);               % 0 for a neighbour-only event

    npnts = size(input.data, 2);
    bad = false(1, npnts);
    for k = 1:size(excluded, 1)
        span = max(1, round(excluded(k, 1))):min(npnts, round(excluded(k, 2)));
        bad(span) = true;
    end
    model = struct('Xdc', work.unfold.Xdc, 'Xdc_terms2cols', work.unfold.Xdc_terms2cols, ...
        'X', work.unfold.X, 'beta_dc', work.unfold.beta_dc, ...
        'timelimits', opts.WindowMs / 1000, 'srate', srate);
    anchors = double([input.event(events).latency]);
    [trials, usable] = Unfold.overlapCorrectedTrials(input.data, model, owner, anchors, bad);

    kept = events(usable);
    if isempty(kept)
        throw(MException('Alakazam:Unfold:NoTrials', '%s', sprintf([ ...
            'None of the %d binned events has a whole window of data the model covers, so ' ...
            'there are no overlap-corrected trials to return. A trial is dropped when its ' ...
            '%g to %g ms window runs off the recording or touches a stretch left out of the ' ...
            'model (artefact, or around a cut). Would you lower or switch off the artefact ' ...
            'threshold, or ask for one waveform per bin instead?'], ...
            numel(events), opts.WindowMs(1), opts.WindowMs(2))));
    end
    trials = trials(:, :, usable);
    if ~isempty(opts.BaselineMs)
        % The samples inside the window, as Unfold's own baseline
        % (uf_plotParam) takes them.
        inWindow = times >= opts.BaselineMs(1) & times <= opts.BaselineMs(2);
        trials = trials - mean(trials(:, inWindow, :), 2);
    end

    % cutEpochs lays out the kept events' trials, time zero on the sample
    % Unfold placed each event on. It is handed one channel only: it would
    % otherwise cut every channel of the raw recording just for that to be
    % replaced by the corrected trials a line later.
    layout = input;
    layout.data = input.data(1, :);
    centre = zeros(1, numel(input.event));
    centre(kept) = round([input.event(kept).latency]);
    lags = round(times / 1000 * srate);
    [EEG, bindesc] = DefineBinsEngine.cutEpochs(layout, keptBins(input.bindesc, plan, kept), ...
        struct('lo', lags(1), 'hi', lags(end) + 1, 'unit', 'samples'), centre);
    EEG.bindesc = bindesc;
    EEG.data = trials;
    EEG.times = times;      % uf_condense's own, which the waveforms carry too

    info.output = 'trials';
    info.trialCandidates = numel(events);
    info.trials = numel(kept);
    info.trialsDropped = numel(events) - numel(kept);
end

function bindesc = keptBins(bindesc, plan, kept)
%KEPTBINS  Each ordinary bin's events cut to those that became trials, which
%   is what cutEpochs makes trials of, with their reaction times kept
%   aligned: cutEpochs derives .trials from .events element by element, and a
%   sort by reaction time pairs .rt with .trials the same way.
    ordinary = find(~comboMask(bindesc));
    for k = 1:numel(ordinary)
        b = ordinary(k);
        members = plan.membership{k};
        members = members(ismember(members, kept));
        rts = nan(1, numel(members));
        if isfield(bindesc, 'events') && isfield(bindesc, 'rt') ...
                && numel(bindesc(b).rt) == numel(bindesc(b).events)
            [found, at] = ismember(members, bindesc(b).events);
            rts(found) = bindesc(b).rt(at(found));
        end
        bindesc(b).events = members;
        bindesc(b).rt = rts;
        bindesc(b).n = numel(members);
    end
end

function info = modelInfo(input, plan, opts, excluded, srate)
%MODELINFO  What was fitted and what was left out, for EEG.etc.alz.unfold.
    info = struct('output', 'average', 'window', opts.WindowMs, 'baseline', opts.BaselineMs, ...
        'binLabels', {plan.binLabels}, ...
        'binTypes', {plan.binTypes}, 'binCounts', plan.binCounts, ...
        'nuisanceTypes', {plan.nuisanceTypes}, ...
        'formulas', struct('type', plan.typeLabels, 'formula', plan.formulas), ...
        'notes', {plan.notes}, ...
        'excludedIntervals', excluded, ...
        'excludedSeconds', sum(diff(excluded, 1, 2)) / srate, ...
        'recordingSeconds', size(input.data, 2) / srate, ...
        'artifact', struct('thresholdUv', opts.ArtifactThresholdUv, ...
                           'windowMs', opts.ArtifactWindowMs, 'stepMs', opts.ArtifactStepMs), ...
        'solverIterations', opts.SolverIterations, ...
        'cellLabels', {plan.cellLabels}, 'binCells', {plan.binCells}, ...
        'hasStandardError', false);
end

function EEG = recordInfo(EEG, info, plan)
%RECORDINFO  The provenance on the dataset, and the model's notes in the log.
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
    inWindow = times >= window(1) & times <= window(2);   % inside, as Unfold's uf_plotParam
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
%   share of the recording left out is counted once rather than twice. By
%   the toolbox's own uf_combineWinrej, as a script joins them, so the
%   exclusion is the one Unfold makes (this file's header says how it joins
%   a stretch lying inside another).
    if isempty(a); intervals = b; return; end
    if isempty(b); intervals = a; return; end
    intervals = uf_combineWinrej(a, b);
end

function EEG = forArtefactScan(EEG, events)
%FORARTEFACTSCAN  A copy shaped the way the ERPLAB scan expects a dataset.
%   The scan is ERPLAB's crap.m, and it reads two fields that EEGLAB always
%   writes but an Alakazam dataset need not carry: {chanlocs.type}, to warn
%   about EYE-EEG channels, and .epoch, to check the data is continuous. Both
%   are absent rather than empty on a dataset whose importer never wrote them,
%   and the scan then fails with a bare "Unrecognized field name" that says
%   nothing about what went wrong. Filled in on the copy handed to the scan, so
%   nothing is written into the dataset the user keeps.
%
%   THE SCAN GETS THE DATASET'S OWN EVENTS (EVENTS), boundaries included, as
%   it does in an Unfold script, where uf_continuousArtifactDetect is handed
%   the dataset itself: ERPLAB's scan then looks at each stretch between cuts
%   on its own. The model's event list, which the design was built from,
%   carries no boundaries, and with it the scan ran across every cut as if
%   the recording were one stretch.
    EEG.event = events;
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

function [waveform, notes] = referencePrediction(unfold, plan, c)
%REFERENCEPREDICTION  The waveform of event type C of the plan (a set of
%   bins, plan.cellTypes): the betas of the type's own columns
%   (cols2eventtypes), weighted by its events' own average design row for
%   the intercept and factors, and with every continuous or spline term at
%   the pooled values (see this file's header). [] when the type is not in
%   the model.
%
%   A SPLINE IS ONLY AVERAGED WHERE EVERY BIN USING IT HAS DATA (the pooled
%   values inside plan.pooled's .common range), because a bin's spline is
%   fitted over its own values only, and outside them it is extrapolating,
%   which a spline does badly. Where the bins share no values at all there
%   is nothing a model can hold constant, and each bin is evaluated over its
%   own; both are said in NOTES. A circular spline covers the whole circle
%   and never extrapolates, so it takes every pooled value. A 2D spline is
%   averaged over the pooled PAIRS of its two fields, inside the box of
%   values every type using it shares.
%
%   AN INTERACTION WITH A CONTINUOUS TERM is held at the pooled values too
%   (pooledInteractions): its column is the product of a factor's dummy and
%   the term, and the term's part of it is set to the pooled mean, as the
%   term's own column is. Read from the type's own average row, it carried
%   the bin's own values into the waveform after all.
    waveform = [];
    notes = {};
    eventType = plan.cellTypes{c};
    label = plan.cellLabels{c};
    t = find(cellfun(@(e) any(strcmp(cellstr(e), eventType)), unfold.eventtypes), 1);
    if isempty(t)
        return;
    end
    rows = strcmp({plan.events.type}, eventType);
    cols = reshape(find(unfold.cols2eventtypes == t), 1, []);
    weights = mean(unfold.X(rows, cols), 1);
    variableOf = unfold.cols2variablenames(cols);
    single = cellfun(@isempty, {plan.pooled.pair});
    for v = reshape(unique(variableOf, 'stable'), 1, [])
        kind = unfold.variabletypes{v};
        if ~any(strcmp(kind, {'continuous', 'spline'}))
            continue;
        end
        name = regexprep(unfold.variablenames{v}, '^\d+_', '');
        at = variableOf == v;
        if strcmp(kind, 'continuous')
            weights(at) = mean(plan.pooled(single & strcmp({plan.pooled.name}, name)).values);
            continue;
        end
        spl = splineFor(unfold, unfold.colnames(cols(at)));
        if size(spl.knots, 1) == 2
            [basis, note] = surfaceBasis(spl, plan.pooled(~single & strcmp({plan.pooled.name}, name)), ...
                plan.events(rows), label);
        else
            [basis, note] = splineBasis(spl, plan.pooled(single & strcmp({plan.pooled.name}, name)), ...
                plan.events(rows), name, label);
        end
        notes = [notes, note]; %#ok<AGROW>
        weights(at) = mean(basis, 1);
    end
    interactions = strcmp(unfold.variabletypes(variableOf), 'interaction');
    vars = plan.variables{c};
    if any(interactions) && any(~[vars.categorical] & ~[vars.spline])
        weights(interactions) = pooledInteractions(plan, c, numel(cols), interactions);
    end
    waveform = sum(unfold.beta_dc(:, :, cols) .* reshape(weights, 1, 1, []), 3);
end

function [basis, notes] = splineBasis(spl, pooled, events, name, label)
%SPLINEBASIS  A spline's basis at the pooled values of its field, cut to the
%   range every type using it shares (see referencePrediction).
    notes = {};
    values = pooled.values;
    if ~contains(func2str(spl.splinefunction), 'cyclical')
        if isempty(pooled.common)
            values = [events.(name)];
            notes{end + 1} = sprintf(['The bins using "%s" share no values of it, so it ' ...
                'cannot be held constant across them: "%s" is evaluated over its own.'], ...
                name, label);
        elseif any(values < pooled.common(1) | values > pooled.common(2))
            values = values(values >= pooled.common(1) & values <= pooled.common(2));
            notes{end + 1} = sprintf(['The spline of "%s" is averaged over its values ' ...
                'from %.4g to %.4g, the range every bin using it shares: outside a bin''s ' ...
                'own values its spline is extrapolating.'], name, ...
                pooled.common(1), pooled.common(2));
        end
    end
    basis = spl.splinefunction(values, spl.knots);
    basis(:, spl.removedSplineIdx) = [];
end

function [basis, notes] = surfaceBasis(spl, pooled, events, label)
%SURFACEBASIS  A 2D spline's basis at the pooled pairs of its two fields,
%   built the way uf_designmat_spline builds it (each pair's two bases
%   multiplied out), cut to the box every type using it shares.
    notes = {};
    values = pooled.values;
    fields = sprintf('"%s" and "%s"', pooled.pair{1}, pooled.pair{2});
    if isempty(pooled.common)
        values = [[events.(pooled.pair{1})]; [events.(pooled.pair{2})]];
        notes{end + 1} = sprintf(['The bins using the 2D spline of %s share no values of it, so ' ...
            'it cannot be held constant across them: "%s" is evaluated over its own.'], fields, label);
    else
        inside = all(values >= pooled.common(:, 1) & values <= pooled.common(:, 2), 1);
        if ~all(inside)
            values = values(:, inside);
            notes{end + 1} = sprintf(['The 2D spline of %s is averaged over the pairs of values ' ...
                'every bin using it shares (%.4g to %.4g, %.4g to %.4g): outside a bin''s own ' ...
                'values its spline is extrapolating.'], fields, pooled.common(1, 1), ...
                pooled.common(1, 2), pooled.common(2, 1), pooled.common(2, 2));
        end
    end
    first = spl.splinefunction(values(1, :), spl.knots(1, :));
    second = spl.splinefunction(values(2, :), spl.knots(2, :));
    basis = zeros(size(values, 2), size(first, 2) * size(second, 2));
    for k = 1:size(values, 2)
        product = first(k, :)' * second(k, :);
        basis(k, :) = product(:)';
    end
    basis(:, spl.removedSplineIdx) = [];
end

function weights = pooledInteractions(plan, c, ncols, interactions)
%POOLEDINTERACTIONS  The average design row of the interaction columns of
%   type C with every linear continuous field of its formula set to its
%   pooled mean: the type's own events, those fields replaced, through the
%   toolbox's own uf_designmat (Unfold.designMatrix), so the columns are
%   built exactly as the fitted ones were. A factor-by-factor interaction
%   has no such field and comes out as its own average row, as before.
    rows = strcmp({plan.events.type}, plan.cellTypes{c});
    events = plan.events(rows);
    vars = plan.variables{c};
    single = cellfun(@isempty, {plan.pooled.pair});
    for v = vars(~[vars.categorical] & ~[vars.spline])
        level = mean(plan.pooled(single & strcmp({plan.pooled.name}, v.name)).values);
        [events.(v.name)] = deal(level);
    end
    one = struct('events', events, 'eventTypes', {plan.cellTypes(c)}, ...
        'formulas', {plan.formulas(c)}, 'typeLabels', {plan.cellLabels(c)}, ...
        'variables', {plan.variables(c)}); %#ok<NASGU>  read inside evalc
    designed = [];
    evalc('designed = Unfold.designMatrix(struct(''event'', events), one);');   % quiet: it prints
    if size(designed.unfold.X, 2) ~= ncols
        throw(MException('Alakazam:Unfold:Interaction', '%s', sprintf([ ...
            'Rebuilding the columns of "%s" at the pooled values gave %d columns where the fit ' ...
            'has %d, so its interaction cannot be evaluated. This is a fault in Alakazam, not in ' ...
            'the model.'], plan.cellLabels{c}, size(designed.unfold.X, 2), ncols)));
    end
    weights = mean(designed.unfold.X(:, interactions), 1);
end

function spl = splineFor(unfold, colnames)
%SPLINEFOR  The entry of EEG.unfold.splines whose columns are COLNAMES, the
%   columns of X it produced. Matched on the columns rather than the name,
%   since two event types can each have a spline of the same field.
    for s = 1:numel(unfold.splines)
        spl = unfold.splines{s};
        if isequal(reshape(cellstr(spl.colnames), 1, []), reshape(cellstr(colnames), 1, []))
            return;
        end
    end
    throw(MException('Alakazam:Unfold:SplineNotFound', '%s', sprintf([ ...
        'No spline in the fitted model produced the columns %s, so the waveform cannot be ' ...
        'evaluated. This is a fault in Alakazam, not in the model.'], strjoin(cellstr(colnames), ', '))));
end

function [EEG, info] = packageTerms(input, plan, work, info, opts, times)
%PACKAGETERMS  One waveform per model term of every binned event type, by
%   Unfold's own route (see this file's header), in Average's shape.
    result = uf_condense(work);
    args = {'auto_method', 'quantile', 'auto_n', 5};
    predictAt = Unfold.predictionValues(opts.EvaluateAt, result.unfold);
    if ~isempty(predictAt)
        args = [args, {'predictAt', predictAt}];
    end
    lastwarn('');
    % 'AME': the other terms as their average marginal effects, a spline
    % averaged over its events' own values, not evaluated at their mean
    % (the toolbox's default, 'MEM'), which for an angle is a direction no
    % event need have had. It is what a bin's waveform does as well.
    marginal = uf_addmarginal(uf_predictContinuous(result, args{:}), 'type', 'AME');
    [warningText, ~] = lastwarn();
    if contains(lower(warningText), 'interaction')
        plan.notes{end + 1} = ['The model has interactions, which uf_addmarginal does not ' ...
            'fold into the other terms: an interaction term is its own beta plus the ' ...
            'intercept, not the response to that combination of levels.'];
        info.notes = plan.notes;
    end

    events = arrayfun(@(p) char(string(p.event)), marginal.param, 'UniformOutput', false);
    labelOf = containers.Map(plan.eventTypes, plan.typeLabels);
    keep = find(ismember(events, plan.cellTypes));
    labels = cell(1, numel(keep));
    counts = zeros(1, numel(keep));
    surfaces = plan.pooled(~cellfun(@isempty, {plan.pooled.pair}));
    terms = struct('label', {}, 'bin', {}, 'name', {}, 'type', {}, 'value', {});
    for j = 1:numel(keep)
        p = marginal.param(keep(j));
        binLabel = labelOf(events{keep(j)});
        labels{j} = termLabel(binLabel, p, ...
            referenceLevels(result.unfold, plan.events, events{keep(j)}), surfaces);
        counts(j) = nnz(strcmp({plan.events.type}, events{keep(j)}));
        terms(j) = struct('label', labels{j}, 'bin', binLabel, 'name', char(string(p.name)), ...
            'type', char(string(p.type)), 'value', double(p.value));
    end

    data = marginal.beta(:, :, keep);
    requireFiniteBetas(data, true(1, numel(keep)), struct('label', labels), opts);
    data = applyBaseline(data, true(1, numel(keep)), times, opts.BaselineMs);

    EEG = input;
    EEG.data = data;
    EEG.times = times;
    EEG.pnts = numel(times);
    EEG.trials = 1;
    EEG.xmin = times(1) / 1000;
    EEG.xmax = times(end) / 1000;
    EEG.DataFormat = "Averaged";
    EEG.ntrials = sum(plan.cellCounts);
    EEG.stErr = zeros(size(data));      % see this file's header: there is none
    EEG.aSME = nan(size(data, 1), numel(keep));
    EEG.bindesc = struct('index', num2cell(1:numel(keep)), 'label', labels, ...
        'combo', repmat({[]}, 1, numel(keep)), 'n', num2cell(counts));

    info.output = 'terms';
    info.terms = terms;
    info.evaluateAt = char(string(opts.EvaluateAt));
end

function text = referenceLevels(unfold, events, eventType)
%REFERENCELEVELS  ", factor = level" for each factor of EVENTTYPE: the level
%   the intercept stands for, which is the one without a column of its own
%   (Unfold's reference coding makes the first level, in sorted order, the
%   reference). '' for a type without factors.
    text = '';
    t = find(cellfun(@(e) any(strcmp(cellstr(e), eventType)), unfold.eventtypes), 1);
    if isempty(t)
        return;
    end
    cols = reshape(find(unfold.cols2eventtypes == t), 1, []);
    variables = reshape(unique(unfold.cols2variablenames(cols), 'stable'), 1, []);
    rows = strcmp({events.type}, eventType);
    for v = variables
        if ~strcmp(unfold.variabletypes{v}, 'categorical')
            continue;
        end
        name = regexprep(unfold.variablenames{v}, '^\d+_', '');
        if ~isfield(events, name)
            continue;
        end
        levels = unique(cellfun(@(x) char(string(x)), {events(rows).(name)}, 'UniformOutput', false));
        own = regexprep(unfold.colnames(cols(unfold.cols2variablenames(cols) == v)), ['^(\d+_)?' name '_'], '');
        reference = setdiff(levels, own);
        if ~isempty(reference)
            text = sprintf('%s, %s = %s', text, name, reference{1});
        end
    end
end

function label = termLabel(binLabel, p, references, surfaces)
%TERMLABEL  "<bin>: <term>" for one of uf_condense's parameters, without the
%   "2_" Unfold puts before a second event type's names: the intercept with
%   the factor levels it stands for, a continuous or spline term with the
%   value it was evaluated at, a 2D spline with the value of each of its
%   fields (SURFACES, Unfold.binModel's pooled entries with a .pair, name
%   them: the toolbox's own name runs the two together), anything else by
%   Unfold's own column name.
    name = regexprep(char(string(p.name)), '^\d+_', '');
    surface = surfaces(strcmp({surfaces.name}, name));
    if strcmpi(name, '(Intercept)')
        label = sprintf('%s: (Intercept)%s', binLabel, references);
    elseif contains(char(string(p.type)), 'converted') && numel(p.value) == 2 && ~isempty(surface)
        label = sprintf('%s: %s = %.4g, %s = %.4g', binLabel, surface(1).pair{1}, p.value(1), ...
            surface(1).pair{2}, p.value(2));
    elseif contains(char(string(p.type)), 'converted') && isfinite(p.value(1))
        label = sprintf('%s: %s = %.4g', binLabel, name, p.value(1));
    else
        label = sprintf('%s: %s', binLabel, name);
    end
end

function data = resolveComboBins(data, bindesc)
%RESOLVECOMBOBINS  Difference bins, as Average computes them: the signed sum
%   of the bins they reference, in the dependency order TransTools.ComboOrder
%   works out for both, so a difference of differences works too. They are
%   not predictors (see Unfold.binModel); subtracting two fitted waveforms is
%   the same operation subtracting two averages is. A combination that
%   cannot be resolved is left NaN, which DefineBins' own parse-time check
%   makes unreachable from a script.
    for s = TransTools.ComboOrder(bindesc)
        acc = zeros(size(data, 1), size(data, 2));
        for t = 1:numel(s.parts)
            acc = acc + s.coeffs(t) * data(:, :, s.parts(t));
        end
        data(:, :, s.target) = acc;
    end
end
