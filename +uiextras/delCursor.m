function delCursor(vl, event)
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here
%data = evalin('base', 'ALAKAZAM.Workspace.EEG');
id = get(vl, 'UserData');
%data.IBIevent.RTopTime(id) = [];
%data.IBIevent.ibis(id) = [];
%data.IBIevent.RTopVal(id) = [];

%evalin('base', ['ans.Workspace.EEG.IBIevent{' num2str(id(1)) '}.RTopTime(' num2str(id(2)) ') = []']);
%evalin('base', ['ans.Workspace.EEG.IBIevent{' num2str(id(1)) '}.RTopVal(' num2str(id(2)) ') = []']);
%valin('base', ['ans.Workspace.EEG.IBIevent{' num2str(id(1)) '}.ibis(' num2str(id(2)) ') = []']);
%evalin('base', "ans.Workspace.EEG.File = 'Edited'");
%evalin('base', "ans.Workspace.EEG.id = 'Edited'");
%evalin('base', 'plotCurrent(ans);');
delete(vl)

end

