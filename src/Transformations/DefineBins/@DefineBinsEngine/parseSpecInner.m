function spec = parseSpecInner(script)
%PARSESPECINNER  The actual parse (see parseSpec for the friendly-error wrapper).
    toks = DefineBinsEngine.tokenize(script);

    % Statements start at a 'let', an 'epoch', or a 'bin <num> "<label>"' (a
    % bare 'bin <num>' inside a combination, = bin 1 - bin 2, is not a
    % statement).
    isStart = false(1, numel(toks));
    for i = 1:numel(toks)
        if toks(i).kind ~= "kw"; continue; end
        if toks(i).val == "let" || toks(i).val == "epoch"
            isStart(i) = true;
        elseif toks(i).val == "bin"
            isStart(i) = (i + 2 <= numel(toks)) ...
                && toks(i+1).kind == "num" && toks(i+2).kind == "str";
        end
    end
    starts = find(isStart);
    if isempty(starts)
        DefineBinsEngine.throwParseError(-1, [ ...
            'I''m afraid I could not find a single bin definition in this script (only ' ...
            'comments and/or let aliases, if anything, from what I can see). Every ' ...
            'script needs at least one line shaped like:' newline newline ...
            '    bin <number> "<label>" <expression>' newline newline ...
            'for example:' newline newline ...
            '    bin 1 "Targets" 112']);
    end

    % NOTHING BEFORE THE FIRST STATEMENT. Tokens there used to be dropped
    % without a word, which is how "epoch [-200,800] ms" was silently ignored
    % before it was a statement: text a reader believes is doing something
    % must either do it or say that it does not.
    if starts(1) > 1
        DefineBinsEngine.throwParseError(toks(1).pos, [ ...
            'I''m afraid I don''t recognise this: a script is a series of statements, ' ...
            'each starting with bin, let or epoch, and this comes before the first ' ...
            'of them. Would you turn it into one of those, or into a comment by ' ...
            'starting the line with %?']);
    end

    stmts = cell(1, numel(starts));
    for s = 1:numel(starts)
        first = starts(s);
        if s < numel(starts); last = starts(s+1) - 1; else; last = numel(toks); end
        stmts{s} = toks(first:last);
    end

    % First pass: collect 'let' aliases, in file order, so a later alias may
    % reference any earlier one (a forward-reference or a cycle is an
    % "unknown name" error from the alias not existing yet).
    aliases = struct();
    for s = 1:numel(stmts)
        if stmts{s}(1).val == "let"
            [name, node] = DefineBinsEngine.parseLetStatement(stmts{s}, aliases);
            if isfield(aliases, name)
                DefineBinsEngine.throwParseError(stmts{s}(1).pos, sprintf([ ...
                    '''%s'' is already defined earlier in this script as a let alias, ' ...
                    'I''m afraid -- each alias name can only be defined once. Would you ' ...
                    'pick a different name for this one, or remove the earlier ' ...
                    'definition if it was a leftover?'], name));
            end
            aliases.(name) = node;
        end
    end

    % The epoch, when the script sets one (at most once).
    spec.epoch = [];
    for s = 1:numel(stmts)
        if stmts{s}(1).val == "epoch"
            if ~isempty(spec.epoch)
                DefineBinsEngine.throwParseError(stmts{s}(1).pos, [ ...
                    'This script sets the epoch twice, I''m afraid; every bin shares one ' ...
                    'epoch window. Would you keep just one epoch line?']);
            end
            spec.epoch = DefineBinsEngine.parseEpochStatement(stmts{s});
        end
    end

    % Second pass: the bins.
    bins = struct('index', {}, 'label', {}, 'text', {}, ...
                  'expr', {}, 'combo', {}, 'rtWindow', {}, 'timelock', {});
    for s = 1:numel(stmts)
        if stmts{s}(1).val == "bin"
            bin = DefineBinsEngine.parseBinStatement(stmts{s}, script, aliases);
            % ONE NUMBER, ONE BIN. A bin's number is how the tagged events, the
            % averages and a combination such as "bin 3 = bin 1 - bin 2" refer
            % to it, so two bins with the same number cannot be told apart.
            % They used to be accepted without a word.
            if any([bins.index] == bin.index)
                DefineBinsEngine.throwParseError(stmts{s}(1).pos, sprintf([ ...
                    'Bin %d is defined twice in this script, I''m afraid; each bin ' ...
                    'number can be used once. Would you give this one a number of its ' ...
                    'own?'], bin.index));
            end
            bins(end + 1) = bin; %#ok<AGROW>
        end
    end
    DefineBinsEngine.checkComboReferences(bins);
    spec.bins = bins;
end
