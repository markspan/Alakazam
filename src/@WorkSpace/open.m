function open(this,~,~)
    this.Tree.clear();
    this.GrandAveragesTree.clear();
    %% Read the ROOT directory for datafiles;
    % We opted to let each of the typeloaders traverse into the tree.
    % Make sure the workspace directories exist. A workspace copied from
    % another computer may point at folders that do not exist here and cannot
    % be created (a different user profile, an absent mapped drive). In that
    % case, warn the user and continue with an empty tree rather than letting
    % mkdir throw and abort the whole application.
    for target = ["CacheDirectory", "RawDirectory", "ExportsDirectory"]
        dirPath = this.(target);
        if isempty(dirPath)
            made = false;
            reason = 'the directory is not set in the workspace';
        elseif isfolder(dirPath)
            continue;
        else
            % The two-output form returns a status instead of throwing.
            [made, reason] = mkdir(dirPath);
        end
        if ~made
            explanation = sprintf([ ...
                'Alakazam could not open a workspace directory:\n\n    %s\n\n', ...
                'This usually means the workspace was copied from another ', ...
                'computer and still points at that machine''s folders.\n\n', ...
                'Use "Open WorkSpace" to load a workspace whose directories ', ...
                'exist on this computer, or "Edit WorkSpace" to point the ', ...
                'Raw, Cache and Exports directories at valid local folders.\n\n', ...
                '(%s)'], dirPath, reason);
            % LEGACY-JAVA-GUI: msgbox is a classic Java/AWT dialog, not a
            % uifigure -- see migration.md's "old-style Java-based
            % graphics" checklist.
            uiwait(msgbox(explanation, ...
                'Alakazam: workspace directory problem', 'warn', 'modal'));
            return;
        end
    end

    fileList = dir (strcat(this.RawDirectory, '*.mat'));
    for file = 1:length(fileList)
        disp(fileList(file).name);
        this.loadMATFile(this, fileList(file).name)
    end
    fileList = dir (strcat(this.RawDirectory, '*.vhdr'));
    for file = 1:length(fileList)
        disp(fileList(file).name);
        this.loadBVAFile(this, fileList(file).name)
    end
    fileList = dir (strcat(this.RawDirectory, '*.set'));
    for file = 1:length(fileList)
        disp(fileList(file).name);
        this.loadSETFile(this, fileList(file).name)
    end

    this.loadGrandAverages();
end