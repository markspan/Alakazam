function [script, warnings] = erplabBdfToBinScript(bdf)
%ERPLABBDFTOBINSCRIPT  Convert an ERPLAB bin descriptor file (BDF) to a
%   DefineBins script.
%
%   [SCRIPT, WARNINGS] = erplabBdfToBinScript(BDF) translates the text of an
%   ERPLAB/BINLISTER bin descriptor file into Alakazam's own bin-definition
%   language (see bin_language.md). BDF is the file's text (a char array or a
%   cellstr/string array of lines). SCRIPT is the DefineBins script; WARNINGS
%   is a cellstr of anything that could not be translated exactly (also left
%   as a "% WARNING:" line in the script, so nothing is dropped silently).
%
%   ERPLAB BDF, in brief: each bin is three lines --
%       bin <n>              (the keyword is matched case-insensitively)
%       <label>
%       <descriptor>
%   The descriptor is a chronological chain of event brackets. Exactly one
%   bracket, prefixed with a dot, is the time-locking (home) event; brackets
%   before it are preceding events, after it following events. Inside a
%   bracket, event codes are separated by ';' (logical OR), and a time
%   condition is written as the flag t<low-high> (ms, relative to the home
%   event); e.g. {t<200-1500>201} is "a 201 occurring 200-1500 ms later".
%
%   Mapping to DefineBins:
%       .{111;112}            -> anchor            111|112
%       {5}.{home}            -> prev(5)           (preceding context)
%       .{home}{t<200-1500>201} -> next(201) within [200,1500] ms
%   Other ERPLAB flags (w write-back, f/a/d flag tests, ...) have no
%   DefineBins equivalent and are reported in WARNINGS, not translated.
%
%   See also DEFINEBINS, the bin-definition language reference (bin_language.md).
    BIG = 100000; % ms, stand-in upper bound for an open-ended one-sided time

    lines = normaliseLines(bdf);
    warnings = {};
    out = {'% Imported from an ERPLAB bin descriptor file (BDF).', ...
           '% Review the bins below; any lines marked WARNING need a look.', ''};
    nbins = 0;

    i = 1;
    while i <= numel(lines)
        tok = regexpi(lines{i}, '^\s*bin\s+(\d+)', 'tokens', 'once'); % case-insensitive
        if isempty(tok)
            i = i + 1;
            continue; % not a "bin N" line -- skip stray text between blocks
        end
        binNum = str2double(tok{1});

        % The next two content lines are the label and the descriptor.
        [label, i] = nextContentLine(lines, i + 1);
        [descriptor, i] = nextContentLine(lines, i);
        if isempty(descriptor)
            warnings{end+1} = sprintf('bin %d: no descriptor line; skipped.', binNum); %#ok<AGROW>
            continue;
        end

        [expr, binWarns] = descriptorToExpr(descriptor, binNum, BIG);
        for w = 1:numel(binWarns)
            warnings{end+1} = binWarns{w}; %#ok<AGROW>
            out{end+1} = sprintf('%% WARNING: %s', binWarns{w}); %#ok<AGROW>
        end
        out{end+1} = sprintf('bin %d "%s" : %s', binNum, cleanLabel(label), expr); %#ok<AGROW>
        nbins = nbins + 1;
    end

    if nbins == 0
        note = ['no "bin N" blocks were found. An ERPLAB bin descriptor file has, ' ...
                'per bin, a "bin <n>" line, a label line, then a descriptor line.'];
        warnings{end+1} = note;
        out{end+1} = sprintf('%% WARNING: %s', note);
    end

    script = strjoin(out, newline);
end

% ======================================================================= %
function [expr, warnings] = descriptorToExpr(descriptor, binNum, BIG)
%DESCRIPTORTOEXPR  One ERPLAB descriptor -> one DefineBins expression.
    warnings = {};

    % Every bracket, in order, tagged with whether a dot (home marker)
    % immediately precedes it.
    brk = regexp(descriptor, '(\.?)\s*\{([^}]*)\}', 'tokens');
    if isempty(brk)
        expr = '';
        warnings{end+1} = sprintf('bin %d: could not read any {..} brackets from "%s".', binNum, strtrim(descriptor));
        return;
    end
    isHome = cellfun(@(t) ~isempty(t{1}), brk);
    homeIdx = find(isHome, 1);
    if isempty(homeIdx)
        homeIdx = 1;
        warnings{end+1} = sprintf('bin %d: no time-locking ".{..}" bracket; used the first bracket as the anchor.', binNum);
    end

    % The anchor (home bracket): codes only; a timing flag on it is meaningless.
    [anchorCs, ~, aWarn] = parseBracket(brk{homeIdx}{2});
    warnings = [warnings, prefixWarns(aWarn, binNum)];
    terms = {anchorCs};

    % Preceding brackets -> prev(); following brackets -> next() (+ timing).
    for k = 1:numel(brk)
        if k == homeIdx; continue; end
        following = k > homeIdx;
        [cs, tflag, bWarn] = parseBracket(brk{k}{2});
        warnings = [warnings, prefixWarns(bWarn, binNum)]; %#ok<AGROW>
        [win, tWarn] = timingToWindow(tflag, following, BIG);
        warnings = [warnings, prefixWarns(tWarn, binNum)]; %#ok<AGROW>
        rel = ternary(following, 'next', 'prev');
        if isempty(win)
            terms{end+1} = sprintf('%s(%s)', rel, cs); %#ok<AGROW>
        else
            terms{end+1} = sprintf('%s(%s) within %s', rel, cs, win); %#ok<AGROW>
        end
    end

    expr = strjoin(terms, ' and ');
end

% ----------------------------------------------------------------------- %
function [cs, tflag, warnings] = parseBracket(inner)
%PARSEBRACKET  Split a bracket's contents into a DefineBins code set, its
%   time-condition flag (the "low-high" inside t<...>, or ''), and warnings
%   for any other ERPLAB flags. Order-independent: the t<...> flag is pulled
%   out wherever it sits, so {t<200-1500>201} and {201:t<200-1500>} both work.
    warnings = {};

    % Pull out the time flag t<...>.
    tflag = '';
    tm = regexp(inner, 't\s*<([^>]*)>', 'tokens', 'once');
    if ~isempty(tm); tflag = strtrim(tm{1}); end
    rest = regexprep(inner, 't\s*<[^>]*>', ' ');

    % Note (and strip) any other flags: X<...> forms (f/a/d flag tests) and
    % bare letters (w write-back, ...). None have a DefineBins equivalent.
    other = regexp(rest, '[A-Za-z]\s*<[^>]*>|[A-Za-z]+', 'match');
    rest = regexprep(rest, '[A-Za-z]\s*<[^>]*>', ' ');
    rest = regexprep(rest, '[A-Za-z]+', ' ');
    rest = strrep(rest, ':', ' ');   % tolerate a codes:flags colon separator

    parts = strtrim(strsplit(rest, ';'));
    parts = parts(~cellfun(@isempty, parts));
    if isempty(parts)
        cs = '""';
    else
        for p = 1:numel(parts)
            if isempty(regexp(parts{p}, '^-?\d+$', 'once'))
                parts{p} = ['"' strrep(parts{p}, '"', '') '"']; % non-numeric -> quoted marker
            end
        end
        cs = strjoin(parts, '|');
    end

    if ~isempty(other)
        warnings{end+1} = sprintf('flag(s) "%s" have no DefineBins equivalent; ignored.', strjoin(other, ' '));
    end
end

function [win, warnings] = timingToWindow(tflag, following, BIG)
%TIMINGTOWINDOW  ERPLAB time condition (the text inside t<...>) -> a DefineBins
%   'within <window> ms' string. The canonical form is a range "low-high"
%   (inclusive, so a closed [lo,hi]); a single value with an optional < / >
%   is also accepted.
    win = '';
    warnings = {};
    if isempty(tflag); return; end

    % Range form: low-high (each may be negative). ERPLAB's range is inclusive.
    m = regexp(tflag, '^\s*(-?\d+\.?\d*)\s*-\s*(-?\d+\.?\d*)\s*$', 'tokens', 'once');
    if ~isempty(m)
        win = sprintf('[%s,%s] ms', m{1}, m{2});
        return;
    end
    % Single value, optionally with a comparison operator.
    m = regexp(tflag, '^\s*(<=|>=|<|>)?\s*(-?\d+\.?\d*)\s*$', 'tokens', 'once');
    if ~isempty(m)
        op = m{1}; v = m{2};
        if isempty(op) || strcmp(op, '<') || strcmp(op, '<=')
            if following
                win = sprintf('(0,%s] ms', v);
            else
                win = sprintf('[-%s,0) ms', v);
            end
        else % > or >=
            win = sprintf('[%s,%d] ms', v, BIG);
            warnings{end+1} = sprintf('open-ended timing "t<%s>" mapped to %s (no upper bound in the BDF).', tflag, win);
        end
        return;
    end

    warnings{end+1} = sprintf('could not parse the time condition "t<%s>"; left off.', tflag);
end

% ----------------------------------------------------------------------- %
function w = prefixWarns(warns, binNum)
    w = cellfun(@(s) sprintf('bin %d: %s', binNum, s), warns, 'UniformOutput', false);
end

function lines = normaliseLines(bdf)
    if ischar(bdf)
        lines = strsplit(bdf, {sprintf('\r\n'), newline, sprintf('\r')});
    elseif isstring(bdf) || iscell(bdf)
        lines = cellstr(bdf);
    else
        error('Alakazam:erplabBdfToBinScript', 'BDF input must be text.');
    end
    lines = cellfun(@stripComment, lines, 'UniformOutput', false);
end

function s = stripComment(s)
    s = char(s);
    c = regexp(s, '[#%]', 'once');
    if ~isempty(c); s = s(1:c-1); end
    s = strtrim(s);
end

function [content, nextIdx] = nextContentLine(lines, idx)
%NEXTCONTENTLINE  The next non-blank line at or after IDX, and where to resume.
    content = '';
    nextIdx = idx;
    while nextIdx <= numel(lines)
        if ~isempty(strtrim(lines{nextIdx}))
            content = strtrim(lines{nextIdx});
            nextIdx = nextIdx + 1;
            return;
        end
        nextIdx = nextIdx + 1;
    end
end

function s = cleanLabel(label)
    s = strtrim(char(label));
    if isempty(s); s = 'bin'; end
    s = strrep(s, '"', '''');   % DefineBins labels are double-quoted
end

function v = ternary(cond, a, b)
    if cond; v = a; else; v = b; end
end
