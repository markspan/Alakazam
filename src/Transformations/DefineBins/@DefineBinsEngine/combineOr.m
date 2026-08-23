function node = combineOr(kids)
%COMBINEOR  OR together codeset terms, merging adjacent literal ('anchor')
%   nodes into one flat code list. A plain pipe/brace list of literals (and/or
%   aliases that are themselves plain code lists) therefore still collapses to
%   a single 'anchor' node, exactly as before; only a compound alias (one
%   built with not/and/or) produces a richer tree.
    merged = {};
    litAcc = strings(1, 0);
    for i = 1:numel(kids)
        kid = kids{i};
        if strcmp(kid.op, 'anchor')
            litAcc = [litAcc, kid.codes];
        else
            if ~isempty(litAcc)
                merged{end + 1} = DefineBinsEngine.anchorNode(litAcc); %#ok<AGROW>
                litAcc = strings(1, 0);
            end
            merged{end + 1} = kid; %#ok<AGROW>
        end
    end
    if ~isempty(litAcc)
        merged{end + 1} = DefineBinsEngine.anchorNode(litAcc); %#ok<AGROW>
    end
    if numel(merged) == 1
        node = merged{1};
    else
        node.op = 'or'; node.kids = merged;
    end
end
