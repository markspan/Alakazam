function [EEG, options] = CreateEpochs(input,opts)
    %% CreateEpochs - Generate epochs from event data in an EEG dataset
    % This function processes an EEG dataset to create epochs from given event
    % codes by matching start and end events, and assigning durations based on
    % these matches.
    %
    % Syntax: [EEG, options] = CreateEpochs(input, opts)
    %
    % Inputs:
    %   input - EEG dataset structure containing event data
    %   opts - (optional) options structure
    %
    % Outputs:
    %   EEG - Updated EEG dataset with modified events including durations
    %   options - Options used or initialized during processing
    %
    % Example:
    %   EEG = CreateEpochs(EEGDataset, options);
    %
    % Notes:
    %   - The function expects event types to be labeled as 'start <type>'
    %     and 'end <type>'.
    %   - The duration of an event is calculated based on the latency
    %     difference between matching start and end events.    
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
    
    startInd = contains(cellstr({input.event.type}), "start", 'IgnoreCase',true);
    endInd = contains(cellstr({input.event.type}), "end",'IgnoreCase',true);
    
    %startevents = events(startind);
    endEvents = events(endInd);

    % match the events start and end: find an end for each start
    % we will change the duration of the startevent to comply with the
    % endevent found.
    for i = 1:length(events)
        if startInd(i) == 1 % is it a start?
            % what type does this start have?
            ts = strrep({events(i).type}, "start ", "");
            ts = strrep(ts, "Start ", ""); % for illiterate programmers
            
            % is there an end with this start type?
            endTypeEvent = {endEvents.type} == "end " + ts;
            % only do this when there is only one end wiht this start
            if sum(endTypeEvent) == 1
                events(i).type = ts;
                events(i).duration = endEvents(endTypeEvent).latency - events(i).latency;
            end
        end
    end
    
    % TODOremove the endevents used!
    EEG.event = events;
end