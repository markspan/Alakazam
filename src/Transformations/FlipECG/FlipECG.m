function [EEG, options] = FlipECG(input,opts)
% FlipECG Flips the ECG trace upside down if necessary.
%
%   [EEG, options] = FlipECG(input, opts) flips the ECG trace data in the
%   EEG structure provided in 'input'. The flipping is performed for the
%   channel specified by 'opts.channelname' if 'opts' is provided. If 'opts'
%   is not provided, or 'opts' is 'Init', the function prompts the user
%   to select a channel for flipping using a settings dialog.
%
%   Input Arguments:
%   ----------------
%   input : struct
%       EEG structure containing ECG data and metadata.
%
%   opts : struct or string, optional
%       Options for flipping. If provided as a struct, should contain the
%       field 'channelname' specifying the channel to flip. If 'Init' is
%       passed, prompts the user to select the channel via a dialog.
%
%   Output Arguments:
%   -----------------
%   EEG : struct
%       Updated EEG structure with flipped ECG data.
%
%   options : struct or string
%       Updated options structure. If 'opts' was 'Init' and user input was
%       provided, 'options' will contain the selected channelname.
%
%   Notes:
%   ------
%   - The function assumes 'input' is an EEG structure with at least a
%     'data' field containing ECG data.
%   - If multiple channels are present and 'opts' is not provided or is
%     'Init', the user is prompted to select a channel via a dialog.
%   - Flipping is performed by inverting the ECG signal around its median
%     value for the specified channel.
%   - If 'input' includes 'Polarchannels', the function also flips the data
%     for the specified channel in 'Polarchannels'.
%
%   Example:
%   --------
%   % Create a sample EEG structure
%   EEG.data = randn(4, 100); % 4 channels of random data
%   EEG.chanlocs.labels = {'ECG1', 'ECG2', 'ECG3', 'ECG4'};
%
%   % Flip the ECG data for channel 'ECG2'
%   opts.channelname = 'ECG2';
%   [EEG, options] = FlipECG(EEG, opts);
%
%   See also: uiextras.settingsdlg
%
%   Reference: Alakazam Toolbox Documentation
%
%   Author: M.M.Span
%   Created: 17/6/2022
%   Updated: 17/6/2024
%
%   Version: 1.0
%   License: GPL 2.0 or newer
%
%   Contact: m.m.span@rug.nl

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:FlipECG','Problem in FlipECG: No Data Supplied'));
end

if (nargin == 1)
    options = 'Init';
else
    options = opts;
end

if ~isfield(input, 'data')
    throw(MException('Alakazam:FlipECG','Problem in FlipECG: No Correct Data Supplied'));
else
    EEG = input;
    ecgData = input.data;
end

if (size(ecgData,1) > 1 )
    cn = unique({input.chanlocs.labels});
    if strcmp(options, 'Init')
        options = uiextras.settingsdlg(...
            'Description', 'Set the parameters for flipECG',...
            'title' , 'Flip options',...
            'separator' , 'Parameters:',...
            {'Use:'; 'channelname'}, cn);
    end
    ecgid = strcmpi(options.channelname, {input.chanlocs.labels});
else
    ecgid=1;
    options = struct();
    options.channelname = 'Unknown1';
end

if sum(ecgid) > 0
    %% there is an ECG trace: flip it
    for c = 1:input.nbchan
        if ecgid(c) 
            channel_ecgData = ecgData(c,:);
            necgData = -(channel_ecgData - median(channel_ecgData,2)) + median(channel_ecgData,2);
            EEG.data(c,:) = necgData;
        end
    end
    if isfield(input, 'Polarchannels')
        for c = 1:input.Polarchannels.nbchan
            if strcmp(input.Polarchannels.chanlocs.labels, options.channelname)
                channel_ecgData = input.Polarchannels.data(c,:);
                necgData = -(channel_ecgData - median(channel_ecgData,2)) + median(channel_ecgData,2);
                EEG.Polarchannels.data(c,:) = necgData;
            end
        end
    end

else
    throw(MException('Alakazam:FlipECG','Problem in FlipECG: No ECG trace Found/Supplied'));
end
end
