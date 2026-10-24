function [EEG, bindesc, centerLat] = evaluateBins(EEG, bins)
%EVALUATEBINS  Match every bin's predicate against every event in EEG, tag
%   each event with its bin membership (EEG.event(i).bini, ERPLAB-style),
%   and build the per-bin EEG.bindesc summary (matched event indices,
%   per-match reaction times; combination bins are left for Average to
%   compute). CENTERLAT is the sample each event's own epoch should be
%   centred on: its own latency, unless some bin's 'timelock' clause
%   overrides it with a matched neighbour's latency instead.
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
    membership = cell(1, nEv);
    % floor, matching EEGLAB/ERPLAB -- see the note in the header above.
    centerLat  = floor([EEG.event.latency]);
    bindesc = struct('index', {}, 'label', {}, 'script', {}, 'plan', {}, ...
                     'combo', {}, 'events', {}, 'rt', {}, 'n', {}, 'rtTrim', {});

    for b = 1:numel(bins)
        if TransTools.IsComboBin(bins(b))
            % Combination (difference) bin: no event predicate; the Average
            % step computes it from the referenced bins' averages.
            bindesc(b) = binRecord(bins(b), [], [], bins(b).combo, []);
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

        matchedOrig = [];
        rts = [];
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
            end

            matchedOrig(end+1)   = order(p);
            rts(end+1)           = rtMs;
            membership{p}(end+1) = bins(b).index;
        end
        if ~isempty(rtTrim)
            rtTrim.removed = rtRemoved;
        end
        bindesc(b) = binRecord(bins(b), matchedOrig, rts, [], rtTrim);
    end

    % Tag events with their bin membership (ERPLAB-style .bini).
    for p = 1:nEv
        EEG.event(order(p)).bini = membership{p};
    end
end

function rec = binRecord(bin, events, rts, combo, rtTrim)
%BINRECORD  Build one EEG.bindesc entry with a stable field order. RTTRIM
%   is what a window relative to the mean reaction time resolved to (see
%   resolveRtWindow), or [] for a bin without one.
    rec.index  = bin.index;
    rec.label  = bin.label;
    rec.script = bin.text;
    rec.plan   = bin.expr;
    rec.combo  = combo;
    rec.events = events;
    rec.rt     = rts;
    rec.n      = numel(events);
    rec.rtTrim = rtTrim;
end
