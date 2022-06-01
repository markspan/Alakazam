function lss = EEG2labeledSignalSet(EEG)
%% EEG2labeledSignalSet convert eeglab EEG structure to similar labeledsignalset
% Labels are derived from the events in the structure
% Part of Alakazam
% Mark Span 2021 (m.m.span@rug.nl)
%% -------------------------------------------------------------------------------------------
% Transform the 'data' part. Dataset and samplerate, labeled names.
    lss=[];
    if isempty(EEG) || isempty(EEG.data)
        return
    end
    TT  = array2timetable(EEG.data', ...
        'SampleRate', EEG.srate, ...
        'VariableNames', {EEG.chanlocs.labels}...
        );
    lss = labeledSignalSet(TT, 'MemberNames', EEG.id);
%% -------------------------------------------------------------------------------------------
% And now transform the event structure into labels.
% Standard labels have a duration of 1. These are translated as pointLabels
% for now. If a dataset has been translated back, ROI's are availeable
% also.

    if ~isfield(EEG, 'event')
        return
    end
    
    Events = EEG.event;
    
    if ~isfield(Events, 'code')
        return
    end
    Labels = unique(cellstr({Events.code}));
     
    for label = Labels
        labelVar = matlab.lang.makeValidName(label);
        if iscell(labelVar) 
            labelVar = char(labelVar);
        end

        addLabelDefinitions(lss,  CreateLabelDefinition(labelVar));
        addLabels(lss, labelVar, Events(strcmp(cellstr({Events.code}), label)));
    end
end
function [loc, vals, endloc] = addLabels(lss,labelVar, eventList)
    if length(eventList) > 1
        loc = lss.Source{1}.Time([eventList.latency]);
        endloc = lss.Source{1}.Time([eventList.duration]+0+[eventList.latency]);
        vals = {eventList.type};
    else
        if isnan(eventList.duration)
            eventList.duration = 1;
        end
        loc = lss.Source{1}.Time(eventList.latency);
        endloc = lss.Source{1}.Time(eventList.duration+eventList.latency);
        vals = string(eventList.type);
    end
    setLabelValue(lss, 1, labelVar, [loc,endloc], vals);
end

function SignalLabelDefinition = CreateLabelDefinition(code)
%   L = signalLabelDefinition(...,'PointLocationsDataType',TYPE) sets the
%   'PointLocationsDataType' property of the signal label definition to
%   TYPE. TYPE can be set to 'double', or 'duration'. The default is
%   'double'. A labeledSignalSet object validates point label location
%   values according to the 'PointLocationsDataType' setting. This property
%   applies only when 'LabelType' is set to 'point'.
     SignalLabelDefinition = signalLabelDefinition( code,...
          'LabelType','roi',...
          'LabelDataType','string',...
          'RoiLimitsDataType', 'duration',...
          'Description','Created from event');
end

