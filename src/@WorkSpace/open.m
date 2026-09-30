function open(this,~,~)
    this.Tree.clear();
    this.GrandAveragesTree.clear();
    this.ReportsTree.clear();
    % Each tree is sent to the page once, when this function returns, not once
    % per node added: addNode sends the whole tree, so a 550-node workspace was
    % hundreds of full sends before anything could be clicked.
    releaseTree    = this.Tree.beginBatch(); %#ok<NASGU>
    releaseGrand   = this.GrandAveragesTree.beginBatch(); %#ok<NASGU>
    releaseReports = this.ReportsTree.beginBatch(); %#ok<NASGU>
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

    % One loader per raw format (rawFormats), in the registry's order: the
    % four formats Alakazam has always read first, in the order they always
    % were, then the rest. fullfile, not strcat -- see resolveCachePaths for
    % why: RawDirectory is not guaranteed to end in a path separator.
    %
    % A recording that cannot be read is set aside and reported, together
    % with the others, once everything readable is open. One unreadable file
    % used to stop the whole workspace from opening, which is the wrong
    % price for a single bad file among forty good ones.
    unreadable = {};
    for format = rawFormats()
        for e = 1:numel(format.extensions)
            fileList = dir(fullfile(this.RawDirectory, ['*' format.extensions{e}]));
            % The extension exactly: Windows' dir matches a short pattern
            % against 8.3 names too, so '*.e' is not trusted to mean '.e'.
            [~, ~, found] = cellfun(@fileparts, {fileList.name}, 'UniformOutput', false);
            fileList = fileList([fileList.isdir] == format.isFolder ...
                & strcmpi(found, format.extensions{e}));
            for file = 1:numel(fileList)
                name = fileList(file).name;
                if ~format.accepts(fullfile(this.RawDirectory, name))
                    continue;   % the extension, but not this format (an EyeLink .edf)
                end
                try
                    if strcmp(format.loader, 'loadRawFile')
                        this.loadRawFile(name, format);
                    else
                        this.(format.loader)(name);
                    end
                catch err
                    unreadable{end + 1} = sprintf('%s: %s', name, err.message); %#ok<AGROW>
                end
            end
        end
    end
    if ~isempty(unreadable)
        reportUnreadable(this, unreadable);
    end

    this.loadGrandAverages();
    this.loadReports();
end

% ======================================================================= %
function reportUnreadable(this, unreadable)
%REPORTUNREADABLE  Say which recordings were left out, and why, once.
    message = sprintf(['%d recording(s) in the raw directory could not be read and are ' ...
        'not in the tree:\n\n%s'], numel(unreadable), strjoin(unreadable, sprintf('\n\n')));
    fprintf('%s\n', message);
    try
        uialert(this.Parent.MainFigure, message, 'Some recordings could not be read', 'Icon', 'warning');
    catch
        % No window to show it in (a headless open): the console has it.
    end
end
