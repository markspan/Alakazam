function [covariates, meta] = eyeEegCovariates(EEG, varargin)
%EYEEEGCOVARIATES  The eye-movement covariates EYE-EEG left on EEG.event.
%   [COVARIATES, META] = Unfold.eyeEegCovariates(EEG) finds the saccade
%   and fixation events EYE-EEG's detecteyemovements wrote into EEG.event and
%   returns them as a covariate table: one row per eye-movement event, one
%   variable per measure, ready for a regression-based ERP model to use as
%   predictors. META describes each variable, which is the half a table
%   cannot carry and a model needs: what it means, its unit, and whether it
%   is linear or circular.
%
%   COVARIATES is a table whose first three variables are always
%   eventIndex (the row in EEG.event), eventType and latency (samples), so a
%   caller can join it back to the events it came from. META is a struct
%   array with one element per measure: .name, .kind ('linear' or
%   'circular'), .unit and .description.
%
%   Unfold.eyeEegCovariates(EEG, 'EventTypes', {'fixation'}) restricts it
%   to some of the event types; the default is every eye-movement type
%   present.
%
%   WHY AN IMPORTER AT ALL, when the measures are already in EEG.event: they
%   are there as a flat pile of fields on a mixed event list, next to the
%   experiment's own triggers, in EYE-EEG's names and EYE-EEG's units. What a
%   model needs is a rectangular table of the events it will model, with the
%   units it will report and the knowledge of which predictors are angles.
%   Doing that conversion once, here, is what keeps it out of every caller.
%
%   WHAT IT KNOWS ABOUT EYE-EEG, all read from detecteyemovements.m rather
%   than assumed:
%
%   THE EVENT TYPES are 'saccade' and 'fixation', plus the monocular
%   'L_saccade', 'R_saccade', 'L_fixation' and 'R_fixation' that a recording
%   of one eye produces. All six are recognised, and the eye is reported
%   separately (META's description for eventType) rather than being folded
%   into the type, so a binocular and a monocular recording give the same
%   table shape.
%
%   DURATION IS IN SAMPLES, not milliseconds. EYE-EEG writes the sample count
%   into EEG.event.duration (its own plots convert with *1000/srate before
%   drawing), and EEGLAB's own convention for that field is samples too. A
%   duration in samples is not comparable across recordings at different
%   sampling rates, and a fixation-duration predictor that silently means
%   "samples" in one dataset and "samples" at another rate in the next is a
%   quiet way to get a wrong answer, so durationMs is added alongside it and
%   is the one a model should use.
%
%   SPATIAL MEASURES ARE IN WHATEVER EYE-EEG WAS TOLD. detecteyemovements
%   multiplies the spatial saccade properties by degperpixel when it is
%   given one, and otherwise leaves them "in the original data metric" and
%   says so in a warning. Nothing in the saved dataset records which
%   happened, so the unit here is reported as 'degrees or pixels' rather
%   than guessed. Whoever ran the detection knows; the table does not.
%
%   SAC_ANGLE IS CIRCULAR, which is why META carries a kind at all. It runs
%   over the full turn, so an ordinary spline treats 359 degrees and 1 degree
%   as far apart and fits a discontinuity where the data has none. Dimigen
%   and Ehinger (2021) model saccade direction with circular splines for
%   exactly this reason, and a caller that ignores .kind will silently do
%   the wrong thing on this one column.
%
%   FIXATIONS CARRY THEIR INCOMING SACCADE. Since EYE-EEG's September 2021
%   change, a fixation event also holds the sac_* properties of the saccade
%   that produced it, which is what makes "the response to this fixation,
%   given the saccade that brought the eye here" expressible at all. Those
%   columns are therefore kept for fixations, not treated as saccade-only.
%
%   Returns an empty table and an empty META when the dataset has no
%   eye-movement events, which is the ordinary case for a recording that
%   never went through EYE-EEG: asking is allowed, and is not an error.
%
%   See also UNFOLD.ENSURE, DEFINEBINS.
    parsed = inputParser();
    parsed.addParameter('EventTypes', {}, @(v) iscellstr(v) || ischar(v) || isstring(v));
    parsed.parse(varargin{:});
    wanted = cellstr(string(parsed.Results.EventTypes));

    catalogue = measureCatalogue();
    [covariates, meta] = emptyResult();
    if ~isfield(EEG, 'event') || isempty(EEG.event) || ~isfield(EEG.event, 'type')
        return;
    end

    types = arrayfun(@(e) char(string(e.type)), EEG.event, 'UniformOutput', false);
    isEyeEvent = ismember(lower(types), lower(eyeMovementTypes()));
    if ~isempty(wanted)
        isEyeEvent = isEyeEvent & ismember(lower(types), lower(wanted));
    end
    rows = find(isEyeEvent);
    if isempty(rows)
        return;
    end

    % Only the measures this dataset actually carries: EYE-EEG writes a
    % different set for saccades and fixations, for one eye and for two, and
    % a column of all-NaN would look like a failed measurement rather than a
    % field this recording never had.
    present = catalogue(cellfun(@(n) isfield(EEG.event, n), {catalogue.field}));

    covariates = table(reshape(rows, [], 1), reshape(types(rows), [], 1), ...
        columnOf(EEG.event(rows), 'latency'), ...
        'VariableNames', {'eventIndex', 'eventType', 'latency'});
    for k = 1:numel(present)
        covariates.(present(k).name) = columnOf(EEG.event(rows), present(k).field);
    end

    srate = TransTools.FieldOr(EEG, 'srate', NaN);
    if ismember('duration', covariates.Properties.VariableNames)
        covariates.durationMs = covariates.duration * 1000 / srate;
    end

    meta = metaFor(present, ismember('duration', covariates.Properties.VariableNames));
end

% ======================================================================= %
function types = eyeMovementTypes()
%EYEMOVEMENTTYPES  The six event types EYE-EEG writes (detecteyemovements.m
%   calls this list em_types when it checks for events it already added).
    types = {'saccade', 'fixation', 'L_saccade', 'R_saccade', 'L_fixation', 'R_fixation'};
end

function catalogue = measureCatalogue()
%MEASURECATALOGUE  Every EEG.event field EYE-EEG writes for an eye movement,
%   with what a model needs to know about it. FIELD is EYE-EEG's own name,
%   NAME is the table variable (the same, so the table stays greppable
%   against the toolbox's documentation).
    c = { ...
        'duration',       'linear',   'samples', ...
            'Duration of the event, in samples (see durationMs).'; ...
        'sac_amplitude',  'linear',   'degrees or pixels', ...
            'Distance from the start of the saccade to its landing point.'; ...
        'sac_vmax',       'linear',   'degrees or pixels per second', ...
            'Peak velocity of the saccade.'; ...
        'sac_angle',      'circular', 'degrees', ...
            'Orientation of the saccade over the full turn; model it with circular splines.'; ...
        'sac_startpos_x', 'linear',   'degrees or pixels', 'Horizontal launch position of the saccade.'; ...
        'sac_startpos_y', 'linear',   'degrees or pixels', 'Vertical launch position of the saccade.'; ...
        'sac_endpos_x',   'linear',   'degrees or pixels', 'Horizontal landing position of the saccade.'; ...
        'sac_endpos_y',   'linear',   'degrees or pixels', 'Vertical landing position of the saccade.'; ...
        'fix_avgpos_x',   'linear',   'degrees or pixels', 'Mean horizontal gaze position during the fixation.'; ...
        'fix_avgpos_y',   'linear',   'degrees or pixels', 'Mean vertical gaze position during the fixation.'; ...
        'fix_avgpupilsize', 'linear', 'tracker units', 'Mean pupil size during the fixation.'};
    catalogue = struct('field', c(:, 1), 'kind', c(:, 2), 'unit', c(:, 3), 'description', c(:, 4));
    [catalogue.name] = deal(catalogue.field);
end

function meta = metaFor(present, hasDuration)
%METAFOR  META for the measures found, plus durationMs when duration was.
    meta = struct('name', {present.name}, 'kind', {present.kind}, ...
        'unit', {present.unit}, 'description', {present.description});
    if hasDuration
        meta(end + 1) = struct('name', 'durationMs', 'kind', 'linear', 'unit', 'ms', ...
            'description', ['Duration in milliseconds, from EYE-EEG''s sample count and ' ...
                            'EEG.srate. Comparable across recordings, which duration is not.']);
    end
end

function [covariates, meta] = emptyResult()
%EMPTYRESULT  The shape returned for a dataset with no eye movements: an
%   empty table with the three always-present variables, so a caller can
%   read its VariableNames and height without a special case.
    covariates = table('Size', [0 3], 'VariableTypes', {'double', 'cell', 'double'}, ...
        'VariableNames', {'eventIndex', 'eventType', 'latency'});
    meta = struct('name', {}, 'kind', {}, 'unit', {}, 'description', {});
end

function values = columnOf(events, field)
%COLUMNOF  One numeric column from a struct array's FIELD, with a missing or
%   non-numeric entry as NaN rather than an error: EEG.event is a mixed list
%   and a field EYE-EEG wrote for one event type is empty on the others.
    values = nan(numel(events), 1);
    if ~isfield(events, field)
        return;
    end
    for k = 1:numel(events)
        v = events(k).(field);
        if isnumeric(v) && isscalar(v)
            values(k) = double(v);
        elseif (ischar(v) || isstring(v)) && ~isempty(v)
            converted = str2double(v);      % some importers round-trip through text
            values(k) = converted;
        end
    end
end
