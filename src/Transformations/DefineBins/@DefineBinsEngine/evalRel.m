function [tf, cap] = evalRel(node, p, ctx)
%EVALREL  Evaluate one 'rel' node (next/prev/adjacent/any) against
%   candidate event P.
    n       = numel(ctx.lat);
    matcher = node.matcher;
    iv      = node.interval;
    found   = 0;

    switch node.quant
        case 'next'
            qHi = n;
            if ~isempty(iv); [~, qHi] = DefineBinsEngine.windowRange(p, ctx, iv); qHi = min(qHi, n); end
            for q = p+1:qHi
                if DefineBinsEngine.evalNode(matcher, q, ctx); found = q; break; end
            end
        case 'prev'
            qLo = 1;
            if ~isempty(iv); [qLo, ~] = DefineBinsEngine.windowRange(p, ctx, iv); qLo = max(qLo, 1); end
            for q = p-1:-1:qLo
                if DefineBinsEngine.evalNode(matcher, q, ctx); found = q; break; end
            end
        case 'adjacent'
            if p+1 <= n && DefineBinsEngine.evalNode(matcher, p+1, ctx); found = p+1; end
        case 'any'
            % 'any' always carries a window (the parser requires it, see
            % pRelation), so its candidates are always a contiguous slice
            % of ctx.lat -- pruning to that slice via windowRange is what
            % keeps any(...) within (...) from re-scanning the whole
            % recording for every single event it is tested against.
            [qLo, qHi] = DefineBinsEngine.windowRange(p, ctx, iv);
            for q = max(qLo, 1):min(qHi, n)
                if q ~= p && DefineBinsEngine.evalNode(matcher, q, ctx) ...
                        && DefineBinsEngine.inInterval(DefineBinsEngine.delta(q, p, ctx, iv), iv)
                    found = q; break;
                end
            end
    end

    tf  = false;
    cap = NaN;
    if found > 0
        if strcmp(node.quant, 'any') || isempty(iv) ...
                || DefineBinsEngine.inInterval(DefineBinsEngine.delta(found, p, ctx, iv), iv)
            tf  = true;
            cap = ctx.lat(found);
        end
    end
end
