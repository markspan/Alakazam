function [EEG, options] = ReRef(input, opts)
%% ReRef  Re-reference the data to the average, or to specific channel(s).
%
%   The app-styled ReRefDialog collects the reference choice (the same one
%   pop_reref offers); the compute delegates to EEGLAB's pop_reref, called
%   programmatically from a plain options struct (no eval of a command string).
%   Reference / exclude channels are stored as labels and resolved to indices
%   against the current dataset, so a stored choice replays on a dataset whose
%   channels differ.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = ReRef(input)        % interactive dialog
%     [EEG, options] = ReRef(input, opts)  % replay a stored options struct
if nargin < 1
    throw(MException('Alakazam:ReRef', 'Problem in ReRef: No Data Supplied'));
end
if nargin < 2
    opts = 'Init';
end

interactive = (ischar(opts) || isstring(opts)) && strcmpi(string(opts), "Init");
if interactive
    options = ReRefDialog(input.chanlocs, TransformSettings.get('ReRef'));
    if isempty(options)
        EEG = [];   % cancelled -- no node, no compute (see Alakazam.onTransformation)
        return;
    end
    TransformSettings.set('ReRef', options);
else
    options = opts;
end

if strcmpi(options.mode, 'Average')
    refarg = [];
else
    refarg = labelsToIdx(input, options.refChannels);
    if isempty(refarg)
        throw(MException('Alakazam:ReRef', ...
            'ReRef: none of the reference channels are in this dataset.'));
    end
end

extra = {};
if isfield(options, 'exclude')
    exidx = labelsToIdx(input, options.exclude);
    if ~isempty(exidx)
        extra = [extra, {'exclude', exidx}];
    end
end
keepref = isfield(options, 'keepref') && logical(options.keepref);
if keepref
    extra = [extra, {'keepref', 'on'}];
else
    extra = [extra, {'keepref', 'off'}];
end

EEG = pop_reref(input, refarg, extra{:});
end

% ======================================================================= %
function idx = labelsToIdx(input, wantLabels)
    if isempty(wantLabels); idx = []; return; end
    all = {input.chanlocs.labels};
    want = cellfun(@(s) char(string(s)), wantLabels, 'UniformOutput', false);
    idx = find(ismember(lower(all), lower(want)));
end
