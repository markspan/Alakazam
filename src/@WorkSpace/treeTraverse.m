function treeTraverse(this, id, branchDir, currentParentNode)
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
            % Load the EEG structure from the .mat file. The file's
            % REAL, current, just-verified-to-exist location -- not
            % data.EEG.File -- is what the tree node points at: EEG.File
            % is whatever was baked into the .mat at the moment it was
            % saved, which is only ever correct on the machine/username
            % that created it. A workspace copied to another computer (or
            % even just a different Windows profile on the same machine)
            % keeps its files at the same path RELATIVE to the workspace's
            % own Cache directory, so deriving the node's file from where
            % it was actually just found on disk is what makes the tree
            % portable; trusting the stored field reintroduces the old
            % machine's absolute path and everything downstream (loading,
            % renaming, recalculating, ...) breaks looking for a folder
            % that only ever existed on that other computer.
            actualFile = fullfile(file.folder, file.name);
            data = load(actualFile, 'EEG');

            % Create a new tree node with the EEG id and file data, iconned
            % by the transformation that produced it (falling back to data
            % type if no matching transformation icon exists -- see
            % WorkSpaceTree.iconForResult) and with List events/Recalculate
            % eligibility baked in from the loaded EEG (see
            % WorkSpaceTree.optsFor).
            transRoot = fullfile(this.Parent.RootDir, 'Transformations');
            newNode = this.Tree.addNode(data.EEG.id, currentParentNode.Id, ...
                WorkSpaceTree.iconForResult(data.EEG, transRoot), actualFile, ...
                WorkSpaceTree.optsFor(data.EEG));

            % Extract the file name without the extension for recursion.
            [~, name, ~] = fileparts(file.name);

            % Recursively traverse the next level of the directory structure.
            treeTraverse(this, name, currentDir, newNode);
        end
    end
end
