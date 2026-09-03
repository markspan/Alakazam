function [EEG, opts] = CoherenceTopography(varargin)
%% CoherenceTopography  Scalp head-map of coherence to a reference, per bin.
%
%   The topographic companion to CoherenceMap: instead of a per-channel
%   time x frequency heatmap, it draws one scalp topography per bin of every
%   channel's magnitude-squared coherence to a reference channel (e.g. a
%   photodiode) at a single frequency, the RIFT / frequency-tagging read-out
%   shown as a head-map (cf. Dimigen et al., 2025, Figure 1C).
%
%   The frequency is taken from the reference itself: for each bin it is the
%   reference channel's strongest evoked response within a search band
%   (so 60 Hz and 64 Hz conditions each get their own tagging frequency with
%   no typing), unless a fixed frequency is entered to override that. Coherence
%   is estimated across the bin's trials over an optional steady-state window
%   (see TransTools.ComputeCoherenceTopography for the maths, shared with
%   SpectralMeasure and CoherenceMap).
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
    if isempty(stored) || ~isstruct(stored)
        stored = struct('RefChannel', '', 'MinFreq', 55, 'MaxFreq', 68, ...
            'Frequency', 0, 'TimeStart', 0, 'TimeStop', 0);
    end
    refList = TransTools.ReferenceChoices(labels, TransTools.FieldOr(stored, 'RefChannel', ''));
    opts = TransformOptionsDialog( ...
        'Description', ['Scalp head-map of every channel''s coherence to a reference ' ...
            '(e.g. a photodiode), per bin. The frequency is auto-detected from the ' ...
            'reference unless a fixed one is given.'], ...
        'title', 'CoherenceTopography options', ...
        'separator', 'Reference:', ...
        {'Reference channel'; 'RefChannel'}, refList, ...
        'separator', 'Frequency (auto-detected from the reference):', ...
        {'Search band, minimum (Hz)'; 'MinFreq'}, stored.MinFreq, ...
        {'Search band, maximum (Hz)'; 'MaxFreq'}, stored.MaxFreq, ...
        {'Fixed frequency (Hz, 0 = auto)'; 'Frequency'}, stored.Frequency, ...
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
end
