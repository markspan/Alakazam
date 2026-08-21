function onTreeRenderError(this, eventData, sourceTree)
%ONTREERENDERERROR  Tree callback: the JS side threw while trying to
%   render a Data push (see src/webtree/src/bridge.js's applyData
%   try/catch, added after a bug -- a MATLAB struct array of exactly
%   one node serializing to a bare JSON object instead of a
%   single-element array -- silently blanked the Grand Averages tree
%   and surfaced only as a generic, unactionable "HTMLSource may be
%   referencing unsupported functionality or may have a JavaScript
%   error" console warning with no message or stack at all). Prints
%   the real message/stack MATLAB would otherwise never see; a
%   warning rather than a dialog since this always indicates a code
%   bug in src/webtree, not something the analyst can act on beyond
%   reporting it.
    if isequal(sourceTree, this.Workspace.GrandAveragesTree)
        treeName = 'Grand Averages';
    else
        treeName = 'Data & Analyses';
    end
    warning('Alakazam:treeRenderError', ...
        ['The %s tree failed to render (this is a bug in src/webtree, ' ...
         'not something wrong with your data): %s\n%s'], ...
        treeName, eventData.Message, eventData.Stack);
end
