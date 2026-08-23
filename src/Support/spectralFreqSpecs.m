function [hz, funds] = spectralFreqSpecs(exprList, fundamentalsText)
%SPECTRALFREQSPECS  Resolve a SpectralMeasure table's frequency column to Hz.
%
%   HZ = SPECTRALFREQSPECS(EXPRLIST, FUNDAMENTALSTEXT) evaluates each frequency
%   expression in the cellstr EXPRLIST to a number, using the named
%   fundamentals declared in FUNDAMENTALSTEXT. Fundamentals are one "let" per
%   line, e.g.
%       let f1 = 63
%       let f2 = 70
%   and a frequency expression is any elementwise arithmetic over them (and
%   plain numbers): f1, 2*f1, f1+f2, 2*f1-f2, (f1+f2)/2, ... -- so harmonics
%   and intermodulation terms are written directly. A later fundamental may
%   use an earlier one.
%
%   The grammar is deliberately small and is parsed, never eval-ed (the same
%   safety stance as measureDerivations.m, since these definitions live in
%   shared preset files): names, numbers, + - * /, parentheses and unary
%   minus. Names are matched case-insensitively. A name that is not a declared
%   fundamental, a syntax error, or a non-finite result throws a friendly,
%   context-named error. FUNDS is returned as a containers.Map (name -> value)
%   for callers that want the fundamentals themselves.
%
%   Shared by SpectralMeasure.m (to compute) and SpectralMeasureDialog.m (to
%   validate at OK time), so the two can never disagree about what parses.
    funds = parseFundamentals(fundamentalsText);
    if isempty(exprList)
        hz = [];
        return;
    end
    exprList = cellstr(exprList);
    hz = zeros(1, numel(exprList));
    for i = 1:numel(exprList)
        expr = strtrim(exprList{i});
        ctx = sprintf('frequency "%s"', expr);
        ast = parseExpression(expr, ctx);
        v = evalNode(ast, funds, ctx);
        if ~isfinite(v)
            error('Alakazam:SpectralMeasure', 'I''m afraid the %s did not evaluate to a finite number.', ctx);
        end
        hz(i) = v;
    end
end

function funds = parseFundamentals(text)
%PARSEFUNDAMENTALS  A "let name = expr" block to a name->value map, each line
%   evaluated over the ones before it. Blank lines and text after '%' ignored.
    funds = containers.Map('KeyType', 'char', 'ValueType', 'double');
    if isempty(text)
        return;
    end
    lines = splitlines(string(text));
    for li = 1:numel(lines)
        raw = char(lines(li));
        cut = find(raw == '%', 1);
        if ~isempty(cut); raw = raw(1:cut - 1); end
        ln = strtrim(raw);
        if isempty(ln); continue; end
        tok = regexp(ln, '^let\s+([A-Za-z]\w*)\s*=\s*(.+)$', 'tokens', 'once', 'ignorecase');
        if isempty(tok)
            error('Alakazam:SpectralMeasure', ['Fundamentals line %d doesn''t look valid, I''m afraid. ' ...
                'Would you write one "let <name> = <value>" per line, e.g. let f1 = 63?'], li);
        end
        name = char(tok{1});
        ctx = sprintf('fundamental "%s"', name);
        ast = parseExpression(strtrim(char(tok{2})), ctx);
        v = evalNode(ast, funds, ctx);
        if ~isfinite(v)
            error('Alakazam:SpectralMeasure', 'I''m afraid the %s did not evaluate to a finite number.', ctx);
        end
        funds(lower(name)) = v;
    end
end

% ======================================================================= %
%  Expression grammar (recursive descent): expr -> term (+/-), term ->
%  factor (*/), factor -> (+/-)? primary, primary -> number | name | (expr)
% ======================================================================= %
function ast = parseExpression(expr, ctx)
    toks = lexExpression(expr, ctx);
    if isempty(toks)
        error('Alakazam:SpectralMeasure', 'Unfortunately, the %s is empty.', ctx);
    end
    [ast, k] = parseAddSub(toks, 1, ctx);
    if k <= numel(toks)
        error('Alakazam:SpectralMeasure', 'The %s has an unexpected "%s", I''m afraid.', ctx, toks(k).text);
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
            node = child;
        end
    else
        [node, k] = parsePrimary(toks, k, ctx);
    end
end

function [node, k] = parsePrimary(toks, k, ctx)
    if k > numel(toks)
        error('Alakazam:SpectralMeasure', 'Unfortunately, the %s ends too early.', ctx);
    end
    t = toks(k);
    switch t.kind
        case 'num'
            node = struct('type', 'num', 'val', t.val); k = k + 1;
        case 'id'
            node = struct('type', 'name', 'name', t.val); k = k + 1;
        case 'lpar'
            [node, k] = parseAddSub(toks, k + 1, ctx);
            if k > numel(toks) || ~strcmp(toks(k).kind, 'rpar')
                error('Alakazam:SpectralMeasure', 'I''m afraid the %s has a "(" with no matching ")".', ctx);
            end
            k = k + 1;
        otherwise
            error('Alakazam:SpectralMeasure', 'The %s has an unexpected "%s", I''m afraid.', ctx, t.text);
    end
end

function toks = lexExpression(s, ctx)
    toks = struct('kind', {}, 'val', {}, 'text', {});
    i = 1; n = numel(s);
    while i <= n
        c = s(i);
        if isspace(c)
            i = i + 1;
        elseif any(c == '+-*/')
            toks(end + 1) = tok('op', c, c); i = i + 1; %#ok<AGROW>
        elseif c == '('
            toks(end + 1) = tok('lpar', [], '('); i = i + 1; %#ok<AGROW>
        elseif c == ')'
            toks(end + 1) = tok('rpar', [], ')'); i = i + 1; %#ok<AGROW>
        elseif isletter(c)
            j = i;
            while j <= n && (isletter(s(j)) || any(s(j) == '0123456789_')); j = j + 1; end
            toks(end + 1) = tok('id', s(i:j - 1), s(i:j - 1)); i = j; %#ok<AGROW>
        elseif any(c == '0123456789.')
            j = i;
            while j <= n && any(s(j) == '0123456789.'); j = j + 1; end
            txt = s(i:j - 1);
            v = str2double(txt);
            if isnan(v)
                error('Alakazam:SpectralMeasure', 'I''m sorry, but the %s has "%s", which is not a number.', ctx, txt);
            end
            toks(end + 1) = tok('num', v, txt); i = j; %#ok<AGROW>
        else
            error('Alakazam:SpectralMeasure', 'I''m sorry, but the %s has an unexpected character "%s".', ctx, c);
        end
    end
end

function t = tok(kind, val, text)
    t = struct('kind', kind, 'val', val, 'text', text);
end

function out = evalNode(node, funds, ctx)
    switch node.type
        case 'num'
            out = node.val;
        case 'name'
            key = lower(node.name);
            if ~isKey(funds, key)
                error('Alakazam:SpectralMeasure', ['The %s refers to "%s", which isn''t a declared ' ...
                    'fundamental, I''m afraid. Would you add it, e.g. let %s = 63?'], ctx, node.name, node.name);
            end
            out = funds(key);
        case 'neg'
            out = -evalNode(node.child, funds, ctx);
        case 'op'
            l = evalNode(node.left, funds, ctx);
            r = evalNode(node.right, funds, ctx);
            switch node.op
                case '+'; out = l + r;
                case '-'; out = l - r;
                case '*'; out = l * r;
                case '/'; out = l / r;
            end
    end
end
