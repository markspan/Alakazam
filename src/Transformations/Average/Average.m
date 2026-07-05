function [EEG, opts] = Average(input,opts)
% Average - Compute the average of epoched EEG data.
%
% Syntax: [EEG, opts] = Average(input, opts)
%
% Inputs:
%   input - EEG structure containing the epoched data
%       .data - 3D matrix of EEG data (channels x samples x epochs)
%       .DataFormat - Format of the data, must be 'EPOCHED'
%       .trials - Number of trials (epochs)
%   opts - Options for the function, default is 'Init' if not provided
%
% Outputs:
%   EEG - Modified EEG structure with averaged data
%       .data - 2D matrix of averaged EEG data (channels x samples)
%       .stErr - Standard error of the mean across epochs
%       .DataFormat - Format of the data, set to 'Averaged'
%       .ntrials - Original number of trials
%       .trials - Set to 1 indicating the data is now averaged
%   opts - Options for the function, returned unchanged
%
% Description:
%   This function computes the average of epoched EEG data along the third
%   dimension (epochs). It checks the validity of the input data, ensuring
%   it is properly segmented (epoched). If the input data is valid, the
%   function calculates the mean and standard error of the mean across epochs
%   and updates the EEG structure accordingly. If any input arguments are
%   missing or invalid, an error is thrown.
%
% Example:
%   EEG = load('eeg_data.mat'); % Load EEG data
%   [EEG_avg, opts] = Average(EEG); % Compute average of epoched data
%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:Average','Problem in Average: No Data Supplied'));
end

if (nargin == 1)
    opts = 'Init';
end
% Validate input data
if ~isfield(input, 'data')
    throw(MException('Alakazam:Average','Problem in Average: No Correct Data Supplied'));
end

if (length(size(input.data)) < 3 || ~strcmpi(input.DataFormat, 'EPOCHED'))
    throw(MException('Alakazam:Average','Problem in Average: Data not Segmented'));
end

if ~isfield(input, 'trials')
    throw(MException('Alakazam:Average','Problem in Average: Trials not specified'));
end
% Compute the average across epochs
EEG = input;
EEG.ntrials = EEG.trials;
EEG.trials = 1;
EEG.data=mean(EEG.data,3,'omitnan');
EEG.stErr = (std(input.data,0,3, 'omitnan') / sqrt(input.trials));
EEG.DataFormat = "Averaged";

