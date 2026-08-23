function bin = parseBinStatement(stmt, script, aliases)
%PARSEBINSTATEMENT  bin <num> "<label>" [:] <expr> [rt within W] [timelock <rel>]
%   or   bin <num> "<label>" = <combination>
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
    [bin.expr, k] = DefineBinsEngine.parseExprTokens(rest, aliases);

    % Suffixes (either order): rt within <window>, timelock <relation>.
    while k <= numel(rest)
        t = rest(k);
        if t.kind == "kw" && t.val == "rt"
            [bin.rtWindow, k] = DefineBinsEngine.scanRtWindow(rest, k + 1, bin.index);
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
end
