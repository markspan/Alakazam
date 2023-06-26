function [EEG,options] = Segmentation(input,opts)
% Segment data given a label
%   Detailed explanation goes here
EEG=input;
%% Called with options?
if (nargin == 1)
    options = 'Init';
else
    options = opts;
end
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:Segmentation','Problem in Segmentation: No Data Supplied');
    throw(ME);
end
%% Are there events availeable in the dataset:
if isfield(input, 'event') ...
        && isfield(input.event, 'type') ...
        && ~isempty({input.event.type}) ...
        && isfield(input.event, 'duration') ...
        && ~isempty({input.event.duration}) 
        
        %&& isfield(input.event, 'code') ...
        %&& ~isempty({input.event.code}) ...

    %%select those events that have a uniform length
    types = {input.event.type};
    durations = zeros(1,length(input.event));
    empties = cellfun(@isempty, {input.event.duration});
    nonempties = ~empties;
    durations(nonempties) = [input.event.duration];
    durations(empties) = 0;
    %durations = {input.event.duration};
    %codes = {input.event.code};
    uniformtypes={};

    for e = unique(types)
        evtdurs = unique(durations(strcmp(types,e)));
        if isempty(evtdurs) 
            uniformtypes{end+1} = char(e); %#ok<AGROW> 
        elseif  (length(evtdurs) == 1 && ~isnan(evtdurs) && evtdurs > 0)
            uniformtypes{end+1} = char(e); %#ok<AGROW> 
        end
    end
    %uniformtypes = uniformtypes{2:end};
    %% incorrect: only works for now.
    uniformtypes = unique(types(durations>0));

%% simplest option....
if strcmp(options, 'Init')
    options = uiextras.settingsdlg(...
        'Description', 'Set the parameters for Segmentation creation',...
        'title' , 'Segmentation options',...
        'separator' , 'Events:',...
        {'Start'; 'tableLabel'}, uniformtypes);
else    
    if isempty(uniformtypes) 
        ME = MException('Alakazam:Segmentation','Problem in Segmentation: No events with duration. Try Epoch');
        throw(ME);    
    end
end

slabel = options.tableLabel;
selection = [];
for l = slabel
    selection = [selection input.event(strcmpi({input.event.type}, l))]; %#ok<AGROW> 
end

% Now restructure the data and create a 3D dataset with trials in the
% z-direction... (channels:points:trials)

EEG.trials = length(selection);
EEG.pnts   = selection(1).duration; %(as they are confirmed uniform)
if (isfield(selection(1), 'preevent') && isfield(selection(1), 'postevent'))
    EEG.times = 1000 * ((-selection(1).preevent:selection(1).postevent-1)/EEG.srate);
end

data = EEG.data;
EEG.data = zeros(EEG.nbchan,EEG.pnts, EEG.trials);
for i = 1:EEG.trials
    EEG.data(:,:,i) = data(:,selection(i).latency:selection(i).latency+(EEG.pnts-1));
end
EEG.DataFormat = 'EPOCHED';
end