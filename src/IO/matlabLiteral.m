function text = matlabLiteral(value, indent)
%MATLABLITERAL  VALUE as MATLAB source that evaluates back to it.
%
%   Used by exportAnalysisScript to write each transformation's stored
%   options struct into the generated script as a literal, so the script
%   reproduces the recorded analysis exactly without needing the workspace
%   or its cache to still exist.
%
%   INDENT is the column the value starts at, used to lay out struct and
%   cell contents readably; omit it at the top level.
%
%   Supports what a transformation's params actually contain: structs
%   (including nested and struct arrays), cell arrays, char, string,
%   logical, numeric scalars/vectors/matrices, function handles and empty.
%   Anything else is rejected rather than silently mis-serialised, because
%   a params value this cannot express would otherwise produce a script
%   that runs and quietly analyses something different.
%
%   Round-tripping is what makes it correct, and exportAnalysisScriptTest
%   checks exactly that: eval(matlabLiteral(x)) must isequaln x.
%
%   See also EXPORTANALYSISSCRIPT.
    if nargin < 2
        indent = 0;
    end
    pad = repmat(' ', 1, indent);

    % A raw-code marker is emitted verbatim rather than as a literal: it is
    % how a caller substitutes an EXPRESSION for a value, e.g. replacing an
    % embedded bin script with the variable that read it back from its own
    % file. See rawCodeMarker below and exportAnalysisScript's own use.
    if isRawCode(value)
        text = value.(rawCodeField());
        return;
    end

    if isa(value, 'function_handle')
        text = func2str(value);
        if ~startsWith(text, '@')
            text = ['@' text];
        end
        return;
    end

    if ischar(value)
        text = charLiteral(value);
    elseif isstring(value)
        text = stringLiteral(value);
    elseif islogical(value)
        text = logicalLiteral(value);
    elseif isnumeric(value)
        text = numericLiteral(value);
    elseif iscell(value)
        text = cellLiteral(value, indent, pad);
    elseif isstruct(value)
        text = structLiteral(value, indent, pad);
    else
        throw(MException('Alakazam:matlabLiteral', ...
            ['I''m afraid a stored option of class "%s" cannot be written into a ' ...
             'generated script. Please report which transformation produced it.'], class(value)));
    end
end

% ======================================================================= %
function name = rawCodeField()
%RAWCODEFIELD  The field name marking a raw-code value. Deliberately one no
%   transformation would ever use as a real option name.
    name = 'Alakazam_rawCode__';
end

function tf = isRawCode(value)
    tf = isstruct(value) && isscalar(value) && isfield(value, rawCodeField()) ...
        && numel(fieldnames(value)) == 1;
end

function text = charLiteral(value)
%CHARLITERAL  A char row as a quoted literal. A char MATRIX is not a string
%   and cannot be written as one, so it goes through a row-by-row layout,
%   rebuilt with char().
%
%   Text containing a NEWLINE cannot be a quoted literal at all: a MATLAB
%   single-quoted string may not span lines, so 'a\nb' written literally is
%   a syntax error. That is not a hypothetical: DefineBins stores its whole
%   bin script as one multi-line char (nearly a kilobyte of it, comments
%   included), which is exactly what a generated script has to carry to
%   reproduce the epoching. Such text is emitted as a sprintf() call with
%   the line breaks escaped, which is the only form that survives both the
%   file and the round trip.
    if isempty(value)
        text = '''''';
    elseif size(value, 1) > 1
        rows = arrayfun(@(r) charLiteral(value(r, :)), (1:size(value, 1))', ...
            'UniformOutput', false);
        text = ['char(' strjoin(rows', '; ') ')'];
    elseif any(value == newline | value == char(13) | value == char(9))
        text = escapedTextLiteral(value);
    else
        text = ['''' strrep(value, '''', '''''') ''''];
    end
end

function text = escapedTextLiteral(value)
%ESCAPEDTEXTLITERAL  Multi-line (or tab-bearing) text as sprintf('...').
%   Percent and backslash have to be escaped first, because sprintf reads
%   them as format and escape introducers: without that, a bin script's own
%   "%" comment lines would be eaten as conversion specifications and the
%   reproduced script would silently epoch on a different set of bins.
    escaped = strrep(value, '\', '\\');
    escaped = strrep(escaped, '%', '%%');
    escaped = strrep(escaped, '''', '''''');
    escaped = strrep(escaped, char(13), '\r');
    escaped = strrep(escaped, newline, '\n');
    escaped = strrep(escaped, char(9), '\t');
    text = ['sprintf(''' escaped ''')'];
end

function text = stringLiteral(value)
    if isscalar(value)
        if ismissing(value)
            text = 'string(missing)';
        else
            text = ['"' strrep(char(value), '"', '""') '"'];
        end
        return;
    end
    if isempty(value)
        text = 'string.empty(0, 0)';
        return;
    end
    parts = arrayfun(@(v) stringLiteral(v), value(:)', 'UniformOutput', false);
    text = ['[' strjoin(parts, ', ') ']'];
    if size(value, 1) > 1 && size(value, 2) > 1
        text = sprintf('reshape(%s, %d, %d)', text, size(value, 1), size(value, 2));
    end
end

function text = logicalLiteral(value)
    if isempty(value)
        text = 'false(0, 0)';
    elseif isscalar(value)
        text = boolWord(value);
    else
        words = arrayfun(@(v) boolWord(v), value(:)', 'UniformOutput', false);
        text = ['[' strjoin(words, ', ') ']'];
        if size(value, 1) > 1 && size(value, 2) > 1
            text = sprintf('reshape(%s, %d, %d)', text, size(value, 1), size(value, 2));
        end
    end
end

function word = boolWord(v)
    if v; word = 'true'; else; word = 'false'; end
end

function text = numericLiteral(value)
%NUMERICLITERAL  Numbers, at the shortest precision that still reads back as
%   exactly the same double.
%
%   Exactness is not negotiable: a rounded threshold or filter cutoff would
%   make the generated script produce subtly different numbers from the
%   analysis it claims to reproduce. But a fixed %.17g buys nothing for it,
%   because 0.4 and 0.40000000000000002 ARE the same double: printing the
%   latter is not more faithful, only less readable, and it reads as a
%   rounding error in a file whose whole purpose is being read. See
%   scalarNumber for how the shortest exact form is found.
    if isempty(value)
        text = '[]';
        return;
    end
    cls = class(value);
    body = numericBody(value);
    if ~ismember(cls, {'double'})
        text = sprintf('%s(%s)', cls, body);
    else
        text = body;
    end
end

function body = numericBody(value)
    if isscalar(value)
        body = scalarNumber(value);
        return;
    end
    rows = cell(1, size(value, 1));
    for r = 1:size(value, 1)
        cells = arrayfun(@(v) scalarNumber(v), value(r, :), 'UniformOutput', false);
        rows{r} = strjoin(cells, ', ');
    end
    body = ['[' strjoin(rows, '; ') ']'];
end

function text = scalarNumber(v)
    if isnan(v)
        text = 'NaN';
    elseif isinf(v)
        if v > 0; text = 'Inf'; else; text = '-Inf'; end
    elseif ~isreal(v)
        text = sprintf('complex(%.17g, %.17g)', real(v), imag(v));
    elseif v == fix(v) && abs(v) < 1e15
        text = sprintf('%d', v);
    else
        text = shortestExact(v);
    end
end

function text = shortestExact(v)
%SHORTESTEXACT  The fewest significant digits that still read back as
%   bit-for-bit V.
%
%   Tried in increasing precision and stopped at the first that round-trips,
%   so 0.4 prints as "0.4" while a value that genuinely needs them keeps all
%   seventeen. 17 significant digits always suffice for a double, so the
%   loop cannot fall through; the final assignment is there so the function
%   is total regardless.
    for digits = 1:16
        text = sprintf('%.*g', digits, v);
        if str2double(text) == v
            return;
        end
    end
    text = sprintf('%.17g', v);
end

function text = cellLiteral(value, indent, pad)
    if isempty(value)
        text = '{}';
        return;
    end
    parts = cell(1, numel(value));
    for i = 1:numel(value)
        parts{i} = matlabLiteral(value{i}, indent + 4);
    end
    oneLine = ['{' strjoin(parts, ', ') '}'];
    if numel(oneLine) + indent <= 90 && ~contains(oneLine, newline)
        text = oneLine;
        if size(value, 1) > 1 && size(value, 2) > 1
            text = sprintf('reshape(%s, %d, %d)', text, size(value, 1), size(value, 2));
        end
        return;
    end
    % Every newline inside the braces is continued with "...". Without it a
    % bare newline inside {} is a ROW separator, so a long cell would come
    % back as an Nx1 cell of rows instead of the 1xN it started as: a shape
    % change that evaluates cleanly and is invisible until something
    % downstream indexes it. (Inside struct(...) the same omission is a
    % plain syntax error, which is how this was found.)
    inner = repmat(' ', 1, indent + 4);
    text = ['{ ...' newline inner strjoin(parts, [', ...' newline inner]) ' ...' newline pad '}'];
end

function text = structLiteral(value, indent, pad)
%STRUCTLITERAL  A struct as a struct(...) call.
%
%   A cell-valued field has to be wrapped one level deeper, as {{...}}:
%   struct() treats a cell argument as "build a struct ARRAY, one element
%   per cell", so struct('x', {1, 2}) is a 1x2 struct array, not a struct
%   whose x is a cell. The extra braces are how a genuinely cell-valued
%   field is expressed, and getting this wrong is the classic way a
%   generated script silently produces the wrong shape.
    if isempty(value)
        if isempty(fieldnames(value))
            text = 'struct([])';
        else
            args = cell(1, 0);
            names = fieldnames(value);
            for i = 1:numel(names)
                args{end + 1} = sprintf('''%s'', {}', names{i}); %#ok<AGROW>
            end
            text = ['struct(' strjoin(args, ', ') ')'];
        end
        return;
    end

    if ~isscalar(value)
        % A struct array: emitted element by element, then concatenated,
        % which keeps each element's own literal simple and correct.
        parts = arrayfun(@(v) matlabLiteral(v, indent + 4), value(:)', ...
            'UniformOutput', false);
        inner = repmat(' ', 1, indent + 4);
        text = ['[ ...' newline inner strjoin(parts, [', ...' newline inner]) ' ...' newline pad ']'];
        if size(value, 1) > 1 && size(value, 2) > 1
            text = sprintf('reshape(%s, %d, %d)', text, size(value, 1), size(value, 2));
        end
        return;
    end

    names = fieldnames(value);
    if isempty(names)
        text = 'struct()';
        return;
    end
    parts = cell(1, numel(names));
    for i = 1:numel(names)
        fieldValue = value.(names{i});
        literal = matlabLiteral(fieldValue, indent + 4);
        if iscell(fieldValue)
            literal = ['{' literal '}'];   % see the note above
        end
        parts{i} = sprintf('''%s'', %s', names{i}, literal);
    end
    oneLine = ['struct(' strjoin(parts, ', ') ')'];
    if numel(oneLine) + indent <= 90 && ~contains(oneLine, newline)
        text = oneLine;
        return;
    end
    inner = repmat(' ', 1, indent + 4);
    text = ['struct( ...' newline inner strjoin(parts, [', ...' newline inner]) ' ...' newline pad ')'];
end
