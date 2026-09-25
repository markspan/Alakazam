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
%   BY DEFAULT THE RESULT IS SHAPED LIKE AN AVERAGE: DataFormat "Averaged",
%   channels x samples x bins, the same EEG.bindesc, so Measure,
%   ScalpDistribution, GrandAverage and the reports read it without knowing
%   it came from a regression. A dataset can carry both this and a plain
%   Average result as sibling nodes: nothing here changes the DefineBins ->
%   Average -> Measure chain, which is untouched and still the default path.
%
%   OR IT CAN BE OVERLAP-CORRECTED TRIALS (output 'trials'): one epoch per
%   binned event, shaped exactly like a DefineBins epoch node, each holding
%   the recording around its event with every other event's fitted response
%   subtracted (Unfold tutorial 7's "modelled plus residuals"). Average of
%   those trials gives back the fitted waveforms, so this does not change
%   the answer; what it adds is the trials themselves: an ERP image in
%   EpochView with the overlap gone, and a data-quality report that can
%   measure trial-to-trial noise (SME, baseline spread) for a deconvolved
%   subject, which the averaged form cannot. Trials whose window touches a
%   stretch left out of the model are dropped (see Unfold.fitBins).
%
%   EACH BIN HAS A FORMULA, in Unfold's own notation, edited in the dialog:
%   'y ~ 1' (the default: one waveform per bin, nothing else), or anything
%   uf_designmat accepts, factors (cat(x)), interactions, linear terms,
%   splines (spl(x, 5)) and circular splines (circspl(angle, 5, 0, 360)).
%   The bins still decide which events each event type holds; the formula
%   decides what explains their response (see Unfold.binModel, which checks
%   every field a formula names against the bin's own events first).
%
%   WHAT COMES OUT (output): one waveform per bin, the model's prediction
%   with every continuous and spline term at the same values for every bin
%   (so a term is a control: see Unfold.fitBins) and every factor at the
%   bin's own mix; overlap-corrected trials; or one waveform per model term
%   ('terms'): every factor level, every spline or continuous term at chosen
%   values (evaluateAt), each as a whole waveform with the other terms at
%   their means (uf_predictContinuous and uf_addmarginal). A waveform has no
%   standard error of its own: see Unfold.fitBins.
%
%   Options (all set in DeconvolveDialog, stored per user by
%   TransformSettings):
%     binScript            bin definitions in DefineBins' language; empty
%                          means the dataset's own tags are used
%     windowMs             response window per event, default -200 to 800 ms
%     baselineMs           window the fitted waveforms are baseline-corrected
%                          over, default the pre-event part of windowMs; []
%                          or an unticked box leaves them uncorrected
%     formulas             each bin's formula, as a struct array of .bin (the
%                          label) and .formula; a bin without one is 'y ~ 1'
%     covariates           the older way to add terms (templates saved before
%                          the formulas): each field becomes a linear term of
%                          every bin without a formula of its own
%     evaluateAt           for output 'terms': "sac_amplitude = 0.5 1 2; ...",
%                          where continuous and spline terms are evaluated;
%                          five quantiles for a term not named
%     otherEvents          event codes in no bin to fit as nuisance and drop:
%                          'all' (default), a list of codes, or empty for
%                          none; the older modelOtherEvents true/false is
%                          still read when otherEvents is absent
%     artifactThresholdUv  peak-to-peak limit within the moving window,
%                          default 150 uV (0 skips detection)
%     artifactWindowMs     the moving window it is measured in, default 2000
%     artifactStepMs       how far that window steps, default 100
%     output               'average' (default): one waveform per bin;
%                          'trials': overlap-corrected trials, epoched;
%                          'terms': one waveform per model term
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
    'Formulas', TransTools.FieldOr(options, 'formulas', []), ...
    'EvaluateAt', char(string(TransTools.FieldOr(options, 'evaluateAt', ''))), ...
    'OtherEvents', Unfold.otherEventsChoice(options), ...
    'ArtifactThresholdUv', TransTools.FieldOr(options, 'artifactThresholdUv', 150), ...
    'ArtifactWindowMs', TransTools.FieldOr(options, 'artifactWindowMs', 2000), ...
    'ArtifactStepMs', TransTools.FieldOr(options, 'artifactStepMs', 100), ...
    'Output', char(string(TransTools.FieldOr(options, 'output', 'average'))));

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
    for k = 1:numel(info.formulas)
        if ~strcmp(strrep(info.formulas(k).formula, ' ', ''), 'y~1')
            fprintf('  %-28s %s\n', info.formulas(k).type, info.formulas(k).formula);
        end
    end
    if isfield(info, 'output') && strcmpi(info.output, 'terms')
        fprintf('  Returned as %d term waveform(s): %s.\n', numel(info.terms), ...
            strjoin({info.terms.label}, '; '));
    end
    if isfield(info, 'output') && strcmpi(info.output, 'trials')
        fprintf('  Returned as %d overlap-corrected trial(s)', info.trials);
        if info.trialsDropped > 0
            fprintf(', %d dropped (window off the recording or on a stretch left out of the model)', ...
                info.trialsDropped);
        end
        fprintf('.\n');
    end
end
