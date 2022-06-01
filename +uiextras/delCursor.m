function delCursor(vl, event)
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here
%data = evalin('base', 'ALAKAZAM.Workspace.EEG');
id = get(vl, 'UserData');
%data.IBIevent.RTopTime(id) = [];
%data.IBIevent.ibis(id) = [];
%data.IBIevent.RTopVal(id) = [];

evalin('base', ['ans.Workspace.EEG.IBIevent.RTopTime(' num2str(id) ') = []']);
evalin('base', ['ans.Workspace.EEG.IBIevent.RTopVal(' num2str(id) ') = []']);
evalin('base', ['ans.Workspace.EEG.IBIevent.ibis(' num2str(id) ') = []']);
evalin('base', "ans.Workspace.EEG.File = 'Edited'");
evalin('base', "ans.Workspace.EEG.id = 'Edited'");
evalin('base', 'plotCurrent(ans);');
delete(vl)

end

