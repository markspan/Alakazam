function out = CurrentTool(transformId, restore)
%CURRENTTOOL  The transformation whose options are being asked for, so that
%   its options dialog can offer the manual of that step.
%
%   ID = TransTools.CurrentTool() is the transformation TransTools.invoke is
%   running interactively, '' outside one.
%
%   RESTORE = TransTools.CurrentTool(ID) makes ID the current one until
%   RESTORE (an onCleanup) is cleared or goes out of scope, and then puts
%   back what was there before, so a transformation that runs another one
%   inside it gets its own back afterwards.
%
%   Set by TransTools.invoke for an interactive run only: a replay asks for
%   nothing. Read by TransformOptionsDialog for its ? button.
%
%   See also TRANSTOOLS.INVOKE, MANUALADDRESS, TRANSFORMOPTIONSDIALOG.
    persistent current
    if isempty(current)
        current = '';
    end
    if nargin == 0
        out = current;
        return;
    end
    previous = current;
    current = char(string(transformId));
    out = [];
    if nargin < 2 || restore
        out = onCleanup(@() TransTools.CurrentTool(previous, false));
    end
end
