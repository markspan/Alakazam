function [EEG, options] = SelectData(input, varargin)
%% SelectData  Keep or remove data along channels, time, points and trials.
%
%   The app-styled SelectDataDialog collects a selection (the same one
%   pop_select offers); the compute delegates to EEGLAB's pop_select, called
%   programmatically from a plain options struct (no eval of a command string).
%   Channels are stored as labels and resolved to indices against the current
%   dataset, so a stored selection replays on a dataset whose channels differ.
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
    if isfield(o, 'trials') && ~strcmp(o.trials.mode, '(off)') && ~isempty(o.trials.indices)
        key = keepKey(o.trials.mode, 'trial', 'notrial');
        args = [args, {key, o.trials.indices(:)'}];
    end
end

function a = rangeArgs(o, field, keepK, removeK, scale)
    a = {};
    if isfield(o, field) && ~strcmp(o.(field).mode, '(off)')
        a = {keepKey(o.(field).mode, keepK, removeK), o.(field).range * scale};
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
