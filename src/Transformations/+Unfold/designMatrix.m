function EEG = designMatrix(EEG, plan)
%DESIGNMATRIX  The design of a bin plan, built by the toolbox itself.
%   EEG = Unfold.designMatrix(EEG, PLAN) sets EEG.event to PLAN.events and
%   runs uf_designmat over PLAN.eventTypes, each with its own formula from
%   PLAN.formulas (see Unfold.binModel), so EEG.unfold holds X, colnames,
%   variablenames, variabletypes, cols2variablenames, cols2eventtypes,
%   eventtypes and splines as the toolbox documents them
%   (https://www.unfoldtoolbox.org/datastructures.html).
%
%   ONE CALL FOR THE FIT AND FOR THE DIALOG'S PREVIEW. Nothing here reads
%   the data (that starts with the time expansion), so DeconvolveDialog
%   builds the same design on the events alone, and a formula the toolbox
%   refuses, or a term that turns into other columns than were meant, shows
%   while it can still be edited, not after the fit has run.
%
%   A REFUSAL NAMES THE BIN. uf_designmat's own message is about its
%   parser, not about which of several formulas it was reading, so when it
%   fails each event type is tried alone and the error
%   (Alakazam:Unfold:Formula) says which bin's formula it was, and what the
%   toolbox said about it.
%
%   ONE-LETTER FACTOR LEVELS (Unfold 1.3.1, unchanged in its current
%   version; seen with MATLAB R2026a). uf_designmat gives every empty event
%   field the value NaN, so that a numeric field stays numeric in the table
%   it builds with MATLAB's struct2table; and struct2table reads levels that
%   are all single characters, together with NaN, as one column of
%   characters rather than a list of texts ({'L','R',NaN} is char, where
%   {'L','R','L'} and {'left','right',NaN} are cells). The design then
%   cannot be built: "Input #2 expected to be a cell array, was char
%   instead". In a script one boundary event without the field is enough;
%   here the model's events carry no boundaries, so it takes another event
%   type in the model without the field. Alakazam calls the toolbox as it
%   is, so a model behaves here exactly as in a script, and the message
%   says why and what to do: name the levels with two characters or more
%   ('left'/'right'). Numeric levels are unaffected.
%
%   See also UNFOLD.BINMODEL, UNFOLD.FITBINS, DECONVOLVEDIALOG.
    EEG.event = plan.events;
    try
        EEG = design(EEG, plan.eventTypes, plan.formulas);
    catch err
        throw(namedRefusal(EEG, plan, err));
    end
end

% ======================================================================= %
function EEG = design(EEG, eventTypes, formulas)
%DESIGN  uf_designmat with one formula per event type. The toolbox takes a
%   list of formulas only when there are two or more: a list of one is not
%   split, and the cell then reaches its formula parser, which fails with
%   "Function is not defined for 'cell' inputs". So a single event type is
%   passed the way the toolbox passes each one to itself.
    if isscalar(eventTypes)
        EEG = uf_designmat(EEG, 'eventtypes', eventTypes(1), 'formula', formulas{1});
    else
        EEG = uf_designmat(EEG, 'eventtypes', cellfun(@(t) {t}, eventTypes, 'UniformOutput', false), ...
            'formula', formulas);
    end
end

function err = namedRefusal(EEG, plan, cause)
%NAMEDREFUSAL  The toolbox's error, with the bin whose formula caused it,
%   and the toolbox bug behind it where it is the known one (see this
%   file's header).
    for k = 1:numel(plan.eventTypes)
        one = EEG;
        one.event = plan.events(strcmp({plan.events.type}, plan.eventTypes{k}));
        try
            design(one, plan.eventTypes(k), plan.formulas(k));
        catch inner
            err = MException('Alakazam:Unfold:Formula', '%s', sprintf( ...
                'Unfold cannot build the formula of "%s", %s. What it said: %s', ...
                plan.typeLabels{k}, plan.formulas{k}, inner.message));
            return;
        end
    end
    message = sprintf(['Unfold cannot build this design, although it accepts each bin''s formula ' ...
        'on its own. What it said: %s'], cause.message);
    factors = oneLetterFactors(plan);
    if contains(cause.message, 'expected to be a cell array, was char') && ~isempty(factors)
        message = sprintf(['%s\n\nThe Unfold toolbox (1.3.1) cannot build a factor whose levels ' ...
            'are all single characters once another event type in the model lacks the field: ' ...
            'MATLAB''s struct2table then reads the levels as characters rather than as text. ' ...
            '%s has such levels. Would you give them names of two characters or more (for ' ...
            'example "left" and "right" instead of "L" and "R")?'], message, listOf(factors));
    end
    err = MException('Alakazam:Unfold:Formula', '%s', message);
end

function names = oneLetterFactors(plan)
%ONELETTERFACTORS  The factors (cat() in a formula) whose text levels are
%   all a single character.
    names = {};
    if ~isfield(plan, 'variables')
        return;
    end
    for t = 1:numel(plan.variables)
        vars = plan.variables{t};
        for v = vars([vars.categorical])
            rows = strcmp({plan.events.type}, plan.eventTypes{t});
            values = {plan.events(rows).(v.name)};
            text = values(cellfun(@(x) ischar(x) || isstring(x), values));
            if ~isempty(text) && all(strlength(string(text)) == 1)
                names{end + 1} = v.name; %#ok<AGROW>
            end
        end
    end
    names = unique(names, 'stable');
end

function s = listOf(names)
    names = cellfun(@(n) ['"' n '"'], names, 'UniformOutput', false);
    if isscalar(names)
        s = names{1};
    else
        s = [strjoin(names(1:end - 1), ', ') ' and ' names{end}];
    end
end
