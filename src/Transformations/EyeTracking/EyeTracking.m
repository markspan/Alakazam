function [EEG, options] = EyeTracking(input, varargin)
%% EyeTracking  Join the EyeLink recording that belongs to this EEG onto it.
%
%   Reads the eye tracker's own recording of the same session, lines its
%   clock up with the EEG's through the triggers both received, and adds its
%   gaze and pupil signals as channels (typed EYE, so nothing treats them as
%   scalp EEG) and, optionally, the tracker's own saccades, fixations and
%   blinks as events. The work is EYE-EEG's (Dimigen, Sommer, Hohlfeld,
%   Jacobs & Kliegl, 2011): parseeyelink reads the file, pop_importeyetracker
%   synchronises and imports. This transformation finds the file, checks the
%   result and says how good the join is.
%
%   THE FILE IS FOUND BY NAME. The eye-tracking file has the recording's own
%   base name with .asc, beside it: subject1myex.set is accompanied by
%   subject1myex.asc (EyeEeg.findEyeFile). That is what lets one set of
%   options be replayed onto every subject by Apply to All. When only an
%   .edf is there and SR Research's edf2asc is on the machine, it is
%   converted automatically; otherwise the .asc is asked for.
%
%   A JOIN IS ONLY AS GOOD AS ITS SYNCHRONISATION, and a bad one is silent:
%   every event lands a little off the EEG it belongs to and nothing
%   downstream can tell. So the result is checked, not just produced:
%     - EYE-EEG returns the dataset unchanged, without an error, when it
%       finds no shared triggers at all; that is caught here and refused.
%     - Its record of how far each shared trigger ended up from its partner
%       (EEG.etc.eyetracker_syncquality) is summarised (EyeEeg.syncQuality)
%       and refused below the limits in the options: too few shared events
%       to judge the alignment by, or too few of them within one sample.
%     - The summary goes into EEG.etc.alz.eyeTracking, so the data-quality
%       report states how good the synchronisation was for every subject.
%
%   IT NEEDS CONTINUOUS DATA, as EYE-EEG does: the two recordings are joined
%   sample by sample, before anything is cut into epochs.
%
%   Options (set in EyeTrackingDialog, stored per workspace):
%     keyword              the EyeLink message keyword that carries the
%                          triggers ("MYKEYWORD 123"); empty reads them from
%                          the parallel-port INPUT lines instead
%     startEvent, endEvent the trigger codes the alignment is anchored on
%                          (the first of the one, the last of the other);
%                          empty picks, per recording, the code of the first
%                          and of the last trigger both recordings share
%     columns              'all', or the eye-tracker columns to import by
%                          name (L_GAZE_X, L_AREA, ...); names rather than
%                          positions, so a replay means the same signals.
%                          EYE-EEG names the resulting channels with hyphens
%                          (L-GAZE-X); either spelling is accepted here
%     importEyeEvents      the tracker's own saccades/fixations/blinks,
%                          default true
%     searchRadius         samples either side of an EEG trigger to look for
%                          its partner, default 4 (EYE-EEG's own default)
%     filterEyetrack       filter at Nyquist when resampling, default false
%                          (EYE-EEG's own default)
%     minSharedEvents      fewest shared triggers to accept, default 10
%     minPctWithinOne      least percentage of them within one sample,
%                          default 90
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = EyeTracking(input)        % interactive dialog
%     [EEG, options] = EyeTracking(input, opts)  % replay a stored struct
%
%   See also EYEEEG.FINDEYEFILE, EYEEEG.SYNCQUALITY, EYEEEG.ENSURE,
%   UNFOLD.EYEEEGCOVARIATES, DECONVOLVE.
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:EyeTracking', varargin{:});

% Both checked before any dialog: a dataset with nothing to join onto, or no
% file to join, should say so rather than ask for settings it will refuse.
requireContinuous(input);
[ascFile, how] = EyeEeg.findEyeFile(input);
EyeEeg.ensure('Eye-tracking import');

if interactive
    options = EyeTrackingDialog(input, ascFile, TransformSettings.get('EyeTracking'));
    if isempty(options)
        EEG = [];       % cancelled; OPTIONS must still be assigned
        options = [];
        return;
    end
    TransformSettings.set('EyeTracking', options);
else
    options = opts;
end

EEG = join(input, ascFile, how, settings(options));
end

% ======================================================================= %
function s = settings(options)
%SETTINGS  The options with every default filled in.
    s = struct( ...
        'keyword', char(string(TransTools.FieldOr(options, 'keyword', ''))), ...
        'startEvent', TransTools.FieldOr(options, 'startEvent', []), ...
        'endEvent', TransTools.FieldOr(options, 'endEvent', []), ...
        'columns', TransTools.FieldOr(options, 'columns', 'all'), ...
        'importEyeEvents', logical(TransTools.FieldOr(options, 'importEyeEvents', true)), ...
        'searchRadius', double(TransTools.FieldOr(options, 'searchRadius', 4)), ...
        'filterEyetrack', logical(TransTools.FieldOr(options, 'filterEyetrack', false)), ...
        'minSharedEvents', double(TransTools.FieldOr(options, 'minSharedEvents', 10)), ...
        'minPctWithinOne', double(TransTools.FieldOr(options, 'minPctWithinOne', 90)));
end

function EEG = join(input, ascFile, how, s)
%JOIN  Parse, synchronise, import, and check.
    matFile = [tempname() '.mat'];
    removeMat = onCleanup(@() deleteIfPresent(matFile));
    et = EyeEeg.parse(ascFile, matFile, s.keyword);

    [columns, labels] = pickColumns(et.colheader, s.columns);
    [codes, triggerCount] = EyeEeg.triggerCodes(input);
    [startCode, endCode] = anchorEvents(codes, et, s, ascFile);

    before = size(input.data, 1);
    EEG = pop_importeyetracker(input, matFile, [startCode endCode], columns, labels, ...
        s.importEyeEvents, true, s.filterEyetrack, false, s.searchRadius);

    if size(EEG.data, 1) == before
        % EYE-EEG's own reaction to finding no shared triggers is to print a
        % line and hand the dataset back unchanged, which would otherwise
        % pass here as a join that added nothing.
        throw(MException('Alakazam:EyeTracking:NotJoined', '%s', sprintf([ ...
            'The eye track could not be joined onto this recording: EYE-EEG found no triggers ' ...
            'that both recordings share between %d and %d, so there is nothing to line the ' ...
            'two clocks up by. Is the message keyword right ("%s")? The EEG''s triggers and the ' ...
            'eye tracker''s have to carry the same numbers.'], startCode, endCode, s.keyword)));
    end

    quality = EyeEeg.syncQuality(EEG.etc.eyetracker_syncquality, EEG.srate, triggerCount);
    requireGoodSync(quality, s, ascFile);

    EEG = restoreAlakazamFields(EEG, input, before);
    channels = {EEG.chanlocs(before + 1:end).labels};
    EEG.etc.alz.eyeTracking = struct('file', ascFile, 'how', how, 'keyword', s.keyword, ...
        'startEvent', startCode, 'endEvent', endCode, 'columns', {labels}, ...
        'channels', {channels}, ...
        'importEyeEvents', s.importEyeEvents, 'searchRadius', s.searchRadius, ...
        'filterEyetrack', s.filterEyetrack, 'quality', quality, ...
        'limits', struct('minSharedEvents', s.minSharedEvents, 'minPctWithinOne', s.minPctWithinOne));
    report(EEG.etc.alz.eyeTracking);
end

function requireContinuous(EEG)
    format = char(string(TransTools.FieldOr(EEG, 'DataFormat', 'not set')));
    if ~strcmpi(format, 'CONTINUOUS') || size(EEG.data, 3) > 1
        throw(MException('Alakazam:EyeTracking:NeedsContinuous', '%s', sprintf([ ...
            'Joining the eye track needs continuous data, and this dataset is not ' ...
            '(DataFormat = "%s"), I''m afraid. The two recordings are lined up sample by ' ...
            'sample, so it has to happen before anything is cut into epochs: would you run ' ...
            'it on the continuous recording?'], format)));
    end
end

function [columns, labels] = pickColumns(colheader, wanted)
%PICKCOLUMNS  The eye-tracker columns to import, by name. TIME is the
%   tracker's clock, which the join replaces, and INPUT is the trigger port,
%   which it reads; neither is a signal worth a channel.
    names = cellstr(string(colheader));
    signal = ~ismember(upper(names), {'TIME', 'INPUT'});
    if (ischar(wanted) || isstring(wanted)) && strcmpi(char(wanted), 'all')
        chosen = signal;
    else
        % Either spelling is accepted: the parser calls a column L_GAZE_X,
        % and EYE-EEG names the channel it becomes L-GAZE-X (underscores
        % break EEGLAB's channel decoding, its own comment says), so a user
        % may well copy either one into the options.
        wanted = strrep(cellstr(string(wanted)), '-', '_');
        chosen = signal & ismember(strrep(names, '-', '_'), wanted);
        missing = setdiff(wanted, strrep(names(signal), '-', '_'));
        if ~isempty(missing)
            throw(MException('Alakazam:EyeTracking:NoSuchColumn', '%s', sprintf([ ...
                'This eye-tracking file has no column %s. It has %s. A column is chosen by ' ...
                'name, so a recording made with a different eye or sample set does not ' ...
                'provide the same ones.'], strjoin(missing, ', '), strjoin(names(signal), ', '))));
        end
    end
    columns = find(chosen);
    labels = names(chosen);
    if isempty(columns)
        throw(MException('Alakazam:EyeTracking:NoColumns', ...
            'There are no eye-tracking columns to import from this file.'));
    end
end

function [startCode, endCode] = anchorEvents(codes, et, s, ascFile)
%ANCHOREVENTS  The trigger codes to anchor the alignment on: given ones as
%   they are, otherwise the first and last trigger both recordings share,
%   found per recording (EyeEeg.sharedAnchors).
    startCode = s.startEvent;
    endCode = s.endEvent;
    if ~isempty(startCode) && ~isempty(endCode)
        return;
    end
    [autoStart, autoEnd] = EyeEeg.sharedAnchors(codes, et);
    if isempty(autoStart)
        etCodes = [];
        if isfield(et, 'event') && ~isempty(et.event)
            etCodes = et.event(:, 2);
        end
        throw(MException('Alakazam:EyeTracking:NoSharedTriggers', '%s', sprintf([ ...
            'No trigger number occurs in both this recording and %s, so the two cannot be ' ...
            'lined up. The EEG has %s; the eye track has %s. If the eye track has none at ' ...
            'all, the message keyword ("%s") is probably not the one the experiment sent.'], ...
            ascFile, codeSummary(codes(~isnan(codes))), codeSummary(etCodes), s.keyword)));
    end
    if isempty(startCode)
        startCode = autoStart;
    end
    if isempty(endCode)
        endCode = autoEnd;
    end
end

function text = codeSummary(codes)
    distinct = unique(codes(:)');
    if isempty(distinct)
        text = 'none';
    elseif numel(distinct) <= 12
        text = strjoin(arrayfun(@(c) sprintf('%g', c), distinct, 'UniformOutput', false), ', ');
    else
        text = sprintf('%d different codes, from %g to %g', numel(distinct), distinct(1), distinct(end));
    end
end

function requireGoodSync(q, s, ascFile)
%REQUIREGOODSYNC  Refuse a join the synchronisation does not support.
    if q.nShared < s.minSharedEvents
        throw(MException('Alakazam:EyeTracking:TooFewShared', '%s', sprintf([ ...
            'Only %d trigger(s) were found in both recordings (of %d in the EEG), which is ' ...
            'too few to judge the alignment of %s by: at least %d are asked for. Too few ' ...
            'usually means the keyword or the anchor codes are not the ones the experiment ' ...
            'used, or a stretch of one recording is missing.'], q.nShared, q.nTriggers, ...
            ascFile, s.minSharedEvents)));
    end
    if q.pctWithinOne < s.minPctWithinOne
        throw(MException('Alakazam:EyeTracking:PoorSync', '%s', sprintf([ ...
            'The eye track of %s does not line up well enough: %.0f%% of the %d shared ' ...
            'triggers ended within one sample of their EEG partner (the limit is %g%%), the ' ...
            'mean offset is %.2f ms and the worst %d sample(s). Every event and gaze sample ' ...
            'would carry that error into the analysis, so it is not joined.'], ascFile, ...
            q.pctWithinOne, q.nShared, s.minPctWithinOne, q.meanAbsMs, q.maxAbsSamples)));
    end
end

function EEG = restoreAlakazamFields(EEG, input, before)
%RESTOREALAKAZAMFIELDS  What EYE-EEG's own eeg_checkset may have changed
%   back to Alakazam's conventions: continuous .times in seconds, the data
%   format and type, and EYE as the type of every channel it added (so
%   eegChannelMask keeps them out of everything meant for the scalp).
    EEG.times = input.times;
    EEG.DataFormat = input.DataFormat;
    if isfield(input, 'DataType')
        EEG.DataType = input.DataType;
    end
    for c = before + 1:size(EEG.data, 1)
        EEG.chanlocs(c).type = 'EYE';
    end
end

function report(info)
    q = info.quality;
    fprintf(['EyeTracking: joined %s (%s) onto the EEG, %d column(s): %s.\n' ...
             '  %d shared trigger(s) of %d, %.0f%% within one sample, mean offset %.2f ms.\n'], ...
        info.file, info.how, numel(info.channels), strjoin(info.channels, ', '), ...
        q.nShared, q.nTriggers, q.pctWithinOne, q.meanAbsMs);
end

function deleteIfPresent(file)
    if isfile(file)
        delete(file);
    end
end
