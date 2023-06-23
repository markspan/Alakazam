function [EEG, ropts] = DecomposeICA(EEG,~)
%% Create a poincare plot for the IBI series
% The ibis are plotted agains a time-delayed version of the same values. If
% the 'bylabel' option is used, the plot has different partitions for each
% value the label takes on.

%#ok<*AGROW>
ropts = 'Init';
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:DecomposeICA','Problem in DecomposeICA: No Data Supplied');
    throw(ME);
end

[~, name, ~]= fileparts(EEG.File);

%pfigure = figure('Name', name, 'Visible', false, 'Units', 'normalized');
%figure(pfigure)
EEG.id = ['timefreq:' name];
EEG = pop_runica(EEG);
EEG = pop_chanedit(EEG);
EEG=iclabel(EEG, 'beta');



