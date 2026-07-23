function [EEG, opts] = CoherenceMap(varargin)
%% CoherenceMap  Time-resolved coherence between every channel and a reference
%   channel (e.g. a photodiode), as a per-channel time x frequency heatmap --
%   the frequency-tagging / RIFT read-out shown in Dimigen et al. (2025).
%
%   Runs on EPOCHED single-trial data. For each channel it estimates the
%   magnitude-squared coherence to the reference across the bin's trials, at
%   every time point and frequency (see TransTools.ComputeCoherenceMap for the
%   maths -- the same coherence SpectralMeasure computes, but resolved over
%   time). The reference is typically a photodiode recording the flicker; the
%   dialog defaults to a photodiode-like channel if one is present.
%
%   Two decompositions are offered: a Morlet Wavelet (the same variable-cycle
%   wavelet TimeFrequency uses) or a fixed-window STFT (as in the RIFT paper's
%   newcrossf).
%
%   Signature (Alakazam transformation contract, matching TimeFrequency.m):
%   [EEG, opts] = CoherenceMap(input) pops the options dialog and stores the
%   chosen settings; [EEG, opts] = CoherenceMap(input, opts) replays a stored
%   options struct with no dialog.
if nargin < 1
    throw(MException('Alakazam:CoherenceMap', ...
        'Problem in CoherenceMap: needs a dataset to run on, and none was given.'));
end
input = varargin{1};

if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'EPOCHED')
    throw(MException('Alakazam:CoherenceMap', sprintf([ ...
        'Problem in CoherenceMap: needs single-trial epoched data (DataFormat = ' ...
        '"EPOCHED"), not this dataset (DataFormat = "%s"). Run DefineBins with an ' ...
        '''epoch'' statement first -- coherence is estimated across trials.'], ...
        input.DataFormat)));
end

labels = {input.chanlocs.labels};

if nargin < 2
    stored = TransformSettings.get('CoherenceMap');
    if isempty(stored) || ~isstruct(stored)
        stored = struct('RefChannel', '', 'Method', 'Wavelet', ...
            'MinFreq', 2, 'MaxFreq', min(80, floor(input.srate / 3)), 'NumFreqs', 40, ...
            'MinCycles', 3, 'MaxCycles', 12, 'WindowMs', 500, 'PadRatio', 4);
    end
    refList = TransTools.ReferenceChoices(labels, getField(stored, 'RefChannel', ''));
    methodList = TransTools.PutFirst({'Wavelet', 'STFT'}, getField(stored, 'Method', 'Wavelet'));

    opts = TransformOptionsDialog( ...
        'Description', ['Time-resolved coherence of every channel to a reference ' ...
            '(e.g. a photodiode), per bin. Pick the reference and a decomposition.'], ...
        'title', 'CoherenceMap options', ...
        'separator', 'Reference and method:', ...
        {'Reference channel'; 'RefChannel'}, refList, ...
        {'Decomposition'; 'Method'}, methodList, ...
        'separator', 'Frequency range:', ...
        {'Minimum frequency (Hz)'; 'MinFreq'}, stored.MinFreq, ...
        {'Maximum frequency (Hz)'; 'MaxFreq'}, stored.MaxFreq, ...
        {'Number of frequencies'; 'NumFreqs'}, stored.NumFreqs, ...
        'separator', 'Morlet wavelet cycles (Wavelet only):', ...
        {'Cycles at minimum frequency'; 'MinCycles'}, stored.MinCycles, ...
        {'Cycles at maximum frequency'; 'MaxCycles'}, stored.MaxCycles, ...
        'separator', 'STFT window (STFT only):', ...
        {'Window length (ms)'; 'WindowMs'}, stored.WindowMs, ...
        {'Zero-padding ratio'; 'PadRatio'}, stored.PadRatio);
    if isempty(opts)
        EEG = [];   % cancelled
        return;
    end
    TransformSettings.set('CoherenceMap', opts);
else
    opts = varargin{2};
end

%% Validate + resolve the reference channel to a row index
if opts.MaxFreq >= input.srate / 2
    throw(MException('Alakazam:CoherenceMap', sprintf([ ...
        'Problem in CoherenceMap: maximum frequency (%.3g Hz) must be below the ' ...
        'Nyquist frequency (%.3g Hz for this %g Hz dataset).'], ...
        opts.MaxFreq, input.srate / 2, input.srate)));
end
if opts.MaxFreq <= opts.MinFreq || opts.NumFreqs < 2
    throw(MException('Alakazam:CoherenceMap', ...
        'Problem in CoherenceMap: need Maximum frequency > Minimum frequency and at least 2 frequencies.'));
end
refIdx = find(strcmpi(labels, strtrim(char(string(opts.RefChannel)))), 1);
if isempty(refIdx)
    throw(MException('Alakazam:CoherenceMap', ...
        'Problem in CoherenceMap: reference channel "%s" is not a channel in this dataset.', ...
        opts.RefChannel));
end

computeOpts = opts;
computeOpts.RefIndex = refIdx;
[coh, freqs, cohTimes] = TransTools.ComputeCoherenceMap(input, computeOpts);

%% Build the result: pass the epoched data through, add the coherence map.
EEG = input;
EEG.coherence = coh;
EEG.cohFreqs  = freqs;
EEG.cohTimes  = cohTimes;
EEG.cohRef    = char(labels{refIdx});
EEG.cohMethod = char(string(opts.Method));
end

function v = getField(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name)); v = s.(name); else; v = default; end
end
