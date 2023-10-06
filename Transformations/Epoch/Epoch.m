function [EEG, options] = Epoch(input,opts)
%% Create Epochs from events
% given event codes create extra labels, and give them a duration.
% duration can be based on stop code, or given duration.

%#ok<*AGROW>

%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:Epoch','Problem in Epoch: No Data Supplied');
    throw(ME);
end
%% Called with options?
if (nargin == 1)
    options = 'Init';
else
    options = opts;
end
%% copy input to output.
EEG = input;

%% What events are availeable in the dataset:
if isfield(input, 'event') ...
        && isfield(input.event, 'type') ...
        && ~isempty({input.event.type})
    %&& isfield(input.event, 'code') ...
    %&& ~isempty({input.event.code}) ...

    % evc = unique({input.event.code});
    %if iscell({input.event.type})
    %    evt = unique(cell2mat({input.event.type}));
    %else
        evt = unique(string([input.event.type]));
    %end
end

%% simplest option....
if strcmp(options, 'Init')
    options = uiextras.settingsdlg(...
        'Description', 'Set the parameters for Epoch creation',...
        'title' , 'Epoch options',...
        'separator' , 'Events:',...
        {'Start'; 'tableStartLabel'}, evt, ...
        {'Use endlabel or duration';'uselab'}, {'durations', 'label'}, ...
        'separator' , 'Use Endlabels:',...
        {'Use Start/Stop?'; 'StartStop'},{'no','yes'},... 
        {'Label for end'; 'EndLabel'}, evt, ...
        'separator' , 'Use Durations:',...
        {'Preduration (ms)', 'pre'}, -100, ...
        {'Postduration (ms)', 'post'}, 900, ...
        'separator', 'originals', ...
        {'Remove Originals', 'remove'}, {'yes', 'no'} );
end
options.StartLabel = options.tableStartLabel;
if ~isStringScalar(options.StartLabel)
    options.StartLabel = string(options.StartLabel);
end

if strcmpi(options.uselab, 'label')
    events = input.event;
    starts = find(strcmpi({events.type}, options.StartLabel));
    if strcmp(options.StartStop, 'yes')
        options.EndLabel = strrep(options.StartLabel, 'Start', 'Stop');
    end
    ends = find(strcmpi({events.type}, options.EndLabel));

    if length(starts) == length(ends)
        for i = 1:length(starts)
            %EEG.event(starts(i)).latency = EEG.event(starts(i)).latency; %% in samples!
            EEG.event(starts(i)).duration = EEG.event(ends(i)).latency-EEG.event(starts(i)).latency; %% in samples!
            EEG.event(starts(i)).unit = 'samples';
            %EEG.event(i).preevent = presamp; %% in samples!
            %EEG.event(i).postevent = postsamp;         %% in samples!
        end
    end
else
    presamp =  floor(abs(options.pre/1000.0)  * EEG.srate); %(IN SAMPLES)
    postsamp = floor(abs(options.post/1000.0) * EEG.srate);

    eventstype = string([input.event.type]);

    selev = strcmpi(eventstype, 'dummyerrornext');
    for lab = options.StartLabel
        selev = selev | strcmpi(eventstype, lab);
    end

    % selev = strcmpi({events.type}, string(options.StartLabel));

    for i = 1:length(selev)
        if selev(i)
            if (presamp+postsamp+EEG.event(i).latency <= EEG.pnts) && (EEG.event(i).latency - presamp > 1)
                EEG.event(i).latency = EEG.event(i).latency - presamp; %% in samples!
                EEG.event(i).duration = presamp+postsamp; %% in samples!
                EEG.event(i).unit = 'samples';
                EEG.event(i).preevent = presamp; %% in samples!
                EEG.event(i).postevent = postsamp;         %% in samples!
            else
                EEG.event(i).type = 'ignore';
            end
        end
    end
    EEG.event = EEG.event(selev);
end