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
if nargin < 1
    throw(MException('Alakazam:CoherenceTopography', ...
        'Problem in CoherenceTopography: needs a dataset to run on, and none was given.'));
end
input = varargin{1};

if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'EPOCHED')
    throw(MException('Alakazam:CoherenceTopography', sprintf([ ...
        'Problem in CoherenceTopography: needs single-trial epoched data ' ...
        '(DataFormat = "EPOCHED"), not this dataset (DataFormat = "%s"). Run ' ...
        'DefineBins with an ''epoch'' statement first -- coherence is estimated ' ...
        'across trials.'], input.DataFormat)));
end

labels = {input.chanlocs.labels};

if nargin < 2
    stored = TransformSettings.get('CoherenceTopography');
    if isempty(stored) || ~isstruct(stored)
        stored = struct('RefChannel', '', 'MinFreq', 55, 'MaxFreq', 68, ...
            'Frequency', 0, 'TimeStart', 0, 'TimeStop', 0);
    end
    refList = referenceChoices(labels, getField(stored, 'RefChannel', ''));
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
        return;
    end
    TransformSettings.set('CoherenceTopography', opts);
else
    opts = varargin{2};
end

%% Validate + resolve the reference channel
if opts.Frequency <= 0 && (opts.MaxFreq <= opts.MinFreq)
    throw(MException('Alakazam:CoherenceTopography', ...
        'Problem in CoherenceTopography: need Maximum frequency > Minimum frequency for auto-detection (or set a fixed frequency).'));
end
targetMax = max(opts.MaxFreq, opts.Frequency);
if targetMax >= input.srate / 2
    throw(MException('Alakazam:CoherenceTopography', sprintf([ ...
        'Problem in CoherenceTopography: frequency (%.3g Hz) must be below the Nyquist ' ...
        'frequency (%.3g Hz for this %g Hz dataset).'], targetMax, input.srate / 2, input.srate)));
end
refIdx = find(strcmpi(labels, strtrim(char(string(opts.RefChannel)))), 1);
if isempty(refIdx)
    throw(MException('Alakazam:CoherenceTopography', ...
        'Problem in CoherenceTopography: reference channel "%s" is not a channel in this dataset.', ...
        opts.RefChannel));
end

computeOpts = opts;
computeOpts.RefIndex = refIdx;
[coh, detFreq, refAmp, ampFreqs] = TransTools.ComputeCoherenceTopography(input, computeOpts);

%% Resolve scalp positions (template lookup, exactly as ScalpDistribution does:
%  a direct readlocs lookup by label, so no eeg_checkset is run on an averaged/
%  bin-based struct, and the template's own nose-up orientation is kept).
[scalpLocs, hasPos] = templateScalpLocs(input.chanlocs, ...
    TransTools.Dipfit1005File('Alakazam:CoherenceTopography'));
if ~any(hasPos)
    throw(MException('Alakazam:CoherenceTopography', ...
        ['Problem in CoherenceTopography: none of this dataset''s channels match a ' ...
         'standard 10-5 scalp position, so there is no head-map to draw. Rename ' ...
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
        ['Problem in CoherenceTopography: no bin has trials to compute coherence ' ...
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

% ======================================================================= %
function [locs, hasPos] = templateScalpLocs(chanlocs, elcFile)
%TEMPLATESCALPLOCS  Copy theta/radius/X/Y/Z from the 10-5 template by label, so
%   DrawScalpMap orients the maps the same as ScalpDistribution. HASPOS marks
%   the channels the template recognised.
    locs = chanlocs;
    hasPos = false(1, numel(locs));
    template = readlocs(elcFile);
    templateLabels = lower(string({template.labels}));
    for c = 1:numel(locs)
        m = find(templateLabels == lower(string(locs(c).labels)), 1);
        if isempty(m); continue; end
        locs(c).X      = template(m).X;
        locs(c).Y      = template(m).Y;
        locs(c).Z      = template(m).Z;
        locs(c).theta  = template(m).theta;
        locs(c).radius = template(m).radius;
        hasPos(c) = true;
    end
end

function list = referenceChoices(labels, preferred)
%REFERENCECHOICES  Channel labels as a dropdown cellstr, with the previously
%   chosen or an auto-detected photodiode-like channel put first.
    labels = cellfun(@(s) char(string(s)), labels, 'UniformOutput', false);
    pick = '';
    if ~isempty(char(string(preferred))) && any(strcmpi(labels, preferred))
        pick = preferred;
    else
        hit = find(~cellfun(@isempty, regexpi(labels, ...
            'photodiode|diode|photo|^pd$|lum|sensor|erg', 'once')), 1);
        if ~isempty(hit); pick = labels{hit}; end
    end
    if isempty(pick); list = labels; else; list = putFirst(labels, pick); end
end

function list = putFirst(list, value)
    idx = find(strcmpi(list, char(string(value))), 1);
    if ~isempty(idx)
        list = [list(idx), list(setdiff(1:numel(list), idx, 'stable'))];
    end
end

function v = getField(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name)); v = s.(name); else; v = default; end
end
