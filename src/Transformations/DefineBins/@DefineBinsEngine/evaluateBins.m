function [EEG, bindesc, centerLat, zeroLat] = evaluateBins(EEG, bins)
%EVALUATEBINS  Match every bin's predicate against every event in EEG, tag
%   each event with its bin membership (EEG.event(i).bini, ERPLAB-style)
%   and the reaction time each of those bins captured (EEG.event(i).binrt),
%   and build the per-bin EEG.bindesc summary (how many events each bin
%   matched, what its windows resolved to; combination bins are left for
%   Average to compute). CENTERLAT is the sample each event's own epoch should be
%   centred on: its own latency, unless some bin's 'timelock' clause
%   overrides it with a matched neighbour's latency instead. ZEROLAT is
%   that same latency before it was floored, the exact time of the event the
%   epoch is locked to, which cutEpochs needs to tell that event from its
%   neighbours (see TransTools.EpochNeighbours).
%
%   THE TIME-LOCKING SAMPLE IS CHOSEN WITH FLOOR, MATCHING EEGLAB AND
%   ERPLAB. Event latencies are fractional once a recording has been
%   resampled (a 1024->256 Hz file carries latencies ending .00, .25, .50
%   and .75), so which sample is labelled t=0 has to be decided, and the two
%   defensible answers disagree:
%
%     floor  -- truncate, as EEGLAB does (epoch.m: pos0 =
%               floor(events(index)*srate)) and as ERPLAB's pop_epochbin
%               does. The sample labelled t=0 then sits up to a full sample
%               BEFORE the event, so every latency measure carries a
%               systematic half-sample bias, about 2 ms at 256 Hz.
%     round  -- take the nearest sample. No mean bias and half the
%               worst-case error, so it is the more accurate labelling.
%
%   Alakazam uses floor, and the reason is reproducibility rather than
%   accuracy. Validated against Luck's own published output (see
%   Docs/luck.md): with floor, Alakazam's epochs are bit-identical to
%   pop_epochbin's on all 267 trials of the chapter 8 N2pc file, and the
%   whole DefineBins + Baseline + ArtefactDetect + Average chain reproduces
%   the published chapter 3 erpset to 0.0004 uV with exactly ERPLAB's
%   accepted and rejected trial counts. With round it did not: one trial
%   crossed the rejection threshold and the averaged ERP moved by 15 to 30%
%   relative RMS on that broadband data. Half a sample of uniform bias
%   shifts every condition equally and so cancels in difference waves and
%   condition contrasts, which is what ERP work actually measures; being
%   unable to reproduce a published ERPLAB result does not cancel.
%
%   So this is a deliberate choice to match the field's reference
%   implementations, not an oversight, and changing it to round would
%   silently break bit-agreement with every EEGLAB/ERPLAB analysis.
%#ok<*AGROW>
    [ctx, order] = DefineBinsEngine.buildContext(EEG);
    nEv = numel(order);
    % Which bins each event is in, and the reaction time each bin captured:
    % the one store of bin membership (see TransTools.BinMembership).
    membership = cell(1, nEv);
    memberRts = cell(1, nEv);
    % floor, matching EEGLAB/ERPLAB -- see the note in the header above.
    zeroLat    = double([EEG.event.latency]);
    centerLat  = floor(zeroLat);
    bindesc = struct('index', {}, 'label', {}, 'script', {}, 'plan', {}, ...
                     'combo', {}, 'n', {}, 'rtTrim', {}, 'filters', {});

    for b = 1:numel(bins)
        if TransTools.IsComboBin(bins(b))
            % Combination (difference) bin: no event predicate; the Average
            % step computes it from the referenced bins' averages.
            bindesc(b) = binRecord(bins(b), 0, bins(b).combo, [], []);
            continue;
        end

        % Every event the condition matches, with its reaction time. The
        % 'rt within' filter comes after, in a pass of its own, because a
        % window relative to the mean needs all of this bin's reaction
        % times before it can say which of them to keep.
        candidates = [];
        candidateRts = [];
        for p = 1:nEv
            [tf, capLat] = DefineBinsEngine.evalNode(bins(b).expr, p, ctx);
            if ~tf; continue; end
            candidates(end+1) = p;
            if isnan(capLat)
                candidateRts(end+1) = NaN;
            else
                candidateRts(end+1) = (capLat - ctx.lat(p)) / ctx.srate * 1000;
            end
        end

        rtWindow = bins(b).rtWindow;
        rtTrim = [];
        if ~isempty(rtWindow)
            [rtWindow, rtTrim] = DefineBinsEngine.resolveRtWindow(rtWindow, candidateRts);
        end

        % The bin's other tests about its trials as a whole (ranks, medians,
        % percentiles, ...; see splitFilters): each over the same candidates,
        % its window resolved from their values, not from what another test
        % left. PASSES(f, c) says whether candidate c passes test f.
        filters = binFilters(bins(b));
        filterRecords = [];
        passes = true(numel(filters), numel(candidates));
        for f = 1:numel(filters)
            values = DefineBinsEngine.filterValues(filters(f), candidates, candidateRts, ctx);
            [iv, record] = DefineBinsEngine.resolveValueWindow(filters(f), values);
            for c = 1:numel(candidates)
                passes(f, c) = ~isnan(values(c)) && DefineBinsEngine.inInterval(values(c), iv);
            end
            record.removed = nnz(~passes(f, :));
            if isempty(filterRecords)
                filterRecords = record;
            else
                filterRecords(f) = record;
            end
        end

        nMatched = 0;
        rtRemoved = 0;
        for c = 1:numel(candidates)
            p = candidates(c);
            rtMs = candidateRts(c);

            % 'rt within W': keep the match only if its reaction time is in W.
            % A bound that could not be computed is NaN, and keeps nothing.
            if ~isempty(rtWindow) ...
                    && (isnan(rtMs) || ~DefineBinsEngine.inInterval(rtMs, rtWindow))
                rtRemoved = rtRemoved + 1;
                continue;
            end
            if ~all(passes(:, c))
                continue;
            end

            % 'timelock <rel>': centre the epoch on a neighbour, not the anchor.
            if ~isempty(bins(b).timelock)
                [okTL, tlLat] = DefineBinsEngine.evalRel(bins(b).timelock, p, ctx);
                if ~okTL; continue; end          % nothing to lock to -> drop
                % floor, for the same reason as centerLat above: a
                % neighbour's latency is just as fractional as the anchor's,
                % and an epoch time-locked to a response has to be cut on
                % the same convention as one time-locked to a stimulus or
                % the two are a sample apart for no stated reason.
                centerLat(order(p)) = floor(tlLat);
                zeroLat(order(p)) = tlLat;
            end

            nMatched             = nMatched + 1;
            membership{p}(end+1) = bins(b).index;
            memberRts{p}(end+1)  = rtMs;
        end
        if ~isempty(rtTrim)
            rtTrim.removed = rtRemoved;
        end
        bindesc(b) = binRecord(bins(b), nMatched, [], rtTrim, filterRecords);
    end

    % Tag events with their bin membership (ERPLAB-style .bini) and, beside
    % it, the reaction time each of those bins captured (.binrt).
    for p = 1:nEv
        EEG.event(order(p)).bini  = membership{p};
        EEG.event(order(p)).binrt = memberRts{p};
    end
end

function rec = binRecord(bin, n, combo, rtTrim, filters)
%BINRECORD  Build one EEG.bindesc entry with a stable field order. N is the
%   number of events the bin matched; which ones, and their reaction times,
%   are on the events (.bini, .binrt). RTTRIM is what a window relative to
%   the mean reaction time resolved to (see resolveRtWindow), or [] for a
%   bin without one; FILTERS what each of the bin's other tests about its
%   trials came to (resolveValueWindow), or [].
    rec.index   = bin.index;
    rec.label   = bin.label;
    rec.script  = bin.text;
    rec.plan    = bin.expr;
    rec.combo   = combo;
    rec.n       = n;
    rec.rtTrim  = rtTrim;
    rec.filters = filters;
end

function filters = binFilters(bin)
%BINFILTERS  A bin's tests about its trials beyond rtWindow: [] for a plan
%   compiled before there were any, and a struct array whichever way a
%   template's JSON brought it back.
    filters = [];
    if isfield(bin, 'filters') && ~isempty(bin.filters)
        filters = bin.filters;
        if iscell(filters)
            filters = [filters{:}];
        end
    end
end
