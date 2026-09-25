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
%   WHAT IT REFUSES, and why it is worth refusing rather than fitting: two
%   bins holding exactly the same events are perfectly collinear. No amount
%   of deconvolution separates them, the solver will still return something,
%   and that something is arbitrary. Deconvolution can only separate two
%   event types where their timing varies relative to each other, so a pair
%   at a fixed lag in every trial (a stimulus and a response exactly 500 ms
%   later, say) is reported as a note: the fit will run, but the two
%   waveforms are not identified apart and the reader has to know.
%
%   PLAN fields: .binLabels, .binTypes, .binIndex, .binCounts (per ordinary
%   bin, in bindesc order), .membership (per ordinary bin, the rows of
%   EEG.event it holds), .comboBins (indices of combination bins, computed
%   after the fit), .eventTypes and .formulas (what uf_designmat is given),
%   .typeLabels (the bin label or event code each type stands for),
%   .pooled (each continuous or spline field's values over every event
%   whose formula uses it, which the bin waveforms are evaluated on),
%   .nuisanceTypes, .events (the rewritten event list), .eventSource (for
%   each row of .events, the row of EEG.event it was made from, which is how
%   an event in two bins is still known to be one trial) and .notes.
%
%   EACH BIN HAS A FORMULA, in Unfold's own Wilkinson notation ('Formulas',
%   a struct array of .bin (the label) and .formula): 'y ~ 1' when none is
%   given, which is one waveform per bin and nothing else, or anything
%   uf_designmat accepts, such as
%       y ~ 1 + cat(emotion)
%       y ~ 1 + spl(sac_amplitude, 5) + circspl(sac_angle, 5, 0, 360)
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
    parsed.parse(varargin{:});
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

    [plan.events, plan.nuisanceTypes, plan.unbinnedCodes, otherNotes, plan.eventSource] = ...
        rewriteEvents(EEG, membership, plan.binTypes, otherCodes);
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

    refuseIdenticalBins(membership, plan.binLabels, ~empty);
    latencies = cellfun(@(rows) double([EEG.event(rows).latency]), membership, 'UniformOutput', false);
    plan.notes = [plan.notes, fixedLagNotes(latencies, plan.binLabels, find(~empty))];

    plan.eventTypes = [plan.binTypes(~empty), plan.nuisanceTypes];
    plan.typeLabels = [plan.binLabels(~empty), cellstr(string({plan.unbinnedCodes([plan.unbinnedCodes.modelled]).code}))];
    plan.formulas = repmat({'y ~ 1'}, 1, numel(plan.eventTypes));
    fitted = find(~empty);
    explicit = false(1, numel(plan.eventTypes));
    for k = 1:numel(fitted)
        [plan.formulas{k}, explicit(k)] = formulaFor(parsed.Results.Formulas, plan.binLabels{fitted(k)});
    end
    [plan.formulas, legacyNotes] = legacyTerms(plan.formulas, ~explicit, ...
        plan.events, plan.eventSource, plan.eventTypes, EEG, wanted);
    plan.notes = [plan.notes, legacyNotes];
    plan.events = checkVariables(plan.events, plan.eventSource, plan.eventTypes, plan.typeLabels, ...
        plan.formulas, EEG);
    plan.pooled = pooledValues(plan.events, plan.eventTypes, plan.formulas);
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
    pooled = struct('name', {}, 'values', {}, 'common', {});
    for t = 1:numel(eventTypes)
        rows = strcmp({events.type}, eventTypes{t});
        for v = formulaVariables(formulas{t})
            if v.categorical
                continue;
            end
            values = [events(rows).(v.name)];
            at = find(strcmp({pooled.name}, v.name), 1);
            if isempty(at)
                pooled(end + 1) = struct('name', v.name, 'values', values, ...
                    'common', [min(values) max(values)]); %#ok<AGROW>
            else
                pooled(at).values = [pooled(at).values, values];
                common = pooled(at).common;
                if ~isempty(common)
                    common = [max(common(1), min(values)), min(common(2), max(values))];
                    if common(1) > common(2)
                        common = [];
                    end
                end
                pooled(at).common = common;
            end
        end
    end
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

function events = checkVariables(events, source, eventTypes, typeLabels, formulas, EEG)
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
%   REFUSED, each with the bin named: a field the recording does not have; a
%   continuous field some event lacks a number for; and a field that has
%   only one value across the bin (one level of a factor, or one number).
%   The last is the one that bites in practice: EYE-EEG fills every field
%   that does not apply with 0 (each fixation carries sac_amplitude = 0), and
%   a term that never varies is a copy of the bin's own intercept, which the
%   solver then splits arbitrarily.
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
                        'Some events of "%s" have no value for "%s", which its formula treats as ' ...
                        'a factor (cat(%s)).'], typeLabels{t}, v.name, v.name)));
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
                if ~all(isfinite(values))
                    throw(MException('Alakazam:Unfold:MissingValue', '%s', sprintf([ ...
                        '%d of the %d events of "%s" have no number for "%s", which its formula ' ...
                        'uses. Unfold needs a value on every event of a type whose formula ' ...
                        'names a field.'], nnz(~isfinite(values)), numel(values), typeLabels{t}, v.name)));
                end
                if all(values == values(1))
                    throw(MException('Alakazam:Unfold:NeverVaries', '%s', sprintf([ ...
                        'Every event of "%s" has "%s" = %g, so the term cannot be told apart from ' ...
                        'the bin''s own waveform. (EYE-EEG fills each field that does not apply ' ...
                        'with 0: a fixation''s sac_amplitude, a saccade''s fix_avgpos_x.)'], ...
                        typeLabels{t}, v.name, values(1))));
                end
                for k = 1:numel(rows)
                    events(rows(k)).(v.name) = values(k);
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

function vars = formulaVariables(formula)
%FORMULAVARIABLES  The event fields a formula names, and whether each is a
%   factor (inside cat()). Everything that is a name and not one of Unfold's
%   term functions, or the response y, is a field.
    rhs = regexprep(formula, '^[^~]*~', '');
    names = unique(regexp(rhs, '[A-Za-z_]\w*', 'match'), 'stable');
    % A row, even when empty: a 0x1 list would still take one turn of a for
    % loop over its columns.
    names = reshape(setdiff(names, {'y', 'cat', 'spl', 'circspl'}, 'stable'), 1, []);
    factors = cellfun(@(t) t{1}, regexp(rhs, 'cat\s*\(\s*([A-Za-z_]\w*)', 'tokens'), ...
        'UniformOutput', false);
    vars = struct('name', names, 'categorical', num2cell(ismember(names, factors)));
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

function [events, nuisanceTypes, unbinned, notes, source] = rewriteEvents(EEG, membership, binTypes, otherCodes)
%REWRITEEVENTS  The event list in the model's own terms.
%   One row per (event, bin) pair, plus one row per unbinned event whose code
%   was chosen for modelling. Only .latency and .type are kept: they are what
%   uf_designmat reads, and carrying the rest would invite a field name to
%   collide with a predictor.
%
%   AN EVENT IN TWO BINS IS MODELLED ADDITIVELY, which is not what Average
%   does. It gets one row per bin, so two sticks at the same latency, and the
%   model explains its data as the SUM of the two bins' responses. Average
%   instead counts that epoch fully in both averages. With mutually exclusive
%   bins the two agree; with overlapping ones ("all targets" and "related
%   targets") the second bin comes out as a difference from the first. This
%   is stated here rather than hidden, and is a known open point.
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
    for b = 1:numel(membership)
        for k = reshape(membership{b}, 1, [])
            events(end + 1) = struct('latency', EEG.event(k).latency, ...
                'type', binTypes{b}); %#ok<AGROW>
            source(end + 1) = k; %#ok<AGROW>
        end
    end

    binned = unique([membership{:}]);
    others = setdiff(1:numel(EEG.event), binned);
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

function refuseIdenticalBins(membership, labels, usable)
%REFUSEIDENTICALBINS  Two bins over the same events cannot be separated.
    idx = find(usable);
    for a = 1:numel(idx)
        for b = a + 1:numel(idx)
            if isequal(membership{idx(a)}, membership{idx(b)})
                throw(MException('Alakazam:Unfold:CollinearBins', sprintf( ...
                    ['The bins "%s" and "%s" hold exactly the same events, so the model ' ...
                     'cannot tell their responses apart: any amount of one can be traded ' ...
                     'for the same amount of the other and fit the data equally well. The ' ...
                     'solver would still return an answer, and it would be arbitrary. ' ...
                     'Please give them different events or drop one of them.'], ...
                    labels{idx(a)}, labels{idx(b)})));
            end
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
