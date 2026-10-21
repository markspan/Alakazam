function bin = parseBinStatement(stmt, script, aliases)
%PARSEBINSTATEMENT  bin <num> "<label>" [:] <expr> [timelock <rel>] [<value tests>]
%   or   bin <num> "<label>" = <combination>
%
%   The tests about the bin's trials as a whole (reaction times, ranks,
%   bounds from the trials' statistics; see isFilterTest) are taken out of
%   the expression by splitFilters. A plain 'rt within' window of numbers
%   or mean +- k sd goes where it always has, in bin.rtWindow (rtWindowOf),
%   so such a plan is what it was; any other such test goes in bin.filters,
%   which evaluateBins applies after it.
    [~,     rest] = DefineBinsEngine.expectTok(stmt, "kw", "bin", 'the keyword ''bin''');
    [idx,   rest] = DefineBinsEngine.expectTok(rest, "num", 'a bin number after ''bin''');
    [label, rest] = DefineBinsEngine.expectTok(rest, "str", 'a quoted label');

    bin.index    = round(idx.val);
    bin.label    = char(label.val);
    bin.text     = char(strtrim(DefineBinsEngine.sliceSource(script, rest)));
    bin.expr     = [];
    bin.combo    = [];
    bin.rtWindow = [];
    bin.timelock = [];
    bin.filters  = [];

    % A '=' after the label makes this a combination (difference) bin, defined
    % from earlier bins' averages rather than by an event predicate.
    if ~isempty(rest) && rest(1).kind == "punc" && rest(1).val == "="
        bin.combo = DefineBinsEngine.parseCombo(rest(2:end), bin.index, bin.label);
        return;
    end

    % Otherwise an optional ':' then a predicate, with optional suffixes.
    if ~isempty(rest) && rest(1).kind == "punc" && rest(1).val == ":"
        rest = rest(2:end);
    end
    if isempty(rest)
        DefineBinsEngine.throwParseError(label.pos + label.len, sprintf([ ...
            'bin %g "%s" has a label but nothing after it, I''m afraid -- I still need an ' ...
            'expression saying which events belong to this bin, for example bin %g "%s" ' ...
            '112, or bin %g "%s" 112 and next(118) within (200,1200] ms.'], ...
            idx.val, label.val, idx.val, label.val, idx.val, label.val));
    end
    [expr, k] = DefineBinsEngine.parseExprTokens(rest, aliases);

    % Suffixes, in any order: timelock <relation>, and value tests (rt within
    % <window> and the like), which are and-ed to the expression as if
    % written in it; the expression itself stops at 'timelock'.
    while k <= numel(rest)
        t = rest(k);
        if DefineBinsEngine.isValueStart(rest, k, aliases)
            [test, k] = DefineBinsEngine.scanValueTest(rest, k);
            expr = struct('op', 'and', 'kids', {{expr, DefineBinsEngine.valueNode(test)}});
        elseif t.kind == "kw" && t.val == "timelock"
            [bin.timelock, k] = DefineBinsEngine.parseTimelock(rest, k + 1, aliases, bin.index);
        else
            DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
                'bin %g "%s": I''ve read the whole expression, but there is a little ' ...
                'more text after it that I do not recognise as ''rt within ...'' or ' ...
                '''timelock ...''. Perhaps you meant to combine two conditions? Adjacent ' ...
                'terms are automatically and-ed (e.g. 112 next(118)), or you can join ' ...
                'them explicitly with and/or.'], idx.val, label.val));
        end
    end

    [bin.expr, tests] = DefineBinsEngine.splitFilters(expr);
    for i = 1:numel(tests)
        iv = DefineBinsEngine.rtWindowOf(tests(i));
        if ~isempty(iv) && isempty(bin.rtWindow)
            bin.rtWindow = iv;
        elseif isempty(bin.filters)
            bin.filters = tests(i);
        else
            bin.filters(end + 1) = tests(i);
        end
    end
end
