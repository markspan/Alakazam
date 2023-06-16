function [pfigure, ropts] = TimeFrequency(EEG,~)
%% Create a poincare plot for the IBI series
% The ibis are plotted agains a time-delayed version of the same values. If
% the 'bylabel' option is used, the plot has different partitions for each
% value the label takes on.

%#ok<*AGROW>
ropts = 'graph';
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:TimeFrequency','Problem in TimeFrequency: No Data Supplied');
    throw(ME);
end

[~, name, ~]= fileparts(EEG.File);

%pfigure = figure('Name', name, 'Visible', false, 'Units', 'normalized');
%figure(pfigure)
EEG.id = ['timefreq:' name];
[command,fig] = Tools.pop_newtimef(EEG,1);
pfigure = gcf;
set(gcf, 'visible', false)

