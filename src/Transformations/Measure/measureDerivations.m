function [EEG, added] = measureDerivations(EEG, text)
%MEASUREDERIVATIONS  Evaluate a block of "let" statements and append each as
%   a new derived channel on EEG.
%
%   TEXT is the Measure dialog's derived-channels field: one statement per
%   line,
%       let <name> = <expression>
%   for example
%       let LRP = C3 - C4
%       let RMSfront = sqrt((Fz*Fz + Cz*Cz) / 2)
%   Blank lines and everything after a '%' are ignored. <name> starts with a
%   letter (letters, digits, underscore and prime after it) and must not
%   clash with an existing channel. <expression> is a *restricted*,
%   elementwise grammar over channel labels (existing ones, and derived ones
%   defined on earlier lines):
%       + - * /        elementwise, with the usual precedence and parentheses
%       unary -        negation
%       abs( ) sqrt( ) elementwise functions
%       numbers        scalar literals, broadcast over the waveform
%   It is parsed and evaluated directly (a small recursive-descent parser,
%   see below), never eval-ed: a saved .alm / template is shared between
%   analysts and loaded from disk, so running its text as MATLAB would be a
%   code-injection hole. The restricted grammar also guarantees the result
%   is either a scalar or a single channel-shaped waveform, so a derivation
%   can never produce a wrongly-sized channel.
%
%   Each derivation is appended to EEG.data as a new row and to EEG.chanlocs
%   as a new entry with .type = 'derived' and no scalp coordinates (a
%   difference/derived channel has no place on the head, so ScalpDistribution
%   -- which keeps only channels that match a scalp-position template --
%   drops it automatically, while the ERP line plot and grand averages show
%   it like any other channel). ADDED is the cellstr of names created.
%
%   Idempotent: any channels already marked .type = 'derived' are stripped
%   first, so re-running Measure with an edited let block (Recalculate,
%   replay) replaces the derived channels rather than accumulating them.
%
%   A no-op (EEG unchanged, ADDED empty) when TEXT defines no statements.
%   Shared by Measure.m (a real averaged EEG) and MeasureDialog (a tiny dummy
%   EEG built from the dataset's chanlocs, purely to validate the block at
%   OK time), so the two can never disagree about what parses.
    added = {};
    derivs = parseLetLines(text);
    if isempty(derivs)
        return;
    end

    EEG = stripDerived(EEG);
    for i = 1:numel(derivs)
        name = derivs(i).name;
        if any(strcmpi({EEG.chanlocs.labels}, name))
            throw(MException('Alakazam:Measure', ['Derived channel "%s" clashes with a channel that ' ...
                'already exists in this dataset -- would you choose a different name?'], name));
        end
        ast = parseExpression(derivs(i).expr, name);
        value = evalNode(ast, @(nm) lookupChannel(EEG, nm, name));
        EEG = appendChannel(EEG, name, value);
        added{end + 1} = name; %#ok<AGROW>
    end
end

% ======================================================================= %
%  "let" line parsing
% ======================================================================= %
function derivs = parseLetLines(text)
%PARSELETLINES  Split TEXT into a struct array of .name / .expr, one per
%   non-blank "let" statement. Throws a friendly, line-numbered error on a
%   line that is not a well-formed "let <name> = <expression>".
    derivs = struct('name', {}, 'expr', {});
    if isempty(text)
        return;
    end
    lines = splitlines(string(text));
    for li = 1:numel(lines)
        raw = char(lines(li));
        cut = find(raw == '%', 1);          % a '%' starts a comment
        if ~isempty(cut)
            raw = raw(1:cut - 1);
        end
        ln = strtrim(raw);
        if isempty(ln)
            continue;
        end
        tok = regexp(ln, '^let\s+([A-Za-z][A-Za-z0-9_'']*)\s*=\s*(.+)$', ...
            'tokens', 'once', 'ignorecase');
        if isempty(tok)
            throw(MException('Alakazam:Measure', ['Derived-channel line %d doesn''t look quite right. Please write one ' ...
                '"let <name> = <expression>" per line, e.g. let LRP = C3 - C4.'], li));
        end
        derivs(end + 1) = struct('name', char(tok{1}), 'expr', strtrim(char(tok{2}))); %#ok<AGROW>
    end
end

% ======================================================================= %
%  Expression grammar (recursive descent)
% ======================================================================= %
%   expr   := term   (('+' | '-') term)*
%   term   := factor (('*' | '/') factor)*
%   factor := ('+' | '-')? factor  |  primary
%   primary:= number | channel | func '(' expr ')' | '(' expr ')'
function ast = parseExpression(expr, ctx)
%PARSEEXPRESSION  EXPR (the text right of '=') to an AST, CTX is the
%   derivation name for error messages.
    toks = lexExpression(expr, ctx);
    if isempty(toks)
        throw(MException('Alakazam:Measure', 'Derived channel "%s" seems to have an empty expression.', ctx));
    end
    [ast, k] = parseAddSub(toks, 1, ctx);
    if k <= numel(toks)
        throw(MException('Alakazam:Measure', 'Derived channel "%s": I wasn''t expecting to find "%s" in the expression.', ...
            ctx, toks(k).text));
    end
end

function [node, k] = parseAddSub(toks, k, ctx)
    [node, k] = parseMulDiv(toks, k, ctx);
    while k <= numel(toks) && strcmp(toks(k).kind, 'op') && any(toks(k).val == '+-')
        op = toks(k).val;
        [rhs, k] = parseMulDiv(toks, k + 1, ctx);
        node = struct('type', 'op', 'op', op, 'left', node, 'right', rhs);
    end
end

function [node, k] = parseMulDiv(toks, k, ctx)
    [node, k] = parseUnary(toks, k, ctx);
    while k <= numel(toks) && strcmp(toks(k).kind, 'op') && any(toks(k).val == '*/')
        op = toks(k).val;
        [rhs, k] = parseUnary(toks, k + 1, ctx);
        node = struct('type', 'op', 'op', op, 'left', node, 'right', rhs);
    end
end

function [node, k] = parseUnary(toks, k, ctx)
    if k <= numel(toks) && strcmp(toks(k).kind, 'op') && any(toks(k).val == '+-')
        op = toks(k).val;
        [child, k] = parseUnary(toks, k + 1, ctx);
        if op == '-'
            node = struct('type', 'neg', 'child', child);
        else
            node = child;   % unary plus is a no-op
        end
    else
        [node, k] = parsePrimary(toks, k, ctx);
    end
end

function [node, k] = parsePrimary(toks, k, ctx)
    if k > numel(toks)
        throw(MException('Alakazam:Measure', 'Derived channel "%s": the expression seems to end too early.', ctx));
    end
    t = toks(k);
    switch t.kind
        case 'num'
            node = struct('type', 'num', 'val', t.val);
            k = k + 1;
        case 'id'
            if k < numel(toks) && strcmp(toks(k + 1).kind, 'lpar')
                fn = lower(t.val);
                if ~ismember(fn, {'abs', 'sqrt'})
                    throw(MException('Alakazam:Measure', ['Derived channel "%s": I don''t recognise the function "%s". ' ...
                        'Only abs and sqrt are allowed here.'], ctx, t.val));
                end
                [arg, k] = parseAddSub(toks, k + 2, ctx);
                k = expectRParen(toks, k, ctx);
                node = struct('type', 'func', 'fn', fn, 'child', arg);
            else
                node = struct('type', 'chan', 'name', t.val);
                k = k + 1;
            end
        case 'lpar'
            [node, k] = parseAddSub(toks, k + 1, ctx);
            k = expectRParen(toks, k, ctx);
        otherwise
            throw(MException('Alakazam:Measure', 'Derived channel "%s": I wasn''t expecting "%s" there.', ctx, t.text));
    end
end

function k = expectRParen(toks, k, ctx)
    if k > numel(toks) || ~strcmp(toks(k).kind, 'rpar')
        throw(MException('Alakazam:Measure', 'Derived channel "%s": a "(" here is missing its closing ")".', ctx));
    end
    k = k + 1;
end

function toks = lexExpression(s, ctx)
%LEXEXPRESSION  S to a token array (kind = num/id/op/lpar/rpar). Rejects any
%   character outside the grammar, so nothing unexpected reaches the parser.
    toks = struct('kind', {}, 'val', {}, 'text', {});
    i = 1;
    n = numel(s);
    while i <= n
        c = s(i);
        if isspace(c)
            i = i + 1;
        elseif any(c == '+-*/')
            toks(end + 1) = token('op', c, c); %#ok<AGROW>
            i = i + 1;
        elseif c == '('
            toks(end + 1) = token('lpar', [], '('); %#ok<AGROW>
            i = i + 1;
        elseif c == ')'
            toks(end + 1) = token('rpar', [], ')'); %#ok<AGROW>
            i = i + 1;
        elseif isletter(c)
            j = i;
            while j <= n && (isletter(s(j)) || any(s(j) == '0123456789_'''))
                j = j + 1;
            end
            name = s(i:j - 1);
            toks(end + 1) = token('id', name, name); %#ok<AGROW>
            i = j;
        elseif any(c == '0123456789.')
            j = i;
            while j <= n && any(s(j) == '0123456789.')
                j = j + 1;
            end
            numText = s(i:j - 1);
            val = str2double(numText);
            if isnan(val)
                throw(MException('Alakazam:Measure', 'Derived channel "%s": "%s" doesn''t look like a valid number.', ctx, numText));
            end
            toks(end + 1) = token('num', val, numText); %#ok<AGROW>
            i = j;
        else
            throw(MException('Alakazam:Measure', 'Derived channel "%s": I''m afraid "%s" isn''t a character this expression grammar allows.', ctx, c));
        end
    end
end

function t = token(kind, val, text)
    t = struct('kind', kind, 'val', val, 'text', text);
end

% ======================================================================= %
%  Evaluation
% ======================================================================= %
function out = evalNode(node, getChan)
%EVALNODE  Evaluate an AST to a scalar or a channel-shaped waveform, using
%   GETCHAN(name) to fetch a channel's samples. Everything is elementwise, so
%   scalars broadcast over a waveform and the result stays channel-shaped.
    switch node.type
        case 'num'
            out = node.val;
        case 'chan'
            out = getChan(node.name);
        case 'neg'
            out = -evalNode(node.child, getChan);
        case 'func'
            v = evalNode(node.child, getChan);
            switch node.fn
                case 'abs';  out = abs(v);
                case 'sqrt'; out = sqrt(v);
            end
        case 'op'
            l = evalNode(node.left, getChan);
            r = evalNode(node.right, getChan);
            switch node.op
                case '+'; out = l + r;
                case '-'; out = l - r;
                case '*'; out = l .* r;
                case '/'; out = l ./ r;
            end
    end
end

function v = lookupChannel(EEG, nm, ctx)
%LOOKUPCHANNEL  The samples of channel NM (case-insensitive), or a friendly
%   error naming the derivation CTX that referred to a channel not present.
    idx = find(strcmpi({EEG.chanlocs.labels}, nm), 1);
    if isempty(idx)
        throw(MException('Alakazam:Measure', ['Derived channel "%s" refers to "%s", which I''m afraid is not a ' ...
            'channel in this dataset (nor a derived one defined on an earlier line).'], ctx, nm));
    end
    v = EEG.data(idx, :, :);
end

% ======================================================================= %
%  Channel bookkeeping
% ======================================================================= %
function EEG = appendChannel(EEG, name, value)
%APPENDCHANNEL  Add VALUE as a new last channel labelled NAME, marked
%   .type = 'derived' with no scalp position. Works for 2-D (channels x
%   samples) and 3-D (channels x samples x bins) EEG.data alike.
    cl = EEG.chanlocs;
    if ~isfield(cl, 'type')
        [cl.type] = deal('');   % keep the struct array's fields uniform
    end
    fields = fieldnames(cl);
    newChan = cell2struct(repmat({[]}, numel(fields), 1), fields, 1);
    newChan.labels = name;
    newChan.type   = 'derived';
    EEG.chanlocs = [cl, newChan];
    EEG.data(end + 1, :, :) = value;   % scalar VALUE broadcasts over the waveform
    EEG.nbchan = size(EEG.data, 1);
end

function EEG = stripDerived(EEG)
%STRIPDERIVED  Remove any channels a previous run marked .type = 'derived',
%   so re-running replaces rather than accumulates them.
    if ~isfield(EEG.chanlocs, 'type') || isempty(EEG.chanlocs)
        return;
    end
    isDerived = strcmpi({EEG.chanlocs.type}, 'derived');
    if ~any(isDerived)
        return;
    end
    EEG.chanlocs = EEG.chanlocs(~isDerived);
    EEG.data = EEG.data(~isDerived, :, :);
    EEG.nbchan = size(EEG.data, 1);
end
