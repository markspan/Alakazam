function [node, k] = parseExprTokens(T, aliases)
%PARSEEXPRTOKENS  Recursive-descent expression parser over a token subarray.
%   Returns the parsed node and the cursor after it; the caller handles any
%   trailing tokens (bin suffixes such as rt/timelock, or its own error).
%
%   The parser's own precedence levels (pOr/pAnd/pNot/pPrimary/pRelation/
%   pCodeset/pInterval) are kept as nested functions, deliberately not split
%   into one-per-file like this class's other methods: they share a single
%   mutable token cursor (k) by closure, and only make sense as one
%   recursive-descent unit -- separating them would mean threading k
%   explicitly through every call instead, a bigger rewrite of working
%   parser internals for no readability gain.
    k = 1;
    node = pOr();

    function nd = pOr()
        kids = {pAnd()};
        while isKw('or'); advance(); kids{end+1} = pAnd(); end
        if numel(kids) == 1; nd = kids{1};
        else; nd.op = 'or'; nd.kids = kids; end
    end

    function nd = pAnd()
        % 'and' is explicit or implied: two adjacent terms are and-ed, so
        % `"s??" not {…}` means `"s??" and not {…}`.
        kids = {pNot()};
        while isKw('and') || startsTerm()
            if isKw('and'); advance(); end
            kids{end+1} = pNot();
        end
        if numel(kids) == 1; nd = kids{1};
        else; nd.op = 'and'; nd.kids = kids; end
    end

    function tf = startsTerm()
        t = cur();
        tf = (t.kind == "num") || (t.kind == "str") || (t.kind == "ident") ...
            || (t.kind == "kw" && any(t.val == ...
                    ["not","next","prev","adjacent","any"])) ...
            || (t.kind == "punc" && (t.val == "(" || t.val == "{"));
    end

    function nd = pNot()
        if isKw('not')
            advance();
            nd.op = 'not'; nd.kid = pNot();
        else
            nd = pPrimary();
        end
    end

    function nd = pPrimary()
        if isPunc('(')
            advance(); nd = pOr(); expectPunc(')');
        elseif isKw('next') || isKw('prev') || isKw('adjacent') || isKw('any')
            nd = pRelation();
        elseif isFieldTest()
            nd = pField();
        else
            nd = pCodeset();   % already a fully-formed anchor/not/and/or node
        end
    end

    function nd = pRelation()
        quant = char(cur().val); advance();
        expectPunc('(');
        matcher = pCodeset();
        expectPunc(')');
        iv = [];
        if isKw('within'); advance(); iv = pInterval(); end
        if strcmp(quant, 'any') && isempty(iv)
            DefineBinsEngine.throwParseError(curCol(), [ ...
                'any(code) always needs a ''within (lo,hi] ms'' window right after it, ' ...
                'I''m afraid -- unlike next/prev/adjacent, "any" has no natural neighbour ' ...
                'to fall back on, so there is no sensible default window to search. ' ...
                'For example: any(200) within (-500,500] ms.']);
        end
        nd.op = 'rel'; nd.quant = quant; nd.matcher = matcher; nd.interval = iv;
    end

    function tf = isFieldTest()
    %ISFIELDTEST  Whether the cursor is at 'field <name> within <window>'.
    %   'field' is read as a plain word rather than a keyword, so that a
    %   script with an alias of that name keeps meaning what it meant: the
    %   alias wins wherever one is defined.
        t = cur();
        tf = t.kind == "ident" && strcmpi(t.val, "field") && ~isfield(aliases, char(t.val));
    end

    function nd = pField()
    %PFIELD  field <name> within <window>: true when the candidate event's
    %   own numeric field NAME lies in the window, such as the interbeat
    %   interval the Heartbeats plugin gives every beat:
    %       "heartbeat" and field ibi within (800,1200]
    %   The window carries no unit: the field is compared in whatever unit
    %   it holds (ms for ibi, beats a minute for hr).
        advance();
        nameTok = cur();
        if nameTok.kind ~= "ident"
            DefineBinsEngine.throwParseError(curCol(), [ ...
                '''field'' needs the name of an event field after it, I''m afraid, ' ...
                'for example field ibi within (800,1200] for the interbeat interval ' ...
                'the Heartbeats plugin gives every beat.']);
        end
        name = char(nameTok.val);
        advance();
        if ~isKw('within')
            DefineBinsEngine.throwParseError(curCol(), sprintf([ ...
                'field %s needs a window after it to say which values to keep, ' ...
                'I''m afraid, for example field %s within (800,1200].'], name, name));
        end
        advance();
        [iv, k] = DefineBinsEngine.scanInterval(T, k);

        % scanInterval reads an optional unit and defaults to ms, so whether
        % one was written is told by the token just read. A unit would
        % suggest a conversion that never happens: the value is compared as
        % the event holds it.
        last = T(k - 1);
        if last.kind == "kw" && any(last.val == ["ms", "samples", "events"])
            DefineBinsEngine.throwParseError(last.pos, sprintf([ ...
                'field %s is compared in the unit the event holds it in, so its ' ...
                'window takes no unit, I''m afraid: field %s within (800,1200] ' ...
                'rather than ... %s.'], name, name, char(last.val)));
        end
        iv.unit = '';
        nd.op = 'field'; nd.name = name; nd.interval = iv;
    end

    function node = pCodeset()
        [node, k] = DefineBinsEngine.scanCodeset(T, k, aliases);   % shared scanner; advances k
    end

    function iv = pInterval()
        [iv, k] = DefineBinsEngine.scanInterval(T, k);   % shared scanner; advances the cursor
    end

    % --- token cursor helpers ---
    function t = cur()
        if k <= numel(T); t = T(k);
        else; t = struct('kind', "eof", 'val', "", 'pos', -1, 'len', 0); end
    end
    function c = curCol(); c = cur().pos; end
    function advance(); k = k + 1; end
    function tf = isKw(w);   t = cur(); tf = t.kind == "kw"   && t.val == w; end
    function tf = isPunc(w); t = cur(); tf = t.kind == "punc" && t.val == w; end
    function expectPunc(w)
        if ~isPunc(w)
            DefineBinsEngine.throwParseError(curCol(), sprintf('I was hoping for a ''%s'' right about here.', w));
        end
        advance();
    end
end
