function [EEG, par] = Rectify(input, varargin)
%% function to cut data from first to last event in the data
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:Rectify','Problem in Rectify: No Data Supplied');
    throw(ME);
end
par = 'Init';
if (~isempty(varargin))
    par = varargin{1};
end
EEG=input;
cn = unique({input.chanlocs.labels});

if strcmp(par, 'Init')
    par = uiextras.settingsdlg(...
        'Description', 'Set the parameters for Rectify',...
        'title' , 'Rectify options',...
        'separator' , 'Parameters:',...
        {'Algorithm: '; 'alg'}, {'abs','squared'},...
        {'Use:'; 'channame'}, cn);
end

emgid = contains({input.chanlocs.labels},par.channame);
if strcmp(par.alg, 'abs')
    EEG.data(emgid,:) = abs(EEG.data(emgid,:));
elseif strcmp(par.alg, 'squared')
    EEG.data(emgid,:) = EEG.data(emgid,:).^2;
end

