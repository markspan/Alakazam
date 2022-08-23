function [EEG, options] = CutStartStop(input,opts)
%%
% CutstartStop: specific plugin for the temperature data from the
% cold-pressor test 
% 
% made for L.Lakhsassi
%
% written by: 23-8-2022 m.m.span
%%

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:CutStartStop','Problem in CutStartStop: No Data Supplied'));
end

if (nargin == 1)
    options = 'Init';
else
    options = opts;
end

STARTCHANNEL = find(strcmpi('Start', {input.chanlocs.labels}), 1);
STOPCHANNEL = find(strcmpi('Stop', {input.chanlocs.labels}), 1);
T1 = find(strcmpi('Temp 1', {input.chanlocs.labels}), 1);
T2 = find(strcmpi('Temp 2', {input.chanlocs.labels}), 1);

ExportsDir = evalin('caller', 'this.Workspace.ExportsDirectory');
if ~isfile([ExportsDir 'stats.csv'])
    f = fopen([ExportsDir 'stats.csv'], 'a');
    fprintf(f,'id\tdur\tpts\tT1Mean\tT1std\ttT2Mean\tT2std\n')
    fclose(f);
end
f = fopen([ExportsDir '/stats.csv'], "a");
EEG=input;
if ~isempty(STARTCHANNEL) && ~isempty(STOPCHANNEL)
    start = find(input.data(STARTCHANNEL,:) > 0);
    start = start(end);
    stop = find(input.data(STOPCHANNEL,:) > 0);
    stop = stop(1);
    EEG.pnts = stop - start;
    EEG.data = EEG.data(:,start:stop);
    EEG.times = EEG.times(start:stop);
    disp(['Temp 1: Mean(sd) = ' num2str(mean(EEG.data(T1,:))) '(' num2str(std(EEG.data(T1,:))) ') (n=' num2str(EEG.pnts) ') (' num2str(EEG.pnts/EEG.srate) 'sec)']);
    disp(['Temp 2: Mean(sd) = ' num2str(mean(EEG.data(T2,:))) '(' num2str(std(EEG.data(T2,:))) ')' ]);
    fprintf(f, '%s\t%3.3f\t%i\t%8.4f\t%8.4f\t%8.4f\t%8.4f\n',  EEG.id, EEG.pnts/EEG.srate, EEG.pnts, mean(EEG.data(T1,:)), std(EEG.data(T2,:)), mean(EEG.data(T2,:)), std(EEG.data(T1,:)));
end
 fclose(f) ; 

