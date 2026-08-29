function defaults = transformDefaults(transformId, transformationsRoot)
%TRANSFORMDEFAULTS  A transformation's default option values, where it
%   declares them somewhere a reader can find them.
%
%   Returns a struct of field -> default value, containing only the fields
%   whose default could be read with confidence. A transformation that
%   declares none returns an empty struct, and that is a normal answer
%   rather than a failure.
%
%   WHY THIS IS ONLY EVER USED FOR ANNOTATION. exportAnalysisScript marks
%   the options that are at their default with a trailing comment; it does
%   NOT omit them. Omitting would make an exported script's meaning depend
%   on the app's defaults at the time it is run, so changing a default
%   later would silently change what an old script does, which is precisely
%   what a record of an analysis must not do. Because the result is only a
%   comment, a default this reads wrongly is untidy rather than harmful,
%   which is what makes reading them out of source acceptable at all.
%
%   Three declaration idioms are recognised, being the ones actually used:
%
%     TransTools.FieldOr(options, 'Name', <literal>)   ArtefactDetect, Fourier
%     stored = struct('Name', <literal>, ...)          Baseline, Resample
%     d('Name', <literal>)                             ArtefactDetect's dialog
%
%   Anything else (Filter's nested highpass/lowpass structs, ReRef's
%   required mode) yields nothing for that field, and it simply goes
%   un-annotated.
%
%   See also EXPORTANALYSISSCRIPT.
    defaults = struct();
    if nargin < 2 || isempty(transformationsRoot)
        transformationsRoot = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
            'Transformations');
    end

    file = fullfile(transformationsRoot, transformId, [transformId '.m']);
    if exist(file, 'file') ~= 2
        return;
    end
    source = fileread(file);

    defaults = mergeInto(defaults, fieldOrDefaults(source));
    defaults = mergeInto(defaults, storedStructDefaults(source));
    defaults = mergeInto(defaults, dialogDefaults(source));
end

% ======================================================================= %
function defaults = fieldOrDefaults(source)
%FIELDORDEFAULTS  TransTools.FieldOr(options, 'Name', <literal>).
    defaults = struct();
    hits = regexp(source, 'FieldOr\(\s*options\s*,\s*''(\w+)''\s*,\s*(.*?)\)\s*;', ...
        'tokens');
    for i = 1:numel(hits)
        defaults = addIfSafe(defaults, hits{i}{1}, hits{i}{2});
    end
end

function defaults = dialogDefaults(source)
%DIALOGDEFAULTS  d('Name', <literal>) inside an options dialog, where d is
%   the "stored value, else this default" shorthand.
    defaults = struct();
    hits = regexp(source, '\bd\(\s*''(\w+)''\s*,\s*(.*?)\)\s*[,)]', 'tokens');
    for i = 1:numel(hits)
        defaults = addIfSafe(defaults, hits{i}{1}, hits{i}{2});
    end
end

function defaults = storedStructDefaults(source)
%STOREDSTRUCTDEFAULTS  stored = struct('A', v, 'B', w); the fallback used
%   when TransformSettings has nothing remembered yet, which is the app's
%   own statement of what the defaults are.
    defaults = struct();
    hits = regexp(source, 'stored\s*=\s*struct\((.*?)\)\s*;', 'tokens', 'once');
    if isempty(hits)
        return;
    end
    pairs = regexp(hits{1}, '''(\w+)''\s*,\s*([^,]+)', 'tokens');
    for i = 1:numel(pairs)
        defaults = addIfSafe(defaults, pairs{i}{1}, pairs{i}{2});
    end
end

% ======================================================================= %
function defaults = addIfSafe(defaults, name, literalText)
%ADDIFSAFE  Record NAME's default when LITERALTEXT is plainly a literal.
%
%   Only shapes that cannot execute anything are accepted: a number, a
%   quoted string, true/false, [], or a cell of those. Anything else (a
%   function call, a variable, an expression) is skipped rather than
%   evaluated, since reading a source file must not run any of it.
    text = strtrim(literalText);
    if isempty(text) || ~isLiteralText(text)
        return;
    end
    try
        value = eval(text); %#ok<EVLDOT>
    catch
        return;   % not something this can read; leave the field un-annotated
    end
    defaults.(name) = value;
end

function tf = isLiteralText(text)
%ISLITERALTEXT  Whether TEXT is one of the safe literal shapes.
    patterns = { ...
        '^-?\d+\.?\d*([eE][-+]?\d+)?$', ...              % a number
        '^''[^'']*''$', ...                              % a quoted string
        '^"[^"]*"$', ...                                 % a double-quoted string
        '^(true|false)$', ...                            % a logical
        '^\[\s*\]$', ...                                 % empty
        '^\{\s*\}$', ...                                 % empty cell
        '^\{\s*(''[^'']*''\s*,?\s*)+\}$', ...            % a cell of strings
        '^\[\s*(-?\d+\.?\d*\s*,?\s*)+\]$'};              % a numeric vector
    tf = any(cellfun(@(p) ~isempty(regexp(text, p, 'once')), patterns));
end

function target = mergeInto(target, extra)
%MERGEINTO  Add EXTRA's fields, without overwriting one already found: the
%   sources are tried in order of how directly they state the compute-time
%   default, so the first to mention a field wins.
    names = fieldnames(extra);
    for i = 1:numel(names)
        if ~isfield(target, names{i})
            target.(names{i}) = extra.(names{i});
        end
    end
end
