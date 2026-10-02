function reason = moveDroppedBranch(this, source, target, tree)
%MOVEDROPPEDBRANCH  Move a dragged branch onto a target dataset (a Shift-drop).
%   REASON = MOVEDROPPEDBRANCH(THIS, SOURCE, TARGET, TREE) re-applies
%   SOURCE's branch onto TARGET, as a plain drop does (evaluateDroppedBranch),
%   and then removes the original from disk, from any open tab and from TREE,
%   as Delete does. A branch's results depend on the dataset under it, so a
%   move recomputes them all the same; what it adds is the removal. REASON is
%   '' when the branch moved, and otherwise says why the original was kept,
%   for onNodeDropped to show. It is kept when
%     - TARGET lies in the branch itself, which removing it would take with
%       it. The tree cannot drop a node on its own descendants, since the
%       dragged row carries them, but a stale event is refused all the same;
%     - a dataset in the branch is a grand average's source. A grand average
%       records its sources and recalculates from them, so it would be left
%       pointing at files that are gone. Nothing is made;
%     - not every dataset was made again, which happens when an average is
%       dropped onto a matching average: that overlays the two, and the
%       overlay is all the drop does.
%   An error while re-applying the branch is not caught here: it reaches
%   onNodeDropped before anything was removed.
%
%   See also ONNODEDROPPED, EVALUATEDROPPEDBRANCH, DELETEBRANCHFILES.
    reason = '';
    sourceFile = char(string(source.UserData));
    targetFile = char(string(target.UserData));
    [folder, stem] = fileparts(sourceFile);
    branchFolder = fullfile(folder, stem);

    if strcmp(pathKey(targetFile), pathKey(sourceFile)) ...
            || startsWith(pathKey(targetFile), pathKey([branchFolder filesep]))
        reason = sprintf(['"%s" cannot be moved onto a dataset in its own branch: ' ...
            'removing the original would remove the target too.'], source.Name);
        return;
    end

    % The datasets the move removes, as evaluateDroppedBranch walks them: the
    % node's own file and every result cached under its folder.
    branchFiles = {sourceFile};
    if isfolder(branchFolder)
        found = dir(fullfile(branchFolder, '**', '*.mat'));
        for k = 1:numel(found)
            branchFiles{end + 1} = fullfile(found(k).folder, found(k).name); %#ok<AGROW>
        end
    end

    users = grandAveragesUsing(this, branchFiles);
    if ~isempty(users)
        if isscalar(users)
            who = sprintf('the grand average "%s" draws', users{1});
        else
            who = sprintf('the grand averages %s draw', strjoin(strcat('"', users, '"'), ', '));
        end
        reason = sprintf(['"%s" was not moved: %s on datasets in its branch, and would be ' ...
            'left without them. Drop it without Shift to copy it instead, or define the ' ...
            'grand average again without them first.'], source.Name, who);
        return;
    end

    nCreated = this.evaluateDroppedBranch(sourceFile, target);
    if nCreated < numel(branchFiles)
        if nCreated == 0
            why = 'an average dropped onto a matching average is overlaid, not moved';
        else
            why = sprintf('only %d of its %d datasets were made again', nCreated, numel(branchFiles));
        end
        reason = sprintf('"%s" was kept where it was: %s.', source.Name, why);
        return;
    end

    this.deleteBranchFiles(sourceFile);
    tree.removeNode(source.Id);
end

% ======================================================================= %
function names = grandAveragesUsing(this, files)
%GRANDAVERAGESUSING  The names of the grand averages whose recorded sources
%   include any of FILES, read from each one's meta record as
%   recalculateAffectedGrandAverages reads them.
    names = {};
    gaNodes = this.Workspace.GrandAveragesTree.allNodes();
    for i = 1:numel(gaNodes)
        gaFile = gaNodes(i).UserData;
        % A grand average is a root of its tree; a step run on one carries
        % its record along, but is not another grand average.
        if ~gaNodes(i).IsRoot || isempty(gaFile) || exist(gaFile, "file") ~= 2
            continue;
        end
        gaEEG = eegProxyFromCacheMeta(readEegCacheMeta(gaFile));
        if ~isfield(gaEEG, "etc") || ~isfield(gaEEG.etc, "GrandAverage")
            continue;
        end
        if any(ismember(pathKey(gaEEG.etc.GrandAverage.sources), pathKey(files)))
            names{end + 1} = char(string(gaNodes(i).Name)); %#ok<AGROW>
        end
    end
end

function keys = pathKey(paths)
%PATHKEY  PATHS as they compare: Windows paths are not case-sensitive.
    keys = cellstr(paths);
    if ispc
        keys = lower(keys);
    end
end
