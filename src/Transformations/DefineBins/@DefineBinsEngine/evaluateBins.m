function [EEG, bindesc, centerLat] = evaluateBins(EEG, bins)
%EVALUATEBINS  Match every bin's predicate against every event in EEG, tag
%   each event with its bin membership (EEG.event(i).bini, ERPLAB-style),
%   and build the per-bin EEG.bindesc summary (matched event indices,
%   per-match reaction times; combination bins are left for Average to
%   compute). CENTERLAT is the sample each event's own epoch should be
%   centred on: its own latency, unless some bin's 'timelock' clause
%   overrides it with a matched neighbour's latency instead.
%#ok<*AGROW>
    [ctx, order] = DefineBinsEngine.buildContext(EEG);
    nEv = numel(order);
    membership = cell(1, nEv);
    centerLat  = round([EEG.event.latency]);
    bindesc = struct('index', {}, 'label', {}, 'script', {}, 'plan', {}, ...
                     'combo', {}, 'events', {}, 'rt', {}, 'n', {});

    for b = 1:numel(bins)
        if ~isempty(bins(b).combo)
            % Combination (difference) bin: no event predicate; the Average
            % step computes it from the referenced bins' averages.
            bindesc(b) = binRecord(bins(b), [], [], bins(b).combo);
            continue;
        end

        matchedOrig = [];
        rts = [];
        for p = 1:nEv
            [tf, capLat] = DefineBinsEngine.evalNode(bins(b).expr, p, ctx);
            if ~tf; continue; end

            if isnan(capLat)
                rtMs = NaN;
            else
                rtMs = (capLat - ctx.lat(p)) / ctx.srate * 1000;
            end

            % 'rt within W': keep the match only if its reaction time is in W.
            if ~isempty(bins(b).rtWindow) ...
                    && (isnan(rtMs) || ~DefineBinsEngine.inInterval(rtMs, bins(b).rtWindow))
                continue;
            end

            % 'timelock <rel>': centre the epoch on a neighbour, not the anchor.
            if ~isempty(bins(b).timelock)
                [okTL, tlLat] = DefineBinsEngine.evalRel(bins(b).timelock, p, ctx);
                if ~okTL; continue; end          % nothing to lock to -> drop
                centerLat(order(p)) = round(tlLat);
            end

            matchedOrig(end+1)   = order(p);
            rts(end+1)           = rtMs;
            membership{p}(end+1) = bins(b).index;
        end
        bindesc(b) = binRecord(bins(b), matchedOrig, rts, []);
    end

    % Tag events with their bin membership (ERPLAB-style .bini).
    for p = 1:nEv
        EEG.event(order(p)).bini = membership{p};
    end
end

function rec = binRecord(bin, events, rts, combo)
%BINRECORD  Build one EEG.bindesc entry with a stable field order.
    rec.index  = bin.index;
    rec.label  = bin.label;
    rec.script = bin.text;
    rec.plan   = bin.expr;
    rec.combo  = combo;
    rec.events = events;
    rec.rt     = rts;
    rec.n      = numel(events);
end
