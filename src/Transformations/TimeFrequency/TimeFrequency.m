function [EEG, opts] = TimeFrequency(varargin)
%TIMEFREQUENCY  Wavelet time-frequency (ERSP) analysis for every bin.
%
%   Computes an event-related spectral perturbation (ERSP) map per bin:
%   complex Morlet wavelet convolution against every trial in that bin,
%   with variable wavelet cycles growing linearly with frequency (the
%   same time/frequency-resolution tradeoff EEGLAB's newtimef uses --
%   few cycles at low frequencies for temporal precision, more cycles at
%   high frequencies for spectral precision), single-trial power
%   averaged across trials, then baseline-corrected in dB relative to a
%   user-set pre-stimulus window (the standard ERSP convention -- see
%   readme.MD's bibliography for the general lineage this app's
%   algorithms follow).
%
%   A normal, persisted transformation (Alakazam.onTransformation):
%   returns a modified dataset, added as a tree node under the source
%   epoched dataset and drawn in its own tab by TimeFrequencyView, the
%   same way Average/Fourier results are. All the actual per-channel,
%   per-bin ERSP power is computed here, once, up front, with a progress
%   bar (see TransTools.ComputeErsp); TimeFrequencyView then only slices
%   the already-computed EEG.ersp array per channel step -- instant,
%   rather than re-running the wavelet convolution live on every
%   keypress.
%
%   Signature (Alakazam transformation contract, matching Fourier.m):
%   [EEG, opts] = TimeFrequency(input) pops the options dialog and stores
%   the chosen settings in TransformSettings for next time; [EEG, opts] =
%   TimeFrequency(input, opts) replays with a stored options struct and no
%   dialog (used when a branch bearing this transformation is dragged
%   onto another dataset).

if nargin < 1
    throw(MException('Alakazam:TimeFrequency', ...
        'Problem in TimeFrequency: needs a dataset to run on, and none was given.'));
end
input = varargin{1};

if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'EPOCHED')
    throw(MException('Alakazam:TimeFrequency', sprintf([ ...
        'Problem in TimeFrequency: needs single-trial epoched data (DataFormat = "EPOCHED"), ' ...
        'not this dataset (DataFormat = "%s"). Run DefineBins with an ''epoch'' ' ...
        'statement first -- time-frequency power has to be computed per trial, ' ...
        'then averaged, so it needs the individual trials, not an ' ...
        'already-averaged ERP.'], input.DataFormat)));
end

if ~isfield(input, 'bindesc') || isempty(input.bindesc)
    throw(MException('Alakazam:TimeFrequency', ...
        'Problem in TimeFrequency: this dataset has no bins (EEG.bindesc is empty). Run DefineBins first.'));
end

if nargin == 1
    stored = TransformSettings.get('TimeFrequency');
    if isempty(stored)
        stored = struct('MinFreq', 2, 'MaxFreq', min(40, floor(input.srate / 3)), ...
            'NumFreqs', 30, 'MinCycles', 3, 'MaxCycles', 10, ...
            'BaselineStart', input.times(1), 'BaselineStop', 0);
    end
    opts = TransformOptionsDialog( ...
        'Description', 'Wavelet time-frequency (ERSP) settings, applied to every bin.', ...
        'title', 'TimeFrequency options', ...
        'separator', 'Frequency range:', ...
        {'Minimum frequency (Hz)'; 'MinFreq'}, stored.MinFreq, ...
        {'Maximum frequency (Hz)'; 'MaxFreq'}, stored.MaxFreq, ...
        {'Number of frequencies'; 'NumFreqs'}, stored.NumFreqs, ...
        'separator', 'Wavelet cycles (time/frequency resolution tradeoff):', ...
        {'Cycles at minimum frequency'; 'MinCycles'}, stored.MinCycles, ...
        {'Cycles at maximum frequency'; 'MaxCycles'}, stored.MaxCycles, ...
        'separator', 'Baseline window for dB correction:', ...
        {'Baseline start (ms)'; 'BaselineStart'}, stored.BaselineStart, ...
        {'Baseline stop (ms)'; 'BaselineStop'}, stored.BaselineStop);
    if isempty(opts)
        % Cancelled: nothing to persist (leave the remembered settings
        % untouched) and nothing to run -- Alakazam.onTransformation
        % treats an empty EEG as "cancelled", not an error.
        EEG = [];
        return;
    end
    TransformSettings.set('TimeFrequency', opts);
elseif nargin == 2
    opts = varargin{2};
end

if opts.MaxFreq >= input.srate / 2
    throw(MException('Alakazam:TimeFrequency', sprintf([ ...
        'Problem in TimeFrequency: maximum frequency (%.3g Hz) must be below ' ...
        'the Nyquist frequency (%.3g Hz for this %g Hz dataset).'], ...
        opts.MaxFreq, input.srate / 2, input.srate)));
end
if opts.BaselineStop <= opts.BaselineStart
    throw(MException('Alakazam:TimeFrequency', ...
        'Problem in TimeFrequency: the baseline window''s stop time must be after its start time.'));
end

%% Compute every channel x bin's ERSP up front (see TimeFrequencyView.m
%  for why: instant channel-stepping afterward, not a live recompute).
[ersp, freqs] = TransTools.ComputeErsp(input, opts);

%% Build the result dataset. EEG.data/.chanlocs/.times/.bindesc etc. are
%  all carried over unchanged from the source epoched dataset (still
%  meaningful, and left alone the same way Fourier.m leaves its own
%  input's non-spectral fields alone) -- TimeFrequencyView draws
%  entirely from the new .ersp/.freqs fields, not from .data.
EEG = input;
EEG.ersp  = ersp;
EEG.freqs = freqs;
