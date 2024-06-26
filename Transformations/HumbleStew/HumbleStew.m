function [EEG, options] = HumbleStew(input,opts)
%%
% HumbleStew: specific plugin for the temperature data from the
% cold-pressor test 
% 
% made for L.Lakhsassi
%
% written by: 23-8-2022 m.m.span
%%

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:HumbleStew','Problem in HumbleStew: No Data Supplied'));
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
if ~isfile([ExportsDir 'Stew.csv'])
    f = fopen([ExportsDir 'Stew.csv'], 'a');
    fprintf(f,'id,dur,pts,T1Mean,T1std,tT2Mean,T2std\n');
    fclose(f);
end
f = fopen([ExportsDir '/Stew.csv'], "a");
EEG=input;
if ~isempty(STARTCHANNEL) && ~isempty(STOPCHANNEL)
    start = find(input.data(STARTCHANNEL,:) > 0);
    if isempty(start)
         throw(MException('Alakazam:HumbleStew','Problem in HumbleStew: No Start code'));
    end
    start = start(end);
    stop = find(input.data(STOPCHANNEL,:) > 0);
    if isempty(stop)
         stop = EEG.pnts;
         disp("No endpoint. Using the last sample as end.")
    end
    stop = stop(1);
    EEG.pnts = stop - start;
    EEG.data = EEG.data(:,start:stop);
    EEG.times = EEG.times(start:stop);
    disp(['Temp 1: Mean(sd) = ' num2str(mean(EEG.data(T1,:))) '(' num2str(std(EEG.data(T1,:))) ') (n=' num2str(EEG.pnts) ') (' num2str(EEG.pnts/EEG.srate) 'sec)']);
    disp(['Temp 2: Mean(sd) = ' num2str(mean(EEG.data(T2,:))) '(' num2str(std(EEG.data(T2,:))) ')' ]);
    fprintf(f, '%s,%f,%i,%f,%f,%f,%f\n',  EEG.id, EEG.pnts/EEG.srate, EEG.pnts, mean(EEG.data(T1,:)), std(EEG.data(T2,:)), mean(EEG.data(T2,:)), std(EEG.data(T1,:)));
else
        throw(MException('Alakazam:HumbleStew','Problem in HumbleStew: No Start and/or Stop channel defined'));
end
 fclose(f) ; 

