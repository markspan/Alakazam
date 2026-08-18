function [EEG, options] = ArtefactDetect(EEG, varargin)
%% ArtefactDetect  Mark artifact-contaminated epochs so averaging omits them.
%
%   Four detectors, matching (and extending) ERPLAB's set:
%     * Absolute threshold      -- any sample outside [Minimum, Maximum] uV.
%     * Step function           -- a moving window whose first-half vs
%                                  second-half mean differs by > Threshold uV
%                                  (blinks, saccades).
%     * Moving-window peak-to-peak -- max-minus-min within a sliding window
%                                  exceeds Threshold uV.
%     * Sample-to-sample        -- any |x[n]-x[n-1]| exceeds Threshold uV
%                                  (a single-sample jump / transient).
%   One or more detectors may be selected at once; a channel trips if any
%   selected detector flags it. Detection runs over a Test window (blank =
%   the whole epoch), and a hit rejects either the whole epoch (all channels,
%   the ERP-standard default) or just the offending channel. Rejected data is
%   set to NaN, which Average omits (mean/std are computed with 'omitnan').
%
%   Backward compatible: an old options struct carrying only Minimum/Maximum
%   is treated as the Absolute-threshold method over the whole epoch.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = ArtefactDetect(input)        % interactive dialog
%     [EEG, options] = ArtefactDetect(input, opts)  % replay a stored struct
[options, interactive] = TransTools.InitGuard(nargin, 'Alakazam:ArtefactDetect', varargin{:});

if ~isfield(EEG, 'data') || isempty(EEG.data)
    throw(MException('Alakazam:ArtefactDetect', 'Problem in ArtefactDetect: this dataset has no data.'));
end
if ismatrix(EEG.data) || (isfield(EEG, 'DataFormat') && ~strcmpi(EEG.DataFormat, 'EPOCHED'))
    throw(MException('Alakazam:ArtefactDetect', ...
        ['Problem in ArtefactDetect: needs segmented (epoched) data. Segment it first ' ...
         '(e.g. with DefineBins), then run artifact detection on the epoched result.']));
end

METHODS = {'Absolute threshold', 'Step function', 'Moving-window peak-to-peak', 'Sample-to-sample'};
SCOPES  = {'Whole epoch', 'This channel only'};

if interactive
    stored = TransformSettings.get('ArtefactDetect');
    if isempty(stored) || ~isstruct(stored)
        stored = struct();
    end
    d = @(f, v) TransTools.FieldOr(stored, f, v);
    options = TransformOptionsDialog( ...
        'title', 'Artefact detection options', ...
        'Description', ['Mark artifact epochs so averaging omits them. Tick one or more ' ...
            'detectors; a channel is flagged if any ticked detector trips. Test window ' ...
            'blank (0 to 0) means the whole epoch.'], ...
        'separator', 'Detectors (tick one or more):', ...
        {'Detectors'; 'Method'}, multiSelectField(METHODS, toMethodList(d('Method', {'Absolute threshold'}))), ...
        'separator', 'Absolute threshold (uV):', ...
        {'Minimum'; 'Minimum'}, d('Minimum', -100), ...
        {'Maximum'; 'Maximum'}, d('Maximum', 100), ...
        'separator', 'Step / peak-to-peak / sample-to-sample:', ...
        {'Threshold (uV)'; 'Threshold'}, d('Threshold', 100), ...
        {'Window (ms)'; 'Window'}, d('Window', 200), ...
        {'Window step (ms)'; 'Step'}, d('Step', 50), ...
        'separator', 'Test window (ms, 0 to 0 = whole epoch):', ...
        {'Start'; 'TestStart'}, d('TestStart', 0), ...
        {'Stop'; 'TestStop'}, d('TestStop', 0), ...
        'separator', 'Rejection:', ...
        {'Reject'; 'Scope'}, TransTools.PutFirst(SCOPES, d('Scope', 'Whole epoch')));
    if isempty(options)
        EEG = [];   % cancelled -- no node, no compute
        return;
    end
    TransformSettings.set('ArtefactDetect', options);
end

opt = normaliseOptions(options);
[nChan, nSamp, nTrials] = size(EEG.data);

% Test window -> sample range (whole epoch when unset / degenerate).
[lo, hi] = testRange(EEG, opt.TestStart, opt.TestStop, nSamp);

% Moving-window sizes in samples.
srate = EEG.srate;
winN  = max(2, round(opt.Window / 1000 * srate));
stepN = max(1, round(opt.Step   / 1000 * srate));

rejectEpoch   = strcmpi(opt.Scope, 'Whole epoch');
markedEpochs  = false(1, nTrials);
markedTrials  = 0; markedChannels = 0;

for t = 1:nTrials
    epochBad = false;
    for c = 1:nChan
        sig = EEG.data(c, lo:hi, t);
        if channelIsBad(sig, opt, winN, stepN)
            if rejectEpoch
                epochBad = true;
                break;   % one bad channel condemns the whole epoch
            else
                EEG.data(c, :, t) = NaN;
                markedChannels = markedChannels + 1;
            end
        end
    end
    if epochBad
        EEG.data(:, :, t) = NaN;
        markedEpochs(t) = true;
        markedTrials = markedTrials + 1;
    end
end

methodLabel = strjoin(opt.Method, ', ');
if rejectEpoch
    fprintf('ArtefactDetect (%s): rejected %d of %d epoch(s).\n', methodLabel, markedTrials, nTrials);
else
    fprintf('ArtefactDetect (%s): flagged %d channel-epoch(s).\n', methodLabel, markedChannels);
end
end

% ======================================================================= %
function bad = channelIsBad(sig, opt, winN, stepN)
%CHANNELISBAD  Does this channel's signal (over the test window) trip any of
%   the selected detectors? A single trip is enough to flag the channel.
    sig = sig(:).';
    bad = false;
    for m = 1:numel(opt.Method)
        if detectorTrips(opt.Method{m}, sig, opt, winN, stepN)
            bad = true;
            return;
        end
    end
end

function bad = detectorTrips(method, sig, opt, winN, stepN)
%DETECTORTRIPS  Evaluate one named detector against SIG.
    switch lower(strrep(method, ' ', ''))
        case 'absolutethreshold'
            bad = any(sig > opt.Maximum) || any(sig < opt.Minimum);
        case 'sample-to-sample'
            bad = any(abs(diff(sig)) > opt.Threshold);
        case 'stepfunction'
            bad = movingWindow(sig, winN, stepN, @(w) stepValue(w)) > opt.Threshold;
        case 'moving-windowpeak-to-peak'
            bad = movingWindow(sig, winN, stepN, @(w) max(w) - min(w)) > opt.Threshold;
        otherwise
            bad = any(sig > opt.Maximum) || any(sig < opt.Minimum);
    end
end

function m = movingWindow(sig, winN, stepN, fcn)
%MOVINGWINDOW  Largest value of FCN over every WINN-sample window, stepped by
%   STEPN. Returns 0 if the signal is shorter than one window.
    n = numel(sig);
    m = 0;
    if n < winN; return; end
    for i = 1:stepN:(n - winN + 1)
        v = fcn(sig(i:i + winN - 1));
        if v > m; m = v; end
    end
end

function v = stepValue(w)
%STEPVALUE  |mean(first half) - mean(second half)| of a window (the ERPLAB
%   step function).
    half = floor(numel(w) / 2);
    v = abs(mean(w(1:half)) - mean(w(half + 1:end)));
end

function opt = normaliseOptions(options)
%NORMALISEOPTIONS  Fill defaults and accept the old Minimum/Maximum-only struct.
%   Method may be a single string (old struct) or a cellstr (multi-select); it
%   is normalised to a cellstr, empty selection falling back to the absolute
%   threshold so detection always does something.
    opt.Method    = toMethodList(TransTools.FieldOr(options, 'Method', {'Absolute threshold'}));
    if isempty(opt.Method)
        opt.Method = {'Absolute threshold'};
    end
    opt.Minimum   = TransTools.FieldOr(options, 'Minimum', -100);
    opt.Maximum   = TransTools.FieldOr(options, 'Maximum', 100);
    opt.Threshold = TransTools.FieldOr(options, 'Threshold', 100);
    opt.Window    = TransTools.FieldOr(options, 'Window', 200);
    opt.Step      = TransTools.FieldOr(options, 'Step', 50);
    opt.TestStart = TransTools.FieldOr(options, 'TestStart', 0);
    opt.TestStop  = TransTools.FieldOr(options, 'TestStop', 0);
    opt.Scope     = TransTools.FieldOr(options, 'Scope', 'Whole epoch');
end

function [lo, hi] = testRange(EEG, startMs, stopMs, nSamp)
    if stopMs <= startMs || ~isfield(EEG, 'times') || isempty(EEG.times)
        lo = 1; hi = nSamp; return;   % whole epoch
    end
    lo = find(EEG.times >= startMs, 1, 'first');
    hi = find(EEG.times <= stopMs,  1, 'last');
    if isempty(lo); lo = 1; end
    if isempty(hi); hi = nSamp; end
    if hi < lo; lo = 1; hi = nSamp; end
end

function list = toMethodList(value)
%TOMETHODLIST  Normalise a Method setting (char, string or cellstr) to a
%   cellstr row of detector names, dropping blanks.
    if isempty(value)
        list = {}; return;
    end
    if ischar(value)
        list = {value};
    else
        list = cellstr(string(value(:)))';
    end
    list = list(~cellfun(@(s) isempty(strtrim(s)), list));
end
