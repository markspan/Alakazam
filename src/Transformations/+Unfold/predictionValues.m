function predictAt = predictionValues(text, unfold)
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
%   toolbox's own grid, five quantiles of each field.
%
%   Throws Alakazam:Unfold:EvaluateAt, naming the part it cannot use, when a
%   part is not "name = numbers" or names no continuous or spline term of
%   the model. Unfold.fitBins reads the values with this, and
%   DeconvolveDialog checks them with it against the same design before OK,
%   so the dialog refuses exactly what the fit would.
%
%   See also UNFOLD.FITBINS, UNFOLD.DESIGNMATRIX, DECONVOLVEDIALOG.
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
    surfaceFields = [surfaces.pair];

    given = struct('name', {}, 'values', {});
    for part = strtrim(strsplit(text, ';'))
        if isempty(part{1})
            continue;
        end
        tokens = regexp(part{1}, '^([A-Za-z_]\w*)\s*=\s*(.+)$', 'tokens', 'once');
        values = [];
        if ~isempty(tokens)
            values = str2double(regexp(tokens{2}, '[^\s,]+', 'match'));
        end
        if isempty(tokens) || isempty(values) || any(isnan(values))
            throw(MException('Alakazam:Unfold:EvaluateAt', '%s', sprintf([ ...
                '"%s" is not a field and its values: would you write it as, for example, ' ...
                '"sac_amplitude = 0.5 1 2"?'], part{1})));
        end
        given(end + 1) = struct('name', tokens{1}, 'values', values); %#ok<AGROW>
        matches = candidates(~cellfun(@isempty, regexp(candidates, ['^(\d+_)?' tokens{1} '$'], 'once')));
        if isempty(matches) && ~ismember(tokens{1}, surfaceFields)
            known = [regexprep(candidates, '^\d+_', ''), surfaceFields];
            throw(MException('Alakazam:Unfold:EvaluateAt', '%s', sprintf([ ...
                '"%s" is not a continuous or spline term of this model, so there is nothing to ' ...
                'evaluate at %s. The ones there are: %s.'], tokens{1}, strtrim(tokens{2}), ...
                strjoin(unique(known), ', '))));
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
            throw(MException('Alakazam:Unfold:EvaluateAt', '%s', sprintf([ ...
                '"%s" and "%s" make one 2D spline, and a point on it needs a value of each: ' ...
                'would you give values for "%s" too?'], pair{1}, pair{2}, pair{~named})));
        end
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
