function [EEG, options] = SelectData(input, varargin)
%% SelectData  Keep or remove data along channels, time, points and trials.
%
%   The app-styled SelectDataDialog collects a selection (the same one
%   pop_select offers); the compute delegates to EEGLAB's pop_select, called
%   programmatically from a plain options struct (no eval of a command string).
%   Channels are stored as labels and resolved to indices against the current
%   dataset, so a stored selection replays on a dataset whose channels differ.
%
%   WHAT IS KEPT BESIDE THE TRIALS. The bins a trial is in, and its reaction
%   times, are on the trial itself (EEG.epoch(t).bini and .binrt, see
%   TransTools.BinMembership), and pop_select keeps the EEG.epoch entries of
%   the trials it keeps, so they follow by themselves; each bin's count, .n,
%   is counted again. What pop_select does not know is the per-trial records
%   in EEG.etc.alz, which a trial selection cuts to the trials that remain
%   (see followKeptTrials). Until 2026-10-24 each bin also listed its trials
%   in EEG.bindesc(b).trials, which this step had to renumber by hand: left
%   alone, Average failed with an index past the last trial or, where the
%   old numbers were still in range, averaged the wrong trials. A dataset
%   that still has those lists is converted first.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = SelectData(input)        % interactive dialog
%     [EEG, options] = SelectData(input, opts)  % replay a stored options struct
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:SelectData', varargin{:});
if interactive
    options = SelectDataDialog(input.chanlocs, size(input.data, 2), size(input.data, 3), ...
        TransformSettings.get('SelectData'), timeUnit(input));
    if isempty(options)
        EEG = [];   % cancelled -- no node, no compute (see Alakazam.onTransformation)
        return;
    end
    TransformSettings.set('SelectData', options);
else
    options = opts;
end

args = buildSelectArgs(input, options);
if isempty(args)
    EEG = input;   % nothing selected -> no-op
    return;
end
input = TransTools.BinMembership.migrate(input);   % bins on the trials, where pop_select keeps them
EEG = pop_select(input, args{:});
if selectsTrials(options)
    EEG = followKeptTrials(EEG, input, keptTrials(input, options));
end

% pop_select (via eeg_checkset) rewrites EEG.times in EEGLAB's millisecond
% convention. Alakazam keeps *continuous* data on a SECONDS time axis (epoched
% and averaged data stay in ms, matching EEGLAB and the rest of the app), so
% restore seconds for a continuous result -- otherwise the axis reads in ms and
% the duration/sample-rate look 1000x off (see Resample.m, same convention).
if isContinuous(input)
    EEG.times = (0:EEG.pnts - 1) / EEG.srate;   % seconds, 0-based
    if ~isempty(EEG.times)
        EEG.xmin = EEG.times(1);
        EEG.xmax = EEG.times(end);
    end
end
end

% ======================================================================= %
function args = buildSelectArgs(input, o)
%BUILDSELECTARGS  The pop_select name/value arguments for one options struct.
    args = {};
    if isfield(o, 'channels') && ~strcmp(o.channels.mode, '(off)')
        idx = TransTools.LabelsToIdx(input, o.channels.labels);
        if strcmp(o.channels.mode, 'Keep')
            if isempty(idx)
                throw(MException('Alakazam:SelectData', ...
                    'SelectData: I''m afraid none of the channels to keep are in this dataset.'));
            end
            args = [args, {'channel', idx}];
        elseif ~isempty(idx)
            args = [args, {'nochannel', idx}];
        end
    end
    % pop_select's 'time' argument is always in seconds. The dialog collects the
    % time range in the data's own display unit -- seconds for continuous data,
    % milliseconds for epoched/averaged data -- so scale to seconds accordingly.
    if isContinuous(input); timeScale = 1; else; timeScale = 1 / 1000; end
    args = [args, rangeArgs(o, 'time',   'time',  'notime',  timeScale)];
    args = [args, rangeArgs(o, 'points', 'point', 'nopoint', 1)];
    if selectsTrials(o)
        key = keepKey(o.trials.mode, 'trial', 'notrial');
        args = [args, {key, o.trials.indices(:)'}];
    end
end

function tf = selectsTrials(o)
%SELECTSTRIALS  True when the options keep or remove trials.
    tf = isfield(o, 'trials') && ~strcmp(o.trials.mode, '(off)') && ~isempty(o.trials.indices);
end

function kept = keptTrials(input, o)
%KEPTTRIALS  The input's trials a trial selection keeps, in the order
%   pop_select leaves them: sorted and without repeats, its 'sorttrial'
%   default. Input trial KEPT(j) becomes trial j.
    asked = double(o.trials.indices(:)');
    if strcmp(o.trials.mode, 'Keep')
        kept = unique(asked);
    else
        kept = setdiff(1:size(input.data, 3), asked);
    end
end

% ======================================================================= %
function EEG = followKeptTrials(EEG, input, kept)
%FOLLOWKEPTTRIALS  What Alakazam keeps per trial, cut to the trials
%   pop_select kept: the per-trial records in EEG.etc.alz (followRecords),
%   and each bin's count. The bins themselves are on the trials, which
%   pop_select keeps, except when it leaves a single trial: it then clears
%   EEG.epoch, and the trial's bins are read from its own event.
    nBefore = size(input.data, 3);
    if numel(kept) ~= size(EEG.data, 3)
        % pop_select chose its trials some other way than keptTrials says.
        % Cutting the records by the wrong list would pair each trial with
        % another's, which is the fault this function exists to prevent.
        throw(MException('Alakazam:SelectData', ...
            ['SelectData: I''m afraid EEGLAB kept %d trial(s) where %d were expected, so ' ...
             'the per-trial records cannot be cut to match. Nothing was changed.'], ...
            size(EEG.data, 3), numel(kept)));
    end
    if isfield(EEG, 'etc') && isstruct(EEG.etc) && isfield(EEG.etc, 'alz') && isstruct(EEG.etc.alz)
        EEG.etc.alz = followRecords(EEG.etc.alz, kept, nBefore);
    end
    EEG = TransTools.BinMembership.recount(EEG);
end

function alz = followRecords(alz, kept, nBefore)
%FOLLOWRECORDS  The per-trial records in EEG.etc.alz cut to the kept
%   trials: the interpolation mask (channels x trials, see
%   TransTools.RecordInterpolated), and DefineBins' epochStart (where each
%   trial began in the recording it was cut from) and epochNeighbours (when
%   the events around it fell, which EpochView sorts by).
%
%   A record whose trial dimension did not match the input was out of step
%   already, and is left for its readers to discard, as they do. The
%   rejection steps' own records (artefactDetectors, autoreject) are not
%   cut either: they count what that step found among the trials it was
%   given, which stays true of it.
    if isfield(alz, 'interpolated') && islogical(alz.interpolated) ...
            && ismatrix(alz.interpolated) && size(alz.interpolated, 2) == nBefore
        alz.interpolated = alz.interpolated(:, kept);
    end
    if isfield(alz, 'epochStart') && isvector(alz.epochStart) && numel(alz.epochStart) == nBefore
        alz.epochStart = alz.epochStart(kept);
    end
    if isfield(alz, 'epochNeighbours') && isstruct(alz.epochNeighbours) ...
            && isscalar(alz.epochNeighbours) ...
            && all(isfield(alz.epochNeighbours, {'next', 'previous'})) ...
            && size(alz.epochNeighbours.next, 2) == nBefore ...
            && size(alz.epochNeighbours.previous, 2) == nBefore
        alz.epochNeighbours.next = alz.epochNeighbours.next(:, kept);
        alz.epochNeighbours.previous = alz.epochNeighbours.previous(:, kept);
        alz.epochNeighbours.trials = numel(kept);
    end
end

function a = rangeArgs(o, field, keepK, removeK, scale)
    a = {};
    if isfield(o, field) && ~strcmp(o.(field).mode, '(off)')
        % (:)' forces a ROW vector: the dialog always produces one ([lo.Value
        % hi.Value]), but jsondecode has no notion of row vs column and turns
        % any JSON numeric array back into a COLUMN on Apply Template -- pop_select
        % rejects that outright ("Time/point range must contain 2 columns exactly").
        % Confirmed directly: jsondecode(jsonencode([883 8594])) comes back 2x1.
        a = {keepKey(o.(field).mode, keepK, removeK), o.(field).range(:)' * scale};
    end
end

function key = keepKey(mode, keepK, removeK)
    if strcmp(mode, 'Keep'); key = keepK; else; key = removeK; end
end

function tf = isContinuous(EEG)
%ISCONTINUOUS  True for continuous (non-epoched) data, whose time axis Alakazam
%   keeps in seconds. Prefers EEG.DataFormat; falls back to the data shape.
    if isfield(EEG, 'DataFormat') && ~isempty(EEG.DataFormat)
        tf = strcmpi(EEG.DataFormat, 'CONTINUOUS');
    else
        tf = ismatrix(EEG.data) && (~isfield(EEG, 'trials') || EEG.trials <= 1);
    end
end

function u = timeUnit(EEG)
%TIMEUNIT  The unit the dataset's time axis is displayed in: 's' for continuous
%   data, 'ms' for epoched/averaged data (matching SignalView / the app).
    if isContinuous(EEG); u = 's'; else; u = 'ms'; end
end
