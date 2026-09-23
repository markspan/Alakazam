function [EEG, options] = Deconvolve(input, varargin)
%% Deconvolve  One waveform per bin, with overlapping responses separated.
%
%   AN ALTERNATIVE TO EPOCH-AND-AVERAGE, not a replacement for it. Average
%   assumes each epoch holds the response to its own event and nothing else.
%   Where events follow one another faster than a response decays (reading,
%   free viewing, fast RSVP, a button press after every stimulus), that
%   assumption is false: the same samples carry the tail of one response and
%   the start of the next, and a bin's average carries a smear of whatever
%   happened around its events. Deconvolve fits every bin at once against the
%   whole continuous recording, so a sample explained by two events is
%   credited to both, and what comes out is each bin's own response with the
%   others' overlap removed (Ehinger & Dimigen, 2019; Dimigen & Ehinger,
%   2021, J Vis 21(1):3, via the Unfold toolbox).
%
%   IT RUNS ON THE CONTINUOUS RECORDING, and defines its own bins. That is
%   not a second bin language: it asks for a script in DefineBins' language,
%   in DefineBins' own editor, and applies it with DefineBins itself in
%   tags-only mode (no epoch window), which adds EEG.bindesc and tags each
%   event with its .bini membership while leaving the data continuous.
%
%   It has to work this way round. Separating responses that overlap in time
%   is only possible while the recording is still one continuous stretch, and
%   a DefineBins node with an epoch window has replaced its data with the
%   epoch stack, so the continuous data this needs is no longer there to fit
%   against. Requiring an already binned dataset would therefore have left
%   nothing to run it on: the node with the bins has no continuous data, and
%   the node with the continuous data has no bins. So this takes the bins as
%   a setting, and a continuous dataset that already carries tags (DefineBins
%   run with both epoch fields left blank) is used as it stands.
%
%   THE RESULT IS SHAPED LIKE AN AVERAGE: DataFormat "Averaged", channels x
%   samples x bins, the same EEG.bindesc, so Measure, ScalpDistribution,
%   GrandAverage and the reports read it without knowing it came from a
%   regression. A dataset can carry both this and a plain Average result as
%   sibling nodes: nothing here changes the DefineBins -> Average -> Measure
%   chain, which is untouched and still the default path.
%
%   COVARIATES ARE NUISANCE REGRESSORS HERE. Any numeric event field can be
%   added to the model (Unfold.eventCovariates lists what a recording
%   offers); each is mean-centred and fitted per event type, and the slopes
%   are then dropped. The result is still one waveform per bin, but one the
%   covariate's variance has been taken out of, and the bin's own waveform is
%   its response at that covariate's average value rather than at zero.
%
%   WHAT IT DOES NOT GIVE YOU. A bin is a set of events, so this inherits
%   what bins can express: no spline (non-linear) covariate terms, no
%   main-effect/interaction parameterisation (a 2x2 is four bins and a
%   difference bin, not four terms), no circular covariates, and no
%   single-trial output. A covariate's own slope is not reported either: it
%   is fitted to get it out of the way, and reporting it would need a node
%   shaped around predictors rather than bins. There is also no standard
%   error: see Unfold.fitBins.
%
%   Options (all set in DeconvolveDialog, stored per user by
%   TransformSettings):
%     binScript            bin definitions in DefineBins' language; empty
%                          means the dataset's own tags are used
%     windowMs             response window per event, default -200 to 800 ms
%     baselineMs           window the fitted waveforms are baseline-corrected
%                          over, default the pre-event part of windowMs; []
%                          or an unticked box leaves them uncorrected
%     covariates           event fields fitted alongside each bin and then
%                          dropped, mean-centred, default none
%     modelOtherEvents     fit events in no bin as nuisance, default true
%     artifactThresholdUv  peak-to-peak rejection threshold, default 150 uV
%                          (0 skips detection)
%     artifactWindowMs     the moving window it is measured in, default 2000
%     artifactStepMs       how far that window steps, default 100
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Deconvolve(input)        % interactive dialog
%     [EEG, options] = Deconvolve(input, opts)  % replay a stored struct
%
%   See also UNFOLD.FITBINS, UNFOLD.BINMODEL, DECONVOLVEDIALOG, AVERAGE,
%   DEFINEBINS.
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Deconvolve', varargin{:});

% Checked before the dialog opens, not after it is filled in: a dataset that
% cannot be deconvolved at all should say so instead of asking for settings
% it will then refuse. This needs no toolbox, so it happens even when Unfold
% is not installed. The bins are NOT checked here, because supplying them is
% what the dialog is for.
Unfold.requireContinuous(input);

if interactive
    options = DeconvolveDialog(input, TransformSettings.get('Deconvolve'));
    if isempty(options)
        EEG = [];       % cancelled; OPTIONS must still be assigned (see SpectralMeasure)
        options = [];
        return;
    end
    TransformSettings.set('Deconvolve', options);
else
    options = opts;
end

tagged = applyBins(input, options);

[EEG, info] = Unfold.fitBins(tagged, ...
    'WindowMs', TransTools.FieldOr(options, 'windowMs', [-200 800]), ...
    'BaselineMs', baselineOption(options), ...
    'Covariates', TransTools.FieldOr(options, 'covariates', {}), ...
    'ModelOtherEvents', logical(TransTools.FieldOr(options, 'modelOtherEvents', true)), ...
    'ArtifactThresholdUv', TransTools.FieldOr(options, 'artifactThresholdUv', 150), ...
    'ArtifactWindowMs', TransTools.FieldOr(options, 'artifactWindowMs', 2000), ...
    'ArtifactStepMs', TransTools.FieldOr(options, 'artifactStepMs', 100));

report(info);
end

% ======================================================================= %
function window = baselineOption(options)
%BASELINEOPTION  The baseline window, where an EMPTY one is a real answer.
%   Not TransTools.FieldOr: that reads an empty field as an absent one and
%   hands back the default, which here would turn "leave these betas as the
%   solver returned them" into "correct them over the pre-event window". The
%   difference is visible in the result, so it has to survive being stored and
%   replayed.
    window = 'pre-event';   % the default: the pre-event part of the window
    if isstruct(options) && isfield(options, 'baselineMs')
        window = options.baselineMs;
    end
end

% ======================================================================= %
function EEG = applyBins(EEG, options)
%APPLYBINS  The bin definitions, applied to the continuous recording.
%   DefineBins in tags-only mode (no epoch window) does the work: one bin
%   language, one parser, one evaluator, and the combination bins ("bin 3 =
%   bin 1 - bin 2") arrive already marked so Unfold.binModel can keep them
%   out of the model and compute them after the fit, exactly as Average does.
%
%   AN UNTAGGED DATASET IS THE NORMAL CASE, so a stored script is applied
%   whether or not the dataset carries tags already: the script is what
%   Deconvolve's own options record, and replaying those options on another
%   recording has to mean the same bins there. Only when there is no script
%   at all do the dataset's existing tags stand, which is the continuous node
%   of a DefineBins run with both epoch fields left blank.
    script = strtrim(char(string(TransTools.FieldOr(options, 'binScript', ''))));
    if isempty(script)
        Unfold.binModel(EEG);   % no script and no tags: says which is missing
        return;
    end
    EEG = DefineBins(EEG, struct('script', script));
end

% ======================================================================= %
function report(info)
%REPORT  What was fitted, in the command window, as the other
%   transformations narrate their own work.
    fprintf('Deconvolve: %d bin(s) from %d event(s) over %g to %g ms', ...
        numel(info.binLabels), sum(info.binCounts), info.window(1), info.window(2));
    if isempty(info.baseline)
        fprintf(', not baseline-corrected');
    else
        fprintf(', baseline %g to %g ms', info.baseline(1), info.baseline(2));
    end
    if ~isempty(info.nuisanceTypes)
        fprintf(', with %d nuisance event type(s)', numel(info.nuisanceTypes));
    end
    if info.excludedSeconds > 0
        fprintf('; %.1f s excluded as artefact', info.excludedSeconds);
    end
    fprintf('.\n');
    for k = 1:numel(info.binLabels)
        fprintf('  %-28s %4d event(s)\n', info.binLabels{k}, info.binCounts(k));
    end
end
