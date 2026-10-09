function plan = binModel(EEG, varargin)
%BINMODEL  Turn DefineBins' bins into an Unfold model, without fitting it.
%   PLAN = Unfold.binModel(EEG) reads the bin membership DefineBins left on a
%   continuous dataset (EEG.event(i).bini, EEG.bindesc) and returns the model
%   Unfold.fitBins will fit: which event types it will have, the formula for
%   each, the event list rewritten in those terms, and what it found wrong
%   with the design. It fits nothing and needs no toolbox, so the mapping can
%   be tested, inspected and explained on its own.
%
%   ONE EVENT TYPE PER BIN, each with its own formula, y ~ 1 unless one is
%   written (see below). With y ~ 1 that is the whole translation: a bin is a
%   set of events, its rERP is the intercept of that event type, and the
%   deconvolution separates the bins' responses where they overlap in time.
%   Averaging asks the same question of epoched data, which is why the answer
%   packages into the same shape; the difference is that averaging assumes
%   the epochs do not overlap and this does not.
%
%   BINS THAT SHARE EVENTS are fitted the way Average counts them: an event
%   counts fully in every bin it belongs to. Strictly the event types are the
%   sets of bins an event can be in (PLAN.cellTypes, one per set that has
%   events), so with bins that share nothing that is one type per bin, as
%   above, and with "All stimuli" and "Rare" nested it is two: the stimuli in
%   "All stimuli" only, and those in both. Unfold.fitBins then makes each
%   bin's waveform the average, over the bin's own events, of those types'
%   responses (PLAN.binCells, PLAN.cellCounts). One type per BIN would have
%   put two sticks on such an event and explained its data as the SUM of two
%   responses, so a nested bin came out as its difference from the outer
%   one, and nothing said so. Bins holding exactly the same events are one
%   type, and come out the same, as they would from Average. The events of a
%   shared type are fitted with the terms of every formula of the bins it
%   belongs to (sharedFormula), and the notes say which bins share events.
%
%   EVENTS IN NO BIN CAN BE MODELLED TOO, one type per event code, each with
%   its own full response that is fitted and then dropped from the output.
%   'OtherEvents' says which codes: 'all' (the default) models every code
%   that occurs outside the bins, a cellstr models just those, and {} models
%   none. This is not a detail: overlap correction only removes the overlap
%   you model. A response, a button press or the next stimulus that is left
%   out of the design does not stop overlapping the bins, it just stops being
%   accounted for, and its response leaks into whichever bin happens to
%   precede it.
%
%   IT IS A CHOICE PER CODE rather than all-or-nothing because the codes are
%   not alike. A response with a hundred events overlapping every target is
%   the thing this exists to remove; a code with one stray event contributes
%   a whole window of free parameters fitted from a single occurrence, which
%   buys almost nothing and costs the fit conditioning. PLAN.UNBINNEDCODES
%   lists every code in no bin with its count and whether it was modelled, so
%   the user can see which is which, and a code left out is named in the
%   notes, because its overlap is still in the result.
%
%   'OtherEvents' is read by Unfold.otherEventsChoice, as a stored setting
%   is, so an empty list means none here exactly as it does in a template.
%
%   COMBINATION BINS ARE NOT PREDICTORS. A difference bin ("bin 3 = bin 1 -
%   bin 2") has no events of its own; Average computes it afterwards from the
%   bins it references, and so does this. Listing it as an event type would
%   be asking the model to estimate a response to nothing.
%
%   WHAT IT WARNS ABOUT: deconvolution can only separate two event types
%   where their timing varies relative to each other, so a pair at a fixed
%   lag in every trial (a stimulus and a response exactly 500 ms later, say)
%   is reported as a note: the fit will run, but the two waveforms are not
%   identified apart and the reader has to know.
%
%   PLAN fields: .binLabels, .binTypes (each bin's own type name, which is
%   the type of its events in no other bin), .binIndex, .binCounts (per
%   ordinary bin, in bindesc order), .membership (per ordinary bin, the rows
%   of EEG.event it holds), .binCells (per ordinary bin, which of the
%   .cellTypes it is made of), .cellTypes, .cellLabels ("A & B" for a shared
%   set), .cellBins (the ordinary bins of each) and .cellCounts (its events),
%   .comboBins (indices of combination bins, computed after the fit),
%   .eventTypes and .formulas (what uf_designmat is given: the cell types,
%   then the nuisance types), .typeLabels (the label or event code each type
%   stands for), .variables (per type, the fields its formula names, each
%   with .categorical and .spline), .pooled (each continuous or spline
%   field's values over every event whose formula uses it, which the bin
%   waveforms are evaluated on; a 2D spline's pair of fields as one entry
%   with .pair), .nuisanceTypes, .events (the rewritten event list, one row
%   per modelled event), .eventSource (for each row of .events, the row of
%   EEG.event it was made from), .missingValues and .missing (the choice
%   for events without a number, and which fields lack how many; see
%   checkVariables), .kept (which rows of .events the fit uses: all of
%   them, until uf_imputeMissing's 'drop' leaves some out, see
%   Unfold.fitBins) and .notes.
%
%   'MissingValues' says what is to happen to an event whose formula names
%   a field it has no number for: 'refuse' (the default here, where nothing
%   is fitted), or one of uf_imputeMissing's methods, 'median', 'mean',
%   'marginal' or 'drop', which Unfold.fitBins applies.
%
%   EACH BIN HAS A FORMULA, in Unfold's own Wilkinson notation ('Formulas',
%   a struct array of .bin (the label) and .formula): 'y ~ 1' when none is
%   given, which is one waveform per bin and nothing else, or anything
%   uf_designmat accepts, such as
%       y ~ 1 + cat(emotion)
%       y ~ 1 + spl(sac_amplitude, 5) + circspl(sac_angle, 5, 0, 360)
%       y ~ 1 + 2dspl(fix_avgpos_x, fix_avgpos_y, 5)
%   A formula may be written without its 'y ~'. The bins decide WHICH events
%   an event type holds (DefineBins' language, which Unfold's own
%   eventtypes cannot express); the formula decides what explains their
%   response. Every field a formula names is checked against the bin's own
%   events before the toolbox sees it (checkVariables), since uf_designmat's
%   own message for a misspelt field is "Function is not defined for 'cell'
%   inputs". Events in no bin are fitted with 'y ~ 1'.
%
%   'Covariates', the older option, still works for templates that carry
%   it: each field in it becomes a term of every event type without a
%   formula of its own, nuisance types included as they always were, whose
%   events all carry a varying value for it (legacyTerms).
%
%   See also UNFOLD.FITBINS, UNFOLD.OTHEREVENTSCHOICE, UNFOLD.EVENTCOVARIATES,
%   DEFINEBINS, AVERAGE.
    parsed = inputParser();
    parsed.addParameter('OtherEvents', 'all', @(v) isempty(v) || ischar(v) || iscellstr(v) || isstring(v));
    parsed.addParameter('Covariates', {}, @(v) isempty(v) || iscellstr(v) || isstring(v));
    parsed.addParameter('Formulas', [], @(v) isempty(v) || isstruct(v));
    parsed.addParameter('MissingValues', 'refuse', @(v) (ischar(v) || isstring(v)) && ...
        any(strcmpi(char(string(v)), {'refuse', 'median', 'mean', 'marginal', 'drop'})));
    parsed.parse(varargin{:});
    missingValues = lower(char(string(parsed.Results.MissingValues)));
    choice.otherEvents = parsed.Results.OtherEvents;
    otherCodes = Unfold.otherEventsChoice(choice);
    wanted = cellstr(string(parsed.Results.Covariates));

    validateInput(EEG);

    bindesc = EEG.bindesc;
    isCombo = false(1, numel(bindesc));
    if isfield(bindesc, 'combo')
        isCombo = ~cellfun(@isempty, {bindesc.combo});
    end
    ordinary = find(~isCombo);

    plan = struct();
    plan.comboBins = find(isCombo);
    plan.binIndex = [bindesc(ordinary).index];
    plan.binLabels = cellstr(string({bindesc(ordinary).label}));
    plan.binTypes = uniqueTypes('bin_', plan.binLabels);
    plan.notes = {};

    membership = binMembership(EEG, plan.binIndex);
    plan.membership = membership;
    plan.binCounts = cellfun(@numel, membership);

    [plan.cellBins, eventCell] = binCombinations(membership, numel(EEG.event));
    plan.cellCounts = arrayfun(@(c) nnz(eventCell == c), 1:numel(plan.cellBins));
    plan.cellTypes = cellTypeNames(plan.cellBins, plan.binTypes);
    plan.cellLabels = cellfun(@(bins) strjoin(plan.binLabels(bins), ' & '), plan.cellBins, ...
        'UniformOutput', false);
    plan.binCells = arrayfun(@(k) find(cellfun(@(bins) any(bins == k), plan.cellBins)), ...
        1:numel(membership), 'UniformOutput', false);

    [plan.events, plan.nuisanceTypes, plan.unbinnedCodes, otherNotes, plan.eventSource] = ...
        rewriteEvents(EEG, eventCell, plan.cellTypes, otherCodes);
    plan.notes = [plan.notes, otherNotes];

    empty = plan.binCounts == 0;
    if any(empty)
        % The same lesson RESS learned: a bin with no events in THIS recording
        % is a fact about the recording, not a broken analysis, so it is named
        % and dropped from the model rather than stopping the run.
        plan.notes{end + 1} = sprintf(['%s %s no events in this recording, so %s left out of the ' ...
            'model and will be empty in the result.'], listOf(plan.binLabels(empty)), ...
            plural(nnz(empty), 'has', 'have'), plural(nnz(empty), 'it is', 'they are'));
    end
    plan.notes = [plan.notes, sharedEventsNotes(plan)];

    latencies = arrayfun(@(c) double([EEG.event(eventCell == c).latency]), ...
        1:numel(plan.cellBins), 'UniformOutput', false);
    plan.notes = [plan.notes, fixedLagNotes(latencies, plan.cellLabels, 1:numel(plan.cellBins))];

    plan.eventTypes = [plan.cellTypes, plan.nuisanceTypes];
    plan.typeLabels = [plan.cellLabels, cellstr(string({plan.unbinnedCodes([plan.unbinnedCodes.modelled]).code}))];
    plan.formulas = repmat({'y ~ 1'}, 1, numel(plan.eventTypes));
    explicit = false(1, numel(plan.eventTypes));
    for c = 1:numel(plan.cellTypes)
        [plan.formulas{c}, explicit(c), note] = sharedFormula(parsed.Results.Formulas, ...
            plan.binLabels(plan.cellBins{c}));
        plan.notes = [plan.notes, note];
    end
    [plan.formulas, legacyNotes] = legacyTerms(plan.formulas, ~explicit, ...
        plan.events, plan.eventSource, plan.eventTypes, EEG, wanted);
    plan.notes = [plan.notes, legacyNotes];
    [plan.events, plan.missing, absentRows] = checkVariables(plan.events, plan.eventSource, ...
        plan.eventTypes, plan.typeLabels, plan.formulas, EEG, missingValues);
    plan.missingValues = missingValues;
    plan.notes = [plan.notes, missingNotes(plan.missing, missingValues)];
    plan.kept = true(1, numel(plan.events));
    if strcmp(missingValues, 'drop')
        plan = withoutDropped(plan, absentRows);
    end
    plan.variables = cellfun(@formulaVariables, plan.formulas, 'UniformOutput', false);
    plan.pooled = pooledValues(plan.events(plan.kept), plan.eventTypes, plan.formulas);
end

function plan = withoutDropped(plan, dropped)
%WITHOUTDROPPED  The plan without the events uf_imputeMissing's 'drop' will
%   leave out: those missing a number their formula uses, whose rows of the
%   design it zeroes (Unfold.fitBins checks it zeroed exactly these). They
%   stay in .events, as the toolbox keeps them in EEG.event, but are not
%   .kept: not in a bin's count, its events or its trials, nor among the
%   values its waveform is held at.
    plan.kept = ~dropped;
    gone = plan.eventSource(dropped);
    for k = 1:numel(plan.membership)
        plan.membership{k} = setdiff(plan.membership{k}, gone, 'stable');
    end
    plan.binCounts = cellfun(@numel, plan.membership);
    plan.cellCounts = cellfun(@(type) nnz(strcmp({plan.events.type}, type) & plan.kept), plan.cellTypes);
end

function notes = missingNotes(missing, method)
%MISSINGNOTES  What will happen to the events without a value, per field.
    notes = {};
    if isempty(missing)
        return;
    end
    what = sprintf('filled in by the Unfold toolbox''s uf_imputeMissing (''%s'')', method);
    if strcmp(method, 'drop')
        what = ['left out of the model by the Unfold toolbox''s uf_imputeMissing (''drop''), ' ...
            'so they are not overlap-corrected either'];
    end
    parts = arrayfun(@(m) sprintf('%d of the %d events of "%s" have no value for "%s"', ...
        m.n, m.of, m.label, m.field), missing, 'UniformOutput', false);
    notes = {sprintf('%s: %s.', strjoin(parts, '; '), what)};
end

% ======================================================================= %
function [sets, eventCell] = binCombinations(membership, nevents)
%BINCOMBINATIONS  The distinct sets of ordinary bins the events belong to,
%   in order (a set of one bin sorts where that bin is, so bins that share
%   nothing keep their own order), and for each row of EEG.event the set it
%   is in, 0 for an event in no bin.
    inBin = false(nevents, numel(membership));
    for k = 1:numel(membership)
        inBin(membership{k}, k) = true;
    end
    binned = find(any(inBin, 2));
    eventCell = zeros(1, nevents);
    sets = {};
    if isempty(binned)
        return;
    end
    [patterns, ~, patternOf] = unique(inBin(binned, :), 'rows');
    sets = arrayfun(@(r) find(patterns(r, :)), 1:size(patterns, 1), 'UniformOutput', false);
    keys = cellfun(@(s) [s, zeros(1, numel(membership) - numel(s))], sets, 'UniformOutput', false);
    [~, order] = sortrows(cat(1, keys{:}));
    sets = sets(order);
    position = zeros(1, numel(order));
    position(order) = 1:numel(order);
    eventCell(binned) = position(patternOf);
end

function types = cellTypeNames(sets, binTypes)
%CELLTYPENAMES  The event type of each set of bins: the bin's own type for a
%   set of one, so a model whose bins share nothing names its types exactly
%   as before, and the bins' names joined for a shared set, numbered if that
%   happens to be taken.
    types = cell(1, numel(sets));
    for c = 1:numel(sets)
        if isscalar(sets{c})
            types{c} = binTypes{sets{c}};
        else
            types{c} = ['bin_' strjoin(regexprep(binTypes(sets{c}), '^bin_', ''), '_and_')];
        end
    end
    for c = 1:numel(types)
        if ~isscalar(sets{c}) && nnz(strcmp(types, types{c})) > 1
            types{c} = sprintf('%s_%d', types{c}, c);
        end
    end
end

function notes = sharedEventsNotes(plan)
%SHAREDEVENTSNOTES  Which bins share events, and what was done about it.
    notes = {};
    shared = find(cellfun(@numel, plan.cellBins) > 1);
    if isempty(shared)
        return;
    end
    parts = arrayfun(@(c) sprintf('%s share %d event(s)', listOf(plan.binLabels(plan.cellBins{c})), ...
        plan.cellCounts(c)), shared, 'UniformOutput', false);
    notes = {sprintf(['%s. As Average does, each event counts fully in every bin it belongs ' ...
        'to: the events of each set of bins are fitted as one event type (%s), and a bin''s ' ...
        'waveform is the average over its own events of those types'' responses.'], ...
        strjoin(parts, '; '), listOf(plan.cellLabels(shared)))};
end

function [formula, given, notes] = sharedFormula(formulas, labels)
%SHAREDFORMULA  The formula of the events in the bins LABELS: the bin's own
%   for one bin; for events several bins share, the one formula they all
%   have, or else every term any of them has, since those events are in each
%   of the bins and each formula says what explains them.
    notes = {};
    [each, written] = cellfun(@(label) formulaFor(formulas, label), labels, 'UniformOutput', false);
    given = any([written{:}]);
    formula = each{1};
    if isscalar(each) || isscalar(unique(regexprep(each, '\s', '')))
        return;
    end
    terms = {};
    keys = {};
    for k = 1:numel(each)
        rhs = strtrim(regexprep(each{k}, '^[^~]*~', ''));
        if numel(topLevelSplit(rhs, '-')) > 1
            throw(MException('Alakazam:Unfold:SharedFormula', '%s', sprintf([ ...
                '%s share events, which are fitted as one event type with every term of their ' ...
                'formulas, and a formula that takes a term out with "-" (%s) cannot be merged ' ...
                'with the others. Would you give these bins the same formula?'], ...
                listOf(labels), each{k})));
        end
        for part = topLevelSplit(rhs, '+')
            key = regexprep(part{1}, '\s', '');
            if ~isempty(key) && ~ismember(key, keys)
                keys{end + 1} = key; %#ok<AGROW>
                terms{end + 1} = strtrim(part{1}); %#ok<AGROW>
            end
        end
    end
    formula = ['y ~ ' strjoin(terms, ' + ')];
    notes = {sprintf('The events %s share are fitted with the terms of all their formulas: %s.', ...
        listOf(labels), formula)};
end

function parts = topLevelSplit(text, separator)
%TOPLEVELSPLIT  TEXT split at SEPARATOR wherever it is outside parentheses,
%   so "1 + spl(x, 5) + cat(a)" is three terms and the commas and numbers
%   inside a term stay with it.
    parts = {};
    depth = 0;
    start = 1;
    for k = 1:numel(text)
        switch text(k)
            case '('
                depth = depth + 1;
            case ')'
                depth = depth - 1;
            case separator
                if depth == 0
                    parts{end + 1} = text(start:k - 1); %#ok<AGROW>
                    start = k + 1;
                end
        end
    end
    parts{end + 1} = text(start:end);
end

% ======================================================================= %
function pooled = pooledValues(events, eventTypes, formulas)
%POOLEDVALUES  For each continuous or spline field any formula uses, its
%   values over every modelled event whose type uses it: the common ground
%   Unfold.fitBins evaluates every bin's waveform on, so that a covariate
%   whose values differ between bins is held at the same values for all of
%   them rather than at each bin's own (see Unfold.fitBins). Factors are
%   not pooled: each bin keeps its own mix of levels. .common is the range
%   of values every type using the field shares, [] when they share none:
%   a spline is only evaluated there, since outside a bin's own values it
%   would be extrapolating.
%
%   A 2D SPLINE (2dspl(x, z, n)) is evaluated at both fields at once, so it
%   gets an entry of its own: named as the toolbox names it, the two field
%   names run together ("xz"), with .pair {x, z}, .values the pairs of every
%   event that uses it (2 x n, from the same events), and .common a 2 x 2
%   box, each row the range of one field every type using it shares.
    pooled = struct('name', {}, 'values', {}, 'common', {}, 'pair', {});
    for t = 1:numel(eventTypes)
        rows = strcmp({events.type}, eventTypes{t});
        [vars, pairs] = formulaVariables(formulas{t});
        for v = vars
            if v.categorical
                continue;
            end
            pooled = addPooled(pooled, v.name, [events(rows).(v.name)], {});
        end
        for p = pairs
            pooled = addPooled(pooled, [p{1}{:}], ...
                [[events(rows).(p{1}{1})]; [events(rows).(p{1}{2})]], p{1});
        end
    end
end

function pooled = addPooled(pooled, name, values, pair)
%ADDPOOLED  VALUES (one row per field) added to the entry NAME of the same
%   kind (a field, or a 2D spline's PAIR), and the range every type using it
%   shares narrowed to the values of this one. A missing value (NaN, before
%   uf_imputeMissing fills it in) is not a value of the field, so it is
%   left out, and a pair with one missing is left out whole.
    values = values(:, all(isfinite(values), 1));
    span = [min(values, [], 2), max(values, [], 2)];
    at = find(strcmp({pooled.name}, name) & cellfun(@isempty, {pooled.pair}) == isempty(pair), 1);
    if isempty(at)
        pooled(end + 1) = struct('name', name, 'values', values, 'common', span, 'pair', {pair});
        return;
    end
    pooled(at).values = [pooled(at).values, values];
    common = pooled(at).common;
    if ~isempty(common)
        common = [max(common(:, 1), span(:, 1)), min(common(:, 2), span(:, 2))];
        if any(common(:, 1) > common(:, 2))
            common = [];
        end
    end
    pooled(at).common = common;
end

% ======================================================================= %
function [formula, given] = formulaFor(formulas, label)
%FORMULAFOR  The formula written for the bin LABEL, as 'y ~ ...', or 'y ~ 1'
%   when there is none. A formula written without its left-hand side is
%   given one, so "1 + spl(x, 5)" and "y ~ 1 + spl(x, 5)" mean the same.
    formula = 'y ~ 1';
    given = false;
    if isempty(formulas) || ~isfield(formulas, 'bin') || ~isfield(formulas, 'formula')
        return;
    end
    hit = find(strcmp(cellstr(string({formulas.bin})), label), 1);
    if isempty(hit)
        return;
    end
    text = strtrim(char(string(formulas(hit).formula)));
    if isempty(text)
        return;
    end
    if ~contains(text, '~')
        text = ['y ~ ' text];
    end
    formula = text;
    given = true;
end

function [formulas, notes] = legacyTerms(formulas, open, events, source, eventTypes, EEG, wanted)
%LEGACYTERMS  The older 'Covariates' option as formula terms: each field a
%   term of every bin in OPEN (no formula of its own) whose events all carry
%   a value for it that varies. A field some bin lacks is left out of that
%   bin and named in the notes, as it always was.
    notes = {};
    if isempty(wanted) || isempty(events)
        return;
    end
    types = {events.type};
    for w = 1:numel(wanted)
        name = wanted{w};
        if ~isfield(EEG.event, name)
            notes{end + 1} = sprintf(['The covariate "%s" is not a field of this recording''s ' ...
                'events, so it was left out of the model.'], name); %#ok<AGROW>
            continue;
        end
        values = numericValues(EEG.event(source), name);
        usable = {};
        for t = find(open)
            rows = strcmp(types, eventTypes{t});
            v = values(rows);
            if any(rows) && all(isfinite(v)) && any(v ~= v(1))
                formulas{t} = [formulas{t} ' + ' name];
                usable{end + 1} = eventTypes{t}; %#ok<AGROW>
            end
        end
        missing = setdiff(eventTypes(open), usable, 'stable');
        if isempty(usable)
            notes{end + 1} = sprintf(['No event type has "%s" varying across all of its events, ' ...
                'so it could not be used as a covariate anywhere in this model.'], name); %#ok<AGROW>
        elseif ~isempty(missing)
            notes{end + 1} = sprintf(['The covariate "%s" was fitted for %s, but not for %s, ' ...
                'whose events either do not all carry a value for it or all carry the same ' ...
                'one, which cannot be told apart from their own waveform.'], name, ...
                listOf(usable), listOf(missing)); %#ok<AGROW>
        end
    end
end

function [events, missing, absentRows] = checkVariables(events, source, eventTypes, typeLabels, formulas, EEG, missingValues)
%CHECKVARIABLES  Every field a formula names, checked against the events it
%   will be read from, and copied onto them.
%
%   Unfold reads a formula's fields from EEG.event: a categorical one
%   (cat(x)) as a string or number per event, anything else as one number.
%   The events here are the rewritten list, which keeps only .latency and
%   .type, so each field is copied across from the event each row was made
%   from (SOURCE), by row rather than by latency, since two events can share
%   a sample. A row of a type whose formula does not use the field gets a
%   placeholder (0, or '' for a categorical one) that Unfold never reads.
%
%   A MISSING NUMBER is passed on as NaN, as uf_designmat itself passes it,
%   for the toolbox's uf_imputeMissing to fill in or drop (MISSINGVALUES, see
%   Unfold.fitBins); with MISSINGVALUES 'refuse' it is refused instead.
%   MISSING lists each field with missing numbers: .label (the bin or code),
%   .field, .n missing, .of events. ABSENTROWS marks the rows of EVENTS that
%   miss at least one number their formula uses.
%
%   REFUSED, each with the bin named: a field the recording does not have; a
%   factor some event has no level of, which uf_designmat cannot build and
%   uf_imputeMissing cannot fill (it fills numbers); a field no event has a
%   number for; and a field that has only one value across the bin (one
%   level of a factor, or one number). The last is the one that bites in
%   practice: EYE-EEG fills every field that does not apply with 0 (each
%   fixation carries sac_amplitude = 0), and a term that never varies is a
%   copy of the bin's own intercept, which the solver then splits
%   arbitrarily.
    missing = struct('label', {}, 'field', {}, 'n', {}, 'of', {});
    absentRows = false(1, numel(events));
    for t = 1:numel(eventTypes)
        rows = find(strcmp({events.type}, eventTypes{t}));
        for v = formulaVariables(formulas{t})
            if ~isfield(EEG.event, v.name)
                throw(MException('Alakazam:Unfold:NoSuchField', '%s', sprintf([ ...
                    'The formula for "%s" (%s) uses "%s", which is not a field of this ' ...
                    'recording''s events. The fields are: %s.'], typeLabels{t}, formulas{t}, ...
                    v.name, strjoin(fieldnames(EEG.event)', ', '))));
            end
            if v.categorical
                values = arrayfun(@(s) levelOf(EEG.event(s).(v.name)), source(rows), 'UniformOutput', false);
                if any(cellfun(@isempty, values))
                    throw(MException('Alakazam:Unfold:MissingValue', '%s', sprintf([ ...
                        '%d of the %d events of "%s" have no value for "%s", which its formula ' ...
                        'treats as a factor (cat(%s)). The Unfold toolbox cannot build a factor ' ...
                        'with an event that has no level of it (uf_designmat), and its ' ...
                        'uf_imputeMissing fills in numbers, not levels. Would you give those ' ...
                        'events a level, or leave the factor out of this bin''s formula?'], ...
                        nnz(cellfun(@isempty, values)), numel(values), typeLabels{t}, v.name, v.name)));
                end
                if numel(unique(values)) < 2
                    throw(MException('Alakazam:Unfold:OneLevel', '%s', sprintf([ ...
                        'Every event of "%s" has the same "%s" (%s), so cat(%s) has nothing to ' ...
                        'compare: one level is the bin''s own intercept.'], typeLabels{t}, ...
                        v.name, values{1}, v.name)));
                end
                for k = 1:numel(rows)
                    events(rows(k)).(v.name) = EEG.event(source(rows(k))).(v.name);
                end
            else
                values = numericValues(EEG.event(source(rows)), v.name);
                absent = ~isfinite(values);
                if all(absent)
                    throw(MException('Alakazam:Unfold:MissingValue', '%s', sprintf([ ...
                        'None of the %d events of "%s" has a number for "%s", which its formula ' ...
                        'uses, so there is nothing to fit it from.'], numel(values), typeLabels{t}, v.name)));
                end
                if any(absent) && strcmp(missingValues, 'refuse')
                    throw(MException('Alakazam:Unfold:MissingValue', '%s', sprintf([ ...
                        '%d of the %d events of "%s" have no number for "%s", which its formula ' ...
                        'uses. The Unfold toolbox can fill them in or leave those events out ' ...
                        '(uf_imputeMissing): would you choose how under Missing values, or give ' ...
                        'those events a value?'], nnz(absent), numel(values), typeLabels{t}, v.name)));
                end
                known = values(~absent);
                if all(known == known(1))
                    throw(MException('Alakazam:Unfold:NeverVaries', '%s', sprintf([ ...
                        'Every event of "%s" has "%s" = %g, so the term cannot be told apart from ' ...
                        'the bin''s own waveform. (EYE-EEG fills each field that does not apply ' ...
                        'with 0: a fixation''s sac_amplitude, a saccade''s fix_avgpos_x.)'], ...
                        typeLabels{t}, v.name, known(1))));
                end
                if any(absent)
                    missing(end + 1) = struct('label', typeLabels{t}, 'field', v.name, ...
                        'n', nnz(absent), 'of', numel(values)); %#ok<AGROW>
                    absentRows(rows(absent)) = true;
                end
                for k = 1:numel(rows)
                    events(rows(k)).(v.name) = values(k);   % NaN where it is missing
                end
            end
        end
    end
    events = fillPlaceholders(events);
end

function events = fillPlaceholders(events)
%FILLPLACEHOLDERS  0 in a numeric field, '' in a text one, wherever a row
%   was not given a value (its type's formula does not use that field).
    for name = setdiff(fieldnames(events)', {'latency', 'type'})
        values = {events.(name{1})};
        isText = cellfun(@(v) ischar(v) || isstring(v), values);
        blank = cellfun(@isempty, values);
        filler = 0;
        if any(isText)
            filler = '';
        end
        [events(blank).(name{1})] = deal(filler);
    end
end

function [vars, pairs] = formulaVariables(formula)
%FORMULAVARIABLES  The event fields a formula names, whether each is a
%   factor (inside cat()) and whether it is a spline's (inside spl(),
%   circspl() or 2dspl()). Everything that is a name and not one of Unfold's
%   term functions, or the response y, is a field. A name has to start the
%   word: Unfold spells its 2D spline 2dspl, which once read as a field
%   called "dspl". PAIRS lists each 2dspl's two fields, {x, z}, in order.
    rhs = regexprep(formula, '^[^~]*~', '');
    names = unique(regexp(rhs, '(?<![\w.])[A-Za-z_]\w*', 'match'), 'stable');
    % A row, even when empty: a 0x1 list would still take one turn of a for
    % loop over its columns.
    names = reshape(setdiff(names, {'y', 'cat', 'spl', 'circspl'}, 'stable'), 1, []);
    factors = cellfun(@(t) t{1}, regexp(rhs, '(?<!\w)cat\s*\(\s*([A-Za-z_]\w*)', 'tokens'), ...
        'UniformOutput', false);
    splines = cellfun(@(t) t{1}, regexp(rhs, '(?<!\w)(?:spl|circspl)\s*\(\s*([A-Za-z_]\w*)', 'tokens'), ...
        'UniformOutput', false);
    pairs = regexp(rhs, '(?<!\w)2dspl\s*\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)', 'tokens');
    surfaces = [pairs{:}];
    vars = struct('name', names, 'categorical', num2cell(ismember(names, factors)), ...
        'spline', num2cell(ismember(names, [splines, surfaces])));
end

function level = levelOf(value)
%LEVELOF  A factor level as text, '' when there is none.
    level = '';
    if ischar(value) || isstring(value)
        level = strtrim(char(value));
    elseif isnumeric(value) && isscalar(value) && isfinite(value)
        level = num2str(value);
    end
end

function values = numericValues(events, name)
%NUMERICVALUES  One number per event from its field NAME, NaN where it is not
%   one number.
    values = nan(1, numel(events));
    for k = 1:numel(events)
        v = events(k).(name);
        if isnumeric(v) && isscalar(v) && ~islogical(v)
            values(k) = double(v);
        end
    end
end

% ======================================================================= %
function validateInput(EEG)
%VALIDATEINPUT  The three things this cannot work without, each named.
%   Bin tags are one of them, but a dataset arriving here without them is not
%   necessarily a mistake by the user: Deconvolve defines its own bins and
%   tags the recording (with DefineBins, tags only, no epoching) before
%   calling this, so these two messages are for a caller that skipped that
%   step, and they say where the tagging comes from rather than sending
%   anyone back to a node that cannot exist.
    Unfold.requireContinuous(EEG);
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
        throw(MException('Alakazam:Unfold:NoBins', ...
            ['This dataset has no bins, so there is nothing to deconvolve into, I''m ' ...
             'afraid. Deconvolve normally asks for them itself and tags the recording ' ...
             'before it fits, so reaching this message means it was given a dataset ' ...
             'with neither bins of its own nor a bin definition to apply. Would you ' ...
             'either run Deconvolve interactively, so it can ask, or pass a .binScript ' ...
             'in its options?']));
    end
    if ~isfield(EEG, 'event') || isempty(EEG.event) || ~isfield(EEG.event, 'bini')
        throw(MException('Alakazam:Unfold:NoBinTags', ...
            ['This dataset has bins but its events carry no bin membership (no .bini ' ...
             'field), so there is no way to tell which event belongs to which bin. ' ...
             'That tagging is DefineBins'' own output, which Deconvolve applies for ' ...
             'itself; re-running either of them should restore it.']));
    end
end

function membership = binMembership(EEG, binIndex)
%BINMEMBERSHIP  The event rows belonging to each ordinary bin.
%   DefineBins writes ERPLAB-style .bini: the INDEX values of the bins an
%   event belongs to, which is not the same as their position in bindesc, so
%   the index is matched rather than the position.
    membership = cell(1, numel(binIndex));
    bini = {EEG.event.bini};
    for b = 1:numel(binIndex)
        membership{b} = find(cellfun(@(v) any(v == binIndex(b)), bini));
    end
end

function [events, nuisanceTypes, unbinned, notes, source] = rewriteEvents(EEG, eventCell, cellTypes, otherCodes)
%REWRITEEVENTS  The event list in the model's own terms.
%   One row per binned event, typed by the set of bins it is in (EVENTCELL,
%   CELLTYPES: see binCombinations), plus one row per unbinned event whose
%   code was chosen for modelling. Only .latency and .type are kept: they are
%   what uf_designmat reads, and carrying the rest would invite a field name
%   to collide with a predictor.
%
%   AN EVENT IN TWO BINS IS ONE ROW, one stick, of the type of the pair of
%   bins. It used to be one row per bin, two sticks at the same latency,
%   which explained its data as the SUM of two responses, unlike Average
%   (see this file's header).
%
%   UNBINNED lists every code that occurs outside the bins (boundaries
%   excepted), with its count and whether it was modelled, in order of first
%   appearance; NOTES name the codes left out and any code that was asked for
%   but does not occur here, which is what a replay onto another recording
%   runs into. SOURCE gives, for each row of EVENTS, the row of EEG.event it
%   came from; it is kept beside the list rather than in it for the reason
%   above.
    events = struct('latency', {}, 'type', {});
    source = zeros(1, 0);
    for k = find(eventCell > 0)
        events(end + 1) = struct('latency', EEG.event(k).latency, ...
            'type', cellTypes{eventCell(k)}); %#ok<AGROW>
        source(end + 1) = k; %#ok<AGROW>
    end

    others = find(eventCell == 0);
    % A boundary is EEGLAB's marker for a cut in the recording, not a thing
    % the brain responded to, and modelling it would fit a response to the
    % editing. It is not even offered.
    rawTypes = arrayfun(@(e) char(string(e.type)), EEG.event(others), 'UniformOutput', false);
    keep = ~strcmpi(rawTypes, 'boundary');
    others = others(keep);
    rawTypes = rawTypes(keep);

    distinct = unique(rawTypes, 'stable');
    counts = cellfun(@(c) nnz(strcmp(rawTypes, c)), distinct);
    if ischar(otherCodes)           % 'all'
        chosen = true(1, numel(distinct));
    else
        chosen = ismember(distinct, otherCodes);
    end
    unbinned = struct('code', distinct, 'n', num2cell(counts), 'modelled', num2cell(chosen));

    nuisanceTypes = uniqueTypes('evt_', distinct(chosen));
    modelledCodes = distinct(chosen);
    for k = 1:numel(others)
        hit = strcmp(modelledCodes, rawTypes{k});
        if any(hit)
            events(end + 1) = struct('latency', EEG.event(others(k)).latency, ...
                'type', nuisanceTypes{hit}); %#ok<AGROW>
            source(end + 1) = others(k); %#ok<AGROW>
        end
    end

    notes = {};
    left = ~chosen;
    if any(left)
        notes{end + 1} = sprintf(['%d event(s) in no bin were left out of the model (%s), so ' ...
            'wherever they overlap a bin their responses are still in its waveform.'], ...
            sum(counts(left)), codeList(distinct(left), counts(left)));
    end
    if iscell(otherCodes)
        absent = setdiff(otherCodes, distinct, 'stable');
        if ~isempty(absent)
            notes{end + 1} = sprintf(['%s %s chosen for modelling but %s not occur outside the ' ...
                'bins in this recording.'], listOf(absent), ...
                plural(numel(absent), 'was', 'were'), plural(numel(absent), 'does', 'do'));
        end
    end

    if ~isempty(events)
        [~, order] = sort([events.latency]);
        events = events(order);
        source = source(order);
    end
end

function text = codeList(codes, counts)
%CODELIST  "201 x110, 211 x1" for a note.
    parts = arrayfun(@(k) sprintf('%s x%d', codes{k}, counts(k)), 1:numel(codes), ...
        'UniformOutput', false);
    text = strjoin(parts, ', ');
end

function types = uniqueTypes(prefix, labels)
%UNIQUETYPES  A usable Unfold event-type name per label.
%   Bin labels are free text ("RIFT 60Hz", "target/rare"), and the type
%   becomes a column name in the design matrix, so it is reduced to word
%   characters. The prefix keeps bins and nuisance events in separate
%   namespaces, so a bin called "response" cannot collide with an event type
%   called "response", and a label that reduces to nothing still gets a name.
    types = cell(1, numel(labels));
    for k = 1:numel(labels)
        stem = regexprep(char(string(labels{k})), '\W+', '_');
        stem = regexprep(stem, '^_+|_+$', '');
        if isempty(stem)
            stem = sprintf('%d', k);
        end
        types{k} = [prefix stem];
    end
    % Two labels can reduce to the same stem ("a/b" and "a b"); numbering the
    % repeats keeps the mapping back to labels one-to-one.
    for k = 1:numel(types)
        same = find(strcmp(types, types{k}));
        if numel(same) > 1 && same(1) ~= k
            types{k} = sprintf('%s_%d', types{k}, find(same == k));
        end
    end
end

function notes = fixedLagNotes(latencies, labels, usable)
%FIXEDLAGNOTES  Pairs whose timing never varies, which is the other way a
%   deconvolution fails to identify two responses. Deconvolution works by
%   seeing the same response at different offsets; two event types that are
%   always the same distance apart never provide that, so their waveforms
%   are estimated as a pair and cannot be attributed separately.
    notes = {};
    for a = 1:numel(usable)
        for b = a + 1:numel(usable)
            lagA = nearestLags(latencies{usable(a)}, latencies{usable(b)});
            lagB = nearestLags(latencies{usable(b)}, latencies{usable(a)});
            if numel(lagA) < 2 || any(isnan(lagA)) || any(isnan(lagB))
                continue;
            end
            % Constant in BOTH directions, which is what makes the pair
            % unidentifiable. One direction alone is not enough: if some
            % events of one bin have no partner in the other, those lone
            % events are precisely the leverage the fit uses to tell the two
            % responses apart, and the design is fine.
            if range(lagA) == 0 && range(lagB) == 0
                notes{end + 1} = sprintf( ...
                    ['Every event of "%s" is exactly %g samples from one of "%s". ' ...
                     'Deconvolution separates responses by seeing them at different ' ...
                     'offsets, so with a lag that never varies these two waveforms are ' ...
                     'not identified apart: read them as one joint response.'], ...
                    labels{usable(a)}, lagA(1), labels{usable(b)}); %#ok<AGROW>
            end
        end
    end
end

function lags = nearestLags(latenciesA, latenciesB)
%NEARESTLAGS  For each event of A, the signed distance to the nearest event
%   of B, in samples. Nearest by absolute distance, and signed, so a B that
%   always follows A by the same amount reads as one constant lag rather
%   than two alternating ones.
    if isempty(latenciesA) || isempty(latenciesB)
        lags = NaN;
        return;
    end
    lags = arrayfun(@(a) pickNearest(latenciesB - a), latenciesA);
end

function lag = pickNearest(differences)
    [~, at] = min(abs(differences));
    lag = differences(at);
end

function s = listOf(labels)
    labels = cellfun(@(l) ['"' char(string(l)) '"'], labels, 'UniformOutput', false);
    if isscalar(labels)
        s = labels{1};
    else
        s = [strjoin(labels(1:end - 1), ', ') ' and ' labels{end}];
    end
end

function s = plural(n, one, many)
    if n == 1
        s = one;
    else
        s = many;
    end
end
