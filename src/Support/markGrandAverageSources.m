function markGrandAverageSources(tree)
%MARKGRANDAVERAGESOURCES  Relabel each grand average in TREE (the Grand
%   Averages tree) by grandAverageLabel, so one whose sources were deleted
%   says so. Called after anything that deletes branches; a label already
%   right is left alone, so the tree is redrawn only for a change.
%
%   See also GRANDAVERAGELABEL, ONDELETENODE, ONCLEAROTHERANALYSES.
    nodes = tree.allNodes();
    for i = 1:numel(nodes)
        if ~nodes(i).IsRoot
            continue;
        end
        label = grandAverageLabel(nodes(i).UserData);
        if ~isempty(label) && ~strcmp(label, nodes(i).Name)
            tree.renameNode(nodes(i).Id, label);
        end
    end
end
