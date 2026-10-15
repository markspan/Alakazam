function predictAt = predictionValues(text, unfold, labels)
%PREDICTIONVALUES  Where the model terms are evaluated, as the toolbox takes it.
%   PREDICTAT = Unfold.predictionValues(TEXT, UNFOLD) reads TEXT, written as
%   "name = v1 v2; name2 = v3", into uf_predictContinuous's predictAt: one
%   {name, values} pair for every term that field became in UNFOLD (an
%   EEG.unfold after uf_designmat). A spline keeps the field's name, a
%   continuous term of a second event type is prefixed ("2_sac_amplitude"),
%   and a value given for the field applies to both. Empty TEXT is {}.
%
%   A 2D SPLINE (2dspl(x, z, n)) is named by its two fields: "x = 1 2; z =
%   0.5" evaluates it at every pair, here (1, 0.5) and (2, 0.5), as the
%   toolbox's {name, xs, zs} does. Naming only one of the two is refused,
%   since a point on the surface needs both; naming neither leaves it on the
%   toolbox's own grid, ten quantiles of each field.
%
%   Throws Alakazam:Unfold:EvaluateAt when a part is not "name = numbers",
%   names no continuous or spline term of the model, or names only one field
%   of a 2D spline. Each refusal says what it could not use and why, lists
%   the terms the model does have, each with its kind and the bin it belongs
%   to (LABELS, optional: the name of each of UNFOLD.eventtypes, as
%   Unfold.binModel's plan.typeLabels gives them), and offers the ways out.
%   Unfold.fitBins reads the values with this, and DeconvolveDialog checks
%   them with it against the same design before OK, so the dialog refuses
%   exactly what the fit would, in the same words.
%
%   See also UNFOLD.FITBINS, UNFOLD.DESIGNMATRIX, DECONVOLVEDIALOG.
    if nargin < 3
        labels = {};
    end
    predictAt = {};
    text = strtrim(char(string(text)));
    if isempty(text)
        return;
    end
    candidates = {};
    surfaces = struct('name', {}, 'pair', {});
    if isfield(unfold, 'splines') && ~isempty(unfold.splines)
        for s = 1:numel(unfold.splines)
            spl = unfold.splines{s};
            if size(spl.knots, 1) == 2
                surfaces(end + 1) = struct('name', char(string(spl.name)), ...
                    'pair', {surfacePair(char(string(spl.name)), unfold)}); %#ok<AGROW>
            else
                candidates{end + 1} = char(string(spl.name)); %#ok<AGROW>
            end
        end
    end
    continuous = strcmp(unfold.variabletypes(unfold.cols2variablenames), 'continuous');
    candidates = unique([reshape(candidates, 1, []), reshape(unfold.colnames(continuous), 1, [])], 'stable');
    surfaceFields = [{}, surfaces.pair];   % a list of names even without a 2D spline
    terms = termInventory(unfold, labels);

    given = struct('name', {}, 'values', {});
    for part = strtrim(strsplit(text, ';'))
        if isempty(part{1})
            continue;
        end
        tokens = regexp(part{1}, '^([A-Za-z_]\w*)\s*=\s*(.+)$', 'tokens', 'once');
        values = [];
        if ~isempty(tokens)
            words = regexp(tokens{2}, '[^\s,]+', 'match');
            values = str2double(words);
        end
        if isempty(tokens) || isempty(values) || any(isnan(values))
            problem = sprintf('it has no "name = values" shape I can make out');
            if ~isempty(tokens) && ~isempty(values)
                problem = sprintf('%s %s not a number I can read', ...
                    listOf(words(isnan(values))), isOrAre(nnz(isnan(values))));
            elseif ~contains(part{1}, '=')
                problem = 'there is no equals sign between the name and its values';
            end
            throw(MException('Alakazam:Unfold:EvaluateAt', '%s', sprintf([ ...
                'I''m terribly sorry to trouble you, but I couldn''t make sense of "%s" in ' ...
                'Terms evaluated at: %s.\n\nEach part needs the name of a term, an equals ' ...
                'sign and one or more numbers, with the parts separated by semicolons, as in ' ...
                '"%s". Decimals take a point, not a comma, since a comma or a space separates ' ...
                'one value from the next.\n\n%s\n\nWould you be so kind as to correct that ' ...
                'part, or to remove it? A term you do not name is drawn at ten quantiles of its ' ...
                'own values, so you need only name the ones whose values matter to you.'], ...
                part{1}, problem, exampleFor(terms), inventoryText(terms))));
        end
        given(end + 1) = struct('name', tokens{1}, 'values', values); %#ok<AGROW>
        matches = candidates(~cellfun(@isempty, regexp(candidates, ['^(\d+_)?' tokens{1} '$'], 'once')));
        if isempty(matches) && ~ismember(tokens{1}, surfaceFields)
            throw(MException('Alakazam:Unfold:EvaluateAt', '%s', ...
                notATermMessage(tokens{1}, strtrim(tokens{2}), terms)));
        end
        for m = 1:numel(matches)
            predictAt{end + 1} = {matches{m}, values}; %#ok<AGROW>
        end
    end

    for s = 1:numel(surfaces)
        pair = surfaces(s).pair;
        named = ismember(pair, {given.name});
        if all(named)
            predictAt{end + 1} = {surfaces(s).name, given(strcmp({given.name}, pair{1})).values, ...
                given(strcmp({given.name}, pair{2})).values}; %#ok<AGROW>
        elseif any(named)
            where = terms(strcmp({terms.name}, sprintf('%s and %s', pair{1}, pair{2})));
            inBin = '';
            if ~isempty(where)
                inBin = sprintf(', in the formula of "%s"', where(1).bin);
            end
            throw(MException('Alakazam:Unfold:EvaluateAt', '%s', sprintf([ ...
                'I''m so sorry, but I can''t draw the 2D spline of "%s" and "%s"%s from the ' ...
                'values you gave for "%s" alone: a point on its surface needs a value of each ' ...
                'field, and I have none for "%s".\n\nWould you be so kind as to add values for ' ...
                '"%s" as well, as in "%s = 1 2; %s = 0.5"? Every combination of the two is ' ...
                'then drawn, here (1, 0.5) and (2, 0.5). Or, if you would rather not choose, ' ...
                'leave both out, and the surface is drawn at ten quantiles of each field.'], ...
                pair{1}, pair{2}, inBin, pair{named}, pair{~named}, pair{~named}, ...
                pair{1}, pair{2})));
        end
    end
end

% ======================================================================= %
function text = notATermMessage(name, values, terms)
%NOTATERMMESSAGE  The refusal of values for a field no term of the model
%   uses: what happened, what the model has instead, and the ways out.
    if isempty(terms)
        text = sprintf([ ...
            'I''m so sorry, but I can''t evaluate "%s" at %s: no formula in this model ' ...
            'uses "%s". Every bin is fitted as y ~ 1 here, which gives each bin one waveform ' ...
            'of its own and leaves no continuous or spline term to evaluate at any value.\n\n' ...
            'Would you be so kind as to do one of two things? Either clear Terms evaluated ' ...
            'at, and each bin then comes out as its own waveform (its intercept), or put "%s" ' ...
            'back into a bin''s formula, for example y ~ 1 + spl(%s, 5) for a smooth curve ' ...
            'or y ~ 1 + %s for a straight line, and its values here will then be used.'], ...
            name, values, name, name, name, name);
        return;
    end
    text = sprintf([ ...
        'I''m so sorry, but I can''t evaluate "%s" at %s: no formula in this model uses ' ...
        '"%s", so there is no term of it to draw.\n\n%s\n\nWould you be so kind as to use ' ...
        'one of those names instead, or to add "%s" to the formula of the bin it belongs ' ...
        'to first (y ~ 1 + spl(%s, 5) for a smooth curve, y ~ 1 + %s for a straight ' ...
        'line)? A term you do not name is drawn at ten quantiles of its own values, so you ' ...
        'need only name the ones whose values matter to you.'], ...
        name, values, name, inventoryText(terms), name, name, name);
end

function terms = termInventory(unfold, labels)
%TERMINVENTORY  The model's terms that can be evaluated at values: each with
%   the field (or pair of fields) it is named by, its kind, and the bin it
%   belongs to.
    terms = struct('name', {}, 'kind', {}, 'bin', {});
    if isfield(unfold, 'splines') && ~isempty(unfold.splines)
        for s = 1:numel(unfold.splines)
            spl = unfold.splines{s};
            name = regexprep(char(string(spl.name)), '^\d+_', '');
            kind = 'a smooth curve (spline)';
            if size(spl.knots, 1) == 2
                pair = surfacePair(char(string(spl.name)), unfold);
                if numel(pair) == 2
                    name = sprintf('%s and %s', pair{1}, pair{2});
                end
                kind = 'a smooth surface (2D spline)';
            elseif contains(func2str(spl.splinefunction), 'cyclical')
                kind = 'a curve round a circle (circular spline)';
            end
            column = find(strcmp(unfold.colnames, spl.colnames{1}), 1);
            terms(end + 1) = struct('name', name, 'kind', kind, ...
                'bin', binOf(unfold, labels, column)); %#ok<AGROW>
        end
    end
    for column = reshape(find(strcmp(unfold.variabletypes(unfold.cols2variablenames), 'continuous')), 1, [])
        terms(end + 1) = struct('name', regexprep(unfold.colnames{column}, '^\d+_', ''), ...
            'kind', 'a straight line', 'bin', binOf(unfold, labels, column)); %#ok<AGROW>
    end
end

function bin = binOf(unfold, labels, column)
%BINOF  The bin (or event code) a column of X belongs to, by its label where
%   LABELS gives one, else by the toolbox's event type, its prefix removed.
    bin = '';
    if isempty(column) || ~isfield(unfold, 'cols2eventtypes')
        return;
    end
    t = unfold.cols2eventtypes(column);
    if t <= numel(labels)
        bin = char(string(labels{t}));
        return;
    end
    names = unfold.eventtypes{t};
    if iscell(names) && ~isempty(names) && (ischar(names{1}) || isstring(names{1}))
        bin = regexprep(char(string(names{1})), '^(bin|evt)_', '');
    end
end

function text = inventoryText(terms)
%INVENTORYTEXT  The terms this model can be evaluated at, in a sentence.
    if isempty(terms)
        text = 'This model has no continuous or spline term: every bin is fitted as y ~ 1.';
        return;
    end
    parts = arrayfun(@(t) termPhrase(t), terms, 'UniformOutput', false);
    text = sprintf('The terms this model can be evaluated at are: %s.', strjoin(parts, '; '));
end

function phrase = termPhrase(term)
    phrase = sprintf('"%s", %s', term.name, term.kind);
    if ~isempty(term.bin)
        phrase = sprintf('%s, in "%s"', phrase, term.bin);
    end
end

function text = exampleFor(terms)
%EXAMPLEFOR  An example written with one of this model's own terms.
    text = 'sac_amplitude = 0.5 1 2; rt = 300 500';
    single = terms(~contains({terms.kind}, '2D'));
    if ~isempty(single)
        text = sprintf('%s = 0.5 1 2', single(1).name);
    end
end

function text = listOf(words)
    words = cellfun(@(w) ['"' w '"'], words, 'UniformOutput', false);
    if isscalar(words)
        text = words{1};
    else
        text = [strjoin(words(1:end - 1), ', ') ' and ' words{end}];
    end
end

function word = isOrAre(n)
    word = 'is';
    if n ~= 1
        word = 'are';
    end
end

% ======================================================================= %
function pair = surfacePair(name, unfold)
%SURFACEPAIR  The two fields of the 2D spline the toolbox named NAME: it
%   runs them together ("xz", or "2_xz" in a second event type), so they are
%   read back from the formulas it was given.
    pair = {};
    stem = regexprep(name, '^\d+_', '');
    formulas = cellstr(string(unfold.formula));
    for f = 1:numel(formulas)
        for found = regexp(formulas{f}, '2dspl\s*\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)', 'tokens')
            if strcmp([found{1}{:}], stem)
                pair = found{1};
                return;
            end
        end
    end
end
