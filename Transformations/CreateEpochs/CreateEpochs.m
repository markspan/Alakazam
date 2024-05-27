function [EEG, options] = CreateEpochs(input,opts)
    %% Create Epochs from events
    % given event codes create extra labels, and give them a duration.
    % duration can be based on stop code, or given duration.
    
    %#ok<*AGROW>
    
    %% Check for the EEG dataset input:
    if (nargin < 1)
        ME = MException('Alakazam:CreateEpochs','Problem in CreateEpochs: No Data Supplied');
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
    events = input.event;
    
    startind = contains(cellstr({input.event.type}), "start", 'IgnoreCase',true);
    endind = contains(cellstr({input.event.type}), "end",'IgnoreCase',true);
    
    %startevents = events(startind);
    endevents = events(endind);

    % match the events start and end: find an end for each start
    % we will change the duration of the startevent to comply with the
    % endevent found.
    for i = 1:length(events)
        if startind(i) == 1 % is it a start?
            % what type does this start have?
            ts = strrep({events(i).type}, "start ", "");
            ts = strrep(ts, "Start ", "");
            
            % is there an end with this start type?
            endTypeEvent = {endevents.type} == "end " + ts;
            % only do this when there is only one end wiht this start
            if sum(endTypeEvent) == 1
                events(i).type = ts;
                events(i).duration = endevents(endTypeEvent).latency - events(i).latency;
            end
        end
    end
    
    % TODOremove the endevents used!
    EEG.event = events;
end