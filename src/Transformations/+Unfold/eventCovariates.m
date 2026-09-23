function candidates = eventCovariates(EEG)
%EVENTCOVARIATES  The numeric event fields a deconvolution could use as
%   covariates, with what is known about each.
%
%   CANDIDATES = Unfold.eventCovariates(EEG) scans EEG.event for fields that
%   hold one finite number per event and returns them as a struct array:
%     .name         the event field
%     .kind         'linear' or 'circular'
%     .unit         '' when unknown
%     .description  what it means, '' when unknown
%     .n            how many events carry a finite value
%     .types        the event types that carry it, as a cellstr
%
%   WHAT IS LEFT OUT, and why each exclusion is deliberate:
%
%     .latency, .duration and the bin tags DefineBins writes. Latency is the
%     event's position, which the deconvolution is already built around;
%     duration is EYE-EEG's sample count, superseded by durationMs; .bini and
%     .urevent are bookkeeping. Offering any of them as a predictor invites a
%     model that regresses the data on its own time axis.
%
%     Fields that are not one finite number per event: a cell, a vector, or a
%     field that is empty on most events. Unfold needs the predictor filled
%     for every event of the types whose formula uses it, so a mostly-missing
%     field cannot be a covariate for those types (Unfold.binModel says which
%     types a covariate could actually be applied to, since that depends on
%     the bins as well as the field).
%
%   CIRCULAR COVARIATES ARE REPORTED BUT MARKED, not silently offered as
%   linear terms. A saccade angle of 359 degrees is next to one of 1 degree
%   and miles from 180, so fitting a slope on it is meaningless; the honest
%   treatment is a sine and cosine pair, which is a real addition rather than
%   a checkbox. Marking the kind here is what lets a caller refuse them with a
%   reason instead of quietly producing a wrong number. EYE-EEG's own measures
%   carry their kind and units from Unfold.eyeEegCovariates, which knows them;
%   anything else is reported as linear with no unit, which is the truth about
%   what is known rather than a guess.
%
%   See also UNFOLD.BINMODEL, UNFOLD.EYEEEGCOVARIATES, DECONVOLVE.
    candidates = struct('name', {}, 'kind', {}, 'unit', {}, 'description', {}, ...
        'n', {}, 'types', {});
    if ~isfield(EEG, 'event') || isempty(EEG.event)
        return;
    end

    known = knownMeta(EEG);
    reserved = {'latency', 'type', 'urevent', 'bini', 'duration', 'epoch', 'bvtime', 'bvmknum'};
    types = cellfun(@(t) char(string(t)), {EEG.event.type}, 'UniformOutput', false);

    for name = setdiff(fieldnames(EEG.event)', reserved, 'stable')
        field = name{1};
        values = numericValues(EEG.event, field);
        usable = isfinite(values);
        if nnz(usable) < 2 || all(values(usable) == values(find(usable, 1)))
            continue;   % nothing to fit a slope on: absent, or constant
        end
        meta = metaFor(known, field);
        candidates(end + 1) = struct('name', field, 'kind', meta.kind, ... %#ok<AGROW>
            'unit', meta.unit, 'description', meta.description, ...
            'n', nnz(usable), 'types', {unique(types(usable), 'stable')});
    end
end

% ======================================================================= %
function values = numericValues(events, field)
%NUMERICVALUES  One number per event, NaN where the field cannot be one.
    values = nan(1, numel(events));
    for k = 1:numel(events)
        v = events(k).(field);
        if isnumeric(v) && isscalar(v) && ~islogical(v)
            values(k) = double(v);
        end
    end
end

function known = knownMeta(EEG)
%KNOWNMETA  What Unfold.eyeEegCovariates knows about this dataset's
%   eye-movement measures, or nothing when there are none. Wrapped because a
%   dataset with no eye events is the ordinary case, not a failure.
    known = struct('name', {}, 'kind', {}, 'unit', {}, 'description', {});
    try
        [~, meta] = Unfold.eyeEegCovariates(EEG);
        if ~isempty(meta)
            known = meta;
        end
    catch
        % no eye-movement events, or none of EYE-EEG's fields: nothing known
    end
end

function meta = metaFor(known, field)
    meta = struct('kind', 'linear', 'unit', '', 'description', '');
    if isempty(known)
        return;
    end
    hit = find(strcmp({known.name}, field), 1);
    if isempty(hit)
        return;
    end
    meta.kind = char(string(known(hit).kind));
    meta.unit = char(string(known(hit).unit));
    meta.description = char(string(known(hit).description));
end
