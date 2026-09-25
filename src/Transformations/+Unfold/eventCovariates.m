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
%     duration is a sample count (EEGLAB's convention, and EYE-EEG's), so a
%     slope on it would mean something different at every sampling rate;
%     .bini and .urevent are bookkeeping. Offering any of them as a predictor
%     invites a model that regresses the data on its own time axis.
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
%   treatment is a circular spline (circspl in a formula), which wraps round.
%   Marking the kind here is what lets DeconvolveDialog list them apart, as
%   angles, instead of beside the numbers a straight line suits. EYE-EEG's
%   own measures carry their kind and units from Unfold.eyeEegMeasures,
%   which knows them; anything else is reported as linear with no unit,
%   which is the truth about what is known rather than a guess.
%
%   See also UNFOLD.BINMODEL, UNFOLD.EYEEEGMEASURES, DECONVOLVE.
    candidates = struct('name', {}, 'kind', {}, 'unit', {}, 'description', {}, ...
        'n', {}, 'types', {});
    if ~isfield(EEG, 'event') || isempty(EEG.event)
        return;
    end

    known = Unfold.eyeEegMeasures();
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
        candidates(end + 1) = struct('name', field, 'kind', meta.kind, ...
            'unit', meta.unit, 'description', meta.description, ...
            'n', nnz(usable), 'types', {unique(types(usable), 'stable')}); %#ok<AGROW>
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

function meta = metaFor(known, field)
%METAFOR  What Unfold.eyeEegMeasures says about FIELD, or linear with no
%   unit when it is not one of EYE-EEG's.
    meta = struct('kind', 'linear', 'unit', '', 'description', '');
    hit = find(strcmp({known.name}, field), 1);
    if isempty(hit)
        return;
    end
    meta.kind = char(string(known(hit).kind));
    meta.unit = char(string(known(hit).unit));
    meta.description = char(string(known(hit).description));
end
