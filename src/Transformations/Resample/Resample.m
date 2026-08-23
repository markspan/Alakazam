function [EEG, options] = Resample(input, varargin)
%% Resample  Change the sampling rate of a continuous recording.
%
%   Wraps EEGLAB's pop_resample (anti-alias filtered resampling), driven by an
%   Alakazam options dialog. Resampling is done on the CONTINUOUS recording,
%   before segmenting, which is the sensible place for it: event latencies are
%   rescaled with the data, and every later step inherits the new rate.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Resample(input)        % interactive dialog
%     [EEG, options] = Resample(input, opts)  % replay a stored options struct
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Resample', varargin{:});
if ~isfield(input, 'data') || isempty(input.data)
    throw(MException('Alakazam:Resample', 'Problem in Resample: I''m afraid this dataset has no data.'));
end
if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'CONTINUOUS')
    throw(MException('Alakazam:Resample', sprintf([ ...
        'Problem in Resample: this only works on a continuous recording, not on this dataset ' ...
        '(DataFormat = "%s"). Would you resample before segmenting (before DefineBins)?'], ...
        char(string(TransTools.FieldOr(input, 'DataFormat', 'unknown'))))));
end

if interactive
    stored = TransformSettings.get('Resample');
    if isempty(stored) || ~isfield(stored, 'NewRate') || isempty(stored.NewRate)
        stored = struct('NewRate', defaultRate(input.srate));
    end
    options = TransformOptionsDialog( ...
        'title', 'Resample options', ...
        'Description', sprintf(['Resample the continuous recording (currently %g Hz) to a new ' ...
            'sampling rate. pop_resample anti-alias filters before decimating.'], input.srate), ...
        'separator', 'Sampling rate:', ...
        {'New sampling rate (Hz)'; 'NewRate'}, stored.NewRate);
    if isempty(options)
        EEG = [];   % cancelled -- no node, no compute
        return;
    end
    TransformSettings.set('Resample', options);
else
    options = opts;
end

newRate = options.NewRate;
if ~isnumeric(newRate) || ~isscalar(newRate) || ~isfinite(newRate) || newRate <= 0
    throw(MException('Alakazam:Resample', ...
        'Problem in Resample: the new sampling rate needs to be a positive number (got %s) -- could you check that value?', ...
        mat2str(newRate)));
end
if abs(newRate - input.srate) < eps
    EEG = input;   % already at this rate -> no-op
    return;
end

EEG = pop_resample(input, newRate);

% Alakazam keeps continuous EEG.times in seconds (see loadSETFile); pop_resample
% leaves EEGLAB's own convention, so re-derive it here so SignalView is right.
EEG.times      = (((1:EEG.pnts) - 1) / EEG.srate);
EEG.DataType   = 'TIMEDOMAIN';
EEG.DataFormat = 'CONTINUOUS';
end

% ======================================================================= %
function r = defaultRate(srate)
%DEFAULTRATE  A sensible pre-fill: 256 Hz if the data is faster, else half.
    if srate > 256
        r = 256;
    else
        r = round(srate / 2);
    end
end
