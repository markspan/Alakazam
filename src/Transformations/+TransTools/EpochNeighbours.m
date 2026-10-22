function context = EpochNeighbours(events, zeroSamples, srate, windowMs, zeroLatencies)
%EPOCHNEIGHBOURS  For each trial, when the nearest event of every type falls
%   before and after the event it is locked to, within its window.
%   CONTEXT = TransTools.EpochNeighbours(EVENTS, ZEROSAMPLES, SRATE,
%   WINDOWMS, ZEROLATENCIES) takes the continuous recording's EVENTS
%   (latencies in samples, before epoching rewrites them), each trial's time
%   zero as a sample of that recording, the epoch window in ms, and the exact
%   latency of the event each trial is locked to, and returns
%     .types     1 x nTypes, every event type in the recording except boundary
%     .next      nTypes x nTrials: ms from time zero to the first event of
%                that type after it, NaN when none falls inside the window
%     .previous  nTypes x nTrials: ms (negative) to the last one before it
%     .trials    nTrials, so a reader can tell the table still fits the data
%   Strictly after and strictly before the locked-to event, so a trial's own
%   event is never its own neighbour. ZEROLATENCIES defaults to ZEROSAMPLES.
%
%   AFTER THE EVENT, NOT AFTER THE SAMPLE. Time zero is a whole sample (the
%   latency floored, as EEGLAB cuts epochs), but an event's latency need not
%   be: the Heartbeats plugin places each R-peak between samples. Compared
%   with the floored sample, a trial's own heartbeat came a fraction of a
%   sample after time zero, so it was its own "next heartbeat", less than a
%   sample from zero in every trial (reported 2026-10-22). Which event is after and which
%   before is therefore decided on the exact latency; the time is still
%   measured from time zero, where the image's own zero is.
%
%   WHY IT IS RECORDED AT ALL. Sorting an ERP image by the next saccade, the
%   next button press or the stimulus before (the plots in Ehinger & Dimigen,
%   2019, Fig. 11, and Unfold's tutorial 7) needs to know where those events
%   were, and an epoched Alakazam dataset keeps only each trial's own event:
%   cutEpochs gives every other event .epoch = 0, which a later eeg_checkset
%   prunes. So the neighbours are measured once, while the continuous
%   latencies still exist, and kept beside the trials (EEG.etc.alz,
%   read by epochSortKeys).
%
%   See also DEFINEBINSENGINE/CUTEPOCHS, UNFOLD.FITBINS, EPOCHSORTKEYS.
    nTrials = numel(zeroSamples);
    if nargin < 5 || isempty(zeroLatencies)
        zeroLatencies = zeroSamples;
    end
    context = struct('types', {{}}, 'next', zeros(0, nTrials), ...
        'previous', zeros(0, nTrials), 'trials', nTrials);
    if isempty(events) || ~isfield(events, 'type') || ~isfield(events, 'latency')
        return;
    end
    types = arrayfun(@(e) char(string(e.type)), events, 'UniformOutput', false);
    latency = double([events.latency]);
    keep = ~strcmpi(types, 'boundary');
    types = types(keep);
    latency = latency(keep);
    context.types = unique(types, 'stable');

    nTypes = numel(context.types);
    context.next = nan(nTypes, nTrials);
    context.previous = nan(nTypes, nTrials);
    zero = double(reshape(zeroSamples, 1, []));
    locked = double(reshape(zeroLatencies, 1, []));
    for k = 1:nTypes
        these = sort(latency(strcmp(types, context.types{k})));
        for t = 1:nTrials
            after = these(find(these > locked(t), 1, 'first'));
            before = these(find(these < locked(t), 1, 'last'));
            if ~isempty(after)
                context.next(k, t) = (after - zero(t)) / srate * 1000;
            end
            if ~isempty(before)
                context.previous(k, t) = (before - zero(t)) / srate * 1000;
            end
        end
    end
    context.next(context.next > windowMs(2)) = NaN;
    context.previous(context.previous < windowMs(1)) = NaN;
end
