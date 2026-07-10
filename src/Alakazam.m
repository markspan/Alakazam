classdef Alakazam < handle
%ALAKAZAM  Toolstrip application for modular EEG / physiology analysis.
%
%   Alakazam presents a "tree of datasets plus draggable transformations"
%   workflow (inspired by BrainVision Analyzer). A WorkSpace holds a data
%   browser tree of EEGLAB EEG structures; transformations in the toolstrip
%   gallery are applied to the selected dataset to produce new child nodes,
%   and dragging a branch onto another dataset re-applies that chain.
%
%   Application roots (resolved once, in the constructor, from this file's
%   own location so nothing depends on the current working directory):
%     RootDir  - the authored source tree (this src/ folder). Holds the
%                Transformations, Icons, the default workspace and the
%                +uiextras helper package.
%     RepoRoot - the repository root (parent of src/). Holds the shared
%                data-file resources. EEGLAB is not bundled; it is expected on
%                the path (see EEGLabEnvironment).
%
%   Launch with the startAlakazam function at the repository root, or add
%   src/ to the MATLAB path and construct Alakazam directly.
%
%   Naming conventions used throughout:
%     * Classes    UpperCamelCase (Alakazam, WorkSpace, AlakazamPlotter)
%     * Methods    lowerCamelCase, verb first (onTransformation, evaluateDroppedBranch)
%     * Properties UpperCamelCase (RootDir, AppContainer, Workspace)
%     * Locals     descriptive lowerCamelCase
%   Double quotes are used for string literals, except where a char array is
%   required: transformation ids (EEG.Call, fed straight to feval), element-wise
%   char comparisons, path components, and arguments to the char-only jTree /
%   ToolGroup APIs.
%
%   Adapted from "matlab.ui.internal.desktop.showcaseMPCDesigner()" by
%   R. Chen; original work (c) 2015 The MathWorks, Inc. Further developed by
%   M.M. Span, University of Groningen, Department of Experimental Psychology.
%
%   See also ALAKAZAMPLOTTER, EEGLABENVIRONMENT, WORKSPACE, BUILDTABGROUPALAKAZAM.

    properties (Transient = true)
        RootDir       % char, absolute path to the authored source tree (src/)
        RepoRoot      % char, absolute path to the repository root (vendored code)
        AppContainer  % matlab.ui.container.internal.AppContainer, the app window
        Figures       % array of figure handles opened as documents
        Workspace     % WorkSpace, the data-browser tree and session state
        Plotter       % AlakazamPlotter, renders datasets into figures
        Debug = true % logical, when true expose the instance in the base workspace
    end

    methods (Access = private)
        function setupDirectories(this)
        %SETUPDIRECTORIES  Put the authored source tree on the path.
        %   All paths are resolved absolutely, so the app does not depend on the
        %   current working directory. RootDir (src) holds the app code and the
        %   +uiextras package (added by putting src on the path); the
        %   Transformations are added with their subfolders (which include the
        %   mlapptools helper co-located with the IIRFilter transform).
            close all;
            warning("off", "MATLAB:ui:javacomponent:FunctionToBeRemoved");
            addpath(this.RootDir, '-end');
            addpath(genpath(fullfile(this.RootDir, 'Transformations')));
        end

        function setupAppContainer(this)
        %SETUPAPPCONTAINER  Create the toolstrip document window (not yet shown).
        %   Builds the AppContainer -- the web/CEF-based successor to the old
        %   Java-Swing ToolGroup (see migration.md): JavaFrame, the mechanism
        %   ToolGroup.addFigure relied on to dock a figure's Swing peer, is
        %   removed entirely from R2025b's figure family. Registers the
        %   "plots" document group AlakazamPlotter docks figures into, wires
        %   the close listener, and populates the tab group from
        %   BuildTabGroupAlakazam.
        %
        %   Visible is deliberately NOT set here: the data-browser panel
        %   (built by the Workspace, constructed after this method returns)
        %   must be added first, and AppContainer -- like the old
        %   ToolGroup.open() -- expects everything added before it is shown.
        %   The constructor sets Visible last, once the panel is attached.
            this.AppContainer = matlab.ui.container.internal.AppContainer( ...
                'Tag', 'AlakazamApp', 'Title', 'Alakazam');
            addlistener(this.AppContainer, 'WindowStateChanged', ...
                @(src, ~) this.onGroupAction(src));
            this.Figures = gobjects(1, 0); % grown as documents are opened

            plotGroup = matlab.ui.container.internal.appcontainer.DocumentGroup();
            plotGroup.Tag   = 'plots';
            plotGroup.Title = 'Plots';
            this.AppContainer.registerDocumentGroup(plotGroup);

            tabgroup = BuildTabGroupAlakazam(this);
            this.AppContainer.addTabGroup(tabgroup);
            this.AppContainer.WindowBounds = [100 100 1080 720];
        end

        function [resultEEG, newNode] = persistResultNode(this, resultEEG, sourceFile, ~, transformId, parentTreeNode)
        %PERSISTRESULTNODE  Save a transformation result and add it to the tree.
        %   [RESULTEEG, NEWNODE] = PERSISTRESULTNODE(THIS, RESULTEEG, SOURCEFILE,
        %   DISPLAYBASE, TRANSFORMID, PARENTTREENODE) performs the persistence
        %   step shared by onTransformation and evaluateDroppedBranch. DISPLAYBASE
        %   (the calling node's own label) is accepted but currently unused, since
        %   the tree shows each node's own transform id rather than an
        %   accumulated lineage string; kept as a parameter in case that changes:
        %     * derive a timestamped cache file in a folder named after the
        %       source dataset's own stem (sibling to SOURCEFILE), creating
        %       that folder if needed;
        %     * set RESULTEEG.File and RESULTEEG.id (just TRANSFORMID: the
        %       tree shows each node's own transform, not its lineage);
        %     * add a tree node under PARENTTREENODE with the matching icon,
        %       expand its parent and select it;
        %     * save RESULTEEG to disk and make it the workspace's current EEG.
        %   Returns the updated dataset and the new tree node.
        %
        %   The child folder MUST be named after the source's own stem, not
        %   the new node's key: treeTraverse (tree rebuild from disk) and
        %   evaluateDroppedBranch (drag-drop recursion) both locate a node's
        %   children this way, by re-deriving the same folder name from the
        %   node's own file path rather than storing it anywhere.

            % Timestamped key, e.g. "Fourier051423". The DDhhMMss format is
            % kept for backwards compatibility with existing cache trees. The
            % key stays a char array because it is used to build a file name.
            nodeKey = [transformId datestr(datetime('now'), 'DDhhMMss')]; %#ok<DATST>

            % The result is cached in a folder named after the source dataset,
            % which is how the tree is later rebuilt from disk.
            [parentDir, parentName] = fileparts(sourceFile);
            childDir = fullfile(parentDir, parentName);
            if ~exist(childDir, "dir")
                mkdir(childDir);
            end

            resultEEG.File = fullfile(childDir, [nodeKey '.mat']);
            resultEEG.id   = transformId;

            % Add the node to the data browser and select it. WorkSpaceTree
            % nodes are always shown expanded, so there is no separate
            % "expand the parent" step to do here.
            newNode = this.Workspace.Tree.addNode(resultEEG.id, parentTreeNode.Id, ...
                WorkSpaceTree.iconFor(resultEEG.DataType), resultEEG.File, ...
                WorkSpaceTree.optsFor(resultEEG));
            this.Workspace.Tree.SelectedNodes = newNode;

            % Persist to disk under the variable name "EEG" and adopt it as the
            % workspace's current dataset.
            EEG = resultEEG; % saved to disk under the variable name "EEG"
            save(resultEEG.File, "EEG");
            this.Workspace.EEG = resultEEG;
        end

        function tf = isOverlayableAverage(~, targetEEG, sourceEEG)
        %ISOVERLAYABLEAVERAGE  True when two datasets are averages of equal shape.
        %   Used by evaluateDroppedBranch to decide whether dropping one
        %   dataset onto another should overlay their average plots rather than
        %   re-apply a transformation.
            tf = strcmpi(targetEEG.DataFormat, "AVERAGED") && ...
                 strcmpi(sourceEEG.DataFormat, "AVERAGED") && ...
                 isequal(size(targetEEG.data), size(sourceEEG.data));
        end

        function overlayAverage(this, targetEEG, sourceEEG)
        %OVERLAYAVERAGE  Overlay a dropped average dataset on the target's plot.
        %   Ensures the target average is shown (reusing its figure if open),
        %   then adds the source average to that figure's AverageView.
        %   Looked up via AppContainer.hasDocument/getDocument, not findobj:
        %   AppContainer-hosted document figures have HandleVisibility=off
        %   and are never parented under groot (see AlakazamPlotter.plotCurrent).
            docTag = string(matlab.lang.makeValidName(targetEEG.File));
            if ~this.AppContainer.hasDocument("plots", docTag)
                this.Workspace.EEG = targetEEG;
                this.Plotter.plotCurrent();
            else
                this.AppContainer.getDocument("plots", docTag).Selected = true;
            end
            existingFig = this.AppContainer.getDocument("plots", docTag).Figure;

            view = getappdata(existingFig, "AverageView");
            if ~isempty(view) && isvalid(view)
                view.addDataset(sourceEEG);
            end
        end

        function [files, labels] = findGrandAverageCandidates(this)
        %FINDGRANDAVERAGECANDIDATES  Every Averaged dataset in the cache
        %   directory that is not itself a grand average -- the pool of
        %   subjects a grand average can be built from.
            files  = {};
            labels = {};
            found = dir(fullfile(this.Workspace.CacheDirectory, '**', '*.mat'));
            for i = 1:numel(found)
                file = fullfile(found(i).folder, found(i).name);
                loaded = load(file, "EEG");
                candidate = loaded.EEG;
                if ~isfield(candidate, "DataFormat") || ~strcmpi(candidate.DataFormat, "Averaged")
                    continue;
                end
                if isfield(candidate, "etc") && isfield(candidate.etc, "GrandAverage")
                    continue; % do not grand-average a grand average
                end
                files{end + 1}  = file; %#ok<AGROW>
                labels{end + 1} = sprintf('%s (%s)', candidate.id, ...
                    strjoin({candidate.bindesc.label}, ', ')); %#ok<AGROW>
            end
        end

        function saveGrandAverage(this, spec, existingNode)
        %SAVEGRANDAVERAGE  Compute a grand average from SPEC (see
        %   GrandAverageDialog) and save it, creating a new tree node under
        %   the "Grand Averages" root (EXISTINGNODE empty) or refreshing an
        %   existing one in place (EXISTINGNODE the node being recalculated).
            EEG = GrandAverage(spec.sources, spec.weighted);   % may throw a
                                                                % friendly
                                                                % compatibility
                                                                % error
            EEG.id = spec.name;

            gaDir = fullfile(this.Workspace.CacheDirectory, 'GrandAverages');
            if ~exist(gaDir, "dir")
                mkdir(gaDir);
            end
            safeName = matlab.lang.makeValidName(spec.name);
            EEG.File = fullfile(gaDir, [safeName '.mat']);
            save(EEG.File, "EEG");

            if isempty(existingNode)
                newNode = this.Workspace.Tree.addNode(EEG.id, this.Workspace.GrandAveragesNode.Id, ...
                    WorkSpaceTree.iconFor(EEG.DataType), EEG.File, WorkSpaceTree.optsFor(EEG));
                this.Workspace.Tree.SelectedNodes = newNode;
            else
                this.Workspace.Tree.renameNode(existingNode.Id, EEG.id);
                this.Workspace.Tree.setUserData(existingNode.Id, EEG.File);
            end

            this.Workspace.EEG = EEG;
            this.Plotter.plotCurrent();
        end
    end

    methods
        function this = Alakazam(varargin)
        %ALAKAZAM  Construct and open the application.
        %   Resolves the application roots, makes sure EEGLAB and its plugins
        %   are available, sets up the paths, builds the toolstrip window,
        %   creates the plotter and the workspace, loads the data tree, docks
        %   the data-browser panel, and only then shows the window --
        %   AppContainer, like the old ToolGroup, expects everything added
        %   before Visible is set.
            this.RootDir  = fileparts(mfilename('fullpath'));
            this.RepoRoot = fileparts(this.RootDir);

            EEGLabEnvironment.ensure();
            this.setupDirectories();
            this.setupAppContainer();
            this.Plotter = AlakazamPlotter(this);

            % Create the workspace (this loads the data) and dock its tree's
            % panel into the app container.
            this.Workspace = WorkSpace(this);
            this.Workspace.open();
            this.AppContainer.addPanel(this.Workspace.DataPanel);
            this.AppContainer.Visible = true;

            % Optional debug aid: expose this instance in the base workspace as
            % "AlakazamInst" (otherwise it is only reachable via "ans", which is
            % easily overwritten). Off by default.
            if this.Debug
                assignin("base", "AlakazamInst", this);
            end
        end

        function delete(this)
        %DELETE  Destructor: close the document window and figures.
            if ~isempty(this.AppContainer) && isvalid(this.AppContainer)
                this.AppContainer.close('force', true);
            end
            delete(this.Figures);
        end

        function openSettings(this)
        %OPENSETTINGS  Open the global settings dialog (toolstrip callback).
        %   Applied changes refresh the open views via onSettingsChanged.
            SettingsDialog(@() this.onSettingsChanged());
        end

        function onSettingsChanged(this)
        %ONSETTINGSCHANGED  Re-draw open views so changed settings take effect.
            for k = 1:numel(this.Figures)
                fig = this.Figures(k);
                if ~isgraphics(fig) || ~isvalid(fig)
                    continue;
                end
                for viewName = ["AverageView", "EpochView"]
                    view = getappdata(fig, char(viewName));
                    if ~isempty(view) && isvalid(view)
                        try
                            view.redraw();
                        catch err
                            warning('Alakazam:viewRefresh', ...
                                'Could not refresh %s: %s', char(viewName), err.message);
                        end
                    end
                end
            end
        end

        function onTransformation(this, ~, ~, entry)
        %ONTRANSFORMATION  Gallery callback: run a transformation on the current EEG.
        %   ONTRANSFORMATION(THIS, ~, ~, ENTRY) executes the transformation
        %   whose entry file is ENTRY (for example "Fourier.m") on the selected
        %   dataset, stores the result as a new child node, and plots it. The
        %   stem of ENTRY is both the transformation id and the function that is
        %   invoked with feval.
        %
        %   A transformation returns [EEG, params]; if it instead returns a
        %   graphics handle it was a pure plot and nothing is persisted.
            figHandle = [];
            try
                % Run from the repository root (historic behaviour): individual
                % plugins may resolve resources relative to it. Restore the
                % previous directory on exit, including on error.
                originalDir = cd(this.RepoRoot);
                restoreDir  = onCleanup(@() cd(originalDir)); % restores cwd at method exit

                % Looked up via AppContainer.hasDocument/getDocument, not
                % findobj (see AlakazamPlotter.plotCurrent).
                docTag = string(matlab.lang.makeValidName(this.Workspace.EEG.File));
                if this.AppContainer.hasDocument("plots", docTag)
                    figHandle = this.AppContainer.getDocument("plots", docTag).Figure;
                end
                set(figHandle, "Pointer", "watch");

                % The gallery passes the entry file name (e.g. "Fourier.m"); its
                % stem is the transformation id and the function to call. The
                % '.' is a char so the element-wise comparison works.
                entryName   = char(entry);
                transformId = entryName(1:find(entryName == '.', 1, "last") - 1);

                % Apply the transformation to the current dataset.
                [result.EEG, usedParams] = feval(transformId, this.Workspace.EEG);

                if ishandle(result.EEG)
                    % The plugin returned a graphics handle, not a dataset: it
                    % was a pure plot, so there is nothing to persist.
                    return;
                end

                % Record how the result was produced, so it can be re-applied
                % when this branch is later dragged onto another dataset.
                % Call is just the transformation id (a plain function name,
                % fed straight to feval on replay -- see evaluateDroppedBranch);
                % it used to be a fake "EEG=<id>(x.EEG);" command string that
                % was then re-parsed with strfind, which added a redundant,
                % error-prone round trip for no benefit.
                result.EEG.Call = transformId;
                if isstruct(usedParams)
                    result.EEG.params = usedParams;
                else
                    result.EEG.params = struct('Param', usedParams);
                end

                % Persist under the selected node (its file is the source cache
                % file at this point) and display the result.
                displayBase = this.Workspace.Tree.SelectedNodes.Name;
                this.persistResultNode(result.EEG, result.EEG.File, displayBase, ...
                    transformId, this.Workspace.Tree.SelectedNodes);

                this.Plotter.plotCurrent();
                set(figHandle, "Pointer", "arrow");

            catch ME
                set(figHandle, "Pointer", "arrow");
                warndlg(ME.message, "Error in transformation");
                rethrow(ME);
            end
        end

        function evaluateDroppedBranch(this, sourceFile, targetNode)
        %EVALUATEDROPPEDBRANCH  Re-apply a dragged branch onto a target dataset.
        %   EVALUATEDROPPEDBRANCH(THIS, SOURCEFILE, TARGETNODE) walks the branch
        %   rooted at SOURCEFILE and re-applies each stored transformation onto
        %   the dataset at TARGETNODE, chaining down the tree while the source
        %   branch has children.
        %
        %   Special case: dropping one AVERAGED dataset onto a matching AVERAGED
        %   dataset overlays their plots instead of transforming.
            atLeaf     = false;
            targetFile = targetNode.UserData;

            while ~atLeaf
                targetStruct = load(targetFile, "EEG");
                sourceStruct = load(sourceFile, "EEG");

                % Call is just the transformation id (see onTransformation); no
                % parsing needed.
                transformId = char(sourceStruct.EEG.Call);

                if this.isOverlayableAverage(targetStruct.EEG, sourceStruct.EEG)
                    % Overlay the dropped average on top of the target average.
                    this.overlayAverage(targetStruct.EEG, sourceStruct.EEG);
                    atLeaf = true;
                else
                    % General case: re-apply the stored transformation to the
                    % target, carrying over the source's call and parameters.
                    % The id is stored data (loaded from a .mat file that may
                    % predate a Transformations-folder cleanup), not something
                    % just derived from code on disk, so it's validated before
                    % feval rather than failing with a cryptic "undefined
                    % function" error.
                    if exist(transformId, "file") ~= 2
                        throw(MException('Alakazam:evaluateDroppedBranch', ...
                            ['Stored transformation ''%s'' no longer exists ' ...
                             '(its .m file is missing from the Transformations ' ...
                             'folder). Cannot replay this branch.'], transformId));
                    end
                    [result.EEG, ~] = feval(transformId, targetStruct.EEG, sourceStruct.EEG.params);
                    result.EEG.Call   = sourceStruct.EEG.Call;
                    result.EEG.params = sourceStruct.EEG.params;

                    [result.EEG, newNode] = this.persistResultNode(result.EEG, ...
                        targetStruct.EEG.File, sourceStruct.EEG.id, transformId, targetNode);

                    % Descend: if the source has a child dataset, continue the
                    % chain with it against the newly created node.
                    [srcDir, srcName] = fileparts(sourceFile);
                    childDir = fullfile(srcDir, srcName);
                    if exist(childDir, "dir")
                        targetNode = newNode;
                        targetFile = result.EEG.File;
                        childMat   = dir(fullfile(childDir, '*.mat'));
                        sourceFile = fullfile(childDir, childMat.name);
                    else
                        atLeaf = true;
                    end
                end
            end
        end

        function onListEvents(this)
        %ONLISTEVENTS  Context-menu callback: list unique event types and
        %   their occurrence counts for the selected dataset in a message
        %   box. The menu item is disabled for epoched/averaged data (its
        %   eligibility is baked into the node at creation time -- see
        %   WorkSpaceTree.optsFor), so this only ever runs for continuous
        %   data; root nodes are allowed here (unlike Rename/Delete), since a root
        %   node is normally the raw continuous import -- the most common
        %   case for wanting to see what events it contains.
            node = this.Workspace.Tree.SelectedNodes;
            if isempty(node)
                return; % nothing selected
            end

            file = node.UserData;
            if isempty(file) || exist(file, "file") ~= 2
                return;
            end

            loaded = load(file, "EEG");
            EEG = loaded.EEG;
            titleText = sprintf('Events in "%s"', node.Name);

            if ~isfield(EEG, "event") || isempty(EEG.event)
                msgbox("This dataset has no events.", titleText);
                return;
            end

            % Event types may be numeric or char/string across loaders;
            % string() normalises both so unique() groups them correctly.
            types = strings(1, numel(EEG.event));
            for i = 1:numel(EEG.event)
                types(i) = string(EEG.event(i).type);
            end
            [uTypes, ~, ic] = unique(types);
            counts = accumarray(ic, 1);
            [counts, order] = sort(counts, "descend");
            uTypes = uTypes(order);

            lines = strings(numel(uTypes), 1);
            for i = 1:numel(uTypes)
                lines(i) = sprintf("%s: %d", uTypes(i), counts(i));
            end
            msgbox(char(strjoin(lines, newline)), titleText);
        end

        function onRenameNode(this)
        %ONRENAMENODE  Context-menu callback: rename the selected node.
        %   Prompts for a new label and persists it both to the tree (its
        %   display name) and to the underlying cached dataset's id
        %   (EEG.id, re-saved to its own file) -- not just the currently
        %   active dataset, since a right-click need not target it. Root
        %   nodes are not renamable here.
            node = this.Workspace.Tree.SelectedNodes;
            if isempty(node) || node.IsRoot
                return; % nothing selected, or a root node
            end

            answer = inputdlg('New name:', 'Rename node', 1, {node.Name});
            if isempty(answer)
                return; % cancelled
            end
            newName = strtrim(answer{1});
            if isempty(newName)
                return;
            end

            file = node.UserData;
            loaded = load(file, "EEG");
            loaded.EEG.id = newName;
            EEG = loaded.EEG; % saved to disk under the variable name "EEG"
            save(file, "EEG");

            this.Workspace.Tree.renameNode(node.Id, newName);

            % Keep the in-memory active dataset in sync if it is this node.
            if isequal(this.Workspace.EEG.File, file)
                this.Workspace.EEG.id = newName;
            end
        end

        function onDeleteNode(this)
        %ONDELETENODE  Context-menu callback: delete the selected node and
        %   every dataset computed from it, on disk and in the tree, after
        %   confirmation. Root nodes are not deletable here: that would also
        %   remove everything ever computed from the source recording, a
        %   much bigger action than pruning a single branch.
            node = this.Workspace.Tree.SelectedNodes;
            if isempty(node) || node.IsRoot
                return; % nothing selected, or a root node
            end

            answer = questdlg( ...
                sprintf('Delete "%s" and everything computed from it? This cannot be undone.', node.Name), ...
                'Delete node', 'Delete', 'Cancel', 'Cancel');
            if ~strcmp(answer, 'Delete')
                return;
            end

            % A node's descendants are cached in a folder named after its own
            % stem, sibling to its own file (see persistResultNode).
            file = node.UserData;
            [folder, stem] = fileparts(file);
            childDir = fullfile(folder, stem);

            % Close any open figure for this node or one of its descendants
            % before their cache files disappear out from under them. Looked
            % up via AppContainer.hasDocument/closeDocument, not findobj (see
            % AlakazamPlotter.plotCurrent).
            descendantFiles = {file};
            if exist(childDir, "dir")
                found = dir(fullfile(childDir, '**', '*.mat'));
                for k = 1:numel(found)
                    descendantFiles{end + 1} = fullfile(found(k).folder, found(k).name); %#ok<AGROW>
                end
            end
            for k = 1:numel(descendantFiles)
                docTag = string(matlab.lang.makeValidName(descendantFiles{k}));
                if this.AppContainer.hasDocument("plots", docTag)
                    this.AppContainer.closeDocument("plots", docTag);
                end
            end

            if exist(file, "file")
                delete(file);
            end
            if exist(childDir, "dir")
                rmdir(childDir, "s");
            end

            this.Workspace.Tree.removeNode(node.Id);
        end

        function onDefineGrandAverage(this)
        %ONDEFINEGRANDAVERAGE  Toolstrip callback (Grand Average tab): define
        %   a brand new grand average. Lets the analyst pick which Averaged
        %   subject datasets to combine, name it, and choose weighted/
        %   unweighted combining (GrandAverageDialog), then computes and
        %   saves it as a new node under the "Grand Averages" tree root.
            [candidateFiles, candidateLabels] = this.findGrandAverageCandidates();
            if numel(candidateFiles) < 2
                msgbox(['A grand average needs at least two Averaged datasets ' ...
                        'to combine, and fewer than two were found in this ' ...
                        'workspace. Run the Average transformation on more ' ...
                        'subjects first.'], 'Not enough subjects');
                return;
            end

            spec = GrandAverageDialog(candidateFiles, candidateLabels, []);
            if isempty(spec)
                return; % cancelled
            end

            try
                this.saveGrandAverage(spec, []);
            catch err
                warndlg(err.message, 'Could not compute grand average');
            end
        end

        function onRecalculateNode(this)
        %ONRECALCULATENODE  Context-menu callback: revisit an existing grand
        %   average's membership. Reopens GrandAverageDialog pre-filled with
        %   its current sources/weighting (its name is fixed), lets the
        %   analyst add/remove subjects or change the weighting, then
        %   recomputes and re-saves it in place. Only ever reachable for a
        %   Grand Average node -- the menu item is disabled otherwise (its
        %   eligibility is baked into the node at creation time, see
        %   WorkSpaceTree.optsFor).
            node = this.Workspace.Tree.SelectedNodes;
            if isempty(node)
                return;
            end

            file = node.UserData;
            loaded = load(file, "EEG");
            if ~isfield(loaded.EEG, "etc") || ~isfield(loaded.EEG.etc, "GrandAverage")
                return; % not a grand average; nothing to recalculate
            end

            existingSpec = struct('name', loaded.EEG.id, ...
                'sources', {loaded.EEG.etc.GrandAverage.sources}, ...
                'weighted', loaded.EEG.etc.GrandAverage.weighted);

            [candidateFiles, candidateLabels] = this.findGrandAverageCandidates();
            spec = GrandAverageDialog(candidateFiles, candidateLabels, existingSpec);
            if isempty(spec)
                return; % cancelled
            end

            try
                this.saveGrandAverage(spec, node);
            catch err
                warndlg(err.message, 'Could not compute grand average');
            end
        end

        function onNodeDropped(this, eventData)
        %ONNODEDROPPED  Tree callback: handle a node dropped onto another node.
        %   No modifier key (EVENTDATA.REPARENTED true) moves the node within
        %   the tree -- WorkSpaceTree has already mirrored this in its own
        %   bookkeeping, so there is nothing further to do here (it is never
        %   persisted to disk; treeTraverse rebuilds the tree from the cache
        %   folder structure on the next full reload, same as the old jTree
        %   behaviour). Ctrl held (REPARENTED false) re-applies the dragged
        %   branch onto the target via evaluateDroppedBranch instead. Root
        %   nodes are ignored.
            % Run from the repository root (historic behaviour): the drop
            % triggers plugins that may resolve resources relative to it.
            % Restore the previous directory when this callback returns.
            originalDir = cd(this.RepoRoot);
            restoreDir  = onCleanup(@() cd(originalDir)); % restores cwd at callback exit

            if eventData.Source.IsRoot
                return; % a root node was dropped; ignore
            end

            if ~eventData.Reparented % Ctrl held: re-apply the dragged branch to the target
                this.evaluateDroppedBranch(eventData.Source.UserData, eventData.Target);
            end
        end

        function onSelectionChanged(this, eventData)
        %ONSELECTIONCHANGED  Tree callback: load and plot the newly selected dataset.
            loaded = load(eventData.UserData, "EEG");
            this.Workspace.EEG = loaded.EEG;
            this.Plotter.plotCurrent();
        end

        function onNodeDoubleClicked(this, eventData)
        %ONNODEDOUBLECLICKED  Tree callback: (re)load and plot the double-clicked
        %   dataset. Loads it itself rather than relying on a preceding single
        %   click's SelectionChangedFcn having already done so, since
        %   WorkSpaceTree does not guarantee that ordering.
            loaded = load(eventData.UserData, "EEG");
            this.Workspace.EEG = loaded.EEG;
            this.Plotter.plotCurrent();
        end

        function onContextMenuAction(this, eventData)
        %ONCONTEXTMENUACTION  Tree callback: dispatch a right-click context
        %   menu action (List events / Rename / Recalculate / Delete) --
        %   WorkSpaceTree has already selected EVENTDATA.NODE before invoking
        %   this, matching the old right-click-selects-first behaviour, so
        %   each handler below can keep reading Workspace.Tree.SelectedNodes.
            switch eventData.Action
                case 'listEvents'
                    this.onListEvents();
                case 'rename'
                    this.onRenameNode();
                case 'recalculate'
                    this.onRecalculateNode();
                case 'delete'
                    this.onDeleteNode();
            end
        end

        function onGroupAction(this, container)
        %ONGROUPACTION  AppContainer listener: destroy the app when its window
        %   closes. WindowStateChanged carries no useful eventdata of its own
        %   (unlike the old ToolGroup's GroupAction/EventType), so the live
        %   WindowState on the container itself (the listener's source) is
        %   checked instead.
            if container.WindowState == matlab.ui.container.internal.appcontainer.AppWindowState.CLOSED
                delete(this);
            end
        end
    end
end
