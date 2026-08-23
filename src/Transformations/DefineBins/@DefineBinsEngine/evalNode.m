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
