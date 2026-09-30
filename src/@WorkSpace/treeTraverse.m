function treeTraverse(this, id, branchDir, currentParentNode, tree)
    % treeTraverse Rebuilds the transformation tree from the directory structure.
    %
    % This function recursively traverses the directory structure, identifying
    % .mat files, and adds nodes to a tree to represent the data contained
    % within these files.
    %
    % Parameters:
    % - this: The object instance, typically used to access properties and methods.
    % - id: The identifier for the current branch being processed.
    % - branchDir: The directory path where the branches are located.
    % - currentParentNode: The current parent node in the tree to which new nodes will be added.
    % - tree: the WorkSpaceTree to add them to; this.Tree when omitted. The
    %   Grand Averages tree passes its own (see loadGrandAverages), since the
    %   steps run on a grand average are stored the same way, in a folder
    %   named after it, and were otherwise never listed again once the
    %   workspace had been closed.
    if nargin < 5
        tree = this.Tree;
    end

    % Construct the full path for the current branch directory.
    currentDir = fullfile(branchDir, id);

    % Check if the directory exists. If not, terminate the function.
    if ~exist(currentDir, 'dir')
        return;
    end

    % List all items in the directory.
    items = dir(currentDir);

    % Filter out the current and parent directory links.
    items = items(~ismember({items.name}, {'.', '..'}));

    % Further filter out directories, keeping only files.
    files = items(~[items.isdir]);

    % If there are no files, terminate the function.
    if isempty(files)
        return;
    end

    % Loop through each file in the directory.
    for i = 1:length(files)
        file = files(i);

        % Check if the file has a '.mat' extension.
        if length(file.name) > 3 && strcmpi(file.name(end-2:end), 'mat')
            % The file's REAL, current, just-verified-to-exist location --
            % not a stored .File field -- is what the tree node points at:
            % a stored .File is whatever was baked into the .mat at the
            % moment it was saved, which is only ever correct on the
            % machine/username that created it. A workspace copied to
            % another computer (or even just a different Windows profile
            % on the same machine) keeps its files at the same path
            % RELATIVE to the workspace's own Cache directory, so deriving
            % the node's file from where it was actually just found on
            % disk is what makes the tree portable; trusting the stored
            % field reintroduces the old machine's absolute path and
            % everything downstream (loading, renaming, recalculating,
            % ...) breaks looking for a folder that only ever existed on
            % that other computer.
            actualFile = fullfile(file.folder, file.name);

            % Reads the file's small JSON cache sidecar (see
            % readEegCacheInfo/saveEegCache) rather than loading the .mat
            % itself: rebuilding the tree from disk on every startup used
            % to fully load EVERY node of EVERY subject's processing
            % history just to read a handful of scalar fields, on cache
            % trees that run to tens of GB, almost none of it needed here
            % -- the actual EEG data is only loaded when a node is opened.
            info = readEegCacheInfo(actualFile);

            % A minimal stand-in for the loaded EEG struct optsFor/
            % iconForResult actually read from -- keeps those two shared
            % functions unchanged (and still correct for their other
            % callers, which do pass a real, fully-loaded EEG).
            proxyEEG = eegProxyFromCacheInfo(info);

            % Create a new tree node with the EEG id and file data, iconned
            % by the transformation that produced it (falling back to data
            % type if no matching transformation icon exists -- see
            % WorkSpaceTree.iconForResult) and with List events/Recalculate
            % eligibility baked in from the loaded EEG (see
            % WorkSpaceTree.optsFor). canApplyToAll is true in the Data &
            % Analyses tree, where every node rebuilt here is a non-root
            % branch node, exactly Save Template/Apply to All Raw Files'
            % eligibility; without it, every node of a REOPENED workspace
            % fell back to addNode's default of false, leaving both items
            % disabled for its entire history. Under a grand average it is
            % false, as persistResultNode makes it for a fresh node there:
            % a grand average's steps cannot be replayed onto a recording.
            transRoot = fullfile(this.Parent.RootDir, 'Transformations');
            opts = WorkSpaceTree.optsFor(proxyEEG);
            opts.canApplyToAll = tree == this.Tree;   % never under a grand average
            newNode = tree.addNode(info.id, currentParentNode.Id, ...
                WorkSpaceTree.iconForResult(proxyEEG, transRoot), actualFile, opts);

            % Extract the file name without the extension for recursion.
            [~, name, ~] = fileparts(file.name);

            % Recursively traverse the next level of the directory structure.
            this.treeTraverse(name, currentDir, newNode, tree);
        end
    end
end
