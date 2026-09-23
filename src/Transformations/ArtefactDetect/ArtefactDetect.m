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
%   WHICH DETECTOR COST WHICH TRIALS is recorded as the detection runs, in
%   EEG.etc.alz.artefactDetectors (see detectorBreakdown below): per detector,
%   the epochs and channel-epochs it would have rejected on its own, and the
%   epochs ONLY it caught. With several detectors ticked, knowing a trial was
%   rejected is not the same as knowing why, and "which of these four is
%   costing me my trials" is the question you ask before moving a threshold.
%   The tree's right-click "Rejection breakdown..." reads exactly this field.
%   The per-detector figures deliberately overlap (one blink trips three
%   detectors), so they do not sum to the total; the "only this one" column is
%   the number to read before switching a detector off.
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
CHANNELS = {'All channels', 'Scalp EEG only'};

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
        'separator', 'Channels to test:', ...
        {'Channels'; 'Channels'}, TransTools.PutFirst(CHANNELS, d('Channels', 'All channels')), ...
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
% user did not ask for; doing nothing is the only reading of an empty
% selection that cannot cost anyone their trials.
if isempty(opt.Method)
    % An empty breakdown rather than no breakdown: the field is then always
    % there after ArtefactDetect has run, so the tree's "Rejection
    % breakdown" reports "no detectors were ticked" instead of having to
    % treat a missing field as a special case it cannot tell apart from an
    % old node computed before any of this existed.
    EEG.etc.alz.artefactDetectors = detectorBreakdown( ...
        false(nChan, nTrials, 0), opt, 1:nChan, nTrials);
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
% WHICH CHANNELS ARE TESTED AT ALL. An EOG channel swings past any
% threshold chosen for scalp EEG every time the participant blinks, so
% testing it flags it on a large fraction of trials by construction. That is
% wanted under 'Whole epoch', where it is the classic blink rejection, and
% is noise under the other two scopes: it marks the eye channel bad without
% telling anyone anything, and it fills the data-quality report's
% candidate-for-interpolation list with the one channel nobody would ever
% interpolate.
%
% The default stays 'All channels', because changing it would silently
% switch off blink rejection for anyone whose pipeline depends on it.
scanIdx = channelsToScan(EEG, opt, nChan);

% PER-DETECTOR ATTRIBUTION, recorded as the detection runs. Knowing that a
% trial was rejected is not the same as knowing WHY, and with several
% detectors ticked the difference matters: "which of these four is costing me
% my trials" is the question you ask before changing a threshold. So each
% ticked detector is evaluated separately and its own verdict kept, rather
% than asking "did anything trip" and discarding the answer.
%
% That costs the two early exits the old loop had (it stopped at the first
% detector that tripped, and under 'Whole epoch' at the first bad channel).
% Both were pure optimisations of a boolean OR; neither can be kept while
% attributing, because a detector that would have tripped on a later channel
% has to be counted. detFlags is channels x trials x detectors, so 33 x 984 x 4
% is about 130 kB -- small next to the data it describes, and it lets a report
% or a view answer per detector without recomputing anything.
detFlags = false(nChan, nTrials, numel(opt.Method));
for t = 1:nTrials
    for c = scanIdx
        sig = EEG.data(c, lo:hi, t);
        % The windows of this channel-epoch are cut once, by whichever
        % moving-window detector asks first, and shared with the others.
        windows = struct('built', false, 'W', []);
        for m = 1:numel(opt.Method)
            [detFlags(c, t, m), windows] = detectorTrips(opt.Method{m}, sig, opt, winN, stepN, windows);
        end
    end
end
flags = any(detFlags, 3);

% Recorded before the scope is applied, because the scope is what turns
% flags into NaN and there would be nothing left to attribute afterwards.
EEG.etc.alz.artefactDetectors = detectorBreakdown(detFlags, opt, scanIdx, nTrials);

methodLabel = strjoin(opt.Method, ', ');
if rejectEpoch
    markedEpochs = any(flags, 1);
    EEG.data(:, :, markedEpochs) = NaN;
    fprintf('ArtefactDetect (%s): rejected %d of %d epoch(s).\n', ...
        methodLabel, sum(markedEpochs), nTrials);
elseif interpolate
    warnCrowdedTrials(flags, nChan);
    % The count comes back from the interpolator rather than from the flags:
    % a channel with no scalp position is left flagged instead of being
    % reconstructed, so the two numbers differ exactly when an EOG or ECG
    % channel tripped a detector.
    [EEG, nInterpolated] = TransTools.InterpolateFlaggedCells(EEG, flags);
    fprintf('ArtefactDetect (%s): interpolated %d of %d flagged channel-epoch(s).\n', ...
        methodLabel, nInterpolated, nnz(flags));
else
    for t = 1:nTrials
        EEG.data(flags(:, t), :, t) = NaN;
    end
    fprintf('ArtefactDetect (%s): flagged %d channel-epoch(s).\n', ...
        methodLabel, nnz(flags));
end
end

% ======================================================================= %
function report = detectorBreakdown(detFlags, opt, scanIdx, nTrials)
%DETECTORBREAKDOWN  Per-detector counts, for the tree's "Rejection
%   breakdown" action and for anything else that wants to know which
%   detector cost which trials.
%
%   Returns a scalar struct:
%     .methods        cellstr, the detectors that ran, in the order ticked
%     .epochs         1 x nMethods, epochs this detector alone would reject
%     .channelEpochs  1 x nMethods, channel-epochs this detector flagged
%     .onlyThis       1 x nMethods, epochs ONLY this detector caught
%     .epochMask      nTrials x nMethods logical, which epochs each caught
%     .totalEpochs    epochs at least one detector caught
%     .nTrials        trials examined
%     .channelsTested how many channels were in scope
%     .scope          the scope the counts are read under
%
%   THE PER-DETECTOR COUNTS OVERLAP ON PURPOSE and do not sum to the total:
%   a blink usually trips the absolute threshold AND the step function AND
%   the peak-to-peak window, so adding them up would double-count badly.
%   Each figure answers "how much would this detector alone have rejected",
%   which is the question worth asking before changing one threshold.
%   .onlyThis is the complement: what each detector contributed that nothing
%   else would have caught, and that IS the number to look at before
%   switching a detector off.
    nMethods = numel(opt.Method);
    epochMask = false(nTrials, nMethods);
    channelEpochs = zeros(1, nMethods);
    for m = 1:nMethods
        thisDet = detFlags(:, :, m);
        epochMask(:, m) = any(thisDet, 1)';
        channelEpochs(m) = nnz(thisDet);
    end

    onlyThis = zeros(1, nMethods);
    for m = 1:nMethods
        others = epochMask;
        others(:, m) = false;
        onlyThis(m) = nnz(epochMask(:, m) & ~any(others, 2));
    end

    report = struct( ...
        'methods',        {opt.Method}, ...
        'epochs',         sum(epochMask, 1), ...
        'channelEpochs',  channelEpochs, ...
        'onlyThis',       onlyThis, ...
        'epochMask',      epochMask, ...
        'totalEpochs',    nnz(any(epochMask, 2)), ...
        'nTrials',        nTrials, ...
        'channelsTested', numel(scanIdx), ...
        'scope',          char(string(opt.Scope)));
end

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
%   loud here. Reported, never enforced -- the user chose this scope, and
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
function idx = channelsToScan(EEG, opt, nChan)
%CHANNELSTOSCAN  The channel indices this run tests.
%   'Scalp EEG only' uses eegChannelMask, which excludes channels that are a
%   known peripheral (EOG, ECG, ...) either by their recorded .type or, when
%   that is blank, by their LABEL -- so it works on the ordinary recording
%   that arrived with no types filled in, which is most of them. It used to
%   read .type alone, which made this option a no-op on exactly those
%   datasets: it quietly tested the eye channels anyway and rejected every
%   blink. eegChannelMask never returns an empty mask, so this cannot end up
%   testing nothing.
    idx = 1:nChan;
    if ~isfield(opt, 'Channels') || ~strcmpi(char(string(opt.Channels)), 'Scalp EEG only')
        return;
    end
    if ~isfield(EEG, 'chanlocs') || numel(EEG.chanlocs) ~= nChan
        return;     % nothing to decide from; test everything, as before
    end
    mask = eegChannelMask(EEG.chanlocs);
    if numel(mask) ~= nChan || ~any(mask)
        return;
    end
    idx = find(mask);
end

function [bad, windows] = detectorTrips(method, sig, opt, winN, stepN, windows)
%DETECTORTRIPS  Evaluate one named detector against SIG.
%   Called once per detector per channel-epoch, so that which detector
%   tripped is recorded rather than collapsed into "something did" -- see the
%   note on attribution at the detection loop. The old channelIsBad wrapper,
%   which OR-ed the detectors and returned on the first trip, is gone with it.
%
%   WINDOWS carries the moving windows of SIG between the detectors that use
%   them (step function and moving-window peak-to-peak), so they are cut once
%   per channel-epoch rather than once each, and are scored as matrices, not
%   by a loop over windows.
    sig = sig(:).';
    switch lower(strrep(method, ' ', ''))
        case 'absolutethreshold'
            bad = any(sig > opt.Maximum) || any(sig < opt.Minimum);
        case 'sample-to-sample'
            bad = any(abs(diff(sig)) > opt.Threshold);
        case 'stepfunction'
            windows = ensureWindows(windows, sig, winN, stepN);
            bad = largestWindowValue(windows.W, 'step') > opt.Threshold;
        case 'moving-windowpeak-to-peak'
            windows = ensureWindows(windows, sig, winN, stepN);
            bad = largestWindowValue(windows.W, 'peak-to-peak') > opt.Threshold;
        otherwise
            bad = any(sig > opt.Maximum) || any(sig < opt.Minimum);
    end
end

function windows = ensureWindows(windows, sig, winN, stepN)
%ENSUREWINDOWS  Cut SIG into its moving windows, once: an nWindows x WINN matrix,
%   empty when the signal is shorter than one window.
%
%   The last start is forced flush with the end of the signal. Stepping by
%   stepN alone stops at the last whole window that fits, leaving up to
%   winN + stepN - 2 samples at the tail that no window ever covers -- for a
%   -200..800 ms epoch at 256 Hz with ERPLAB's usual 200 ms / 100 ms
%   settings that is the last 90 ms, i.e. an artefact sitting on the P3 or
%   the LRP goes unseen. Found by validating against Luck's ch10 LRP data:
%   ERPLAB's artmwppth flagged trial 222 (FC4, 311 uV peak-to-peak at
%   602..797 ms) and this detector did not. See Docs/luck.md.
    if windows.built
        return;
    end
    windows.built = true;
    n = numel(sig);
    if n < winN
        windows.W = zeros(0, winN);
        return;
    end
    starts = unique([1:stepN:(n - winN + 1), n - winN + 1]);
    windows.W = sig(starts(:) + (0:winN - 1));
end

function m = largestWindowValue(W, kind)
%LARGESTWINDOWVALUE  Largest of the per-window scores, 0 if there are none.
%   A window holding NaN (a sample rejected or blanked upstream) scores NaN for
%   the step function and is passed over, exactly as the loop this replaces
%   passed over a NaN by testing "v > m"; max() ignores NaN, and the 0 in front
%   is the loop's own starting value.
    if isempty(W)
        m = 0;
        return;
    end
    switch kind
        case 'step'
            % |mean(first half) - mean(second half)| of a window (the ERPLAB
            % step function).
            half = floor(size(W, 2) / 2);
            v = abs(mean(W(:, 1:half), 2) - mean(W(:, half + 1:end), 2));
        otherwise
            v = max(W, [], 2) - min(W, [], 2);
    end
    m = max([0; v(:)]);
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
    % Defaults to every channel, so an options struct stored before this
    % field existed replays exactly as it did.
    opt.Channels  = TransTools.FieldOr(options, 'Channels', 'All channels');
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
