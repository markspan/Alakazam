function s = canonType(t)
%CANONTYPE  An event's raw .type (numeric or char/string) as a single
%   trimmed, whitespace-collapsed string, so buildContext and the codeset
%   scanner compare event types the same way regardless of source format.
    if isnumeric(t)
        s = num2str(t);
    else
        s = char(string(t));
    end
    s = string(regexprep(strtrim(s), '\s+', ''));
end
