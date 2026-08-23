function toks = tokenize(s)
%TOKENIZE  Lex a DefineBins script into a token stream.
%#ok<*AGROW>
    keywords = ["bin","let","rt","timelock","and","or","not", ...
                "next","prev","adjacent","any","within","ms","samples","events"];
    toks = struct('kind', {}, 'val', {}, 'pos', {}, 'len', {});
    i = 1; n = numel(s);
    while i <= n
        c = s(i);
        if isspace(c)
            i = i + 1;
        elseif c == '%' || c == '#'
            while i <= n && s(i) ~= newline; i = i + 1; end
        elseif c == '"'
            j = i + 1;
            while j <= n && s(j) ~= '"'; j = j + 1; end
            if j > n
                DefineBinsEngine.throwParseError(i, [ ...
                    'This quoted text marker never closes, I''m afraid -- I read all ' ...
                    'the way to the end of the script looking for its matching ''"''. ' ...
                    'Would you check for a missing closing quote?']);
            end
            toks(end+1) = mkTok("str", string(s(i+1:j-1)), i, j-i+1);
            i = j + 1;
        elseif isdigit(c) || (c == '-' && i < n && isdigit(s(i+1)))
            j = i + 1;
            while j <= n && (isdigit(s(j)) || s(j) == '.'); j = j + 1; end
            toks(end+1) = mkTok("num", str2double(s(i:j-1)), i, j-i);
            i = j;
        elseif isletter(c) || c == '_'
            j = i + 1;
            while j <= n && (isletter(s(j)) || isdigit(s(j)) || s(j) == '_')
                j = j + 1;
            end
            word = s(i:j-1);
            if any(strcmpi(word, keywords))
                toks(end+1) = mkTok("kw", lower(string(word)), i, j-i);
            else
                % A bare word is an identifier (an alias name); the parser
                % reports "quote text markers" if it is used where a code is
                % expected and is not a defined alias.
                toks(end+1) = mkTok("ident", string(word), i, j-i);
            end
            i = j;
        elseif any(c == '()[]{}|,:=+-')
            toks(end+1) = mkTok("punc", string(c), i, 1);
            i = i + 1;
        else
            DefineBinsEngine.throwParseError(i, sprintf([ ...
                'I don''t know what to do with the character ''%s'' here, I''m afraid -- ' ...
                'it is not part of any code, keyword, or punctuation this language uses. ' ...
                'If you meant it as part of a text marker, would you wrap it in quotes, ' ...
                'e.g. "%s"?'], c, c));
        end
    end
end

function t = mkTok(kind, val, pos, len)
    t = struct('kind', kind, 'val', val, 'pos', pos, 'len', len);
end

function tf = isdigit(c)
    tf = c >= '0' && c <= '9';
end
