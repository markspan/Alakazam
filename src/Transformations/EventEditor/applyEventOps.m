function [events, notes] = applyEventOps(events, ops, srate, pnts)
%APPLYEVENTOPS  Apply an ordered list of event-table operations.
%   [EVENTS, NOTES] = applyEventOps(EVENTS, OPS, SRATE, PNTS) returns the
%   edited event struct array and NOTES, a cellstr of anything worth telling
%   the analyst (an operation that matched nothing, a per-event edit whose
%   target no longer looks like the event it was recorded against).
%
%   OPS IS THE WHOLE POINT. This transformation stores an ordered list of
%   OPERATIONS, not the resulting event table, and the difference is what
%   makes it replayable at all.
%
%   Storing the result would be easy and wrong: replaying subject 1's
%   finished event table onto subject 2 would overwrite subject 2's events
%   with subject 1's, silently, and the tree would record it as a
%   successful step. Storing "rename 112 to 121, then shift every 121 back
%   16 ms" means the same CORRECTION is applied to each subject's own
%   events, which is what an analyst reaching for this actually wants:
%   trigger faults are properties of the recording setup, so they are
%   usually wrong the same way in every file.
%
%   Compare ChannelEditor, which stores the edited chanlocs but merges them
%   onto a different dataset BY LABEL. Channels have a stable key. Events do
%   not: event 47 of one recording is not event 47 of another, so nothing
%   here may be keyed on position alone (see 'setValue' below, which records
%   a fingerprint precisely because it must be).
%
%   The operations, all of which are order-dependent and applied in order:
%
%     renameType    .from  .to           every event of one type becomes another
%     deleteType    .types                events of these types are removed
%     keepTypes     .types                everything else is removed
%     shiftLatency  .types .ms            move these events in time (all, if
%                                         .types is empty)
%     setValue      .index .field .value  one event, changed by hand
%                   .wasType .wasLatency  what it looked like when recorded
%
%   See also EVENTEDITOR, EVENTEDITORDIALOG.
    notes = {};
    if isempty(ops)
        return;
    end
    if isempty(events)
        notes{end + 1} = 'This dataset has no events, so none of the recorded edits applied.';
        return;
    end

    for k = 1:numel(ops)
        op = ops(k);
        switch op.op
            case 'renameType'
                [events, n] = renameType(events, op);
                notes = [notes, n]; %#ok<AGROW>
            case 'deleteType'
                [events, n] = deleteTypes(events, op.types, false);
                notes = [notes, n]; %#ok<AGROW>
            case 'keepTypes'
                [events, n] = deleteTypes(events, op.types, true);
                notes = [notes, n]; %#ok<AGROW>
            case 'shiftLatency'
                [events, n] = shiftLatency(events, op, srate);
                notes = [notes, n]; %#ok<AGROW>
            case 'setValue'
                [events, n] = setValue(events, op);
                notes = [notes, n]; %#ok<AGROW>
            otherwise
                notes{end + 1} = sprintf('Unknown event operation "%s"; skipped.', ...
                    char(op.op)); %#ok<AGROW>
        end
    end

    [events, n] = tidy(events, pnts);
    notes = [notes, n];
end

% ======================================================================= %
function [events, notes] = renameType(events, op)
    notes = {};
    mask = typeMask(events, {op.from});
    if ~any(mask)
        notes{end + 1} = sprintf('No event of type "%s" to rename.', char(op.from));
        return;
    end
    idx = find(mask);
    for i = idx(:)'
        events(i).type = matchTypeClass(events(i).type, op.to);
    end
end

function [events, notes] = deleteTypes(events, types, keepInstead)
    notes = {};
    mask = typeMask(events, types);
    if keepInstead
        mask = ~mask;
        verb = 'kept';
    else
        verb = 'removed';
    end
    if ~any(mask)
        notes{end + 1} = sprintf('Nothing matched, so no event was %s.', verb);
        return;
    end
    events(mask) = [];
end

function [events, notes] = shiftLatency(events, op, srate)
%SHIFTLATENCY  Move events in time. Milliseconds in the operation, samples
%   in the data: the correction an analyst knows is "the triggers are 16 ms
%   late", and that stays true across recordings at different sampling
%   rates, which a sample count would not.
    notes = {};
    if isempty(srate) || ~isfinite(srate) || srate <= 0
        notes{end + 1} = 'Cannot shift latencies: this dataset has no usable sampling rate.';
        return;
    end
    % "Empty means every type" is decided on the FLATTENED value, not the raw
    % field: an operation built with struct() carries {'A'} where one built
    % by assignment carries {{'A'}}, and an empty one is {} or {{}}
    % accordingly. Deciding on the raw field made {{}} mean "no types at
    % all", so a shift meant to move everything moved nothing, quietly.
    if isempty(flattenTypes(op.types))
        mask = true(1, numel(events));
    else
        mask = typeMask(events, op.types);
    end
    if ~any(mask)
        notes{end + 1} = 'No event matched the latency shift.';
        return;
    end
    delta = op.ms * srate / 1000;
    idx = find(mask);
    for i = idx(:)'
        events(i).latency = events(i).latency + delta;
    end
end

function [events, notes] = setValue(events, op)
%SETVALUE  One event, changed by hand.
%
%   THE FINGERPRINT IS NOT DEFENSIVENESS, IT IS THE ONLY THING MAKING THIS
%   SAFE TO REPLAY. A hand edit is recorded against a position, and position
%   is meaningless in another recording: event 47 here is a different event
%   there. So the operation also records what the event looked like when it
%   was edited, and on replay the target must still match, or the edit is
%   skipped and said out loud. Applying it anyway would corrupt one event of
%   every other subject, invisibly.
    notes = {};
    i = op.index;
    if i < 1 || i > numel(events)
        notes{end + 1} = sprintf(['A hand edit was recorded for event %d, which this ' ...
            'dataset does not have (it has %d). Skipped.'], i, numel(events));
        return;
    end
    if ~fingerprintMatches(events(i), op)
        notes{end + 1} = sprintf(['A hand edit was recorded for event %d when it was ' ...
            'type "%s" at %.0f samples; here that event is type "%s" at %.0f samples, ' ...
            'so the edit was skipped. Hand edits are tied to one recording; a rename or ' ...
            'a latency shift would carry across.'], i, char(string(op.wasType)), ...
            op.wasLatency, char(string(events(i).type)), double(events(i).latency));
        return;
    end

    if strcmp(op.field, 'type')
        events(i).type = matchTypeClass(events(i).type, op.value);
    else
        events(i).(op.field) = op.value;
    end
end

% ======================================================================= %
function [events, notes] = tidy(events, pnts)
%TIDY  Put the table back in a state the rest of EEGLAB expects: ordered by
%   latency, and without events that have been pushed outside the data.
%
%   Both matter after a shift. EEGLAB assumes EEG.event is sorted by
%   latency, and a negative or past-the-end latency is not merely odd: it
%   makes epoching fail in ways that are hard to trace back to here.
    notes = {};
    if isempty(events)
        return;
    end

    if ~isempty(pnts) && isfinite(pnts) && pnts > 0
        lat = [events.latency];
        outside = lat < 1 | lat > pnts;
        if any(outside)
            notes{end + 1} = sprintf(['%d event(s) fell outside the data after editing ' ...
                'and were removed.'], sum(outside));
            events(outside) = [];
        end
    end
    if isempty(events)
        return;
    end

    [~, order] = sort([events.latency]);
    if ~isequal(order, 1:numel(events))
        events = events(order);
        notes{end + 1} = 'Events were re-sorted by latency after editing.';
    end
end

function mask = typeMask(events, types)
%TYPEMASK  Which events carry one of TYPES, comparing as text so a numeric
%   112 and the string "112" are the same code (the same rule the bin
%   language uses, see DefineBinsEngine.canonType).
    mask = false(1, numel(events));
    wanted = flattenTypes(types);
    if isempty(wanted)
        return;
    end
    for i = 1:numel(events)
        mask(i) = any(wanted == lower(strtrim(string(events(i).type))));
    end
end

function out = flattenTypes(types)
%FLATTENTYPES  TYPES as a lowercase string array, whatever shape it arrives
%   in: a char, a string, a cell of those, or a cell holding one of those.
%   The last case is not hypothetical -- struct() unwraps one cell level and
%   field assignment does not, so an operation built one way carries {'A'}
%   where the other carries {{'A'}}, and a reader should not have to know
%   which built it.
    out = strings(1, 0);
    if isempty(types)
        return;
    end
    if ischar(types) || isstring(types)
        out = lower(strtrim(string(types(:)')));
        return;
    end
    if ~iscell(types)
        out = lower(strtrim(string(types)));
        return;
    end
    for k = 1:numel(types)
        out = [out, flattenTypes(types{k})]; %#ok<AGROW>
    end
end

function value = matchTypeClass(existing, wanted)
%MATCHTYPECLASS  Write a new type without changing the column's class.
%   EEG.event(i).type is numeric in some recordings and char in others, and
%   a struct array holding both is a nuisance downstream. If the field was
%   numeric here and the new value reads as a number, keep it numeric.
    wanted = char(string(wanted));
    if isnumeric(existing)
        asNum = str2double(wanted);
        if ~isnan(asNum)
            value = asNum;
            return;
        end
    end
    value = wanted;
end

function tf = fingerprintMatches(event, op)
%FINGERPRINTMATCHES  Whether EVENT still looks like the one OP was recorded
%   against. Latency within half a sample, since a shift recorded earlier in
%   the same op list may legitimately have moved it.
    tf = strcmpi(strtrim(string(event.type)), strtrim(string(op.wasType))) ...
        && abs(double(event.latency) - double(op.wasLatency)) <= 0.5;
end
