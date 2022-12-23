function [EEG, options] = Border(input, ~)
%% function to cut data from first to last event in the data
options = 'None';
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:Border','Problem in Border: No Data Supplied');
    throw(ME);
end

srate = input.srate;
events = input.event;

validevents = events(isnan(str2double(string({events.type}))));

StartTime = validevents(1).latency / srate;
EndTime = validevents(end).latency / srate;

EEG=input;

params.Param = ['[EEG, options] = pop_select( EEG,''time'',[' int2str(max(0,StartTime-1)) ' ' int2str(EndTime+1) '] );'];

[EEG, options] = SelectData(input,params);
