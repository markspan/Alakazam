function [EEG, opts] = Average(input,opts)
%% Flip the EGC trace if it is upside down....

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:Average','Problem in Average: No Data Supplied'));
end

if (nargin == 1)
    opts = 'Init';
end

if ~isfield(input, 'data')
    throw(MException('Alakazam:Average','Problem in Average: No Correct Data Supplied'));
end

if (length(size(input.data)) < 3 || ~strcmpi(input.DataFormat, 'EPOCHED'))
    throw(MException('Alakazam:Average','Problem in Average: Data not Segmented'));
end

if ~isfield(input, 'trials')
    throw(MException('Alakazam:Average','Problem in Average: Trials not specified'));
end

% if strcmp(opts, 'Init')
%     opts = uiextras.settingsdlg(...
%         'Description', 'Set the parameters for Average',...
%         'title' , 'Average options',...
%         'separator' , 'Location:',...
%         {'Start'; 'Start'}, -100, ...
%         {'Stop'; 'Stop'}, 0);
% end

EEG = input;
EEG.ntrials = EEG.trials;
EEG.trials = 1;
EEG.data=mean(EEG.data,3,'omitnan');
EEG.stDev = std(input.data,0,3, 'omitnan');

