function onRecalculateNode(this)
%ONRECALCULATENODE  Context-menu callback: revisit an existing
%   node's inputs. Two cases, both only ever reachable when
%   eligible (the menu item's eligibility is baked into the node
%   at creation time, see WorkSpaceTree.optsFor):
%     * a Grand Average node -- reopens GrandAverageDialog
%       pre-filled with its current sources/weighting (its name is
%       fixed), lets the analyst add/remove subjects or change the
%       weighting, then recomputes and re-saves it in place;
%     * a node produced by one of WorkSpaceTree.RecalculableTransforms
%       -- delegates to recalculateTransformNode, see there.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node)
        return;
    end

    file = node.UserData;
    ownEEG = this.loadNodeEEG(file, 'recalculate this dataset');
    if isempty(ownEEG)
        return;
    end

    if isfield(ownEEG, "etc") && isfield(ownEEG.etc, "GrandAverage")
        existingSpec = struct('name', ownEEG.id, ...
            'sources', {ownEEG.etc.GrandAverage.sources}, ...
            'weighted', ownEEG.etc.GrandAverage.weighted);

        [candidateFiles, candidateLabels] = this.findGrandAverageCandidates();
        spec = GrandAverageDialog(candidateFiles, candidateLabels, existingSpec);
        if isempty(spec)
            return; % cancelled
        end

        try
            this.saveGrandAverage(spec, node);
        catch err
            % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
            warndlg(err.message, 'Could not compute grand average');
        end
        return;
    end

    this.recalculateTransformNode(node, ownEEG);
end
