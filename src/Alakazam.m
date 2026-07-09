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
%     * Properties UpperCamelCase (RootDir, ToolGroup, Workspace)
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
        ToolGroup     % matlab.ui.internal.desktop.ToolGroup, the app window
        Figures       % array of figure handles opened as documents
        Workspace     % WorkSpace, the data-browser tree and session state
        Plotter       % AlakazamPlotter, renders datasets into figures
        Debug = false % logical, when true expose the instance in the base workspace
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

        function setupToolGroup(this)
        %SETUPTOOLGROUP  Create and open the toolstrip document window.
        %   Builds the ToolGroup, wires its close listener, populates the tab
        %   group from BuildTabGroupAlakazam, and tiles the document area. The
        %   ToolGroup names and tags are char arrays, as that desktop API expects.
            this.ToolGroup = matlab.ui.internal.desktop.ToolGroup('Alakazam', 'AlakazamApp');
            addlistener(this.ToolGroup, 'GroupAction', @(src, event) this.onGroupAction(event));
            this.Figures = gobjects(1, 0); % grown as documents are opened

            tabgroup = BuildTabGroupAlakazam(this);
            this.ToolGroup.addTabGroup(tabgroup);
            this.ToolGroup.SelectedTab = 'tabHome';
            this.ToolGroup.setPosition(100, 100, 1080, 720);
            this.ToolGroup.open();
            desktop = com.mathworks.mlservices.MatlabDesktopServices.getDesktop; %#ok<JAPIMATHWORKS>
            desktop.setDocumentArrangement(this.ToolGroup.Name, desktop.TILED, java.awt.Dimension(1, 1));
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

            % Add the node to the data browser and select it. The jTree
            % property names are char arrays, as that API expects.
            newNode = uiextras.jTree.TreeNode('Name', resultEEG.id, ...
                'Parent', parentTreeNode, 'UserData', resultEEG.File);
            this.setNodeIcon(newNode, resultEEG.DataType);
            newNode.Parent.expand();
            this.Workspace.Tree.SelectedNodes = newNode;

            % Persist to disk under the variable name "EEG" and adopt it as the
            % workspace's current dataset.
            EEG = resultEEG; % saved to disk under the variable name "EEG"
            save(resultEEG.File, "EEG");
            this.Workspace.EEG = resultEEG;
        end

        function setNodeIcon(this, node, dataType)
        %SETNODEICON  Give a tree node the icon matching its data type.
        %   Time-domain datasets get the time-series icon and frequency-domain
        %   datasets the frequencies icon; other types are left unchanged.
            if strcmpi(dataType, "TIMEDOMAIN")
                setIcon(node, this.Workspace.TimeSeriesIcon);
            elseif strcmpi(dataType, "FREQUENCYDOMAIN")
                setIcon(node, this.Workspace.FrequenciesIcon);
            end
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
            existingFig = findobj("Type", "Figure", "Tag", targetEEG.File);
            if isempty(existingFig)
                this.Workspace.EEG = targetEEG;
                this.Plotter.plotCurrent();
                existingFig = findobj("Type", "Figure", "Tag", targetEEG.File);
            else
                this.ToolGroup.showClient(get(existingFig, "Name"));
            end

            view = getappdata(existingFig, "AverageView");
            if ~isempty(view) && isvalid(view)
                view.addDataset(sourceEEG);
            end
        end
    end

    methods
        function this = Alakazam(varargin)
        %ALAKAZAM  Construct and open the application.
        %   Resolves the application roots, makes sure EEGLAB and its plugins
        %   are available, sets up the paths, opens the toolstrip window,
        %   creates the plotter and the workspace, and loads the data tree.
            this.RootDir  = fileparts(mfilename('fullpath'));
            this.RepoRoot = fileparts(this.RootDir);

            EEGLabEnvironment.ensure();
            this.setupDirectories();
            this.setupToolGroup();
            this.Plotter = AlakazamPlotter(this);

            % Create the workspace (this loads the data) and attach its tree to
            % the document browser panel.
            this.Workspace = WorkSpace(this);
            this.Workspace.open();
            this.ToolGroup.setDataBrowser(this.Workspace.Panel);

            % Optional debug aid: expose this instance in the base workspace as
            % "AlakazamInst" (otherwise it is only reachable via "ans", which is
            % easily overwritten). Off by default.
            if this.Debug
                assignin("base", "AlakazamInst", this);
            end
        end

        function delete(this)
        %DELETE  Destructor: close the document window and figures.
            if ~isempty(this.ToolGroup) && isvalid(this.ToolGroup)
                delete(this.ToolGroup);
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

                figHandle = findobj("Type", "Figure", "Tag", this.Workspace.EEG.File);
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

        function onNodeEdited(this, ~, eventData)
        %ONNODEEDITED  Tree callback: persist a renamed node's new label.
        %   Updates the current dataset's id to the node's new name and saves.
            this.Workspace.EEG.id = eventData.Nodes.Name;
            EEG = this.Workspace.EEG;
            save(this.Workspace.EEG.File, "EEG");
        end

        function onListEvents(this)
        %ONLISTEVENTS  Context-menu callback: list unique event types and
        %   their occurrence counts for the selected dataset in a message
        %   box. The menu item is greyed out for epoched/averaged data (see
        %   onMouseClicked), so this only ever runs for continuous data;
        %   root nodes are allowed here (unlike Rename/Delete), since a root
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
            if isempty(node) || isempty(node.Parent) || isempty(node.Parent.Parent)
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

            node.Name = newName;

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
            if isempty(node) || isempty(node.Parent) || isempty(node.Parent.Parent)
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
            % before their cache files disappear out from under them.
            descendantFiles = {file};
            if exist(childDir, "dir")
                found = dir(fullfile(childDir, '**', '*.mat'));
                for k = 1:numel(found)
                    descendantFiles{end + 1} = fullfile(found(k).folder, found(k).name); %#ok<AGROW>
                end
            end
            for k = 1:numel(descendantFiles)
                fig = findobj("Type", "Figure", "Tag", descendantFiles{k});
                if ~isempty(fig)
                    close(fig);
                end
            end

            if exist(file, "file")
                delete(file);
            end
            if exist(childDir, "dir")
                rmdir(childDir, "s");
            end

            delete(node);
        end

        function onNodeDropped(this, ~, eventData)
        %ONNODEDROPPED  Tree callback: handle a node dropped onto another node.
        %   A "copy" drop (no modifier key) moves the node within the tree; a
        %   "move" drop (Ctrl held) re-applies the dragged branch onto the
        %   target via evaluateDroppedBranch. Root nodes are ignored. The
        %   DropAction is a char array, so the case labels are char arrays too.
            % Run from the repository root (historic behaviour): the drop
            % triggers plugins that may resolve resources relative to it.
            % Restore the previous directory when this callback returns.
            originalDir = cd(this.RepoRoot);
            restoreDir  = onCleanup(@() cd(originalDir)); % restores cwd at callback exit

            if isempty(eventData.Source.Parent.Parent)
                return; % a root node was dropped; ignore
            end

            switch eventData.DropAction
                case 'copy' % no modifier key: move the node in the tree
                    set(eventData.Source, 'Parent', eventData.Target);
                    expand(eventData.Target);
                    expand(eventData.Source);
                case 'move' % Ctrl held: re-apply the dragged branch to the target
                    this.evaluateDroppedBranch(eventData.Source.UserData, eventData.Target);
            end
        end

        function onMouseClicked(this, tree, eventData)
        %ONMOUSECLICKED  Tree callback: load/plot on click, context menu on right-click.
        %   A single left click loads and displays the clicked dataset; a
        %   double left click redisplays it. A right click shows the tree's
        %   context menu (this.Workspace.jmenu, a raw Java JPopupMenu) at the
        %   click position.
        %
        %   jmenu.show(invoker, x, y) positions the popup relative to
        %   INVOKER's own coordinate space, so INVOKER must be the exact
        %   component the click coordinates came from -- Tree.m sets
        %   MouseClickedCallback on tObj.jTree itself (createTreeCustomizations),
        %   so eventData.Position ([e.getX, e.getY]) is already relative to
        %   that same jTree; no further coordinate conversion is needed or
        %   correct here.
            switch eventData.Button
                case 1 % left button
                    if eventData.Clicks == 1
                        % Single click: load the selected dataset and show it.
                        try
                            nodeName = tree.SelectedNodes.Name;
                        catch
                            return; % nothing selected
                        end
                        matFile = tree.SelectedNodes.UserData;
                        if exist(matFile, "file") == 2
                            loaded = load(matFile, "EEG");
                            loaded.EEG.id = string(nodeName);
                            this.Workspace.EEG = loaded.EEG;
                        end
                        this.Plotter.plotCurrent();
                    elseif eventData.Clicks == 2
                        this.Plotter.plotCurrent();
                    end
                case 3 % right button: select the clicked node, then show the
                       % context menu at the click position
                    if ~isempty(eventData.Nodes) && ~any(tree.SelectedNodes == eventData.Nodes)
                        tree.SelectedNodes = eventData.Nodes;
                    end

                    % 'List events' only makes sense for continuous
                    % (non-epoched) data; grey it out otherwise.
                    canListEvents = false;
                    if ~isempty(tree.SelectedNodes)
                        selFile = tree.SelectedNodes.UserData;
                        if exist(selFile, "file") == 2
                            selLoaded = load(selFile, "EEG");
                            canListEvents = isfield(selLoaded.EEG, "DataFormat") ...
                                && strcmpi(selLoaded.EEG.DataFormat, "CONTINUOUS");
                        end
                    end
                    set(this.Workspace.jmenuListEvents, "Enabled", canListEvents);

                    javaObjs = tree.getJavaObjects();
                    this.Workspace.jmenu.show(javaObjs.jTree, ...
                        eventData.Position(1), eventData.Position(2));
            end
        end

        function onSelectionChanged(this, ~, eventData)
        %ONSELECTIONCHANGED  Tree callback: load and plot the newly selected dataset.
            loaded = load(eventData.Nodes.UserData, "EEG");
            this.Workspace.EEG = loaded.EEG;
            this.Plotter.plotCurrent();
        end

        function onGroupAction(this, eventData)
        %ONGROUPACTION  ToolGroup listener: destroy the app when its window closes.
            if strcmp(eventData.EventData.EventType, "CLOSED")
                delete(this);
            end
        end
    end
end
