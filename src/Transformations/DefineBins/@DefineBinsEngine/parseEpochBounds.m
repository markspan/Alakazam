function win = parseEpochBounds(startStr, stopStr)
%PARSEEPOCHBOUNDS  Turn the dialog's start/stop text (ms) into an epoch window.
%   Both blank means no epoching ([]); otherwise both bounds are required and
%   the window is inclusive, in milliseconds.
    if isempty(startStr) && isempty(stopStr)
        win = [];
        return;
    end
    lo = epochNum(startStr, 'start');
    hi = epochNum(stopStr,  'stop');
    if hi <= lo
        throw(MException('Alakazam:DefineBins', ...
            ['The Epoch stop field (%g ms) needs to come after Epoch start (%g ms), ' ...
             'I''m afraid, so there is a positive stretch of time to cut around each ' ...
             'event. A window like -200 to 800 covers 200 ms before the event to ' ...
             '800 ms after it.'], ...
            hi, lo));
    end
    win = struct('lo', lo, 'hi', hi, 'unit', 'ms');
end

function v = epochNum(str, which)
    if isempty(str)
        throw(MException('Alakazam:DefineBins', ...
            ['The Epoch %s field is empty, but Epoch %s has a value, I''m afraid. ' ...
             'Would you fill in both fields to segment the data (for example, -200 ' ...
             'and 800), or clear both to leave the data continuous and just tag ' ...
             'the bins?'], ...
            which, otherEpochField(which)));
    end
    v = str2double(str);
    if isnan(v)
        throw(MException('Alakazam:DefineBins', ...
            ['Epoch %s is set to "%s", which I''m afraid is not a plain number of ' ...
             'milliseconds (no units, just a number -- e.g. -200, not "-200ms").'], which, str));
    end
end

function other = otherEpochField(which)
    if strcmp(which, 'start'); other = 'stop'; else; other = 'start'; end
end
