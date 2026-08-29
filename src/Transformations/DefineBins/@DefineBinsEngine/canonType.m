function s = canonType(t)
%CANONTYPE  An event's raw .type (numeric or char/string) as a single
%   trimmed, whitespace-collapsed string, so buildContext and the codeset
%   scanner compare event types the same way regardless of source format.
%
%   A LEADING 's' BEFORE A NUMBER IS DROPPED. BrainVision writes its
%   stimulus markers as "S 12", "S201" and so on, so a recording's codes
%   arrive as text even though they are numbers with a prefix. Dropping the
%   prefix makes them numeric again, which means they can be written
%   unquoted, compared numerically, and covered by a range: 21-30 matches
%   S21 through S30. Response markers ("R 12") keep their prefix, since
%   only 's' was asked for and R codes routinely reuse the same numbers.
%
%   APPLIED TO BOTH SIDES, which is the point. This function normalises
%   event types (buildContext) and the literal codes in a script
%   (scanCodeElem), so the two can only ever agree: "S12", "S 12", "s12"
%   and 12 all become "12", whether they are written in a bin definition or
%   recorded in the file.
%
%   WILDCARDS COUNT AS DIGITS HERE. A pattern like "s??" has to lose its
%   prefix too, or it would keep an 's' the events no longer have and match
%   nothing -- which would break the "s??" example in the language
%   reference. So the character class below is digits AND the two wildcard
%   characters, not digits alone.
    if isnumeric(t)
        s = num2str(t);
    else
        s = char(string(t));
    end
    s = regexprep(strtrim(s), '\s+', '');

    % One leading s/S, then nothing but digits and wildcards, and at least
    % one of them: "S12" -> "12", "s??" -> "??", but "s" alone, "S1a" and
    % "R12" are left exactly as they are.
    s = regexprep(s, '^[sS]([0-9?*]+)$', '$1');

    s = string(s);
end
