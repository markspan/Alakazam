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
    [anchorCs, ~, anchorNeg, aWarn] = parseBracket(brk{homeIdx}{2});
    warnings = [warnings, prefixWarns(aWarn, binNum)];
    if anchorNeg
        warnings{end+1} = sprintf(['bin %d: the time-locking bracket negates every code, ' ...
            'so the anchor is "any event that is not one of these". Translated literally; ' ...
            'worth checking it is what was meant.'], binNum);
        terms = {sprintf('not %s', anchorCs)};
    else
        terms = {anchorCs};
    end

    % Preceding brackets -> prev(); following brackets -> next().
    %
    % ORDINAL WINDOWS, not bare relations. A BINLISTER sequencer is
    % POSITIONAL: each bracket is the ADJACENT event in the chain, so the
    % second bracket after the home event is the event two positions later,
    % not "a matching event somewhere later" (see neobinlister2's own
    % sequencer countup/countdown). DefineBins' next()/prev() scan until they
    % find a match, so a bare next(201) is a looser condition than the BDF
    % actually asked for. Anchoring each bracket to its own ordinal offset
    % with "within [k,k] events" restores the original meaning exactly.
    %
    % An explicit t<lo-hi> replaces the ordinal window rather than joining
    % it: the millisecond range is what the BDF author actually constrained,
    % and DefineBins allows one window per relation.
    for k = 1:numel(brk)
        if k == homeIdx; continue; end
        following = k > homeIdx;
        [cs, tflag, negated, bWarn] = parseBracket(brk{k}{2});
        warnings = [warnings, prefixWarns(bWarn, binNum)]; %#ok<AGROW>
        [win, tWarn] = timingToWindow(tflag, following, BIG);
        warnings = [warnings, prefixWarns(tWarn, binNum)]; %#ok<AGROW>

        rel = ternary(following, 'next', 'prev');
        offset = k - homeIdx;          % negative for preceding brackets
        if isempty(win)
            win = sprintf('[%d,%d] events', offset, offset);
        elseif negated
            % A negated code with an explicit ms window is the one case the
            % two languages genuinely disagree on: BINLISTER asks whether the
            % event AT THIS POSITION is not the code, DefineBins asks whether
            % the code occurs ANYWHERE in the window. They differ as soon as
            % more than one event falls inside it.
            warnings{end+1} = sprintf(['bin %d: "~" with an explicit time window becomes ' ...
                '"no such event anywhere in the window", which is stricter than ' ...
                'BINLISTER''s "the event at this position is not this code" when several ' ...
                'events fall inside it. Worth checking.'], binNum); %#ok<AGROW>
        end

        term = sprintf('%s(%s) within %s', rel, cs, win);
        if negated
            term = ['not ' term];
        end
        terms{end+1} = term; %#ok<AGROW>
    end

    expr = strjoin(terms, ' and ');
end

% ----------------------------------------------------------------------- %
function [cs, tflag, negated, warnings] = parseBracket(inner)
%PARSEBRACKET  Split a bracket's contents into a DefineBins code set, its
%   time-condition flag (the "low-high" inside t<...>, or ''), whether the
%   bracket is negated, and warnings for anything with no equivalent.
%
%   The grammar is ERPLAB's own, from bdf2struct.m's expp{} table:
%
%       t<lo-hi>        time condition, ms relative to the home event
%       ~<code>         negation, attached to each CODE (not to the bracket)
%       <lo>-<hi>       a RANGE of event codes, expanded here
%       ;  ,            alternatives within the bracket
%       :f<>  :fa<> :fb<>   flag tests    -- no equivalent, warned
%       :w<>  :wa<> :wb<>   flag writes   -- no equivalent, warned
%       :rt<"name">     named reaction time -- no equivalent, warned
%       *   ~*          all codes / no codes
%
%   NEGATION IS ALL-OR-NOTHING per bracket, following neobinlister2: it
%   counts the non-negated ("desired") codes, and only when there are none
%   does the bracket match by MISmatching. A bracket mixing ~ and plain
%   codes therefore behaves as a positive test over all of them, which is
%   surprising enough to warn about rather than reproduce silently.
    warnings = {};
    negated = false;

    % :rt<"name"> FIRST. It contains a literal "t<", so leaving it in place
    % would let the time-flag regex below capture "name" as a time condition
    % and then fail to parse it -- which is exactly what used to happen.
    rtm = regexp(inner, ':\s*rt\s*<\s*"([^"]*)"\s*>', 'tokens', 'once');
    if ~isempty(rtm)
        warnings{end+1} = sprintf(['named reaction time rt<"%s"> has no DefineBins ' ...
            'equivalent and was dropped. DefineBins can FILTER on reaction time ' ...
            '(rt within (lo,hi] ms) but does not name or export RT variables.'], rtm{1});
    end
    inner = regexprep(inner, ':\s*rt\s*<[^>]*>', ' ');

    % The time flag t<...>.
    tflag = '';
    tm = regexp(inner, '(?<![A-Za-z])t\s*<([^>]*)>', 'tokens', 'once');
    if ~isempty(tm); tflag = strtrim(tm{1}); end
    rest = regexprep(inner, '(?<![A-Za-z])t\s*<[^>]*>', ' ');

    % Flag tests and writes: f/fa/fb, w/wa/wb. None has an equivalent.
    flagged = regexp(rest, '[A-Za-z]+\s*<[^>]*>', 'match');
    rest = regexprep(rest, '[A-Za-z]+\s*<[^>]*>', ' ');
    bare = regexp(rest, '[A-Za-z]+', 'match');
    bare = bare(~strcmp(bare, '*'));
    rest = regexprep(rest, '(?<![*~])[A-Za-z]+', ' ');
    rest = strrep(rest, ':', ' ');

    other = [flagged, bare];
    if ~isempty(other)
        warnings{end+1} = sprintf('flag(s) "%s" have no DefineBins equivalent; ignored.', ...
            strjoin(other, ' '));
    end

    % Codes. ERPLAB separates alternatives with ';' or ','.
    parts = strtrim(strsplit(rest, {';', ','}));
    parts = parts(~cellfun(@isempty, parts));

    codes = {};
    nNegated = 0;
    for p = 1:numel(parts)
        item = parts{p};
        isNeg = startsWith(item, '~');
        if isNeg
            nNegated = nNegated + 1;
            item = strtrim(item(2:end));
        end
        if isempty(item)
            continue;
        end
        [expanded, itemWarns] = expandCodeItem(item);
        codes = [codes, expanded]; %#ok<AGROW>
        warnings = [warnings, itemWarns]; %#ok<AGROW>
    end

    if isempty(codes)
        cs = '""';
    elseif numel(codes) == 1
        cs = codes{1};
    else
        cs = ['{' strjoin(codes, ' ') '}'];
    end

    % All negated -> the bracket matches when the event is none of them.
    if nNegated > 0 && nNegated == numel(parts)
        negated = true;
    elseif nNegated > 0
        warnings{end+1} = ['this bracket mixes negated and plain codes; ERPLAB treats ' ...
            'that as a positive test over all of them, and so does this translation.'];
    end
end

% ----------------------------------------------------------------------- %
function [codes, warnings] = expandCodeItem(item)
%EXPANDCODEITEM  One ERPLAB code item as DefineBins code literals.
%
%   A numeric range "21-30" is passed through AS A RANGE. DefineBins has
%   range syntax of its own now, and it means the same thing, so an imported
%   script reads like the descriptor it came from instead of listing ten
%   codes where the BDF wrote two. (It was enumerated here until the
%   language gained ranges; the enumeration was only ever a workaround.)
%
%   "*" (ERPLAB's "any code") becomes the "*" wildcard, which DefineBins
%   matches inside quotes. Anything else non-numeric becomes a quoted text
%   marker.
    warnings = {};

    m = regexp(item, '^(\d+)\s*-\s*(\d+)$', 'tokens', 'once');
    if ~isempty(m)
        lo = str2double(m{1});
        hi = str2double(m{2});
        if hi < lo
            % Emitted as written rather than silently swapped: guessing at
            % the intent of a malformed descriptor is worse than saying so
            % and letting the analyst decide. DefineBins refuses a backwards
            % range too, so the script will not run until it is corrected.
            warnings{end + 1} = sprintf(['the code range %d-%d runs backwards, so it ' ...
                'covers nothing. It has been carried over as written; did the BDF mean ' ...
                '%d-%d?'], lo, hi, hi, lo);
        end
        codes = {sprintf('%d-%d', lo, hi)};
        return;
    end

    if strcmp(item, '*')
        codes = {'"*"'};
    elseif ~isempty(regexp(item, '^-?\d+$', 'once'))
        codes = {item};
    else
        codes = {['"' strrep(item, '"', '') '"']};
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
        error('Alakazam:erplabBdfToBinScript', 'I''m afraid the BDF input must be text.');
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
