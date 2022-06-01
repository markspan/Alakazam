function [EEG, options] = Labeler(input,opts)
%% Example Transformation
% Calls the SignalLabeler App from the signal processing toolkit
% First copies the current ECG file to a labeledSignalSet to be used by the
% SignalLabeler. When finished, copies the areas to the event section of
% the EEG struct.

%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:Export','Problem in Export: No Data Supplied');
    throw(ME);
end
options = '15';
EEG=input;
lss = Tools.EEG2labeledSignalSet(input);

assignin('base',genvarname(EEG.id), lss);

existingvars = evalin('base', 'who');

signalLabeler;

uiwait(msgbox({'Operation Completed'; 'Close this box when finished labeling'}));

allvars =  evalin('base', 'who');

if length(existingvars) ~= length(allvars)
    newvar = setdiff(allvars,existingvars);
    newvar = newvar{1};
else
    newvar = 'ls'; % default when a previous variable is overwritten by the labeler.
end

EEG.lss = evalin('base', newvar);
EEG=Tools.labeledSignalSet2EEG(EEG);
pause(5);
