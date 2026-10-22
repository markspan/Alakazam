function [EEG, added, replaced, removed] = ApplyDerivations(EEG, text)
%APPLYDERIVATIONS  Evaluate a block of "let" statements: each adds a
%   derived channel to EEG, overwrites a channel it already has, or removes
%   one.
%
%   TEXT is the Measure dialog's derived-channels field: one statement per
%   line,
%       let <name> = <expression>
%       let <name> = []
%   for example
%       let LRP = C3 - C4
%       let RMSfront = sqrt((Fz*Fz + Cz*Cz) / 2)
%       let ECG = -ECG          (overwrites ECG)
%       let ECG2 = []           (removes ECG2)
%   Blank lines and everything after a '%' are ignored. <name> starts with a
%   letter (letters, digits, underscore and prime after it), or is any label
%   in double quotes ("53", "EOG-R"). The lines run in order, each on the
%   channels as the lines above left them. <expression> is a *restricted*,
%   elementwise grammar over channel labels:
%       + - * /        elementwise, with the usual precedence and parentheses
%       unary -        negation
%       abs( ) sqrt( ) elementwise functions
%       numbers        scalar literals, broadcast over the waveform
%       "name"         a channel named in double quotes: any label, such as
%                      a number (BrainVision caps name channels 1 to 64) or
%                      one with a hyphen or a space; a bare number that is
%                      also a channel's name is refused rather than guessed
%                      (refuseNumbersNamingChannels)
%   It is parsed and evaluated directly (a small recursive-descent parser,
%   see below), never eval-ed: a saved .alm / template is shared between
%   users and loaded from disk, so running its text as MATLAB would be a
%   code-injection hole. The restricted grammar also guarantees the result
%   is either a scalar or a single channel-shaped waveform, so a derivation
%   can never produce a wrongly-sized channel.
%
%   A NEW NAME is appended to EEG.data as a new row and to EEG.chanlocs as
%   a new entry with .type = 'derived' and no scalp coordinates (a
%   difference/derived channel has no place on the head, so ScalpDistribution
%   -- which keeps only channels that match a scalp-position template --
%   drops it automatically, while the ERP line plot and grand averages show
%   it like any other channel).
%
%   A NAME THE DATA ALREADY HAS is overwritten in place: its row of
%   EEG.data takes the new values, and its entry in EEG.chanlocs, position
%   and type included, stays as it was. "let ECG = -ECG" turns an inverted
%   ECG the right way up.
%
%   "LET <NAME> = []" removes the channel, data and entry. A channel the ICA
%   decomposition was computed on is refused, since the decomposition would
%   no longer match the data; the decomposition's channel numbers
%   (EEG.icachansind) follow any other removal.
%
%   ADDED, REPLACED and REMOVED name the channels that are new, that were
%   overwritten, and that are gone, comparing the result with the input.
%
%   NOTHING IS STRIPPED FIRST. Until 2026-10-22 every channel marked
%   'derived' was removed before the block ran, so that running a block
%   again replaced its channels rather than stacking duplicates. That also
%   removed the channels an earlier step had derived: deriving ECG2 from ECG
%   in one step, removing ECG, and then deriving ECG from ECG2 in another
%   failed with "ECG2 is not a channel", although the dialog listed it. A
%   name that already exists is now overwritten, which keeps re-running
%   free of duplicates, and a step re-run (Recalculate, replay) starts from
%   its parent's data in any case.
%
%   The per-channel arrays beside EEG.data follow the channels (see
%   TransTools.AlignChannelCompanions): a computed channel's standard error,
%   aSME and noise covariance are NaN, since an average no longer holds the
%   covariance between electrodes they depend on, and it counts as
%   interpolated in a trial where any channel it is computed from was.
%
%   A no-op (EEG unchanged, the names empty) when TEXT defines no
%   statements. Shared by Measure.m (a real averaged EEG) and MeasureDialog
%   (a tiny dummy EEG built from the dataset's chanlocs, purely to validate
%   the block at OK time), so the two can never disagree about what parses.
    added = {};
    replaced = {};
    removed = {};
    derivs = parseLetLines(text);
    if isempty(derivs)
        return;
    end

    inputChanlocs = EEG.chanlocs;
    flags = interpolationFlags(EEG);
    computed = {};   % lower-case labels of the channels a statement set
    for i = 1:numel(derivs)
        name = derivs(i).name;
        row = find(strcmpi({EEG.chanlocs.labels}, name), 1);
        if derivs(i).remove
            if isempty(row)
                throw(MException('Alakazam:Derivations', ['"let %s = []" removes a channel, ' ...
                    'but I''m afraid there is no channel "%s" here to remove.'], name, name));
            end
            EEG = removeChannel(EEG, row, name);
            computed(strcmpi(computed, name)) = []; %#ok<AGROW>
            if ~isempty(flags) && isKey(flags, lower(name))
                remove(flags, lower(name));
            end
            continue;
        end

        ast = parseExpression(derivs(i).expr, name);
        refuseNumbersNamingChannels(ast, EEG, name);
        value = evalNode(ast, @(nm) lookupChannel(EEG, nm, name));
        if isempty(row)
            EEG = appendChannel(EEG, name, value);
        else
            EEG.data(row, :, :) = value;   % a scalar VALUE broadcasts over the waveform
        end
        computed = union(computed, {lower(name)});
        if ~isempty(flags)
            flags(lower(name)) = sourceFlags(flags, channelNames(ast));
        end
    end
    EEG = computedCompanions(EEG, inputChanlocs, computed, flags);

    before = lower({inputChanlocs.labels});
    after = {EEG.chanlocs.labels};
    added = after(~ismember(lower(after), before));
    replaced = after(ismember(lower(after), before) & ismember(lower(after), computed));
    removed = {inputChanlocs(~ismember(before, lower(after))).labels};
end

% ======================================================================= %
%  "let" line parsing
% ======================================================================= %
function derivs = parseLetLines(text)
%PARSELETLINES  Split TEXT into a struct array of .name / .expr / .remove,
%   one per non-blank "let" statement. Throws a friendly, line-numbered
%   error on a line that is not a well-formed "let <name> = <expression>".
    derivs = struct('name', {}, 'expr', {}, 'remove', {});
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
        % One token for the name, plain or quoted: MATLAB returns no named
        % token from inside an alternation.
        tok = regexp(ln, '^let\s+(?<name>[A-Za-z][A-Za-z0-9_'']*|"[^"]+")\s*=\s*(?<expr>.+)$', ...
            'names', 'once', 'ignorecase');
        if isempty(tok)
            throw(MException('Alakazam:Derivations', ['Derived-channel line %d doesn''t look quite right. Please write one ' ...
                '"let <name> = <expression>" per line, e.g. let LRP = C3 - C4.'], li));
        end
        name = strip(tok.name, '"');
        expr = strtrim(tok.expr);
        derivs(end + 1) = struct('name', name, 'expr', expr, ...
            'remove', ~isempty(regexp(expr, '^\[\s*\]$', 'once'))); %#ok<AGROW>
    end
end

% ======================================================================= %
%  Expression grammar (recursive descent)
% ======================================================================= %
%   expr   := term   (('+' | '-') term)*
%   term   := factor (('*' | '/') factor)*
%   factor := ('+' | '-')? factor  |  primary
%   primary:= number | channel | '"' label '"' | func '(' expr ')' | '(' expr ')'
function ast = parseExpression(expr, ctx)
%PARSEEXPRESSION  EXPR (the text right of '=') to an AST, CTX is the
%   derivation name for error messages.
    toks = lexExpression(expr, ctx);
    if isempty(toks)
        throw(MException('Alakazam:Derivations', 'Derived channel "%s" seems to have an empty expression.', ctx));
    end
    [ast, k] = parseAddSub(toks, 1, ctx);
    if k <= numel(toks)
        throw(MException('Alakazam:Derivations', 'Derived channel "%s": I wasn''t expecting to find "%s" in the expression.', ...
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
        throw(MException('Alakazam:Derivations', 'Derived channel "%s": the expression seems to end too early.', ctx));
    end
    t = toks(k);
    switch t.kind
        case 'num'
            node = struct('type', 'num', 'val', t.val, 'text', t.text);
            k = k + 1;
        case 'quoted'
            node = struct('type', 'chan', 'name', t.val);
            k = k + 1;
        case 'id'
            if k < numel(toks) && strcmp(toks(k + 1).kind, 'lpar')
                fn = lower(t.val);
                if ~ismember(fn, {'abs', 'sqrt'})
                    throw(MException('Alakazam:Derivations', ['Derived channel "%s": I don''t recognise the function "%s". ' ...
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
            throw(MException('Alakazam:Derivations', 'Derived channel "%s": I wasn''t expecting "%s" there.', ctx, t.text));
    end
end

function k = expectRParen(toks, k, ctx)
    if k > numel(toks) || ~strcmp(toks(k).kind, 'rpar')
        throw(MException('Alakazam:Derivations', 'Derived channel "%s": a "(" here is missing its closing ")".', ctx));
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
        elseif c == '"'
            % A channel named in double quotes: any label, a number or one
            % with a hyphen or a space included, and never a function.
            closing = find(s(i + 1:end) == '"', 1);
            if isempty(closing)
                throw(MException('Alakazam:Derivations', ['Derived channel "%s": a channel name ' ...
                    'opened with " is missing its closing ".'], ctx));
            end
            name = s(i + 1:i + closing - 1);
            if isempty(strtrim(name))
                throw(MException('Alakazam:Derivations', 'Derived channel "%s": "" names no channel.', ctx));
            end
            toks(end + 1) = token('quoted', name, ['"' name '"']); %#ok<AGROW>
            i = i + closing + 1;
        elseif any(c == '0123456789.')
            j = i;
            while j <= n && any(s(j) == '0123456789.')
                j = j + 1;
            end
            numText = s(i:j - 1);
            val = str2double(numText);
            if isnan(val)
                throw(MException('Alakazam:Derivations', 'Derived channel "%s": "%s" doesn''t look like a valid number.', ctx, numText));
            end
            toks(end + 1) = token('num', val, numText); %#ok<AGROW>
            i = j;
        else
            throw(MException('Alakazam:Derivations', 'Derived channel "%s": I''m afraid "%s" isn''t a character this expression grammar allows.', ctx, c));
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

function names = channelNames(node)
%CHANNELNAMES  Every channel label an AST refers to, as a cellstr.
    switch node.type
        case 'chan'
            names = {node.name};
        case {'neg', 'func'}
            names = channelNames(node.child);
        case 'op'
            names = [channelNames(node.left), channelNames(node.right)];
        otherwise
            names = {};
    end
end

function texts = numberTexts(node)
%NUMBERTEXTS  Every number literal in an AST, as it was written.
    switch node.type
        case 'num'
            texts = {node.text};
        case {'neg', 'func'}
            texts = numberTexts(node.child);
        case 'op'
            texts = [numberTexts(node.left), numberTexts(node.right)];
        otherwise
            texts = {};
    end
end

function refuseNumbersNamingChannels(ast, EEG, ctx)
%REFUSENUMBERSNAMINGCHANNELS  A bare number that is also a channel's name.
%   Some caps name their channels by number (BrainVision's 1 to 64, for
%   one), and there "LEOG - 53" could mean channel 53 or the number 53; read
%   as the number, it gives a channel that looks right and is not. Neither
%   reading is guessed: the statement is refused, with both ways of saying
%   it unambiguously.
    for text = numberTexts(ast)
        if any(strcmpi({EEG.chanlocs.labels}, text{1}))
            throw(MException('Alakazam:Derivations', ['Derived channel "%s": %s is a number ' ...
                'here, but this dataset also has a channel called "%s". Would you write "%s", ' ...
                'in double quotes, for the channel, or %s.0 for the number?'], ...
                ctx, text{1}, text{1}, text{1}, text{1}));
        end
    end
end

function v = lookupChannel(EEG, nm, ctx)
%LOOKUPCHANNEL  The samples of channel NM (case-insensitive), or a friendly
%   error naming the derivation CTX that referred to a channel not present.
    idx = find(strcmpi({EEG.chanlocs.labels}, nm), 1);
    if isempty(idx)
        throw(MException('Alakazam:Derivations', ['Derived channel "%s" refers to "%s", which I''m afraid is not a ' ...
            'channel at this line: it is not in this dataset or defined on an earlier line, or an ' ...
            'earlier line removed it.'], ctx, nm));
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

function EEG = removeChannel(EEG, row, name)
%REMOVECHANNEL  Remove channel ROW ("let NAME = []"), keeping the ICA
%   decomposition's channel numbers on the channels they named. A channel
%   the decomposition was computed on is refused: its mixing matrix has a
%   row for it, and the components would no longer match the data.
    if isfield(EEG, 'icachansind') && ~isempty(EEG.icachansind)
        if any(EEG.icachansind == row)
            throw(MException('Alakazam:Derivations', ['"let %s = []": the ICA decomposition in ' ...
                'this dataset was computed with %s, so removing it would leave the components ' ...
                'not matching the data, and I have kept it. Removing it before the decomposition ' ...
                'is computed avoids this.'], name, name));
        end
        later = EEG.icachansind > row;
        EEG.icachansind(later) = EEG.icachansind(later) - 1;
    end
    EEG.chanlocs(row) = [];
    EEG.data(row, :, :) = [];
    EEG.nbchan = size(EEG.data, 1);
end

function flags = interpolationFlags(EEG)
%INTERPOLATIONFLAGS  The interpolation record by lower-case label (a
%   containers.Map of logical rows), or [] when EEG keeps none in step with
%   its channels.
    flags = [];
    try
        mask = EEG.etc.alz.interpolated;
    catch
        return;
    end
    if ~islogical(mask) || size(mask, 1) ~= numel(EEG.chanlocs)
        return;
    end
    flags = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for r = 1:size(mask, 1)
        key = lower(char(string(EEG.chanlocs(r).labels)));
        if ~isKey(flags, key)
            flags(key) = mask(r, :);
        end
    end
end

function row = sourceFlags(flags, names)
%SOURCEFLAGS  A computed channel is interpolated in a trial where any of
%   the channels it is computed from (NAMES) was.
    row = [];
    for k = 1:numel(names)
        key = lower(names{k});
        if isKey(flags, key)
            if isempty(row)
                row = flags(key);
            else
                row = row | flags(key);
            end
        end
    end
    if isempty(row)
        row = false(size(flags(firstKey(flags))));
    end
end

function key = firstKey(map)
    keys = map.keys();
    key = keys{1};
end

function EEG = computedCompanions(EEG, inputChanlocs, computed, flags)
%COMPUTEDCOMPANIONS  Bring the per-channel arrays in step with the channels
%   after the statements, then set the rows of the channels a statement
%   computed (COMPUTED, lower-case labels): an unknown error (NaN) and noise
%   covariance, whatever row a channel of that name had before, and the
%   interpolation flags gathered from its sources (FLAGS).
    EEG = TransTools.AlignChannelCompanions(EEG, inputChanlocs);
    labels = lower({EEG.chanlocs.labels});
    rows = find(ismember(labels, computed));
    if isempty(rows)
        return;
    end
    if isfield(EEG, 'stErr') && ~isempty(EEG.stErr)
        EEG.stErr(rows, :) = NaN;
    end
    if isfield(EEG, 'aSME') && ~isempty(EEG.aSME)
        EEG.aSME(rows, :) = NaN;
    end
    if isfield(EEG, 'noiseCov') && ~isempty(EEG.noiseCov)
        EEG.noiseCov(rows, :, :) = NaN;
        EEG.noiseCov(:, rows, :) = NaN;
    end
    if isempty(flags)
        return;
    end
    try
        mask = EEG.etc.alz.interpolated;
    catch
        return;   % no interpolation record to extend
    end
    if islogical(mask) && size(mask, 1) == numel(labels)
        for r = rows
            mask(r, :) = flags(labels{r});
        end
        EEG.etc.alz.interpolated = mask;
    end
end
