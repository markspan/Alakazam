function [EEG, opts] = CoherenceMap(varargin)
%% CoherenceMap  Time-resolved coherence between every channel and a reference
%   channel (e.g. a photodiode), as a per-channel time x frequency heatmap --
%   the frequency-tagging / RIFT read-out shown in Dimigen et al. (2025).
%
%   Runs on EPOCHED single-trial data. For each channel it estimates the
%   magnitude-squared coherence to the reference across the bin's trials, at
%   every time point and frequency (see ComputeCoherenceMap for the
%   maths -- the same coherence SpectralMeasure computes, but resolved over
%   time). The reference is typically a photodiode recording the flicker; the
%   dialog defaults to a photodiode-like channel if one is present.
%
%   Three decompositions are offered: a Morlet Wavelet (the same variable-cycle
%   wavelet TimeFrequency uses), a fixed-window STFT (as in the RIFT paper's
%   newcrossf) with a Hann or boxcar taper, or a filter-Hilbert band-pass
%   around each frequency (Arora et al. 2026), which resolves time more finely
%   for a narrow band.
%
%   The reference can also be a synthetic sine at a chosen frequency, for a
%   recording with no photodiode. A sine that starts at the same phase on every
%   trial makes this the inter-trial coherence of each channel; it measures
%   nothing if the flicker's phase was randomised from trial to trial.
%
%   Also stores, all of them about the reference channel itself:
%     EEG.cohRefPower     its OWN power in the analysed band (see
%                         ComputeCoherenceMap's own header).
%                         exportCoherenceCSVs.m reads the tagged frequency off
%                         this, not off an average of every channel's
%                         coherence, since the reference (typically a
%                         photodiode) measures the physical flicker directly
%                         and a noisy EEG channel's coherence to it can peak
%                         at the wrong frequency entirely.
%     EEG.cohRefSpectrum, EEG.cohRefSpecFreqs, EEG.cohRefPeakHz
%                         its amplitude spectrum from 0 Hz to 150 Hz and its
%                         strongest frequency, per bin (see
%                         TransTools.ReferenceSpectrum). The band above is
%                         only what the user chose to look at; this shows
%                         where the flicker actually was, so a condition tagged
%                         outside the band can be recognised as such.
%
%   Signature (Alakazam transformation contract, matching TimeFrequency.m):
%   [EEG, opts] = CoherenceMap(input) pops the options dialog and stores the
%   chosen settings; [EEG, opts] = CoherenceMap(input, opts) replays a stored
%   options struct with no dialog. Options stored before Taper, SineHz,
%   BandwidthHz and StepMs existed replay unchanged.
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:CoherenceMap', varargin{2:end});
input = varargin{1};

sineLabel = '(synthetic sine)';

if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'EPOCHED')
    throw(MException('Alakazam:CoherenceMap', sprintf([ ...
        'Problem in CoherenceMap: this needs single-trial epoched data (DataFormat = ' ...
        '"EPOCHED"), not this dataset (DataFormat = "%s"). Please run DefineBins with an ' ...
        '''epoch'' statement first -- coherence is estimated across trials.'], ...
        input.DataFormat)));
end

labels = {input.chanlocs.labels};

if interactive
    stored = TransformSettings.get('CoherenceMap');
    if isempty(stored) || ~isstruct(stored)
        stored = struct('RefChannel', '', 'Method', 'Wavelet', ...
            'MinFreq', 2, 'MaxFreq', min(80, floor(input.srate / 3)), 'NumFreqs', 40, ...
            'MinCycles', 3, 'MaxCycles', 12, 'WindowMs', 500, 'PadRatio', 4);
    end
    storedRef = TransTools.FieldOr(stored, 'RefChannel', '');
    refList = [TransTools.ReferenceChoices(labels, storedRef), {sineLabel}];
    if strcmp(storedRef, sineLabel)
        refList = TransTools.PutFirst(refList, sineLabel);
    end
    methodList = TransTools.PutFirst({'Wavelet', 'STFT', 'FilterHilbert'}, ...
        TransTools.FieldOr(stored, 'Method', 'Wavelet'));
    taperList = TransTools.PutFirst({'Hann', 'Boxcar'}, TransTools.FieldOr(stored, 'Taper', 'Hann'));

    opts = TransformOptionsDialog( ...
        'Description', ['Time-resolved coherence of every channel to a reference ' ...
            '(e.g. a photodiode), per bin. Pick the reference and a decomposition.'], ...
        'title', 'CoherenceMap options', ...
        'separator', 'Reference and method:', ...
        {'Reference channel'; 'RefChannel'}, refList, ...
        {'Sine frequency (Hz), if sine'; 'SineHz'}, TransTools.FieldOr(stored, 'SineHz', 60), ...
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
        {'Zero-padding ratio'; 'PadRatio'}, stored.PadRatio, ...
        {'Window taper'; 'Taper'}, taperList, ...
        'separator', 'Band-pass (FilterHilbert only):', ...
        {'Bandwidth (Hz, FWHM)'; 'BandwidthHz'}, TransTools.FieldOr(stored, 'BandwidthHz', 2), ...
        {'Time step (ms)'; 'StepMs'}, TransTools.FieldOr(stored, 'StepMs', 50));
    if isempty(opts)
        EEG = [];   % cancelled
        opts = [];   % the contract is two outputs; both must be assigned
        % (named for THIS function's own second output: assigning a
        % variable called "options" here left opts holding the Init
        % sentinel, which is what the caller then tried to store)
        return;
    end
    TransformSettings.set('CoherenceMap', opts);
end

%% Validate + resolve the reference channel to a row index
if opts.MaxFreq >= input.srate / 2
    throw(MException('Alakazam:CoherenceMap', sprintf([ ...
        'Problem in CoherenceMap: I''m afraid the maximum frequency (%.3g Hz) must be below the ' ...
        'Nyquist frequency (%.3g Hz for this %g Hz dataset).'], ...
        opts.MaxFreq, input.srate / 2, input.srate)));
end
if opts.MaxFreq <= opts.MinFreq || opts.NumFreqs < 2
    throw(MException('Alakazam:CoherenceMap', ...
        'Problem in CoherenceMap: please set Maximum frequency greater than Minimum frequency, with at least 2 frequencies.'));
end

refName = strtrim(char(string(opts.RefChannel)));
work = input;
if strcmp(refName, sineLabel)
    sineHz = double(TransTools.FieldOr(opts, 'SineHz', NaN));
    if ~isscalar(sineHz) || ~(sineHz > 0) || sineHz >= input.srate / 2
        throw(MException('Alakazam:CoherenceMap', sprintf([ ...
            'Problem in CoherenceMap: I''m afraid the synthetic sine frequency must be above 0 Hz ' ...
            'and below the Nyquist frequency (%.3g Hz for this %g Hz dataset).'], ...
            input.srate / 2, input.srate)));
    end
    % The sine is appended as one more channel, so the whole coherence
    % machinery treats it exactly like a recorded reference; its own row is
    % dropped from the result again below. Its phase is fixed to the epoch's
    % time zero, the same on every trial.
    tone = sin(2 * pi * sineHz * double(input.times(:).') / 1000);
    work.data(end + 1, :, :) = repmat(cast(tone, 'like', input.data), [1, 1, size(input.data, 3)]);
    work.nbchan = input.nbchan + 1;
    refIdx = work.nbchan;
    refLabel = sprintf('sine %g Hz', sineHz);
else
    refIdx = find(strcmpi(labels, refName), 1);
    if isempty(refIdx)
        throw(MException('Alakazam:CoherenceMap', ...
            'Problem in CoherenceMap: I''m afraid reference channel "%s" is not a channel in this dataset.', ...
            opts.RefChannel));
    end
    refLabel = char(labels{refIdx});
end

computeOpts = opts;
computeOpts.RefIndex = refIdx;
[coh, freqs, cohTimes, refPower] = ComputeCoherenceMap(work, computeOpts);
[refSpectrum, refSpecFreqs, refPeakHz] = TransTools.ReferenceSpectrum(work, refIdx);
if strcmp(refName, sineLabel)
    coh = coh(1:end - 1, :, :, :);
end

%% Build the result: pass the epoched data through, add the coherence map.
EEG = input;
% Clear any CoherenceTopography/TimeFrequency fields inherited from an
% ancestor node -- both are a normal thing to chain this onto (EPOCHED data
% with a reference channel; TimeFrequency needs no reference channel at
% all). See TransTools.ClearForeignResultFields for why a stale sibling
% field here would break AlakazamPlotter.plotEpoched's routing.
EEG = TransTools.ClearForeignResultFields(EEG, 'CoherenceTopography', 'TimeFrequency');
EEG.coherence      = coh;
EEG.cohFreqs       = freqs;
EEG.cohTimes       = cohTimes;
EEG.cohRefPower    = refPower;
EEG.cohRefSpectrum = single(refSpectrum);
EEG.cohRefSpecFreqs = refSpecFreqs;
EEG.cohRefPeakHz   = refPeakHz;
EEG.cohRef         = refLabel;
EEG.cohMethod      = char(string(opts.Method));
end
