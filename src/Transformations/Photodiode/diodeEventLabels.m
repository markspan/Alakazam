function labels = diodeEventLabels(onsets, events, pairs, suffix)
%DIODEEVENTLABELS  What to call each diode onset: its own trigger's name.
%   LABELS = diodeEventLabels(ONSETS, EVENTS, PAIRS, SUFFIX) returns one
%   label per onset. An onset paired with a trigger takes that trigger's
%   type with SUFFIX appended, so a diode onset answering "s70" is called
%   "s70PD". PAIRS is diodeTriggerDelay's own pairing.
%
%   WHY NOT ONE NAME FOR ALL OF THEM. A single type, "diode", says only
%   that the screen changed, and every downstream step then has to work out
%   WHICH change it was by looking at what came before it. Carrying the
%   trigger's own name means the diode events can be binned, counted and
%   epoched exactly like the triggers they stand in for: DefineBins can
%   name "s70PD" directly, and an analysis can be re-run against true
%   display times by changing which event type it reads.
%
%   THE SUFFIX IS WHAT KEEPS THEM DISTINGUISHABLE, and that matters more
%   than it looks. The diode event and its trigger are different instants,
%   tens of milliseconds apart, and an event table that called them both
%   "s70" would be one in which nobody could tell which timing they had
%   epoched to.
%
%   AN UNPAIRED ONSET GETS THE SUFFIX ALONE, since there is no trigger to
%   borrow a name from. That is a screen change nobody asked for, or one
%   whose trigger was lost, and it should stand out in the event table
%   rather than be quietly dropped or given a name it has not earned.
%
%   THE PAIRING IS PASSED IN RATHER THAN RECOMPUTED so that the label and
%   the measured lag cannot disagree: both come from the same run of
%   diodeTriggerDelay, with the same Types and MaxLagMs the analyst set.
%   Recomputing here with defaults is exactly how a report would come to
%   say one thing and the event table another.
%
%   See also DIODETRIGGERDELAY, PHOTODIODE, PHOTODIODEPREVIEW.
    arguments
        onsets double
        events struct = struct('type', {}, 'latency', {})
        pairs struct = struct('onset', {}, 'event', {}, 'lagMs', {})
        suffix (1, :) char = 'PD'
    end

    labels = repmat({suffix}, 1, numel(onsets));
    if isempty(onsets) || isempty(pairs)
        return;
    end

    pairedOnsets = [pairs.onset];
    for k = 1:numel(onsets)
        match = find(pairedOnsets == onsets(k), 1);
        if isempty(match)
            continue;
        end
        idx = pairs(match).event;
        if idx < 1 || idx > numel(events)
            continue;
        end
        labels{k} = [char(string(events(idx).type)) suffix];
    end
end
