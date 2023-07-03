function [EEG, options] = ArtefactDetect(EEG,options)
%% Rereference the EEG data
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:ReRef','Problem in ReRef: No Data Supplied');
    throw(ME);
end
if (nargin < 2)
    options = 'Init';
end
if strcmp(options, 'Init')
    options = uiextras.settingsdlg(...
        'Description', 'Set the parameters for Artefact Detection',...
        'title' , 'Artefact Detaction Options',...
        'separator' , 'absolute limits: (mV)',...
        {'Min'; 'Minimum'}, -100, ...
        {'Max'; 'Maximum'}, 100);
end

[chans, ~, trials] = size(EEG.data);

for t = 1:trials
    for c = 1:chans
        tdat = EEG.data(c,:,t);
        if max(tdat) > options.Maximum
            EEG.data(c,:,t) = nan;
        end
        if min(tdat) < options.Minimum
            EEG.data(c,:,t) = nan;
        end
    end
end
