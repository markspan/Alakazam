function [EEG, opts] = CoherenceTopography(varargin)
%% CoherenceTopography  Scalp head-map of coherence to a reference, per bin.
%
%   The topographic companion to CoherenceMap: instead of a per-channel
%   time x frequency heatmap, it draws one scalp topography per bin of every
%   channel's magnitude-squared coherence to a reference channel (e.g. a
%   photodiode) at a single frequency, the RIFT / frequency-tagging read-out
%   shown as a head-map (cf. Dimigen et al., 2025, Figure 1C).
%
%   The frequency is taken from the reference itself, so 60 Hz and 64 Hz
%   conditions each get their own tagging frequency with no typing: by default
%   the reference's strongest spectral component (the same peak CoherenceMap
%   stores), or, as an option, its strongest evoked response within a search
%   band; a fixed frequency entered overrides both. Coherence is estimated across
%   the bin's trials over an optional steady-state window, by default as the
%   frame-averaged coherence that CoherenceMap draws and SpectralMeasure reports
%   (see TransTools.ComputeCoherenceTopography for the two estimators).
%
%   Runs on EPOCHED single-trial data. Only channels with a standard 10-5 scalp
%   position are drawn (the reference and any EOG/ECG have none and are left
%   out of the map, exactly as ScalpDistribution does); coherence is still
%   computed for every channel and kept for export.
%
%   Signature (Alakazam transformation contract):
%   [EEG, opts] = CoherenceTopography(input)       % options dialog
%   [EEG, opts] = CoherenceTopography(input, opts) % replay a stored struct
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:CoherenceTopography', varargin{2:end});
input = varargin{1};

if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'EPOCHED')
    throw(MException('Alakazam:CoherenceTopography', sprintf([ ...
        'Problem in CoherenceTopography: this needs single-trial epoched data ' ...
        '(DataFormat = "EPOCHED"), not this dataset (DataFormat = "%s"). Please run ' ...
        'DefineBins with an ''epoch'' statement first -- coherence is estimated ' ...
        'across trials.'], input.DataFormat)));
end

labels = {input.chanlocs.labels};

if interactive
    stored = TransformSettings.get('CoherenceTopography');
    % A first run offers the estimator of record and the reference's own peak. A
    % stored run keeps what it was made with: options from before these two
    % existed mean the single window and the band search.
    if isempty(stored) || ~isstruct(stored)
        stored = struct('RefChannel', '', 'MinFreq', 55, 'MaxFreq', 68, ...
            'Frequency', 0, 'TimeStart', 0, 'TimeStop', 0, ...
            'Method', 'frames', 'TagSource', 'reference', 'WindowMs', 510);
    end
    methodList = TransTools.PutFirst({'frames', 'window'}, TransTools.FieldOr(stored, 'Method', 'window'));
    tagList = TransTools.PutFirst({'reference', 'band'}, TransTools.FieldOr(stored, 'TagSource', 'band'));
    refList = TransTools.ReferenceChoices(labels, TransTools.FieldOr(stored, 'RefChannel', ''));
    opts = TransformOptionsDialog( ...
        'Description', ['Scalp head-map of every channel''s coherence to a reference ' ...
            '(e.g. a photodiode), per bin. The frequency is taken from the ' ...
            'reference unless a fixed one is given.'], ...
        'title', 'CoherenceTopography options', ...
        'separator', 'Reference:', ...
        {'Reference channel'; 'RefChannel'}, refList, ...
        'separator', 'Coherence estimator:', ...
        {'Estimator (frames = averaged over sliding frames)'; 'Method'}, methodList, ...
        {'Frame length (ms), frames only'; 'WindowMs'}, TransTools.FieldOr(stored, 'WindowMs', 510), ...
        'separator', 'Frequency (taken from the reference):', ...
        {'Source (reference = its strongest component)'; 'TagSource'}, tagList, ...
        {'Search band, minimum (Hz), band source only'; 'MinFreq'}, stored.MinFreq, ...
        {'Search band, maximum (Hz), band source only'; 'MaxFreq'}, stored.MaxFreq, ...
        {'Fixed frequency (Hz, 0 = from the reference)'; 'Frequency'}, stored.Frequency, ...
        'separator', 'Analysis window (ms, 0 to 0 = whole epoch):', ...
        {'Start'; 'TimeStart'}, stored.TimeStart, ...
        {'Stop'; 'TimeStop'}, stored.TimeStop);
    if isempty(opts)
        EEG = [];   % cancelled
        opts = [];   % the contract is two outputs; both must be assigned
        % (named for THIS function's own second output: assigning a
        % variable called "options" here left opts holding the Init
        % sentinel, which is what the caller then tried to store)
        return;
    end
    TransformSettings.set('CoherenceTopography', opts);
end

%% Validate + resolve the reference channel
if opts.Frequency <= 0 && (opts.MaxFreq <= opts.MinFreq)
    throw(MException('Alakazam:CoherenceTopography', ...
        'Problem in CoherenceTopography: Maximum frequency needs to be greater than Minimum frequency for auto-detection (or please set a fixed frequency).'));
end
targetMax = max(opts.MaxFreq, opts.Frequency);
if targetMax >= input.srate / 2
    throw(MException('Alakazam:CoherenceTopography', sprintf([ ...
        'Problem in CoherenceTopography: I''m afraid frequency (%.3g Hz) must be below the Nyquist ' ...
        'frequency (%.3g Hz for this %g Hz dataset).'], targetMax, input.srate / 2, input.srate)));
end
refIdx = find(strcmpi(labels, strtrim(char(string(opts.RefChannel)))), 1);
if isempty(refIdx)
    throw(MException('Alakazam:CoherenceTopography', ...
        'Problem in CoherenceTopography: I''m afraid reference channel "%s" is not a channel in this dataset.', ...
        opts.RefChannel));
end

computeOpts = opts;
computeOpts.RefIndex = refIdx;
[coh, detFreq, refAmp, ampFreqs] = TransTools.ComputeCoherenceTopography(input, computeOpts);

%% Resolve scalp positions (template lookup, exactly as ScalpDistribution does:
%  a direct readlocs lookup by label, so no eeg_checkset is run on an averaged/
%  bin-based struct, and the template's own nose-up orientation is kept).
[scalpLocs, hasPos] = TransTools.TemplateScalpLocs(input.chanlocs, ...
    TransTools.Template1005File('Alakazam:CoherenceTopography'));
if ~any(hasPos)
    throw(MException('Alakazam:CoherenceTopography', ...
        ['Problem in CoherenceTopography: I''m afraid none of this dataset''s channels match a ' ...
         'standard 10-5 scalp position, so there is no head-map to draw. Please rename ' ...
         'channels to 10-5 nomenclature, or set locations (Channel editor) first.']));
end

% Keep only bins that have real trials: a difference / combination bin has no
% trials of its own, so coherence (a normalised ratio, not linear across bins)
% is undefined for it -- don't draw an empty tile for it.
if isfield(input, 'bindesc') && ~isempty(input.bindesc) && isfield(input.bindesc, 'trials')
    hasTrials = arrayfun(@(d) isnumeric(d.trials) && ~isempty(d.trials), input.bindesc);
    binLabels = {input.bindesc.label};
else
    hasTrials = true(1, size(coh, 2));
    binLabels = {char(string(input.id))};
end
keep = find(hasTrials);
if isempty(keep)
    throw(MException('Alakazam:CoherenceTopography', ...
        ['Problem in CoherenceTopography: I''m afraid no bin has trials to compute coherence ' ...
         'from (only difference/combination bins were found).']));
end
coh       = coh(:, keep);
detFreq   = detFreq(keep);
refAmp    = refAmp(:, keep);
binLabels = binLabels(keep);

drawn   = hasPos(:)' & (1:numel(hasPos) ~= refIdx);   % never draw the reference itself
mapVals = coh(drawn, :);
mapLim  = max(mapVals(:), [], 'omitnan');
if ~isfinite(mapLim) || mapLim <= 0; mapLim = 1; end

EEG = input;
% Clear any CoherenceMap/TimeFrequency fields inherited from an ancestor
% node (running CoherenceTopography on either's result is a normal thing to
% do -- all three just need EPOCHED data, CoherenceMap/CoherenceTopography
% also a reference channel). Left in place, a stale non-empty EEG.coherence
% or EEG.ersp made AlakazamPlotter.plotEpoched's routing (both checked
% BEFORE the CohTopoValues branch, since "or a grand average, renamed"
% needs a field-presence fallback alongside the id check) pick CoherenceView
% or TimeFrequencyView over CoherenceTopographyView for this node --
% reported directly for the CoherenceMap case: CoherenceMap and
% CoherenceTopography rendering identically. See
% TransTools.ClearForeignResultFields for the full field lists.
EEG = TransTools.ClearForeignResultFields(EEG, 'CoherenceMap', 'TimeFrequency');
EEG.CohTopoValues    = coh;                 % nChan x nKeptBins (all channels; NaN ref)
EEG.CohTopoChanlocs  = scalpLocs(drawn);    % positioned, non-reference channels drawn
EEG.CohTopoDrawn     = find(drawn);         % their indices into the full channel list
EEG.CohTopoFreqs     = detFreq;             % 1 x nKeptBins Hz used per bin
EEG.CohTopoRef       = char(labels{refIdx});
EEG.CohTopoLimit     = mapLim;
EEG.CohTopoRefAmp    = refAmp;              % reference evoked spectrum over the band (per kept bin)
EEG.CohTopoAmpFreqs  = ampFreqs;
EEG.CohTopoBins      = keep;                % original bin indices of the kept (trial-bearing) bins
EEG.CohTopoBinLabels = binLabels;
EEG.CohTopoMethod    = lower(char(string(TransTools.FieldOr(opts, 'Method', 'window'))));      % what made COH
EEG.CohTopoTagSource = lower(char(string(TransTools.FieldOr(opts, 'TagSource', 'band'))));     % where CohTopoFreqs came from
end
