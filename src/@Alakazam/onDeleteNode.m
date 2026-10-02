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

    % A node's descendants are cached in a folder named after its own
    % stem, sibling to its own file (see persistResultNode).
    file = node.UserData;
    [folder, stem] = fileparts(file);
    childDir = fullfile(folder, stem);
    descendantFiles = branchCacheFiles(file);

    % A grand average made from any of them keeps its numbers but loses its
    % sources: it cannot be recalculated, and is marked so afterwards. Said
    % before, so the deletion is not a surprise to find later.
    question = sprintf('Delete "%s" and everything computed from it? This cannot be undone.', node.Name);
    users = grandAveragesUsing(this.Workspace.GrandAveragesTree.allNodes(), descendantFiles);
    if ~isempty(users)
        question = sprintf(['%s\n\nThe grand average%s %s %s made from it, and would keep ' ...
            'its numbers without the datasets behind them, marked as such.'], question, ...
            pluralS(users), strjoin(strcat('"', users, '"'), ', '), isAre(users));
    end
    if ~confirmAction(this.MainFigure, question, 'Delete node', 'Delete', 'Cancel', 'Icon', 'warning')
        return;
    end

    % Close any open tab for this node or one of its descendants
    % before their cache files disappear out from under them. Plots
    % are uitabs in PlotsTabGroup, found directly by their own Tag
    % (see AlakazamPlotter.plotCurrent). If tiled, the tab's content
    % has been reparented into TileGrid (see retile) and tagged the
    % same way -- that copy must be deleted too, or it becomes an
    % orphaned tile that outlives its own tree node. An undocked plot is
    % the third place a tab's content can be (see undockTab), and its
    % window outlives the tab in exactly the same way.
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
            undocked = undockedFigureOf(tab(1));
            if ~isempty(undocked)
                delete(undocked);
            end
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
    if ~isempty(users)
        markGrandAverageSources(this.Workspace.GrandAveragesTree);
    end
end

function s = pluralS(items)
    s = '';
    if numel(items) > 1
        s = 's';
    end
end

function s = isAre(items)
    s = 'was';
    if numel(items) > 1
        s = 'were';
    end
end
