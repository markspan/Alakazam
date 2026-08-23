function rx = wildcardToRegex(c)
%WILDCARDTOREGEX  Translate a ?/* wildcard marker into an anchored regex.
    rx = regexptranslate('escape', char(c));   % escape regex metacharacters
    rx = strrep(rx, '\?', '.');                % ? -> any single character
    rx = strrep(rx, '\*', '.*');               % * -> any run of characters
    rx = ['^' rx '$'];
end
