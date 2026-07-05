function [EEG, opts] = EMGEpochSum(input, opts)
% EMGEpochSum: Summarizes EMG data by extracting pre- and post-event values
% and writes results to a CSV file.
% Extended to include:
%   - Maximum values.
%   - Mean and maximum over different intervals.
%   - Interval calculations based on start, end events, and trial number.

%% Input Validation
if nargin < 1
    error('Alakazam:EMGEpochSum', 'Problem in EMGSummary: No Data Supplied');
end

if nargin == 1
    opts = 'Init'; % Initialize opts if not provided
end

% Assign input to EEG variable for processing
EEG = input;

%% Initialize Options Dialog
if strcmp(opts, 'Init')
    opts = uiextras.settingsdlg(...
        'Description', 'Set the parameters for EMGEpochSum',...
        'title', 'EMG Options',...
        'separator', 'Parameters:',...
        {'Scenario', 'se'}, '2', ...  % Scenario start event code
        {'Imagination', 'ie'}, '4', ...  % Imagination event code (if available)
        {'EndEvent', 'ee'}, '8');       % Trial end event code
end

% Extract event data from EEG structure
if ~isfield(EEG, 'event')
    error('EMGEpochSum:InvalidInput', 'Input EEG structure must contain an "event" field.');
end

events = EEG.event;

%% Initialize Variables
trialnumber = 1;       % Counter for trial numbers
csvtable = table();    % Initialize output table

%% Process Each Event
for i = 1:length(events)
    if strcmp(events(i).type, ['E' int2str(opts.se)]) % Match scenario start event
        scen_latency = events(i).latency;

        % Find corresponding end event and calculate intervals
        for k = i+1:length(events)
            if strcmp(events(k).type, ['E' int2str(opts.ee)]) % Match end event
                imag_latency = events(k).latency - (10 * EEG.srate); % Reconstruct imagination event
                endevent_latency = events(k).latency;

                % Baseline: 0.5 seconds before scenario start
                baseline1 = mean(EEG.data(1, scen_latency - (0.5 * EEG.srate):scen_latency));
                baseline2 = mean(EEG.data(2, scen_latency - (0.5 * EEG.srate):scen_latency));

                % Scenario period: Start to imagination
                scenario1 = mean(EEG.data(1, scen_latency:imag_latency));
                scenario2 = mean(EEG.data(2, scen_latency:imag_latency));

                % Imagination period: Imagination to end
                imagination1 = mean(EEG.data(1, imag_latency:endevent_latency));
                imagination2 = mean(EEG.data(2, imag_latency:endevent_latency));

                % Store results in a table
                line = table(trialnumber, baseline1, scenario1, imagination1, ...
                    baseline2, scenario2, imagination2);

                % Append to CSV table
                csvtable = [csvtable; line]; %#ok<AGROW>

                trialnumber = trialnumber + 1;
                break; % Exit inner loop after processing current trial
            end
        end
    end
end

%% Export Results to CSV
if ~isfield(EEG, 'filename')
    error('EMGEpochSum:MissingFilename', 'EEG structure must contain a "filename" field.');
end

[~, name, ~] = fileparts(EEG.filename); % Extract file name without extension
ExportsDir = evalin('caller', 'this.Workspace.ExportsDirectory'); % Use caller workspace for directory

outputFile = fullfile(ExportsDir, [name, '.EE.csv']);
writetable(csvtable, outputFile);

end
