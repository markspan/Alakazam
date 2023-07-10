function [EEG, opts] = RemoveComp(EEG,~)
%% Create a poincare plot for the IBI series
% The ibis are plotted agains a time-delayed version of the same values. If
% the 'bylabel' option is used, the plot has different partitions for each
% value the label takes on.
opts = 'Init';
%#ok<*AGROW>
ropts = 'graph';
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:RemoveComp','Problem in RemoveComp: No Data Supplied');
    throw(ME);
end
if (nargin == 1)
    opts = 'Init';
end

[~, name, ~]= fileparts(EEG.File);

EEG.id = ['timefreq:' name];
pop_viewprops(EEG,0);
EEG = pop_subcomp(EEG);

