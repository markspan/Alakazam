function [EEG, options] = SelectData(input, opts)
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
if nargin < 1
    throw(MException('Alakazam:SelectData', 'Problem in SelectData: No Data Supplied'));
end
if nargin < 2
    opts = 'Init';
end

interactive = (ischar(opts) || isstring(opts)) && strcmpi(string(opts), "Init");
if interactive
    options = SelectDataDialog(input.chanlocs, size(input.data, 2), size(input.data, 3), ...
        TransformSettings.get('SelectData'));
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

% EEGLAB sometimes leaves EEG.times in seconds after pop_select; this ratio
% check (real recordings are well under 500x xmax/times(end) when both are in
% the same unit) detects and corrects that rather than assuming a fixed unit.
if isfield(EEG, 'times') && ~isempty(EEG.times) && (EEG.xmax / EEG.times(end) > 500)
    EEG.times = EEG.times * 1000;
end
end

% ======================================================================= %
function args = buildSelectArgs(input, o)
%BUILDSELECTARGS  The pop_select name/value arguments for one options struct.
    args = {};
    if isfield(o, 'channels') && ~strcmp(o.channels.mode, '(off)')
        idx = labelsToIdx(input, o.channels.labels);
        if strcmp(o.channels.mode, 'Keep')
            if isempty(idx)
                throw(MException('Alakazam:SelectData', ...
                    'SelectData: none of the channels to keep are in this dataset.'));
            end
            args = [args, {'channel', idx}];
        elseif ~isempty(idx)
            args = [args, {'nochannel', idx}];
        end
    end
    args = [args, rangeArgs(o, 'time',   'time',  'notime',  1 / 1000)];  % ms -> s
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

function idx = labelsToIdx(input, wantLabels)
%LABELSTOIDX  Row indices in EEG.chanlocs of WANTLABELS (case-insensitive),
%   in dataset order; labels not present are skipped.
    all = {input.chanlocs.labels};
    want = cellfun(@(s) char(string(s)), wantLabels, 'UniformOutput', false);
    idx = find(ismember(lower(all), lower(want)));
end
