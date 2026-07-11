function [EEG, opts] = Baseline(input,opts)
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

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:Baseline','Problem in Baseline: No Data Supplied'));
end

if (nargin == 1)
    opts = 'Init';
end

if ~isfield(input, 'data')
    throw(MException('Alakazam:Baseline', ...
        'Problem in Baseline: this dataset has no data at all, so there is nothing to baseline-correct.'));
end

if (length(size(input.data)) < 3 || ~strcmpi(input.DataFormat, 'EPOCHED'))
    throw(MException('Alakazam:Baseline', ...
        ['Problem in Baseline: this needs segmented (epoched) data, but the selected ' ...
         'dataset is still continuous. Segment it first (e.g. with DefineBins), then ' ...
         'run Baseline on the segmented result.']));
end

if ~isfield(input, 'trials')
    throw(MException('Alakazam:Baseline', ...
        'Problem in Baseline: this dataset is missing its trial count, so it cannot be treated as segmented data.'));
end

if strcmp(opts, 'Init')
    stored = TransformSettings.get('Baseline');
    if isempty(stored)
        stored = struct('Start', -100, 'Stop', 0);
    end
    opts = uiextras.settingsdlg(...
        'Description', 'Set the parameters for Baseline',...
        'title' , 'Baseline options',...
        'separator' , 'Location:',...
        {'Start'; 'Start'}, stored.Start, ...
        {'Stop'; 'Stop'}, stored.Stop);
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
