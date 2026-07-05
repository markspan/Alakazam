function [EEG, options] = Border(input, ~)
    % Border - Cuts EEG data from the first to the last valid event.
    %
    % This function trims the EEG data to only include the time window from the
    % first to the last valid event, excluding specific event types such as 'Impedance'
    % and 'Boundary'.
    %
    % Syntax:
    %   [EEG, options] = Border(input, ~)
    %
    % Inputs:
    %   input - Struct containing the EEG data with fields 'srate' (sampling rate),
    %           'event' (array of event structs), and 'times' (array of time points).
    %   ~     - Ignored input, can be used to match the expected function signature.
    %
    % Outputs:
    %   EEG     - The input EEG struct trimmed to the specified time window.
    %   options - Options string, set to 'None'.
    %
    % Example:
    %   % Load EEG data
    %   load('EEG.mat');
    %   % Trim EEG data based on events
    %   [EEG, options] = Border(EEG, []);
    %
    % See also: pop_select, SelectData

    %% Initialize options
    options = 'None';

    %% Check for the EEG dataset input
    if nargin < 1
        error('Border:NoData', 'No EEG data supplied.');
    end

    %% Extract necessary information from input
    srate = input.srate;
    events = input.event;

    %% Filter valid events
    validevents = events(isnan(str2double(string({events.type}))) & ...
                         ~strcmpi({events.type}, 'Impedance') & ...
                         ~strcmpi({events.type}, 'Boundary'));

    %% Determine start and end times based on valid events
    StartTime = validevents(1).latency / srate;
    EndTime = validevents(end).latency / srate;

    %% Create parameter string for SelectData function
    params.Param = ['[EEG, options] = pop_select(EEG, ''time'', [' ...
                    num2str(max(0, StartTime - 1)) ' ' ...
                    num2str(min(EndTime + 1, input.times(end))) ']);'];

    %% Trim the EEG data using the SelectData function
    [EEG, options] = SelectData(input, params);
end
