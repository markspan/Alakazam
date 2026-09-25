function predictAt = predictionValues(text, unfold)
%PREDICTIONVALUES  Where the model terms are evaluated, as the toolbox takes it.
%   PREDICTAT = Unfold.predictionValues(TEXT, UNFOLD) reads TEXT, written as
%   "name = v1 v2; name2 = v3", into uf_predictContinuous's predictAt: one
%   {name, values} pair for every term that field became in UNFOLD (an
%   EEG.unfold after uf_designmat). A spline keeps the field's name, a
%   continuous term of a second event type is prefixed ("2_sac_amplitude"),
%   and a value given for the field applies to both. Empty TEXT is {}.
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
    if isfield(unfold, 'splines') && ~isempty(unfold.splines)
        candidates = cellfun(@(s) char(string(s.name)), unfold.splines, 'UniformOutput', false);
    end
    continuous = strcmp(unfold.variabletypes(unfold.cols2variablenames), 'continuous');
    candidates = unique([reshape(candidates, 1, []), reshape(unfold.colnames(continuous), 1, [])], 'stable');
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
        matches = candidates(~cellfun(@isempty, regexp(candidates, ['^(\d+_)?' tokens{1} '$'], 'once')));
        if isempty(matches)
            throw(MException('Alakazam:Unfold:EvaluateAt', '%s', sprintf([ ...
                '"%s" is not a continuous or spline term of this model, so there is nothing to ' ...
                'evaluate at %s. The ones there are: %s.'], tokens{1}, strtrim(tokens{2}), ...
                strjoin(unique(regexprep(candidates, '^\d+_', '')), ', '))));
        end
        for m = 1:numel(matches)
            predictAt{end + 1} = {matches{m}, values}; %#ok<AGROW>
        end
    end
end
