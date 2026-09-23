function plan = binModel(EEG, varargin)
%BINMODEL  Turn DefineBins' bins into an Unfold model, without fitting it.
%   PLAN = Unfold.binModel(EEG) reads the bin membership DefineBins left on a
%   continuous dataset (EEG.event(i).bini, EEG.bindesc) and returns the model
%   Unfold.fitBins will fit: which event types it will have, the formula for
%   each, the event list rewritten in those terms, and what it found wrong
%   with the design. It fits nothing and needs no toolbox, so the mapping can
%   be tested, inspected and explained on its own.
%
%   ONE EVENT TYPE PER BIN, each with the formula y ~ 1. That is the whole
%   translation: a bin is a set of events, its rERP is the intercept of that
%   event type, and the deconvolution separates the bins' responses where
%   they overlap in time. Averaging asks the same question of epoched data,
%   which is why the answer packages into the same shape; the difference is
%   that averaging assumes the epochs do not overlap and this does not.
%
%   EVENTS IN NO BIN ARE MODELLED TOO, by default, one type per event type
%   found ('ModelOtherEvents', false to turn that off). This is not a detail:
%   overlap correction only removes the overlap you model. A response, a
%   button press or the next stimulus that is left out of the design does not
%   stop overlapping the bins, it just stops being accounted for, and its
%   response leaks into whichever bin happens to precede it. Those types are
%   fitted and then dropped from the output, which is what a nuisance
%   regressor is.
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
%   bin, in bindesc order), .comboBins (indices of combination bins, computed
%   after the fit), .eventTypes and .formulas (what uf_designmat is given),
%   .nuisanceTypes, .events (the rewritten event list) and .notes.
%
%   THE FORMULAS ARE THE SEAM FOR COVARIATES. Every formula here is 'y ~ 1'
%   because a bin carries no covariate, but a later extension that wants
%   "the response to this bin, holding saccade amplitude constant" changes
%   one string per event type and adds the field to the rewritten events
%   (see Unfold.eyeEegCovariates, which already produces exactly that table).
%   Nothing else in the pipeline needs to know.
%
%   See also UNFOLD.FITBINS, UNFOLD.EYEEEGCOVARIATES, DEFINEBINS, AVERAGE.
    parsed = inputParser();
    parsed.addParameter('ModelOtherEvents', true, @(v) islogical(v) && isscalar(v));
    parsed.addParameter('Covariates', {}, @(v) isempty(v) || iscellstr(v) || isstring(v)); %#ok<ISCLSTR>
    parsed.parse(varargin{:});
    modelOther = parsed.Results.ModelOtherEvents;
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
    plan.binCounts = cellfun(@numel, membership);

    [plan.events, plan.nuisanceTypes] = rewriteEvents(EEG, membership, plan.binTypes, modelOther);

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
    plan.formulas = repmat({'y ~ 1'}, 1, numel(plan.eventTypes));
    [plan.events, plan.formulas, plan.covariates, covariateNotes] = ...
        addCovariates(plan.events, plan.formulas, plan.eventTypes, EEG, wanted);
    plan.notes = [plan.notes, covariateNotes];
end

% ======================================================================= %
function [events, formulas, applied, notes] = addCovariates(events, formulas, eventTypes, EEG, wanted)
%ADDCOVARIATES  Put the chosen event fields into the model as covariates.
%
%   THEY ARE NUISANCE REGRESSORS, not the thing being reported. Each one adds
%   a slope per event type that uses it; the slopes are fitted and thrown
%   away, and what comes back is still one waveform per bin. The point is the
%   waveform that is left: variance that a covariate explains stops being
%   attributed to the bin, so the bin's own estimate is cleaner and, where the
%   covariate differs between bins, less biased.
%
%   EVERY COVARIATE IS MEAN-CENTRED, and that is not a detail. A bin's
%   waveform is the model's intercept for that event type, which is the
%   response when every predictor is zero. Enter a raw saccade amplitude and
%   the bin waveform becomes the response to a saccade of zero degrees, which
%   is not a thing that happened and is an extrapolation off the end of the
%   data. Centred, the intercept is the response at that covariate's average
%   value, which is what "the bin's waveform, holding the covariate constant"
%   should mean and is comparable with the average of the same events.
%
%   A COVARIATE IS APPLIED ONLY TO THE EVENT TYPES THAT ACTUALLY CARRY IT.
%   Unfold needs a predictor filled for every event of a type whose formula
%   names it, and a bin whose events have no saccade amplitude cannot be
%   fitted against one. Rather than refuse the whole model or invent values,
%   each type keeps the covariates its own events all have, and the ones it
%   does not are named in the notes so the difference between bins is visible
%   rather than silent.
    applied = struct('name', {}, 'types', {}, 'centre', {}, 'n', {});
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
        values = covariateValues(events, EEG, name);
        usableTypes = typesWithEveryValue(types, values, eventTypes);
        if isempty(usableTypes)
            notes{end + 1} = sprintf(['No event type has "%s" on every one of its events, so ' ...
                'it could not be used as a covariate anywhere in this model.'], name); %#ok<AGROW>
            continue;
        end

        inModel = ismember(types, usableTypes);
        centre = mean(values(inModel), 'omitnan');
        centred = zeros(1, numel(events));       % 0, not NaN, for the types that do not use it:
        centred(inModel) = values(inModel) - centre;   % their columns never read it, and a NaN
        for k = 1:numel(events)                        % anywhere in the design is a trap
            events(k).(name) = centred(k);
        end
        for t = 1:numel(eventTypes)
            if ismember(eventTypes{t}, usableTypes)
                formulas{t} = [formulas{t} ' + ' name];
            end
        end
        applied(end + 1) = struct('name', name, 'types', {usableTypes}, ... %#ok<AGROW>
            'centre', centre, 'n', nnz(inModel));

        missing = setdiff(eventTypes, usableTypes, 'stable');
        if ~isempty(missing)
            notes{end + 1} = sprintf(['The covariate "%s" was fitted for %s, but not for %s, ' ...
                'whose events do not all carry a value for it.'], name, ...
                listOf(usableTypes), listOf(missing)); %#ok<AGROW>
        end
    end
end

function values = covariateValues(events, EEG, name)
%COVARIATEVALUES  The covariate for each row of the rewritten event list,
%   fetched from the ORIGINAL events by latency. rewriteEvents keeps only
%   .latency and .type (and one row per event-bin pair), so the value has to
%   be carried across from the dataset rather than read off the rewritten row.
    original = nan(1, numel(EEG.event));
    for k = 1:numel(EEG.event)
        v = EEG.event(k).(name);
        if isnumeric(v) && isscalar(v) && ~islogical(v)
            original(k) = double(v);
        end
    end
    lookup = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for k = 1:numel(EEG.event)
        lookup(double(EEG.event(k).latency)) = original(k);
    end

    values = nan(1, numel(events));
    for k = 1:numel(events)
        key = double(events(k).latency);
        if isKey(lookup, key)
            values(k) = lookup(key);
        end
    end
end

function usable = typesWithEveryValue(types, values, eventTypes)
%TYPESWITHEVERYVALUE  The event types whose every event has a finite value.
    usable = {};
    for t = 1:numel(eventTypes)
        rows = strcmp(types, eventTypes{t});
        if any(rows) && all(isfinite(values(rows)))
            usable{end + 1} = eventTypes{t}; %#ok<AGROW>
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

function [events, nuisanceTypes] = rewriteEvents(EEG, membership, binTypes, modelOther)
%REWRITEEVENTS  The event list in the model's own terms.
%   One row per (event, bin) pair, since an event in two bins is evidence
%   about both, plus one row per unbinned event when those are modelled.
%   Only .latency and .type are kept: they are what uf_designmat reads, and
%   carrying the rest would invite a field name to collide with a predictor.
    events = struct('latency', {}, 'type', {});
    for b = 1:numel(membership)
        for k = reshape(membership{b}, 1, [])
            events(end + 1) = struct('latency', EEG.event(k).latency, ...
                'type', binTypes{b}); %#ok<AGROW>
        end
    end

    nuisanceTypes = {};
    if modelOther
        binned = unique([membership{:}]);
        others = setdiff(1:numel(EEG.event), binned);
        % A boundary is EEGLAB's marker for a cut in the recording, not a
        % thing the brain responded to, and modelling it would fit a response
        % to the editing.
        rawTypes = arrayfun(@(e) char(string(e.type)), EEG.event(others), 'UniformOutput', false);
        keep = ~strcmpi(rawTypes, 'boundary');
        others = others(keep);
        rawTypes = rawTypes(keep);

        distinct = unique(rawTypes, 'stable');
        nuisanceTypes = uniqueTypes('evt_', distinct);
        for k = 1:numel(others)
            hit = strcmp(distinct, rawTypes{k});
            events(end + 1) = struct('latency', EEG.event(others(k)).latency, ...
                'type', nuisanceTypes{hit}); %#ok<AGROW>
        end
    end

    if ~isempty(events)
        [~, order] = sort([events.latency]);
        events = events(order);
    end
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
