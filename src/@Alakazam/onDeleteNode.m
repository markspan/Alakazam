function onDeleteNode(this)
%ONDELETENODE  Context-menu callback: delete the selected node and
%   every dataset computed from it, on disk and in the tree, after
%   confirmation. Root nodes are not deletable here: that would also
%   remove everything ever computed from the source recording, a
%   much bigger action than pruning a single branch.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node) || node.IsRoot
        return; % nothing selected, or a root node
    end

    % LEGACY-JAVA-GUI: questdlg is a classic Java/AWT dialog, not
    % a uifigure -- see migration.md's "old-style Java-based
    % graphics" checklist.
    answer = questdlg( ...
        sprintf('Delete "%s" and everything computed from it? This cannot be undone.', node.Name), ...
        'Delete node', 'Delete', 'Cancel', 'Cancel');
    if ~strcmp(answer, 'Delete')
        return;
    end

    % A node's descendants are cached in a folder named after its own
    % stem, sibling to its own file (see persistResultNode).
    file = node.UserData;
    [folder, stem] = fileparts(file);
    childDir = fullfile(folder, stem);

    % Close any open tab for this node or one of its descendants
    % before their cache files disappear out from under them. Plots
    % are uitabs in PlotsTabGroup, found directly by their own Tag
    % (see AlakazamPlotter.plotCurrent). If tiled, the tab's content
    % has been reparented into TileGrid (see retile) and tagged the
    % same way -- that copy must be deleted too, or it becomes an
    % orphaned tile that outlives its own tree node.
    descendantFiles = {file};
    if exist(childDir, "dir")
        found = dir(fullfile(childDir, '**', '*.mat'));
        for k = 1:numel(found)
            descendantFiles{end + 1} = fullfile(found(k).folder, found(k).name); %#ok<AGROW>
        end
    end
    for k = 1:numel(descendantFiles)
        if strcmp(this.PickedTileTag, descendantFiles{k})
            this.PickedTileTag = ""; % avoid a stale picked-tag pointing at nothing
        end
        tiledContent = findobj(this.TileGrid.Children, 'flat', 'Tag', descendantFiles{k});
        if ~isempty(tiledContent)
            delete(tiledContent);
        end
        tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', descendantFiles{k});
        if ~isempty(tab)
            delete(tab);
        end
    end

    if exist(file, "file")
        delete(file);
    end
    if exist(childDir, "dir")
        rmdir(childDir, "s");
    end

    this.Workspace.ActiveTree.removeNode(node.Id);
end
