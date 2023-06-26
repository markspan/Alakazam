function [EEG, ropts] = ReRef(EEG,init)
%% Rereference the EEG data
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:ReRef','Problem in ReRef: No Data Supplied');
    throw(ME);
end
%% TODO
ropts = 'Init';
EEG = pop_reref(EEG);



