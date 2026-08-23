function ME = wrapParseError(script, err)
%WRAPPARSEERROR  Turn a throwParseError (or any other) exception into a
%   warm, specific, example-rich one that shows exactly where the trouble is
%   in the analyst's own script -- or, if it is not one of ours (an
%   unexpected internal error), passes it through untouched.
    tok = regexp(err.identifier, '^Alakazam:DefineBins:ParseAtCol(\d+)$', 'tokens', 'once');
    if isempty(tok)
        ME = err;
        return;
    end
    col = str2double(tok{1});

    opener = "I'm afraid I got a little stuck reading your DefineBins script -- let's sort it out together.";
    if col > 0 && col <= numel(script)
        [lineTxt, lineNo, colInLine] = DefineBinsEngine.locateInScript(script, col);
        pointer = [repmat(' ', 1, colInLine - 1) '^-- right about here'];
        body = sprintf('%s\n\nLine %d:\n    %s\n    %s\n\n%s', ...
            opener, lineNo, lineTxt, pointer, char(err.message));
    else
        % No single column pinpoints this one (e.g. a mistake that spans
        % several statements); still explain what and why, just without a
        % snippet to point at.
        body = sprintf('%s\n\n%s', opener, char(err.message));
    end
    ME = MException('Alakazam:DefineBins', '%s', body);
end
