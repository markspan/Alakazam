function onClearOtherAnalyses(this)
%ONCLEAROTHERANALYSES  Ribbon action ("Clear Other", Home tab, Workspace
%   group): delete every OTHER subject's whole analysis (everything below
%   its raw import), keeping just one subject's branches untouched.
%
%   Which subject is kept:
%     - if a ROOT node is currently selected in Data & Analyses
%       (Workspace.ActiveTree is Workspace.Tree, and SelectedNodes.IsRoot),
%       that subject is kept;
%     - otherwise, the "top" subject is kept: the one whose root node was
%       created first this session (lowest WorkSpaceTree node id), a
%       stable, well-defined stand-in for "first in the list" that does not
%       depend on the tree's own key-ordering quirks (WorkSpaceTree pushes
%       nodes via containers.Map's own key order, which is lexicographic,
%       not creation order, once ids run past a single digit).
%
%   For every OTHER subject, every one of its direct child branches is
%   deleted (files, tabs, and tree nodes -- see deleteBranchFiles), which
%   recursively takes every descendant with it; the subject's own raw
%   import node/file is left alone, so it is exactly as it was right after
%   import, ready to be reprocessed (e.g. by Apply Template, then Apply to
%   All Raw Files back onto the others).
    roots = this.Workspace.Tree.allNodes();
    roots = roots([roots.IsRoot]);
    if isempty(roots)
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox('This workspace has no subjects yet.', 'Clear Other');
        return;
    end

    idNums = cellfun(@(s) str2double(regexp(s, '\d+', 'match', 'once')), {roots.Id});
    [~, topIdx] = min(idNums);
    keepId = roots(topIdx).Id;

    selected = this.Workspace.ActiveTree.SelectedNodes;
    if isequal(this.Workspace.ActiveTree, this.Workspace.Tree) && ~isempty(selected) && selected.IsRoot
        keepId = selected.Id;
    end
    keepNode = roots(strcmp({roots.Id}, keepId));
    keepName = keepNode(1).Name;

    others = roots(~strcmp({roots.Id}, keepId));
    if isempty(others)
        msgbox(sprintf('"%s" is the only subject in this workspace -- nothing to clear.', keepName), ...
            'Clear Other');
        return;
    end

    allNodes = this.Workspace.Tree.allNodes();
    victims = struct('Id', {}, 'UserData', {});
    affectedSubjects = 0;
    for r = 1:numel(others)
        rootFile = others(r).UserData;
        [folder, stem] = fileparts(rootFile);
        childDir = fullfile(folder, stem);
        if exist(childDir, "dir") ~= 7
            continue; % already unprocessed -- nothing to clear for this subject
        end
        childMat = dir(fullfile(childDir, '*.mat'));
        if isempty(childMat)
            continue;
        end
        affectedSubjects = affectedSubjects + 1;
        for k = 1:numel(childMat)
            deadFile = fullfile(childMat(k).folder, childMat(k).name);
            match = allNodes(strcmp({allNodes.UserData}, deadFile));
            if isempty(match)
                continue; % a stray cache file with no tree node -- nothing to remove from the tree
            end
            victims(end + 1) = struct('Id', match(1).Id, 'UserData', match(1).UserData); %#ok<AGROW>
        end
    end

    if isempty(victims)
        msgbox(sprintf('Every other subject is already unprocessed -- nothing to clear (kept: "%s").', keepName), ...
            'Clear Other');
        return;
    end

    % LEGACY-JAVA-GUI: questdlg, see the note near onDeleteNode. Same
    % button-label style and "safe option is the default" convention as
    % WorkSpace.rawclear's own "Clear WorkSpace" dialog, its closest
    % sibling -- adapted here to also say WHICH subject survives and how
    % much is being deleted, since (unlike a full workspace wipe) that
    % detail is the one thing worth double-checking before confirming.
    answer = questdlg(sprintf(['Are you sure you want to delete every OTHER subject''s analysis, keeping ' ...
        'only "%s"? This removes %d branch(es) across %d subject(s), and cannot be undone -- a Grand ' ...
        'Average built from a branch being removed will go stale.'], keepName, numel(victims), affectedSubjects), ...
        'Clear Other?', 'Yes, delete!', 'Sorry, what? No!', 'Sorry, what? No!');
    if ~strcmp(answer, 'Yes, delete!')
        return;
    end

    restoreBusy = beginBusy(this.MainFigure, "Clearing other subjects' analyses...");
    for k = 1:numel(victims)
        this.deleteBranchFiles(victims(k).UserData);
        this.Workspace.Tree.removeNode(victims(k).Id);
    end
end
