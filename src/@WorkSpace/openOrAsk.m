function openOrAsk(this, alert)
%OPENORASK  Open the workspace, or, when folders it names do not exist on
%   this computer, say so and open Edit WorkSpace instead.
%
%   OPENORASK(THIS) is what starting Alakazam with a workspace, and Open
%   WorkSpace, do. When every folder exists the workspace opens as before
%   (open). When one does not, a message lists the missing folders and,
%   once it is closed, Edit WorkSpace opens with the workspace's folders
%   filled in; its OK opens the workspace. Nothing is created or changed
%   before then.
%
%   This used to go straight to open(), which made any missing folder it
%   could: a Raw folder whose data had moved to another disk came back as
%   a new empty folder, and the tree as an empty tree, with nothing to say
%   why.
%
%   OPENORASK(THIS, ALERT) shows the message with ALERT, called as uialert
%   is (figure, message, title, name-value pairs with a CloseFcn); the
%   tests pass their own.
%
%   See also WORKSPACE.MISSINGDIRECTORIES, WORKSPACE.EDIT, WORKSPACE.OPEN.
    if nargin < 2
        alert = @uialert;
    end
    missing = this.missingDirectories();
    if isempty(missing)
        this.open();
        return;
    end

    lines = arrayfun(@(m) sprintf('    %s:  %s', m.label, displayPath(m.path)), missing, ...
        'UniformOutput', false);
    if isscalar(missing)
        folders = 'a folder';
        them = 'it is';
    else
        folders = 'folders';
        them = 'they are';
    end
    message = sprintf([ ...
        'I am terribly sorry to trouble you, but this workspace refers to %s that ' ...
        'I cannot find on this computer:\n\n%s\n\n' ...
        'Perhaps the data have been moved, or the workspace was made on another ' ...
        'computer. Would you be so very kind as to tell me where %s now? I will open ' ...
        'Edit WorkSpace for you as soon as you close this message. Nothing has been ' ...
        'changed or created in the meantime, and I am most grateful for your patience.'], ...
        folders, strjoin(lines, newline), them);
    parentFigure = [];
    if isprop(this.Parent, 'MainFigure') && isvalid(this.Parent.MainFigure)
        parentFigure = this.Parent.MainFigure;
    end
    alert(parentFigure, message, 'Where might I find this workspace''s folders?', ...
        'Icon', 'warning', 'CloseFcn', @(~, ~) this.edit());
end

function text = displayPath(path)
    text = path;
    if isempty(text)
        text = '(not set)';
    end
end
