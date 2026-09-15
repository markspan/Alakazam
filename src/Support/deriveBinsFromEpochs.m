function EEG = deriveBinsFromEpochs(EEG)
%DERIVEBINSFROMEPOCHS  Adapt a foreign (non-Alakazam) epoched dataset's own
%   EEGLAB-native per-epoch event info into Alakazam's own bin-tagging
%   convention (EEG.bindesc / EEG.event(i).bini / EEG.epoch(k).bini -- see
%   DefineBins.m's own header comment for the authoritative shape), so an
%   already-epoched .set dropped into the data directory (another EEGLAB
%   pipeline's output, not one DefineBins itself produced) is immediately
%   groupable by condition -- EpochView's "group by bin", AverageView's
%   per-bin lines, CoherenceMap/CoherenceTopography/SpectralMeasure's
%   per-bin output -- and further editable the same way a DefineBins result
%   is (rename a bin, add a difference bin, re-run with a script).
%
%   A no-op (returns EEG unchanged) when there is nothing sensible to do:
%   EEG already carries .bindesc (an Alakazam-produced or already-adapted
%   result -- re-deriving would just discard whatever editing happened
%   since), EEG.trials <= 1 (nothing to group), or EEG lacks the per-epoch
%   event metadata (.epoch(k).eventlatency/.event, .event(i).type) pop_epoch
%   itself always writes -- a dataset that reached here some other way (a
%   raw .mat, say) has nothing to derive from.
%
%   THE ANCHOR, AND WHY LATENCY 0. EEGLAB's pop_epoch keeps every event that
%   falls inside an epoch's time window, not just the one it was cut around
%   -- a wide window (as RIFT's own -2 to +11 s epochs are) routinely also
%   catches a neighbouring trial's onset/offset markers at large positive or
%   negative latencies. The event pop_epoch actually CENTRED the epoch on is
%   always the one at EXACTLY latency 0 (by construction: every other
%   event's latency is computed relative to it), so that is the one trial-
%   defining "anchor" event picked out here -- its own .type string becomes
%   the condition this trial is grouped under. A trial with no event at
%   latency 0 (malformed data, or an epoch window that does not actually
%   contain its own centring event) is kept in the dataset -- not dropped --
%   but tagged with no bin (.bini = []), the same way DefineBins itself
%   leaves an event that matched no bin's predicate.
%
%   Alakazam's OWN epoch model is deliberately leaner than pop_epoch's: one
%   anchor event per trial, not every event the window happened to catch
%   (see cutEpochs.m) -- EEG.epoch is REPLACED here with that leaner shape,
%   not merely added to, since nothing downstream reads pop_epoch's own
%   richer per-epoch fields (eventduration, eventbvtime, ...) and carrying
%   them forward risks a stale, unrelated-to-bini field being trusted later.
%
%   Bin labels are the anchor's own raw type string (e.g. "10"), not a
%   guessed human name: this has to work for any foreign recording's own
%   marker vocabulary, not just RIFT's -- rename via DefineBins or the
%   workspace tree once the data is in, the same as any other bin.
%
%   See also LOADSETFILE, DEFINEBINS, DEFINEBINSENGINE.EVALUATEBINS,
%   DEFINEBINSENGINE.CUTEPOCHS.
    if isfield(EEG, 'bindesc') && ~isempty(EEG.bindesc)
        return;
    end
    if ~isfield(EEG, 'trials') || EEG.trials <= 1
        return;
    end
    if ~isfield(EEG, 'epoch') || isempty(EEG.epoch) ...
            || ~isfield(EEG.epoch, 'eventlatency') || ~isfield(EEG.epoch, 'event') ...
            || ~isfield(EEG.epoch, 'eventtype')
        return;
    end
    if ~isfield(EEG, 'event') || isempty(EEG.event) || ~isfield(EEG.event, 'type')
        return;
    end

    nTrials = numel(EEG.epoch);
    anchorEvent = nan(1, nTrials);
    for t = 1:nTrials
        lat = asCellRow(EEG.epoch(t).eventlatency);
        idx = asCellRow(EEG.epoch(t).event);
        if isempty(lat) || numel(lat) ~= numel(idx)
            continue;
        end
        latNum = cellfun(@double, lat);
        [minAbs, zi] = min(abs(latNum));
        if isempty(zi) || minAbs > 1e-6
            continue; % no event sits at this trial's own time-zero
        end
        anchorEvent(t) = double(idx{zi});
    end

    valid = ~isnan(anchorEvent) & anchorEvent >= 1 & anchorEvent <= numel(EEG.event);
    if ~any(valid)
        return; % nothing usable to group by -- leave EEG exactly as loaded
    end

    if ~isfield(EEG.event, 'bini')
        [EEG.event.bini] = deal([]);
    end

    anchorType = strings(1, nTrials);
    anchorType(valid) = arrayfun(@(ei) string(EEG.event(ei).type), anchorEvent(valid));
    [uTypes, ~, ic] = unique(anchorType(valid));
    trialNums = find(valid);

    bindesc = struct('index', {}, 'label', {}, 'script', {}, 'plan', {}, ...
                      'combo', {}, 'events', {}, 'rt', {}, 'n', {}, 'trials', {});
    for b = 1:numel(uTypes)
        members  = trialNums(ic == b);
        eventIdx = anchorEvent(members);
        for k = 1:numel(eventIdx)
            EEG.event(eventIdx(k)).bini = [EEG.event(eventIdx(k)).bini, b];
        end
        bindesc(b).index  = b;
        bindesc(b).label  = char(uTypes(b));
        bindesc(b).script = '';
        bindesc(b).plan   = [];
        bindesc(b).combo  = [];
        bindesc(b).events = eventIdx;
        bindesc(b).rt     = nan(1, numel(eventIdx));
        bindesc(b).n      = numel(eventIdx);
        bindesc(b).trials = members;
    end

    newEpoch = struct('event', {}, 'eventtype', {}, 'eventlatency', {}, 'bini', {});
    for t = 1:nTrials
        if ~valid(t)
            newEpoch(t).event        = [];
            newEpoch(t).eventtype    = '';
            newEpoch(t).eventlatency = 0;
            newEpoch(t).bini         = [];
            continue;
        end
        ei = anchorEvent(t);
        newEpoch(t).event        = ei;
        newEpoch(t).eventtype    = EEG.event(ei).type;
        newEpoch(t).eventlatency = 0;
        newEpoch(t).bini         = EEG.event(ei).bini;
    end

    EEG.epoch   = newEpoch;
    EEG.bindesc = bindesc;
end

function c = asCellRow(v)
%ASCELLROW  pop_epoch stores a per-epoch field (.eventtype/.eventlatency/
%   ...) as a bare scalar when only one event fell in that epoch, and as a
%   cell row once there are two or more -- EXCEPT .event itself, which
%   pop_epoch keeps as a plain numeric row even with several events
%   (confirmed directly against a real multi-event epoch: .eventlatency was
%   a 1x7 cell, .event the plain double row [8 9 10 11 12 13 14] for the
%   same epoch) -- so a >1-element numeric array is split into one cell per
%   element too, not treated as a single scalar value. Normalises every
%   field's shape to a cell row so every trial is handled the same way
%   regardless of which of pop_epoch's two conventions a given field uses.
    if iscell(v)
        c = v;
    elseif isnumeric(v) && numel(v) > 1
        c = num2cell(v);
    else
        c = {v};
    end
end
