function [EEG, options] = ReRef(input, varargin)
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
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:ReRef', varargin{:});
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
    refarg = TransTools.LabelsToIdx(input, options.refChannels);
    if isempty(refarg)
        throw(MException('Alakazam:ReRef', ...
            'ReRef: I''m afraid none of the reference channels are in this dataset.'));
    end
end

extra = {};
if isfield(options, 'exclude')
    exidx = TransTools.LabelsToIdx(input, options.exclude);
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
