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
%   the whole epoch), and a hit is acted on in one of three ways (Scope):
%     * 'Whole epoch'            -- reject every channel of that trial (the
%                                  ERP-standard default).
%     * 'This channel only'      -- reject just the offending channel of
%                                  that trial, leaving the rest of the trial.
%     * 'Interpolate this channel' -- reconstruct the offending channel of
%                                  that trial from its neighbours instead of
%                                  discarding it (the automatic counterpart
%                                  of ManualReject's own Interpolate mode).
%   Rejected data is set to NaN, which Average omits (mean/std are computed
%   with 'omitnan'). Interpolated data is NOT NaN, so it is recorded in
%   EEG.etc.alz.interpolated instead -- see TransTools.InterpolateFlaggedCells
%   for why that mask has to exist, and note the caveat there about
%   reconstructing spatially correlated artefacts (a blink is present on the
%   neighbours too). The warning printed below is the automatic caller's
%   share of that caveat: unlike ManualReject, nobody has looked at these.
%
%   Backward compatible: an old options struct carrying only Minimum/Maximum
%   is treated as the Absolute-threshold method over the whole epoch.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = ArtefactDetect(input)        % interactive dialog
%     [EEG, options] = ArtefactDetect(input, opts)  % replay a stored struct
[options, interactive] = TransTools.InitGuard(nargin, 'Alakazam:ArtefactDetect', varargin{:});

if ~isfield(EEG, 'data') || isempty(EEG.data)
    throw(MException('Alakazam:ArtefactDetect', 'Problem in ArtefactDetect: I''m afraid this dataset has no data.'));
end
if ismatrix(EEG.data) || (isfield(EEG, 'DataFormat') && ~strcmpi(EEG.DataFormat, 'EPOCHED'))
    throw(MException('Alakazam:ArtefactDetect', ...
        ['Problem in ArtefactDetect: this needs segmented (epoched) data. Please segment it first ' ...
         '(e.g. with DefineBins), then run artifact detection on the epoched result.']));
end

METHODS = {'Absolute threshold', 'Step function', 'Moving-window peak-to-peak', 'Sample-to-sample'};
SCOPES  = {'Whole epoch', 'This channel only', 'Interpolate this channel'};

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

% No detectors ticked: pass the data through untouched.
%
% This used to fall back to the absolute threshold instead, silently, which
% meant "I selected nothing" quietly became "reject anything outside
% +/-100 uV over the whole epoch". On real data that discarded up to 45% of
% one subject's trials on a threshold nobody had chosen, and, because the
% only trace was a console line that scrolls past, the loss then showed up
% much later as an unexplained rejection rate in the data-quality report.
% A transformation must never destroy data on the strength of a default the
% analyst did not ask for; doing nothing is the only reading of an empty
% selection that cannot cost anyone their trials.
if isempty(opt.Method)
    fprintf(['ArtefactDetect: no detectors were ticked, so nothing was tested and no ' ...
        'data was changed (%d epoch(s) passed through untouched).\n'], nTrials);
    return;
end

% Test window -> sample range (whole epoch when unset / degenerate).
[lo, hi] = testRange(EEG, opt.TestStart, opt.TestStop, nSamp);

% Moving-window sizes in samples.
srate = EEG.srate;
winN  = max(2, round(opt.Window / 1000 * srate));
stepN = max(1, round(opt.Step   / 1000 * srate));

rejectEpoch = strcmpi(opt.Scope, 'Whole epoch');
interpolate = strcmpi(opt.Scope, 'Interpolate this channel');

% Detection is now separated from what is done about it. Interpolation has
% to read the neighbouring channels of a trial, so it cannot run while the
% same trial is still being NaN'd cell by cell: the flags are collected
% first, then applied once, whole.
flags = false(nChan, nTrials);
for t = 1:nTrials
    for c = 1:nChan
        sig = EEG.data(c, lo:hi, t);
        if channelIsBad(sig, opt, winN, stepN)
            flags(c, t) = true;
            if rejectEpoch
                break;   % one bad channel condemns the whole epoch
            end
        end
    end
end

methodLabel = strjoin(opt.Method, ', ');
if rejectEpoch
    markedEpochs = any(flags, 1);
    EEG.data(:, :, markedEpochs) = NaN;
    fprintf('ArtefactDetect (%s): rejected %d of %d epoch(s).\n', ...
        methodLabel, sum(markedEpochs), nTrials);
elseif interpolate
    warnCrowdedTrials(flags, nChan);
    EEG = TransTools.InterpolateFlaggedCells(EEG, flags);
    fprintf('ArtefactDetect (%s): interpolated %d channel-epoch(s).\n', ...
        methodLabel, nnz(flags));
else
    for t = 1:nTrials
        EEG.data(flags(:, t), :, t) = NaN;
    end
    fprintf('ArtefactDetect (%s): flagged %d channel-epoch(s).\n', ...
        methodLabel, nnz(flags));
end
end

% ======================================================================= %
function warnCrowdedTrials(flags, nChan)
%WARNCROWDEDTRIALS  Warn when interpolation is asked to reconstruct a channel
%   from neighbours that are themselves flagged.
%
%   Spherical-spline interpolation assumes the surviving channels are clean.
%   That assumption is weakest exactly where an automatic detector fires
%   hardest: a blink or a movement artefact trips a whole cluster of
%   neighbouring electrodes at once, and reconstructing one of them from the
%   others reproduces the artefact rather than removing it. A human working
%   through ManualReject sees that; a threshold does not, so it is said out
%   loud here. Reported, never enforced -- the analyst chose this scope, and
%   a transformation that silently overrode that choice would be worse than
%   one that explains itself.
    CROWDED = 0.25;   % a quarter of the montage flagged in one trial
    perTrial = sum(flags, 1);
    crowded  = find(perTrial > max(1, floor(CROWDED * nChan)));
    if isempty(crowded)
        return;
    end
    fprintf(['ArtefactDetect: WARNING -- %d trial(s) had more than %d%% of channels flagged ' ...
        '(worst: trial %d, %d of %d channels). Interpolation reconstructs each flagged channel ' ...
        'from the others in the same trial, so where an artefact spans neighbouring electrodes ' ...
        'the reconstruction can reproduce it. Consider ''Whole epoch'' for these.\n'], ...
        numel(crowded), round(CROWDED * 100), ...
        crowded(find(perTrial(crowded) == max(perTrial(crowded)), 1)), ...
        max(perTrial(crowded)), nChan);
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
%   is normalised to a cellstr.
%
%   Deliberately NOT read through TransTools.FieldOr, unlike every other
%   field here: FieldOr treats a present-but-empty field as absent and
%   returns the default, which would turn "no detectors ticked" back into
%   {'Absolute threshold'} and reinstate exactly the silent data loss the
%   no-op guard above exists to prevent. The two cases have to be told
%   apart, so isfield is tested directly:
%     * ABSENT  -> the old Minimum/Maximum-only options struct, which meant
%                  the absolute threshold; that default is kept.
%     * PRESENT but EMPTY -> a deliberate empty selection; left empty.
    if isstruct(options) && isfield(options, 'Method')
        opt.Method = toMethodList(options.Method);
    else
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
