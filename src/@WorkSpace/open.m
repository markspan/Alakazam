function open(this,~,~)
    this.Tree.clear();
    this.GrandAveragesTree.clear();
    this.ReportsTree.clear();
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

    % One loader per raw format, in a fixed order (mat, vhdr, set, erp --
    % unchanged from before this was table-driven, in case anything ever
    % turns out to depend on it). fullfile, not strcat -- see
    % resolveCachePaths for why: RawDirectory is not guaranteed to end in
    % a path separator, and strcat blindly concatenating one with a glob
    % pattern silently searched the wrong (parent) directory.
    formats = {'*.mat', 'loadMATFile'; '*.vhdr', 'loadBVAFile'; ...
               '*.set', 'loadSETFile'; '*.erp', 'loadERPFile'};
    for row = 1:size(formats, 1)
        fileList = dir(fullfile(this.RawDirectory, formats{row, 1}));
        for file = 1:numel(fileList)
            this.(formats{row, 2})(fileList(file).name);
        end
    end

    this.loadGrandAverages();
    this.loadReports();
end