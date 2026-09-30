function onRecalculateNode(this)
%ONRECALCULATENODE  Context-menu callback: revisit an existing
%   node's inputs. Two cases, both only ever reachable when
%   eligible (the menu item's eligibility is baked into the node
%   at creation time, see WorkSpaceTree.optsFor):
%     * a Grand Average node -- reopens GrandAverageDialog
%       pre-filled with its current sources/weighting (its name is
%       fixed), lets the user add/remove subjects or change the
%       weighting, then recomputes and re-saves it in place;
%     * a node produced by one of WorkSpaceTree.RecalculableTransforms
%       -- delegates to recalculateTransformNode, see there.
%
%   THE GRAND AVERAGE IS THE ROOT NODE, not any node whose data carries
%   etc.GrandAverage: every step run on a grand average keeps that record,
%   so a Filter under one carried it too, and Recalculate on the Filter
%   reopened the grand average's subject list and recomputed the grand
%   average, leaving the filter as it was. A grand average is always a
%   top-level node of the Grand Averages tree (saveGrandAverage), and the
%   steps under it are ordinary transformation nodes.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node)
        return;
    end

    file = node.UserData;
    ownEEG = this.loadNodeEEG(file, 'recalculate this dataset');
    if isempty(ownEEG)
        return;
    end

    isGrandAverageNode = node.IsRoot && isfield(ownEEG, "etc") && isfield(ownEEG.etc, "GrandAverage");
    if isGrandAverageNode
        existingSpec = struct('name', ownEEG.id, ...
            'sources', {ownEEG.etc.GrandAverage.sources}, ...
            'weighted', ownEEG.etc.GrandAverage.weighted);

        [candidateFiles, candidateLabels, candidateKinds] = this.findGrandAverageCandidates();
        spec = GrandAverageDialog(candidateFiles, candidateLabels, candidateKinds, existingSpec);
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
