function [EEG, options] = FlipECG(input,opts)
%% Flip the EGC trace if it is upside down....

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
