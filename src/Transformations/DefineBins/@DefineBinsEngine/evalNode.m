function [tf, cap] = evalNode(node, p, ctx)
%EVALNODE  Evaluate one compiled expression-tree node against candidate
%   event P. CAP is the captured neighbour latency a 'rel' node matched at
%   (NaN for a plain anchor/not/and/or), threaded up through and/or so a
%   bin's reaction time and 'timelock' target can be read off the match.
    switch node.op
        case 'anchor'
            tf  = DefineBinsEngine.matchCode(ctx.typ(p), node.codes);
            cap = NaN;
        case 'rel'
            [tf, cap] = DefineBinsEngine.evalRel(node, p, ctx);
            % ONLY A FORWARD MATCH BECOMES A REACTION TIME. evalRel captures
            % whatever latency it matched, in either direction, and that is
            % right for its other caller: 'timelock' may legitimately lock the
            % epoch to a PRECEDING event. But a backward match must not become
            % the bin's rt, and it used to. Because 'and' takes the first
            % non-NaN capture left to right, a bin written as
            %     112 and prev(cue) ... and next(response) ...
            % recorded the CUE delay -- negative -- as its reaction time,
            % while the same bin with the two relations written the other way
            % round recorded the response. An rt that depends on the order the
            % terms happen to appear in is worse than no rt at all, so a
            % capture is kept only when it is later than the anchor.
            if ~isnan(cap) && cap <= ctx.lat(p)
                cap = NaN;
            end
        case 'not'
            tf  = ~DefineBinsEngine.evalNode(node.kid, p, ctx);
            cap = NaN;
        case 'and'
            tf = true; cap = NaN;
            for k = 1:numel(node.kids)
                [t, c] = DefineBinsEngine.evalNode(node.kids{k}, p, ctx);
                tf = tf && t;
                if isnan(cap) && ~isnan(c); cap = c; end
            end
            if ~tf; cap = NaN; end
        case 'or'
            tf = false; cap = NaN;
            for k = 1:numel(node.kids)
                [t, c] = DefineBinsEngine.evalNode(node.kids{k}, p, ctx);
                if t
                    tf = true;
                    if isnan(cap) && ~isnan(c); cap = c; end
                end
            end
        otherwise
            throw(MException('Alakazam:DefineBins', ...
                ['I''m sorry, something has gone wrong internally: the compiled ' ...
                 'expression tree contains a node type (''%s'') the evaluator does not ' ...
                 'know how to handle. This should be impossible from any script the ' ...
                 'parser accepts, so it likely means a saved/replayed .bins struct was ' ...
                 'hand-edited or came from an incompatible version -- please would you ' ...
                 'report this as a bug?'], node.op));
    end
end
