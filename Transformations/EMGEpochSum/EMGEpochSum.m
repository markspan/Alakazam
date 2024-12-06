function [EEG, opts] = EMGEpochSum(input, opts)
% EMGEpochSum: Summarizes EMG data by extracting pre- and post-event values
% and writes results to a CSV file.
% Extended to include max values, mean and max over different intervals
% based on start and end events, and trial number.


%% Input Validation
if nargin < 1
    % Check if at least one argument (input data) is provided
    error('Alakazam:EMGEpochSum', 'Problem in EMGSummary: No Data Supplied');
end

if nargin == 1
    % If only input data is provided, initialize opts
    opts = 'Init';
end

% Assign input to EEG variable for processing
EEG = input;
% Extract channel labels from input

%% Initialize Options Dialog
if strcmp(opts, 'Init')
    % Create a settings dialog for the user to set parameters
    opts = uiextras.settingsdlg(...
        'Description', 'Set the parameters for EMGEpochSum',...
        'title', 'Rectify options',...
        'separator', 'Parameters:',...
        {'Scenario', 'se'}, '2', ... % Pre-event time in seconds
        {'Imagination', 'ie'}, '4', ... % washout time in seconds
        {'EndEvent:', 'ee'}, '8'); % Post-event time in seconds
end

% Extract event data from EEG structure
events = input.event;

% Process Each Event
trialnumber = 1;
csvtable = table();  % Initialize the table

for i = 1:length(events)
    if strcmp(events(i).type, ['E' int2str(opts.se)])  % scenario event
        scen_latency = events(i).latency;
        % Find the corresponding scenario imagination event
        for k = i+1:length(events)
            if strcmp(events(k).type, ['E' int2str(opts.ee)])  % event end event
                imag_latency = events(k).latency - (10 * EEG.srate);
                endevent_latency = events(k).latency;
                baseline1 = mean(EEG.data(1, scen_latency - (.5*EEG.srate):scen_latency));
                scenario1 = mean(EEG.data(1, scen_latency:imag_latency));
                imagination1 = mean(EEG.data(1, imag_latency:endevent_latency));
                baseline2 = mean(EEG.data(2, scen_latency - (.5*EEG.srate):scen_latency));
                scenario2 = mean(EEG.data(2, scen_latency:imag_latency));
                imagination2 = mean(EEG.data(2, imag_latency:endevent_latency));

                % Create a table row for current event data
                eventnr = i;

                line = table(trialnumber, baseline1, scenario1, imagination1, baseline2, scenario2, imagination2 );

                % Append to CSV table or initialize if not exists
                if exist('csvtable', 'var')
                    csvtable = [csvtable; line]; %#ok<AGROW>
                else
                    csvtable = line;
                end

                trialnumber = trialnumber + 1;
                break;  % Break out of the inner loop once ee is found
            end
        end
    end
end

% Export Results to CSV
[~,name,~] = fileparts(EEG.filename);

ExportsDir = evalin('caller', 'this.Workspace.ExportsDirectory');
writetable(csvtable, fullfile(ExportsDir, [name, '.EE.csv']));
end
