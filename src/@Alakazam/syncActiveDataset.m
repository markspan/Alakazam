function syncActiveDataset(this, file)
%SYNCACTIVEDATASET  Keep Workspace.EEG, Workspace.ActiveTree and
%   the tree's own visual selection in step with FILE (a tab's
%   own Tag, which is that dataset's EEG.File) whenever the
%   user's attention visibly moves to a different open dataset.
%
%   Before this existed, Workspace.EEG (the dataset a ribbon
%   transformation actually runs on) was only ever updated by
%   clicking a TREE node (onSelectionChanged/onNodeDoubleClicked)
%   -- switching tabs by clicking a tab header, or clicking a
%   different tile's own content in Grid/Stack mode, silently
%   left it unchanged. That let Workspace.EEG quietly diverge
%   from whatever dataset was actually on screen: running a
%   transformation from the ribbon would then apply to whatever
%   was last tree-selected, not the one being viewed -- root
%   cause of a "path not found" error running ScalpDistribution
%   on a visibly-active Grand Average that was not, in fact, the
%   tree's own current selection.
    file = string(file);
    currentFile = "";
    if isstruct(this.Workspace.EEG) && isfield(this.Workspace.EEG, 'File')
        currentFile = string(this.Workspace.EEG.File);
    end
    if strcmp(file, "") || strcmp(file, currentFile)
        return;
    end
    try
        loaded = load(char(file), "EEG");
    catch
        return; % the tab's own file is gone/unreadable; leave Workspace.EEG as-is
    end
    for tree = [this.Workspace.Tree, this.Workspace.GrandAveragesTree]
        nodes = tree.allNodes();
        if isempty(nodes)
            continue;
        end
        hit = nodes(strcmp({nodes.UserData}, char(file)));
        if ~isempty(hit)
            tree.SelectedNodes = hit(1);
            this.Workspace.ActiveTree = tree;
            break;
        end
    end
    this.Workspace.EEG = loaded.EEG;
end
