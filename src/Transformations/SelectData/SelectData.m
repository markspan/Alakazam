function [EEG, options] = SelectData(input, varargin)
%% SelectData  Keep or remove data along channels, time, points and trials.
%
%   The app-styled SelectDataDialog collects a selection (the same one
%   pop_select offers); the compute delegates to EEGLAB's pop_select, called
%   programmatically from a plain options struct (no eval of a command string).
%   Channels are stored as labels and resolved to indices against the current
%   dataset, so a stored selection replays on a dataset whose channels differ.
%
%   WHAT IS KEPT BESIDE THE TRIALS. pop_select renumbers what EEGLAB knows
%   about (EEG.epoch, each event's .epoch) but not what Alakazam keeps per
%   trial: each bin's trial list, EEG.bindesc(b).trials, which
%   TransTools.BinTrials and so Average read in preference to
%   EEG.epoch(t).bini, with its .events, .rt and .n beside it, and the
%   per-trial records in EEG.etc.alz. Left alone, every bin still listed the
%   trials it had before the selection: Average then failed with an index
%   past the last trial or, where the old numbers were still in range,
%   averaged the wrong trials without a word. So a trial selection renumbers
%   them to the trials that remain (see followKeptTrials).
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = SelectData(input)        % interactive dialog
%     [EEG, options] = SelectData(input, opts)  % replay a stored options struct
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:SelectData', varargin{:});
if interactive
    options = SelectDataDialog(input.chanlocs, size(input.data, 2), size(input.data, 3), ...
        TransformSettings.get('SelectData'), timeUnit(input));
    if isempty(options)
        EEG = [];   % cancelled -- no node, no compute (see Alakazam.onTransformation)
        return;
    end
    TransformSettings.set('SelectData', options);
else
    options = opts;
end

args = buildSelectArgs(input, options);
if isempty(args)
    EEG = input;   % nothing selected -> no-op
    return;
end
EEG = pop_select(input, args{:});
if selectsTrials(options)
    EEG = followKeptTrials(EEG, input, keptTrials(input, options));
end

% pop_select (via eeg_checkset) rewrites EEG.times in EEGLAB's millisecond
% convention. Alakazam keeps *continuous* data on a SECONDS time axis (epoched
% and averaged data stay in ms, matching EEGLAB and the rest of the app), so
% restore seconds for a continuous result -- otherwise the axis reads in ms and
% the duration/sample-rate look 1000x off (see Resample.m, same convention).
if isContinuous(input)
    EEG.times = (0:EEG.pnts - 1) / EEG.srate;   % seconds, 0-based
    if ~isempty(EEG.times)
        EEG.xmin = EEG.times(1);
        EEG.xmax = EEG.times(end);
    end
end
end

% ======================================================================= %
function args = buildSelectArgs(input, o)
%BUILDSELECTARGS  The pop_select name/value arguments for one options struct.
    args = {};
    if isfield(o, 'channels') && ~strcmp(o.channels.mode, '(off)')
        idx = TransTools.LabelsToIdx(input, o.channels.labels);
        if strcmp(o.channels.mode, 'Keep')
            if isempty(idx)
                throw(MException('Alakazam:SelectData', ...
                    'SelectData: I''m afraid none of the channels to keep are in this dataset.'));
            end
            args = [args, {'channel', idx}];
        elseif ~isempty(idx)
            args = [args, {'nochannel', idx}];
        end
    end
    % pop_select's 'time' argument is always in seconds. The dialog collects the
    % time range in the data's own display unit -- seconds for continuous data,
    % milliseconds for epoched/averaged data -- so scale to seconds accordingly.
    if isContinuous(input); timeScale = 1; else; timeScale = 1 / 1000; end
    args = [args, rangeArgs(o, 'time',   'time',  'notime',  timeScale)];
    args = [args, rangeArgs(o, 'points', 'point', 'nopoint', 1)];
    if selectsTrials(o)
        key = keepKey(o.trials.mode, 'trial', 'notrial');
        args = [args, {key, o.trials.indices(:)'}];
    end
end

function tf = selectsTrials(o)
%SELECTSTRIALS  True when the options keep or remove trials.
    tf = isfield(o, 'trials') && ~strcmp(o.trials.mode, '(off)') && ~isempty(o.trials.indices);
end

function kept = keptTrials(input, o)
%KEPTTRIALS  The input's trials a trial selection keeps, in the order
%   pop_select leaves them: sorted and without repeats, its 'sorttrial'
%   default. Input trial KEPT(j) becomes trial j.
    asked = double(o.trials.indices(:)');
    if strcmp(o.trials.mode, 'Keep')
        kept = unique(asked);
    else
        kept = setdiff(1:size(input.data, 3), asked);
    end
end

% ======================================================================= %
function EEG = followKeptTrials(EEG, input, kept)
%FOLLOWKEPTTRIALS  Renumber what Alakazam keeps per trial to the trials
%   pop_select kept: every bin's trial list (followBin) and the per-trial
%   records in EEG.etc.alz (followRecords).
    nBefore = size(input.data, 3);
    if numel(kept) ~= size(EEG.data, 3)
        % pop_select chose its trials some other way than keptTrials says.
        % Renumbering the bins by the wrong list would average the wrong
        % trials, which is the fault this function exists to prevent.
        throw(MException('Alakazam:SelectData', ...
            ['SelectData: I''m afraid EEGLAB kept %d trial(s) where %d were expected, so ' ...
             'the bins'' trial lists cannot be renumbered to match. Nothing was changed.'], ...
            size(EEG.data, 3), numel(kept)));
    end
    newNumber = zeros(1, nBefore);   % 0 for a trial that was removed
    newNumber(kept) = 1:numel(kept);
    if isfield(EEG, 'bindesc') && isstruct(EEG.bindesc) && isfield(EEG.bindesc, 'trials')
        for b = 1:numel(EEG.bindesc)
            EEG.bindesc(b) = followBin(EEG.bindesc(b), newNumber);
        end
    end
    if isfield(EEG, 'etc') && isstruct(EEG.etc) && isfield(EEG.etc, 'alz') && isstruct(EEG.etc.alz)
        EEG.etc.alz = followRecords(EEG.etc.alz, kept, nBefore);
    end
end

function bin = followBin(bin, newNumber)
%FOLLOWBIN  One bin's trial list with the removed trials dropped and the
%   rest renumbered, and its .events, .rt and .n kept in step with it.
%
%   .events and .rt run parallel to .trials, one entry per trial the bin
%   matched, as DefineBins and deriveBinsFromEpochs build them; one that does
%   not is left alone, since nothing says which of its entries went with a
%   removed trial. The kept .events are not renumbered: they are rows of the
%   event table the bins were matched in, a record of which event each trial
%   was cut around, and EEGLAB's own event checks prune an epoched dataset's
%   table whatever SelectData does. The live link from a trial to its event,
%   each event's .epoch, is pop_select's, and it renumbers that itself.
%
%   A bin with no list (a combination bin, or one read from
%   EEG.epoch(t).bini) has nothing to renumber; pop_select subsets
%   EEG.epoch itself.
    trials = bin.trials;
    if isempty(trials)
        return;
    end
    old = double(trials);
    stays = false(size(old));
    known = old >= 1 & old <= numel(newNumber) & old == round(old);
    stays(known) = newNumber(old(known)) > 0;
    for f = {'events', 'rt'}
        if isfield(bin, f{1}) && numel(bin.(f{1})) == numel(trials)
            bin.(f{1}) = bin.(f{1})(stays);
        end
    end
    renumbered = trials(stays);
    renumbered(:) = newNumber(old(stays));   % keeps the list's own shape and class
    bin.trials = renumbered;
    if isfield(bin, 'n') && isnumeric(bin.n)
        bin.n = numel(renumbered);
    end
end

function alz = followRecords(alz, kept, nBefore)
%FOLLOWRECORDS  The per-trial records in EEG.etc.alz cut to the kept
%   trials: the interpolation mask (channels x trials, see
%   TransTools.RecordInterpolated), and DefineBins' epochStart (where each
%   trial began in the recording it was cut from) and epochNeighbours (when
%   the events around it fell, which EpochView sorts by).
%
%   A record whose trial dimension did not match the input was out of step
%   already, and is left for its readers to discard, as they do. The
%   rejection steps' own records (artefactDetectors, autoreject) are not
%   cut either: they count what that step found among the trials it was
%   given, which stays true of it.
    if isfield(alz, 'interpolated') && islogical(alz.interpolated) ...
            && ismatrix(alz.interpolated) && size(alz.interpolated, 2) == nBefore
        alz.interpolated = alz.interpolated(:, kept);
    end
    if isfield(alz, 'epochStart') && isvector(alz.epochStart) && numel(alz.epochStart) == nBefore
        alz.epochStart = alz.epochStart(kept);
    end
    if isfield(alz, 'epochNeighbours') && isstruct(alz.epochNeighbours) ...
            && isscalar(alz.epochNeighbours) ...
            && all(isfield(alz.epochNeighbours, {'next', 'previous'})) ...
            && size(alz.epochNeighbours.next, 2) == nBefore ...
            && size(alz.epochNeighbours.previous, 2) == nBefore
        alz.epochNeighbours.next = alz.epochNeighbours.next(:, kept);
        alz.epochNeighbours.previous = alz.epochNeighbours.previous(:, kept);
        alz.epochNeighbours.trials = numel(kept);
    end
end

function a = rangeArgs(o, field, keepK, removeK, scale)
    a = {};
    if isfield(o, field) && ~strcmp(o.(field).mode, '(off)')
        % (:)' forces a ROW vector: the dialog always produces one ([lo.Value
        % hi.Value]), but jsondecode has no notion of row vs column and turns
        % any JSON numeric array back into a COLUMN on Apply Template -- pop_select
        % rejects that outright ("Time/point range must contain 2 columns exactly").
        % Confirmed directly: jsondecode(jsonencode([883 8594])) comes back 2x1.
        a = {keepKey(o.(field).mode, keepK, removeK), o.(field).range(:)' * scale};
    end
end

function key = keepKey(mode, keepK, removeK)
    if strcmp(mode, 'Keep'); key = keepK; else; key = removeK; end
end

function tf = isContinuous(EEG)
%ISCONTINUOUS  True for continuous (non-epoched) data, whose time axis Alakazam
%   keeps in seconds. Prefers EEG.DataFormat; falls back to the data shape.
    if isfield(EEG, 'DataFormat') && ~isempty(EEG.DataFormat)
        tf = strcmpi(EEG.DataFormat, 'CONTINUOUS');
    else
        tf = ismatrix(EEG.data) && (~isfield(EEG, 'trials') || EEG.trials <= 1);
    end
end

function u = timeUnit(EEG)
%TIMEUNIT  The unit the dataset's time axis is displayed in: 's' for continuous
%   data, 'ms' for epoched/averaged data (matching SignalView / the app).
    if isContinuous(EEG); u = 's'; else; u = 'ms'; end
end
