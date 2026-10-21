function [test, k] = scanValueTest(T, k)
%SCANVALUETEST  '<value> within <window>': a test of a number every trial
%   has, read from the token list T at cursor K.
%
%   THE VALUE is one of
%       rt                 the bin's reaction time, in ms
%       field <name>       a number the event carries (ibi, hr, ...)
%       log(<value>)       its natural logarithm (0 or less has none)
%       rank(<value>)      its percentile rank among the bin's trials, 0-100
%   where the <value> inside log or rank is rt or field <name>.
%
%   EACH BOUND of the window is a number, inf (or -inf), or a statistic of
%   the values of the bin's trials, mean, median or a percentile (p25, p75,
%   any whole number from p0 to p100), optionally plus or minus a number of
%   sd, iqr or mad:
%       rt within (200, 500] ms
%       rt within (0, median] ms                       a median split
%       rt within [p25 - 1.5 iqr, p75 + 1.5 iqr] ms    Tukey's fences
%       log(rt) within [mean - 2.5 sd, mean + 2.5 sd]
%       rank(field ibi) within (50, 100]
%   A reaction-time window is in milliseconds (ms may be written); every
%   other window takes no unit: a field is compared in the unit the event
%   holds it in, and a logarithm and a rank have none.
%
%   TEST has source ('rt' or 'field'), name (the field's), transform
%   ('none', 'log' or 'rank'), window (lo and hi bounds, loOpen, hiOpen),
%   text (the test written out, for the summary) and pos (where it starts,
%   for messages). A bound is struct(kind, value, stat, pct, k, spread):
%   kind 'num' (value), 'inf' (value -1 or 1, its sign) or 'stat' (stat
%   'mean', 'median' or 'p' with pct, plus k times spread 'sd', 'iqr' or
%   'mad'; k 0 and spread '' for none). No bound is stored as NaN or Inf.
%
%   'log', 'rank', 'field', the statistics and the spreads are plain words,
%   not keywords: an alias of any of those names keeps working, and the
%   caller decides (DefineBinsEngine.isValueStart) where a value test begins.
%
%   See also DEFINEBINSENGINE.RESOLVEVALUEWINDOW, DEFINEBINSENGINE.SPLITFILTERS.
    first = DefineBinsEngine.tokAt(T, k);
    test = struct('source', '', 'name', '', 'transform', 'none', 'window', [], ...
        'text', '', 'pos', first.pos);
    [test, k] = scanValue(T, k, test, true);
    what = valueText(test);

    t = DefineBinsEngine.tokAt(T, k);
    if ~(t.kind == "kw" && t.val == "within")
        DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
            '%s needs a window after it to say which values to keep, I''m afraid, ' ...
            'for example %s within %s.'], what, what, example(test)));
    end
    [test.window, k, unitTok] = scanWindow(T, k + 1);
    checkUnit(test, unitTok, what);
    checkOrder(test.window, first.pos);
    test.text = DefineBinsEngine.describeTest(test);
end

% ======================================================================= %
function [test, k] = scanValue(T, k, test, outer)
%SCANVALUE  rt, field <name>, or log(...) / rank(...) around one of those.
    t = DefineBinsEngine.tokAt(T, k);
    if t.kind == "kw" && t.val == "rt"
        test.source = 'rt';
        k = k + 1;
    elseif isWord(t, "field")
        k = k + 1;
        nameTok = DefineBinsEngine.tokAt(T, k);
        if nameTok.kind ~= "ident"
            DefineBinsEngine.throwParseError(nameTok.pos, [ ...
                '''field'' needs the name of an event field after it, I''m afraid, ' ...
                'for example field ibi within (800,1200] for the interbeat interval ' ...
                'the Heartbeats plugin gives every beat.']);
        end
        test.source = 'field';
        test.name = char(nameTok.val);
        k = k + 1;
    elseif (isWord(t, "log") || isWord(t, "rank")) && isPunc(DefineBinsEngine.tokAt(T, k + 1), "(")
        if ~outer
            DefineBinsEngine.throwParseError(t.pos, [ ...
                'log and rank take rt or field <name> inside, not another log or ' ...
                'rank, I''m afraid: the rank of a logarithm is the rank itself, so ' ...
                'rank(rt) says all that rank(log(rt)) would.']);
        end
        test.transform = lower(char(t.val));
        [test, k] = scanValue(T, k + 2, test, false);
        c = DefineBinsEngine.tokAt(T, k);
        if ~isPunc(c, ")")
            DefineBinsEngine.throwParseError(c.pos, sprintf( ...
                'I was hoping for a '')'' to close %s(...) right about here.', test.transform));
        end
        k = k + 1;
    else
        DefineBinsEngine.throwParseError(t.pos, [ ...
            'log(...) and rank(...) take rt or field <name> inside, for example ' ...
            'log(rt) or rank(field ibi) -- I''m afraid I could not read this as either.']);
    end
end

function [win, k, unitTok] = scanWindow(T, k)
%SCANWINDOW  (lo, hi] with ( or [ and ) or ], each bound read by
%   scanBound, and an optional unit after it (UNITTOK, or [] for none).
    o = DefineBinsEngine.tokAt(T, k);
    if ~(isPunc(o, "(") || isPunc(o, "["))
        DefineBinsEngine.throwParseError(o.pos, [ ...
            'A window needs to start with ''('' (exclusive bound) or ''['' (inclusive ' ...
            'bound), like within (200,1200] -- I wasn''t able to find either one here.']);
    end
    [lo, k] = scanBound(T, k + 1);
    c = DefineBinsEngine.tokAt(T, k);
    if ~isPunc(c, ",")
        DefineBinsEngine.throwParseError(c.pos, [ ...
            'A window needs a comma between its low and high bound, for example ' ...
            'rt within (150, mean + 2.5 sd] ms -- I''m afraid I found the low bound, ' ...
            'but no comma after it.']);
    end
    [hi, k] = scanBound(T, k + 1);
    c = DefineBinsEngine.tokAt(T, k);
    if ~(isPunc(c, ")") || isPunc(c, "]"))
        DefineBinsEngine.throwParseError(c.pos, [ ...
            'A window needs to end with '')'' (exclusive bound) or '']'' (inclusive ' ...
            'bound), like within (200,1200] -- I couldn''t find either one here, ' ...
            'I''m afraid.']);
    end
    win = struct('lo', lo, 'hi', hi, 'loOpen', o.val == "(", 'hiOpen', c.val == ")");
    k = k + 1;
    unitTok = [];
    u = DefineBinsEngine.tokAt(T, k);
    if u.kind == "kw" && any(u.val == ["ms", "samples", "events"])
        unitTok = u;
        k = k + 1;
    end
end

function [bound, k] = scanBound(T, k)
%SCANBOUND  A number, inf or -inf, or mean / median / pNN, optionally
%   (+|-) <num> sd / iqr / mad.
    t = DefineBinsEngine.tokAt(T, k);
    bound = struct('kind', 'num', 'value', 0, 'stat', '', 'pct', 0, 'k', 0, 'spread', '');

    % inf, and -inf or +inf (the sign is a token of its own before a word)
    if isWord(t, "inf")
        bound.kind = 'inf';
        bound.value = 1;
        k = k + 1;
        return;
    end
    if (isPunc(t, "-") || isPunc(t, "+")) && isWord(DefineBinsEngine.tokAt(T, k + 1), "inf")
        bound.kind = 'inf';
        bound.value = 1 - 2 * (t.val == "-");
        k = k + 2;
        return;
    end

    if t.kind == "num"
        % A number directly followed by a spread is a relative bound with
        % its centre left out; saying so beats a puzzling "expected a comma".
        next = DefineBinsEngine.tokAt(T, k + 1);
        if isSpread(next)
            DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
                'A bound in %s is measured from a centre, so it needs the word ' ...
                'mean, median or a percentile in front of it, I''m afraid: ' ...
                'mean + %g %s rather than %g %s.'], lower(char(next.val)), abs(t.val), ...
                lower(char(next.val)), t.val, lower(char(next.val))));
        end
        bound.value = t.val;
        k = k + 1;
        return;
    end

    [stat, pct] = centreOf(t);
    if isempty(stat)
        DefineBinsEngine.throwParseError(t.pos, [ ...
            'Each bound of a window is a number, inf, or a statistic of the bin''s ' ...
            'trials: mean, median or a percentile such as p75, optionally with + or - ' ...
            'a number of sd, iqr or mad, for example (150, mean + 2.5 sd] -- I''m ' ...
            'afraid I could not read this one as any of those.']);
    end
    bound.kind = 'stat';
    bound.stat = stat;
    bound.pct = pct;
    centre = char(t.val);
    k = k + 1;

    % The centre on its own: nothing more to read.
    s = DefineBinsEngine.tokAt(T, k);
    if isPunc(s, ",") || isPunc(s, ")") || isPunc(s, "]")
        return;
    end

    % The sign: an explicit + or -, or (since the tokenizer reads "-2.5" as
    % one negative number) a number that carries its own minus.
    if isPunc(s, "+") || isPunc(s, "-")
        direction = 1 - 2 * (s.val == "-");
        n = DefineBinsEngine.tokAt(T, k + 1);
        if n.kind ~= "num"
            DefineBinsEngine.throwParseError(n.pos, sprintf([ ...
                'After %s %s I was hoping to find a number of sd, iqr or mad, for ' ...
                'example %s %s 2.5 sd, but did not, I''m afraid.'], centre, s.val, centre, s.val));
        end
        multiplier = direction * n.val;
        k = k + 2;
    elseif s.kind == "num" && s.val < 0
        n = s;
        multiplier = s.val;
        k = k + 1;
    else
        DefineBinsEngine.throwParseError(s.pos, sprintf([ ...
            'After %s I expected + or - and a number of sd, iqr or mad, for example ' ...
            '%s + 2.5 sd, or the end of the bound, I''m afraid.'], centre, centre));
    end

    w = DefineBinsEngine.tokAt(T, k);
    if ~isSpread(w)
        DefineBinsEngine.throwParseError(n.pos + n.len, sprintf([ ...
            'A number added to the %s needs the word sd, iqr or mad after it, so it ' ...
            'is clear what it counts: %s + %g sd. A fixed number belongs in a bound ' ...
            'of its own, I''m afraid.'], centre, centre, abs(multiplier)));
    end
    bound.k = multiplier;
    bound.spread = lower(char(w.val));
    k = k + 1;
end

function [stat, pct] = centreOf(t)
%CENTREOF  The statistic token T names: 'mean', 'median' or 'p' with its
%   percentage; '' when it names none.
    stat = '';
    pct = 0;
    if isWord(t, "mean") || isWord(t, "median")
        stat = lower(char(t.val));
        return;
    end
    if t.kind == "ident"
        digits = regexp(char(t.val), '^[pP](\d+)$', 'tokens', 'once');
        if ~isempty(digits) && str2double(digits{1}) <= 100
            stat = 'p';
            pct = str2double(digits{1});
        end
    end
end

function checkUnit(test, unitTok, what)
%CHECKUNIT  A reaction time is in milliseconds; nothing else has a unit.
    if isempty(unitTok)
        return;
    end
    unit = char(unitTok.val);
    if strcmp(test.source, 'rt') && strcmp(test.transform, 'none')
        if ~strcmp(unit, 'ms')
            DefineBinsEngine.throwParseError(unitTok.pos, sprintf([ ...
                'A reaction time is a duration, so ''rt within'' is measured in ' ...
                'milliseconds -- ''%s'' is not a unit it can use. Would you write it ' ...
                'as rt within (200,500] ms? (''samples'' and ''events'' do work on an ' ...
                'ordinary within-window, just not on this one.)'], unit));
        end
        return;
    end
    if strcmp(test.transform, 'none')
        DefineBinsEngine.throwParseError(unitTok.pos, sprintf([ ...
            'field %s is compared in the unit the event holds it in, so its window ' ...
            'takes no unit, I''m afraid: field %s within (800,1200] rather than ... %s.'], ...
            test.name, test.name, unit));
    end
    kind = 'percentile rank';
    if strcmp(test.transform, 'log')
        kind = 'logarithm';
    end
    DefineBinsEngine.throwParseError(unitTok.pos, sprintf([ ...
        '%s is a plain number (a %s), so its window takes no unit, I''m afraid: ' ...
        '%s within %s rather than ... %s.'], what, kind, what, example(test), unit));
end

function checkOrder(win, pos)
%CHECKORDER  A window no value could ever fall inside, when that shows
%   already: two numbers the wrong way round, an infinite bound on the wrong
%   side, or two bounds from the same statistic and spread the wrong way
%   round. Other mixtures depend on the data, and resolveValueWindow says
%   so when it happens.
    lo = win.lo;
    hi = win.hi;
    if strcmp(lo.kind, 'num') && strcmp(hi.kind, 'num') && lo.value > hi.value
        DefineBinsEngine.throwParseError(pos, sprintf([ ...
            'This window''s low bound (%g) is greater than its high bound (%g), ' ...
            'I''m afraid, so no trial could ever fall inside it. Did you perhaps ' ...
            'mean (%g,%g]?'], lo.value, hi.value, hi.value, lo.value));
    end
    if (strcmp(lo.kind, 'inf') && lo.value > 0) || (strcmp(hi.kind, 'inf') && hi.value < 0)
        DefineBinsEngine.throwParseError(pos, [ ...
            'This window runs from inf down, or up to -inf, I''m afraid, so no trial ' ...
            'could ever fall inside it: -inf belongs at the low end and inf at the high end.']);
    end
    if strcmp(lo.kind, 'stat') && strcmp(hi.kind, 'stat') && strcmp(lo.stat, hi.stat) ...
            && lo.pct == hi.pct && (strcmp(lo.spread, hi.spread) || lo.k == 0 || hi.k == 0) ...
            && lo.k > hi.k
        DefineBinsEngine.throwParseError(pos, sprintf([ ...
            'This window''s low bound (%s) lies above its high bound (%s), I''m afraid, ' ...
            'so no trial could ever fall inside it. Did you perhaps mean the two the ' ...
            'other way round?'], DefineBinsEngine.describeTest(lo), ...
            DefineBinsEngine.describeTest(hi)));
    end
end

function text = valueText(test)
%VALUETEXT  The value as written: rt, field ibi, log(rt), rank(field ibi).
    if strcmp(test.source, 'rt')
        text = 'rt';
    else
        text = ['field ' test.name];
    end
    if ~strcmp(test.transform, 'none')
        text = sprintf('%s(%s)', test.transform, text);
    end
end

function text = example(test)
%EXAMPLE  A window that suits the value, for the messages.
    if strcmp(test.transform, 'rank')
        text = '[0, 50]';
    elseif strcmp(test.transform, 'log')
        text = '[mean - 2.5 sd, mean + 2.5 sd]';
    elseif strcmp(test.source, 'rt')
        text = '(200, 500] ms';
    else
        text = '(800, 1200]';
    end
end

function tf = isWord(t, word)
%ISWORD  Whether token T is the plain word WORD, in any case.
    tf = t.kind == "ident" && strcmpi(t.val, word);
end

function tf = isPunc(t, p)
    tf = t.kind == "punc" && t.val == p;
end

function tf = isSpread(t)
    tf = isWord(t, "sd") || isWord(t, "iqr") || isWord(t, "mad");
end
