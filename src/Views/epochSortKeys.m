function keys = epochSortKeys(EEG)
%EPOCHSORTKEYS  What an epoched dataset's trials can be sorted by.
%   KEYS = epochSortKeys(EEG) lists every per-trial value EpochView can order
%   its ERP image by, as a struct array with
%     .id      'rt'; 'next:<type>' or 'previous:<type>' for the nearest event
%              of a type after or before the trial's own; or 'field:<name>'
%              for a field of the time-locking event
%     .label   the text the "Sort by" dropdown shows
%     .values  1 x nTrials, NaN where a trial has no value
%     .timeMs  true when the values are times relative to the time-locking
%              event, in ms, which EpochView then draws across the image as
%              a line
%   Only keys with at least two different values are offered: a sort by
%   something every trial shares changes nothing and only lengthens the list.
%
%   THE REACTION TIME is DefineBins' own: the delay to the neighbour a bin's
%   definition captured going forward (next(...) within ...). It is read
%   from bindesc(b).rt, which cutEpochs (and Deconvolve's trials) keep
%   aligned element by element with bindesc(b).trials. A trial in two bins
%   takes the first finite one.
%
%   THE NEIGHBOURS need nothing in the bin definition: "Next saccade (ms)",
%   "Previous stimonset (ms)" and so on, for every event type, from the
%   table cutEpochs and Deconvolve's trials record while the continuous
%   latencies still exist (TransTools.EpochNeighbours). A capture in the bin
%   definition would also drop every trial without that neighbour, which is
%   wrong for a model that has to see every event; this sorts without
%   dropping anything, and a trial with no such neighbour in its window goes
%   last.
%
%   AN EVENT FIELD is any numeric field of each trial's own time-locking
%   event: an importer's or EYE-EEG's (fixation position, pupil size,
%   saccade amplitude), or one added with EventEditor. The event is found
%   through EEG.epoch(t).event when that event still says it belongs to
%   trial t, and otherwise by the event whose .epoch is t, because a later
%   eeg_checkset can renumber the event list. DURATION IS CONVERTED from
%   samples (EEGLAB's unit for it) to ms and drawn as a time, which for a
%   fixation is when the next saccade begins: the tutorial picture of a
%   response that moves with it (Unfold tutorial 7).
%
%   See also EPOCHVIEW, DEFINEBINS, DECONVOLVE.
    keys = struct('id', {}, 'label', {}, 'values', {}, 'timeMs', {});
    if ~isfield(EEG, 'data') || size(EEG.data, 3) < 2
        return;     % nothing to put in an order
    end
    nTrials = size(EEG.data, 3);

    rt = reactionTimes(EEG, nTrials);
    if varies(rt)
        keys(end + 1) = struct('id', 'rt', 'label', 'Reaction time (ms)', ...
            'values', rt, 'timeMs', true);
    end
    keys = [keys, neighbourKeys(EEG, nTrials)];

    anchors = anchorEvents(EEG, nTrials);
    if ~any(anchors) || ~isfield(EEG, 'event') || isempty(EEG.event)
        return;
    end
    % Position and bookkeeping, not properties of the event: the latency is
    % the trial's place in the recording, which "Recording order" already
    % is, and the rest are EEGLAB's and DefineBins' own indices.
    skip = {'latency', 'urevent', 'epoch', 'bini', 'type', 'init_index', 'init_time'};
    for name = reshape(setdiff(fieldnames(EEG.event), skip, 'stable'), 1, [])
        values = nan(1, nTrials);
        for t = find(anchors)
            v = EEG.event(anchors(t)).(name{1});
            if isnumeric(v) && isscalar(v) && ~islogical(v)
                values(t) = double(v);
            end
        end
        if ~varies(values)
            continue;
        end
        if strcmpi(name{1}, 'duration')
            keys(end + 1) = struct('id', 'field:duration', 'label', 'Event duration (ms)', ...
                'values', values / EEG.srate * 1000, 'timeMs', true); %#ok<AGROW>
        else
            keys(end + 1) = struct('id', ['field:' name{1}], 'label', ['Event: ' name{1}], ...
                'values', values, 'timeMs', false); %#ok<AGROW>
        end
    end
end

% ======================================================================= %
function keys = neighbourKeys(EEG, nTrials)
%NEIGHBOURKEYS  "Next <type>" and "Previous <type>": when the nearest event
%   of each type fell after and before each trial's own event, as measured
%   when the trials were cut (TransTools.EpochNeighbours). Not offered when
%   the table no longer has one column per trial, since a column that belongs
%   to another trial is worse than none.
    keys = struct('id', {}, 'label', {}, 'values', {}, 'timeMs', {});
    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) || ~isfield(EEG.etc, 'alz') ...
            || ~isstruct(EEG.etc.alz) || ~isfield(EEG.etc.alz, 'epochNeighbours')
        return;
    end
    context = EEG.etc.alz.epochNeighbours;
    if ~isstruct(context) || ~all(isfield(context, {'types', 'next', 'previous'})) ...
            || size(context.next, 2) ~= nTrials || size(context.previous, 2) ~= nTrials
        return;
    end
    for k = 1:numel(context.types)
        name = context.types{k};
        if varies(context.next(k, :))
            keys(end + 1) = struct('id', ['next:' name], 'label', ['Next ' name ' (ms)'], ...
                'values', context.next(k, :), 'timeMs', true); %#ok<AGROW>
        end
        if varies(context.previous(k, :))
            keys(end + 1) = struct('id', ['previous:' name], 'label', ['Previous ' name ' (ms)'], ...
                'values', context.previous(k, :), 'timeMs', true); %#ok<AGROW>
        end
    end
end

function rt = reactionTimes(EEG, nTrials)
%REACTIONTIMES  Each trial's DefineBins reaction time, NaN where it has none.
    rt = nan(1, nTrials);
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc) ...
            || ~isfield(EEG.bindesc, 'rt') || ~isfield(EEG.bindesc, 'trials')
        return;
    end
    for b = 1:numel(EEG.bindesc)
        trials = double(EEG.bindesc(b).trials);
        times = double(EEG.bindesc(b).rt);
        if numel(trials) ~= numel(times)
            continue;   % not aligned (a hand-built bindesc): nothing safe to read
        end
        for k = 1:numel(trials)
            t = trials(k);
            if t >= 1 && t <= nTrials && isnan(rt(t)) && isfinite(times(k))
                rt(t) = times(k);
            end
        end
    end
end

function anchors = anchorEvents(EEG, nTrials)
%ANCHOREVENTS  The row of EEG.event each trial is locked to, 0 if unknown.
    anchors = zeros(1, nTrials);
    if ~isfield(EEG, 'event') || isempty(EEG.event) || ~isfield(EEG.event, 'epoch')
        return;
    end
    owner = zeros(1, numel(EEG.event));
    for i = 1:numel(EEG.event)
        e = EEG.event(i).epoch;
        if isnumeric(e) && isscalar(e)
            owner(i) = e;
        end
    end
    hasEpoch = isfield(EEG, 'epoch') && numel(EEG.epoch) == nTrials && isfield(EEG.epoch, 'event');
    for t = 1:nTrials
        if hasEpoch
            ei = EEG.epoch(t).event;
            if isnumeric(ei) && isscalar(ei) && ei >= 1 && ei <= numel(owner) && owner(ei) == t
                anchors(t) = ei;
                continue;
            end
        end
        first = find(owner == t, 1);
        if ~isempty(first)
            anchors(t) = first;
        end
    end
end

function tf = varies(values)
    finite = values(isfinite(values));
    tf = numel(finite) >= 2 && any(finite ~= finite(1));
end
