function persons = candidatePersonLabels(this, candidateFiles)
%CANDIDATEPERSONLABELS  The person each candidate belongs to, same order as
%   CANDIDATEFILES: WorkSpace.personFor of its root node, which is the
%   recording's own name until someone links recordings under one person. A
%   candidate with no node has '', and counts as a person of its own.
%   Matched to its node the way candidateGroupLabels is, and for the same
%   reasons.
    allNodes = this.Workspace.Tree.allNodes();
    persons = cell(1, numel(candidateFiles));
    for i = 1:numel(candidateFiles)
        persons{i} = '';
        match = allNodes(strcmp({allNodes.UserData}, candidateFiles{i}));
        if isempty(match)
            continue;
        end
        root = this.Workspace.Tree.rootOf(match(1).Id);
        if ~isempty(root)
            persons{i} = char(this.Workspace.personFor(root.Name));
        end
    end
end
