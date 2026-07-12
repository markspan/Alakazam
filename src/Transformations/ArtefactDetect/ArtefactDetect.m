function [EEG, options] = ArtefactDetect(EEG,options)
%% Mark epochs exceeding an absolute amplitude limit as NaN
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:ArtefactDetect','Problem in ArtefactDetect: No Data Supplied');
    throw(ME);
end
if (nargin < 2)
    options = 'Init';
end
if strcmp(options, 'Init')
    stored = TransformSettings.get('ArtefactDetect');
    if isempty(stored)
        stored = struct('Minimum', -100, 'Maximum', 100);
    end
    options = TransformOptionsDialog(...
        'Description', 'Set the parameters for Artefact Detection',...
        'title' , 'Artefact Detection Options',...
        'separator' , 'absolute limits: (mV)',...
        {'Min'; 'Minimum'}, stored.Minimum, ...
        {'Max'; 'Maximum'}, stored.Maximum);
    TransformSettings.set('ArtefactDetect', options);
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
