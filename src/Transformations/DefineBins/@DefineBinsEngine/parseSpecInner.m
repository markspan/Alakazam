function spec = parseSpecInner(script)
%PARSESPECINNER  The actual parse (see parseSpec for the friendly-error wrapper).
    toks = DefineBinsEngine.tokenize(script);

    % Statements start at a 'let', or at a 'bin <num> "<label>"' (a bare
    % 'bin <num>' inside a combination, = bin 1 - bin 2, is not a statement).
    isStart = false(1, numel(toks));
    for i = 1:numel(toks)
        if toks(i).kind ~= "kw"; continue; end
        if toks(i).val == "let"
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

    % Second pass: the bins.
    bins = struct('index', {}, 'label', {}, 'text', {}, ...
                  'expr', {}, 'combo', {}, 'rtWindow', {}, 'timelock', {});
    for s = 1:numel(stmts)
        if stmts{s}(1).val == "bin"
            bins(end + 1) = DefineBinsEngine.parseBinStatement(stmts{s}, script, aliases); %#ok<AGROW>
        end
    end
    DefineBinsEngine.checkComboReferences(bins);
    spec.bins = bins;
end
