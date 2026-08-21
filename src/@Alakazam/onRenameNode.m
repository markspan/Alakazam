function onRenameNode(this)
%ONRENAMENODE  Context-menu callback: rename the selected node.
%   Prompts for a new label and persists it both to the tree (its
%   display name) and to the underlying cached dataset's id
%   (EEG.id, re-saved to its own file) -- not just the currently
%   active dataset, since a right-click need not target it. Root
%   nodes are not renamable here.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node) || node.IsRoot
        return; % nothing selected, or a root node
    end

    % LEGACY-JAVA-GUI: inputdlg is a classic Java/AWT dialog, not
    % a uifigure -- see migration.md's "old-style Java-based
    % graphics" checklist.
    answer = inputdlg('New name:', 'Rename node', 1, {node.Name});
    if isempty(answer)
        return; % cancelled
    end
    newName = strtrim(answer{1});
    if isempty(newName)
        return;
    end

    file = node.UserData;
    EEG = this.loadNodeEEG(file, 'rename this dataset');
    if isempty(EEG)
        return;
    end
    EEG.id = newName; % saved to disk under the variable name "EEG"
    save(file, "EEG");

    this.Workspace.ActiveTree.renameNode(node.Id, newName);

    % Keep the in-memory active dataset in sync if it is this node.
    if isequal(this.Workspace.EEG.File, file)
        this.Workspace.EEG.id = newName;
    end
end
