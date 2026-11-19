function EEG = AlignUrevents(EEG, before)
%ALIGNUREVENTS  Keep EEG.urevent, EEGLAB's table of a recording's original
%   events, true to the events of this dataset.
%
%   EEG = TransTools.AlignUrevents(EEG) gives a continuous recording with
%   events the table it does not have yet; EEG = TransTools.AlignUrevents(EEG,
%   BEFORE) does what EEGLAB's own steps do when EEG is the result of a step
%   run on BEFORE.
%
%   WHAT IT IS FOR. EEGLAB keeps every event of the recording in EEG.urevent,
%   at its latency in the recording, and each event in EEG.event points to its
%   entry (EEG.event(i).urevent). Cutting data or trials, or removing events,
%   does not touch the table. So a dataset reached through any number of steps
%   can still say where each event lay in the recording and what came before
%   and after it, which is what EEGLAB's eeg_context and eeg_time2prev read,
%   and what the epoch view's next and previous events fall back on
%   (epochSortKeys).
%
%   EEGLAB'S RULES, as its own functions keep them:
%     - The table is made once, from the events the recording arrives with,
%       as eeg_checkset(EEG, 'makeur') makes it. BioSig, FileIO and BrainVision
%       readers do that themselves, but the XDF reader and others do not, so
%       every import comes through here (WorkSpace's load*File).
%     - A removed event, or a change to an event's type or latency, leaves
%       the table as it was: it records what the recording held (pop_select,
%       pop_selectevent, pop_editeventvals' delete and assign).
%     - An added event goes in at its place in the recording, the table stays
%       in latency order and every pointer follows (pop_editeventvals' insert,
%       eeg_checkset's 'checkur'). A latency is taken back across cuts by
%       adding up the durations of the boundaries before it (eeg_urlatency).
%     - A boundary marking a cut has an empty pointer: it is not an event of
%       the recording (eeg_eegrej).
%     - Resampling rescales the table, and pop_resample does that itself.
%   EEGLAB's eeg_addnewevents is not used for the additions: it builds the
%   table again from the events still present, which loses every event since
%   removed from them, and fills their absent fields with NaN.
%
%   IT RUNS AT THE CONTRACT SEAM, on the input and on the result of every step
%   (TransTools.invoke), so no transformation or plugin has to know about the
%   table: the beats Heartbeats adds, an eye tracker's saccades and a
%   photodiode's onsets all arrive here with no pointer and leave with one. An
%   event added again at the same place, under the same type, points to the
%   entry it had, so re-running a step does not fill the table with copies.
%
%   A TOOLBOX'S OWN ENTRIES ARE LEFT AS IT LEFT THEM, order included. EYE-EEG's
%   addevents writes a saccade's or a fixation's entry and pointer itself, with
%   the event's own fields, so they arrive here linked. It appends them: its last
%   sort, pop_editeventvals with 'sort' from a script, skips 'checkur'. So after
%   EYE-EEG the table is not in latency order, and eeg_context and eeg_time2prev,
%   which walk it by position, give the recording's first saccade as the next one
%   after every trigger, and find no previous one (measured 2026-11-02 with
%   EYE-EEG 1.01). That is kept, and documented in the Eye tracking plugin's
%   manual: an Alakazam result is the toolbox's result. epochSortKeys is not
%   affected, since TransTools.EpochNeighbours sorts by latency. An event a later
%   step adds does sort the table, as EEGLAB's own insert does.
%
%   ONLY CONTINUOUS DATA IS CHANGED. On trials, or an average, a new event's
%   latency says nothing about the recording, so it has no pointer, as a
%   boundary has none. EEGLAB's pop_resample empties the table of epoched
%   data, because it cannot rescale it; the pointers then point at nothing, and
%   they are removed. A dataset whose steps ran before there was a table
%   (a workspace saved before 2026-11-02) gets it from the next step that runs
%   on it, while it is continuous. Trials cut before then stay without one,
%   since the recording's events are no longer there to make it from.
%
%   See also TRANSTOOLS.INVOKE, TRANSTOOLS.EPOCHNEIGHBOURS, EPOCHSORTKEYS.
    if nargin < 2
        before = [];
    end
    if ~isstruct(EEG) || ~isfield(EEG, 'event') || ~isstruct(EEG.event) || isempty(EEG.event)
        return;
    end

    if ~isContinuous(EEG)
        if ~hasTable(EEG) && isfield(EEG.event, 'urevent')
            EEG.event = rmfield(EEG.event, 'urevent');
        end
        return;
    end

    % A step that rebuilt the events can lose the table on the way: eeg_checkset
    % removes it when the pointers are gone. Unless the step changed the
    % rate, which only pop_resample can rescale for, it still holds.
    if ~hasTable(EEG) && hasTable(before) && sameRate(EEG, before)
        EEG.urevent = before.urevent;
    end

    if ~hasTable(EEG)
        EEG = makeTable(EEG);
    else
        EEG = linkEvents(EEG);
    end
end

% ======================================================================= %
function EEG = makeTable(EEG)
%MAKETABLE  What eeg_checkset(EEG, 'makeur') makes: every event an entry, each
%   pointing to its own. Latencies are the recording's: on data already cut,
%   the boundaries' durations are added back, which changes nothing otherwise.
    table = entriesOf(EEG.event);
    latency = originalLatency(EEG.event, [EEG.event.latency]);
    for k = 1:numel(table)
        table(k).latency = latency(k);
    end
    EEG.urevent = table;
    pointers = num2cell(1:numel(EEG.event));
    [EEG.event.urevent] = pointers{:};
end

function EEG = linkEvents(EEG)
%LINKEVENTS  Give every event without a pointer, other than a boundary, the
%   entry it matches or a new one, keeping the table in latency order.
    if ~isfield(EEG.event, 'urevent')
        [EEG.event.urevent] = deal([]);
    end
    nEntries = numel(EEG.urevent);
    unlinked = find(arrayfun(@(e) ~isPointer(e.urevent, nEntries) && ~isBoundary(e), EEG.event));
    if isempty(unlinked)
        return;
    end

    latency = originalLatency(EEG.event, [EEG.event(unlinked).latency]);
    tableLatency = [EEG.urevent.latency];
    tableType = typeTexts(EEG.urevent);
    isNew = false(1, numel(unlinked));
    for k = 1:numel(unlinked)
        same = find(abs(tableLatency - latency(k)) < 1e-6);
        same = same(strcmp(tableType(same), typeText(EEG.event(unlinked(k)))));
        if isempty(same)
            isNew(k) = true;
        else
            EEG.event(unlinked(k)).urevent = same(1);
        end
    end

    fresh = unlinked(isNew);
    if isempty(fresh)
        return;
    end
    added = entriesOf(EEG.event(fresh));
    freshLatency = latency(isNew);
    for k = 1:numel(added)
        added(k).latency = freshLatency(k);
        if ~isfield(added, 'duration') || isempty(added(k).duration)
            added(k).duration = 0;
        end
    end
    [table, added] = withSameFields(EEG.urevent, added);
    combined = [reshape(table, 1, []), reshape(added, 1, [])];

    [~, order] = sort([combined.latency]);
    position(order) = 1:numel(order);
    for i = 1:numel(EEG.event)
        p = EEG.event(i).urevent;
        if isPointer(p, nEntries)
            EEG.event(i).urevent = position(p);
        end
    end
    for k = 1:numel(fresh)
        EEG.event(fresh(k)).urevent = position(nEntries + k);
    end
    EEG.urevent = combined(order);
end

function latency = originalLatency(events, latency)
%ORIGINALLATENCY  A latency in the recording, as eeg_urlatency works it out:
%   each boundary before it stands for that much data taken out. A boundary
%   with no duration, or NaN (a break in the recording), took out nothing.
    if ~isfield(events, 'duration')
        return;
    end
    latencies = latency;
    for b = find(arrayfun(@isBoundary, events))
        duration = events(b).duration;
        if isnumeric(duration) && isscalar(duration) && ~isnan(duration)
            after = events(b).latency < latencies;
            latency(after) = latency(after) + duration;
        end
    end
end

function table = entriesOf(events)
%ENTRIESOF  Events as table entries, without what belongs to this dataset's
%   own bookkeeping: the pointer, the trial, and the bins of a later step.
    table = rmfield(events, intersect(fieldnames(events), {'urevent', 'epoch', 'bini', 'binrt'}));
end

function [a, b] = withSameFields(a, b)
%WITHSAMEFIELDS  Two struct arrays made joinable: a field only one has is
%   empty in the other, so a new event's own fields (a beat's .ibi) are kept.
    for f = setdiff(fieldnames(b), fieldnames(a))'
        [a.(f{1})] = deal([]);
    end
    for f = setdiff(fieldnames(a), fieldnames(b))'
        [b.(f{1})] = deal([]);
    end
    b = orderfields(b, a);
end

% ======================================================================= %
function tf = hasTable(EEG)
    tf = isstruct(EEG) && isfield(EEG, 'urevent') && isstruct(EEG.urevent) ...
        && ~isempty(EEG.urevent) && isfield(EEG.urevent, 'latency');
end

function tf = isContinuous(EEG)
%ISCONTINUOUS  By its DataFormat, or for a dataset without one, by its shape.
    format = char(string(TransTools.FieldOr(EEG, 'DataFormat', '')));
    if ~isempty(format)
        tf = strcmpi(format, 'CONTINUOUS');
    else
        tf = (~isfield(EEG, 'data') || size(EEG.data, 3) == 1) ...
            && (~isfield(EEG, 'epoch') || isempty(EEG.epoch));
    end
end

function tf = sameRate(a, b)
    tf = isequal(TransTools.FieldOr(a, 'srate', []), TransTools.FieldOr(b, 'srate', []));
end

function tf = isPointer(p, nEntries)
    tf = isnumeric(p) && isscalar(p) && ~isnan(p) && p >= 1 && p <= nEntries;
end

function tf = isBoundary(event)
%ISBOUNDARY  EEGLAB's two spellings of a cut, as pop_resample tests them.
    text = typeText(event);
    tf = strcmpi(text, 'boundary') || strcmp(text, '-99');
end

function text = typeText(event)
    text = char(string(event.type));
end

function texts = typeTexts(events)
    texts = arrayfun(@typeText, events, 'UniformOutput', false);
end
