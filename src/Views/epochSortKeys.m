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
%   from the trial itself, EEG.epoch(t).binrt beside .bini (see
%   TransTools.BinMembership; an old dataset's bindesc(b).rt is read the
%   same way). A trial in two bins takes the first finite one.
%
%   THE NEIGHBOURS need nothing in the bin definition: "Next saccade (ms)",
%   "Previous stimonset (ms)" and so on, for every event type, from the
%   table cutEpochs and Deconvolve's trials record while the continuous
%   latencies still exist (TransTools.EpochNeighbours). A capture in the bin
%   definition would also drop every trial without that neighbour, which is
%   wrong for a model that has to see every event; this sorts without
%   dropping anything, and a trial with no such neighbour in its window goes
%   last. Trials cut by something else, such as an epoched .set from an EEGLAB
%   pipeline, have no such table, and are measured here from EEGLAB's own
%   record of the recording's events, EEG.urevent, through each trial's
%   time-locking event.
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
    context = recordedNeighbours(EEG, nTrials);
    if isempty(context)
        context = neighboursFromUrevents(EEG, nTrials);
    end
    if isempty(context)
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

function context = recordedNeighbours(EEG, nTrials)
%RECORDEDNEIGHBOURS  The table measured when the trials were cut, [] when
%   there is none, or it no longer fits the trials.
    context = [];
    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) || ~isfield(EEG.etc, 'alz') ...
            || ~isstruct(EEG.etc.alz) || ~isfield(EEG.etc.alz, 'epochNeighbours')
        return;
    end
    recorded = EEG.etc.alz.epochNeighbours;
    if isstruct(recorded) && all(isfield(recorded, {'types', 'next', 'previous'})) ...
            && size(recorded.next, 2) == nTrials && size(recorded.previous, 2) == nTrials
        context = recorded;
    end
end

function context = neighboursFromUrevents(EEG, nTrials)
%NEIGHBOURSFROMUREVENTS  The same table measured from EEG.urevent: each trial's
%   time zero is where its time-locking event lay in the recording. [] when
%   the dataset has no such table, or no trial's event points into it. A trial
%   whose event does not point into it has no neighbours.
    context = [];
    if ~isfield(EEG, 'urevent') || ~isstruct(EEG.urevent) || isempty(EEG.urevent) ...
            || ~isfield(EEG.urevent, 'latency') || ~isfield(EEG, 'event') ...
            || ~isfield(EEG.event, 'urevent') || ~isfield(EEG, 'srate') || ~isfield(EEG, 'times')
        return;
    end
    zero = nan(1, nTrials);
    for t = 1:nTrials
        anchor = zeroEvent(EEG, t);
        if anchor > 0
            p = EEG.event(anchor).urevent;
            if isnumeric(p) && isscalar(p) && p >= 1 && p <= numel(EEG.urevent)
                zero(t) = double(EEG.urevent(p).latency);
            end
        end
    end
    if all(isnan(zero))
        return;
    end
    context = TransTools.EpochNeighbours(EEG.urevent, zero, EEG.srate, EEG.times([1 end]));
end

function anchor = zeroEvent(EEG, t)
%ZEROEVENT  The event at trial T's time zero, 0 if it has none. An epoch that
%   holds several events lists them all, as pop_epoch and eeg_checkset leave
%   it, with each one's latency in the epoch beside it.
    anchor = 0;
    if ~isfield(EEG, 'epoch') || numel(EEG.epoch) < t || ~isfield(EEG.epoch, 'event')
        return;
    end
    events = EEG.epoch(t).event;
    if iscell(events)
        events = [events{:}];
    end
    if isscalar(events)
        if isnumeric(events) && events >= 1 && events <= numel(EEG.event)
            anchor = events;
        end
        return;
    end
    if isempty(events) || ~isfield(EEG.epoch, 'eventlatency')
        return;
    end
    latency = EEG.epoch(t).eventlatency;
    if iscell(latency)
        latency = [latency{:}];
    end
    if isnumeric(latency) && numel(latency) == numel(events)
        at = find(abs(latency) < 1e-6, 1);
        if ~isempty(at) && events(at) >= 1 && events(at) <= numel(EEG.event)
            anchor = events(at);
        end
    end
end

function rt = reactionTimes(EEG, nTrials)
%REACTIONTIMES  Each trial's DefineBins reaction time, NaN where it has none:
%   the first finite one of the bins it is in, in the order it matched them.
    rt = nan(1, nTrials);
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
        return;
    end
    [~, binrt] = TransTools.BinMembership.perUnit(TransTools.BinMembership.migrate(EEG));
    for t = 1:min(nTrials, numel(binrt))
        first = find(isfinite(binrt{t}), 1);
        if ~isempty(first)
            rt(t) = binrt{t}(first);
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
