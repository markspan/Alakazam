function [EEG, opts] = Baseline(input, varargin)
%% corrects the EEG data by subtracting
%   the mean of a specified baseline period from each data point within each trial.
%
%   Inputs:
%       input - Struct containing the EEG dataset and related information.
%       opts  - Struct containing options for baseline correction. If not provided,
%               default settings dialog is prompted.
%
%   Outputs:
%       EEG   - Struct of the baseline-corrected EEG dataset.
%       opts  - Struct containing the used or updated baseline options.

[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Baseline', varargin{:});

if ~isfield(input, 'data')
    throw(MException('Alakazam:Baseline', ...
        'Problem in Baseline: I''m afraid this dataset has no data at all, so there is nothing to baseline-correct.'));
end

% TransTools.FieldOr, not a bare input.DataFormat: this condition is true when
% the field is ABSENT as well as when it is wrong, and reading it directly then
% throws a raw "Unrecognized field name" from inside the very message meant to
% explain the problem. The format is named rather than assumed to be
% continuous, since the commonest way to reach this is running Baseline on an
% Average node, which is averaged, not continuous.
dataFormat = char(string(TransTools.FieldOr(input, 'DataFormat', 'not set')));
if (length(size(input.data)) < 3 || ~strcmpi(dataFormat, 'EPOCHED'))
    throw(MException('Alakazam:Baseline', sprintf([ ...
        'Problem in Baseline: this needs segmented (epoched) data, and this dataset ' ...
        'is not (DataFormat = "%s"). Please segment it first (e.g. with DefineBins), ' ...
        'then run Baseline on the segmented result -- baseline correction belongs ' ...
        'before Average, not after it.'], dataFormat)));
end

if ~isfield(input, 'trials')
    throw(MException('Alakazam:Baseline', ...
        'Problem in Baseline: I''m afraid this dataset is missing its trial count, so it cannot be treated as segmented data.'));
end

if interactive
    stored = TransformSettings.get('Baseline');
    if isempty(stored)
        stored = struct('Start', -100, 'Stop', 0);
    end
    opts = TransformOptionsDialog(...
        'Description', 'Set the parameters for Baseline',...
        'title' , 'Baseline options',...
        'separator' , 'Location:',...
        {'Start'; 'Start'}, stored.Start, ...
        {'Stop'; 'Stop'}, stored.Stop);
    if isempty(opts)
        % Cancelled: nothing to persist (leave the remembered settings
        % untouched) and nothing to run -- Alakazam.onTransformation
        % treats an empty EEG as "cancelled", not an error.
        EEG = [];
        opts = [];   % the contract is two outputs; both must be assigned
        % (named for THIS function's own second output: assigning a
        % variable called "options" here left opts holding the Init
        % sentinel, which is what the caller then tried to store)
        return;
    end
    TransformSettings.set('Baseline', opts);
end

[~,zeropoint] = min(abs(input.times));

start = max(1, floor((opts.Start * input.srate / 1000)) + zeropoint);
stop = min(size(input.data,2), floor((opts.Stop * input.srate / 1000)) + zeropoint);

EEG = input;
for i = 1:EEG.trials
    for c = 1:EEG.nbchan
        bl = mean(EEG.data(c,start:stop,i));
        EEG.data(c,:,i) = EEG.data(c,:,i) - bl;
    end
end
