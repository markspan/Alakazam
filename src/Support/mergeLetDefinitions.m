function [merged, keptNames] = mergeLetDefinitions(existingText, loadedText)
%MERGELETDEFINITIONS  Add one "let" block to another without redefining a
%   name that is already there.
%
%   [MERGED, KEPTNAMES] = mergeLetDefinitions(EXISTINGTEXT, LOADEDTEXT)
%   returns EXISTINGTEXT followed by every line of LOADEDTEXT that defines a
%   name EXISTINGTEXT does not. KEPTNAMES are the names that were already
%   defined, so a caller can report which of the loaded definitions went
%   unused.
%
%   THE EXISTING DEFINITION WINS, deliberately. It is the one the analyst
%   typed, and every window already in their table was written against it;
%   replacing it would silently change what those windows measure.
%
%   WHY NOT SIMPLY CONCATENATE. measureDerivations appends each derived
%   channel to the dataset as it evaluates the block, so a second "let LRP"
%   finds LRP already present and raises "already exists in this dataset"
%   at OK time, in a message that names the channel and gives no hint that
%   loading a file caused it.
%
%   ITS OWN FILE SO IT CAN BE TESTED. As a local function inside
%   MeasureDialog it was reachable only by opening the dialog, and the
%   parsing below has more cases than that would ever exercise: a
%   commented-out definition defines nothing, a name differing only in case
%   is the same name (measureDerivations matches channel labels with
%   strcmpi), and blank lines carry nothing either way.
%
%   See also MEASUREDERIVATIONS, MEASUREDIALOG, LINESFROMTEXT.
    merged = existingText;
    keptNames = {};

    loadedLines = linesFromText(loadedText);
    have = letNames(existingText);
    additions = {};
    for i = 1:numel(loadedLines)
        name = letName(loadedLines{i});
        if isempty(name)
            continue;       % a blank line or a comment carries no definition
        end
        if any(strcmpi(have, name))
            if ~any(strcmpi(keptNames, name))
                keptNames{end + 1} = name; %#ok<AGROW>
            end
            continue;
        end
        have{end + 1} = name; %#ok<AGROW>
        additions{end + 1} = loadedLines{i}; %#ok<AGROW>
    end

    if isempty(additions)
        return;
    end
    if isempty(strtrim(char(string(merged))))
        merged = char(strjoin(string(additions), newline));
    else
        merged = char(strjoin(string([{merged}, additions]), newline));
    end
end

% ======================================================================= %
function names = letNames(text)
%LETNAMES  Every name defined by a "let" line in TEXT.
    names = {};
    lines = linesFromText(text);
    for i = 1:numel(lines)
        name = letName(lines{i});
        if ~isempty(name)
            names{end + 1} = name; %#ok<AGROW>
        end
    end
end

function name = letName(line)
%LETNAME  The name a "let" line defines, or '' for anything else.
%   Comments run from '%' to the end of the line, the rule
%   measureDerivations applies, so a commented-out definition defines
%   nothing and must not block a real one from being added.
    name = '';
    text = char(string(line));
    hash = strfind(text, '%');
    if ~isempty(hash)
        text = text(1:hash(1) - 1);
    end
    token = regexp(strtrim(text), '^let\s+([A-Za-z]\w*)\s*=', 'tokens', 'once');
    if ~isempty(token)
        name = token{1};
    end
end
