function expanded = expandTriggerRanges(parts)
%EXPANDTRIGGERRANGES  Expand MATLAB-style colon ranges among trigger codes.
%   EXPANDED = expandTriggerRanges(PARTS), where PARTS is a cellstr of
%   trigger-code tokens (as typed into PhotodiodeDialog's Triggers field,
%   already split on commas/spaces/semicolons), returns PARTS with any token
%   shaped like MATLAB colon notation ("40:43", or "40:2:48" with a step)
%   replaced by the individual codes it names, as plain number strings.
%   Anything else -- a bare code, or a string type like "s106" -- passes
%   through unchanged.
%
%   HAND-PARSED, NOT EVAL'D. This text reaches here from a UI field the
%   analyst typed into, and running arbitrary typed text through eval to
%   build an event-type filter is a needless door to leave open for what is
%   really just a compact way to write a handful of consecutive numbers. A
%   regexp anchored to exactly N:M or N:STEP:M, all integers, cannot be
%   anything other than a range.
%
%   A CAP AGAINST A TYPO. "40:43" is four codes; "4:34000" is a typo for
%   something, not a real trigger list, and expanding it would hang the
%   dialog rebuilding its preview. A range wider than this is left as
%   literal text instead -- unlikely to match a real event type, which
%   surfaces the mistake rather than silently doing a lot of pointless work.
%
%   TWO FLAT PATTERNS, NOT ONE WITH AN OPTIONAL NESTED GROUP. MATLAB's
%   regexp only reports the outermost capturing group at each nesting level
%   ("tokens" silently drops a group captured inside another group), so
%   '^(\d+):(\d+)(?::(\d+))?$' looks right and is wrong: against "40:2:48"
%   it returns just two tokens, the innermost step silently lost. Confirmed
%   empirically before writing this. Trying the with-step pattern first and
%   falling back to the plain one sidesteps nesting entirely.
%
%   See also PHOTODIODEDIALOG.
    MAX_RANGE = 500;

    expanded = {};
    for k = 1:numel(parts)
        p = parts{k};
        stepped = regexp(p, '^(-?\d+):(-?\d+):(-?\d+)$', 'tokens', 'once');
        plain   = regexp(p, '^(-?\d+):(-?\d+)$', 'tokens', 'once');
        if ~isempty(stepped)
            a = str2double(stepped{1});
            step = str2double(stepped{2});
            b = str2double(stepped{3});
        elseif ~isempty(plain)
            a = str2double(plain{1});
            step = 1;
            b = str2double(plain{2});
        else
            expanded{end + 1} = p; %#ok<AGROW>
            continue;
        end
        codes = a:step:b;
        if step == 0 || isempty(codes) || numel(codes) > MAX_RANGE
            expanded{end + 1} = p; %#ok<AGROW>   % degenerate or implausibly wide: leave as typed
            continue;
        end
        for v = codes
            expanded{end + 1} = sprintf('%d', v); %#ok<AGROW>
        end
    end
end
