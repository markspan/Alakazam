function [EEG, options] = Magnitude(input,opts)
%% Flip the EGC trace if it is upside down....

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:Magnitude','Problem in Magnitude: No Data Supplied'));
end

if (nargin == 1)
    options = 'Init';
else
    options = opts;
end

if ~isfield(input, 'data')
    throw(MException('Alakazam:Magnitude','Problem in Magnitude: No Correct Data Supplied'));
else
    EEG = input;
    ecgData = input.data;
end

if (size(ecgData,1) > 2 )
    cn = unique({input.chanlocs.labels});
    if strcmp(options, 'Init')
        options = uiextras.settingsdlg(...
            'Description', 'Set the parameters for Magnitude',...
            'title' , 'Flip options',...
            'separator' , 'Parameters:',...
            {'1st channelname'; 'cn1'}, cn, ...
            {'2nd channelname'; 'cn2'}, cn);
    end
    eye1 = strcmpi(options.cn1, {input.chanlocs.labels});
    eye2 = strcmpi(options.cn2, {input.chanlocs.labels});
else
    eye1=1;eye2=2;
    options = struct();
    options.channelname = 'Unknown1';
end
    EEG.nbchan = EEG.nbchan+1;
    EEG.chanlocs(end+1) = EEG.chanlocs(1);
    EEG.chanlocs(end).labels = 'Magnitude';
    e = [ecgData(eye1,:); ecgData(eye2,:)];
    EEG.data(end+1,:) = [nan abs(diff(sqrt(sum(e.^2))))];
end
