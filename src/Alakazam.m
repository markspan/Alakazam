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
%     RootDir  - the authored source tree (this src/ folder), holding the
%                Transformations, Icons and the default workspace.
%     RepoRoot - the repository root (parent of src/), holding the vendored
%                toolkits (EEGLAB, mlapptools, +Tools, +uiextras, device SDKs)
%                and the shared data-file resources.
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
%   required: literals that build command strings later indexed character by
%   character (EEG.Call), element-wise char comparisons, path components, and
%   arguments to the char-only jTree / ToolGroup APIs.
%
%   Adapted from "matlab.ui.internal.desktop.showcaseMPCDesigner()" by
%   R. Chen; original work (c) 2015 The MathWorks, Inc. Further developed by
%   M.M. Span, University of Groningen, Department of Experimental Psychology.
%
%   See also ALAKAZAMPLOTTER, WORKSPACE, BUILDTABGROUPALAKAZAM.

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
        function setupEEGLab(this)
        %SETUPEEGLAB  Ensure EEGLAB is on the MATLAB path, offering to install it.
        %   EEGLAB is expected to be installed and already on the path. If it is
        %   not found, the user is asked for permission to download and install
        %   the latest version into <home>/Documents/MATLAB/eeglab. We do not
        %   call savepath, so the user's global MATLAB path is left untouched.
        %   Once EEGLAB is available, the import plugins Alakazam relies on are
        %   installed through EEGLAB itself (see ensureEEGLabPlugins).
            if isempty(which('eeglab'))
                answer = questdlg([ ...
                    'EEGLAB was not found on the MATLAB path, and Alakazam requires it. ', ...
                    'Download and install the latest EEGLAB now (about 150 MB) into ', ...
                    'your Documents/MATLAB folder?'], ...
                    'EEGLAB not found', ...
                    'Download and install', 'Cancel', 'Download and install');
                if ~strcmp(answer, 'Download and install')
                    error('Alakazam:eeglabMissing', ...
                        'EEGLAB is required but was not found on the MATLAB path.');
                end
                this.installEEGLab();
            end
            this.ensureEEGLabPlugins();
        end

        function ensureEEGLabPlugins(this)
        %ENSUREEEGLABPLUGINS  Install the EEGLAB plugins Alakazam relies on.
        %   The import plugins (BrainVision, XDF) and ICLabel are installed
        %   through EEGLAB's own plugin manager (plugin_askinstall). FastICA is
        %   not an EEGLAB-registry plugin, so it is downloaded directly. Each
        %   item is installed only if its entry function is missing; a failure
        %   (for example, offline) is warned about, not fatal, so the app still
        %   starts.
            plugins = { ...
                'bva-io',    'pop_loadbv';  ...  % BrainVision (.vhdr) import
                'xdfimport', 'load_xdf';    ...  % XDF / Lab Streaming Layer import
                'ICLabel',   'iclabel'};         % IC classification
            for i = 1:size(plugins, 1)
                pluginName = plugins{i, 1};
                probeFcn   = plugins{i, 2};
                if ~isempty(which(probeFcn))
                    continue; % plugin already provides this function
                end
                try
                    plugin_askinstall(pluginName, probeFcn, true);
                catch installError
                    warning('Alakazam:pluginInstall', ...
                        'Could not install EEGLAB plugin ''%s'': %s', ...
                        pluginName, installError.message);
                end
            end

            % FastICA is a standalone package (not in the EEGLAB registry).
            if isempty(which('fastica'))
                try
                    this.installFromZip( ...
                        'https://research.ics.aalto.fi/ica/fastica/code/FastICA_2.5.zip', ...
                        'FastICA', 'fastica.m');
                catch installError
                    warning('Alakazam:pluginInstall', ...
                        'Could not install FastICA: %s', installError.message);
                end
            end
        end

        function installEEGLab(this)
        %INSTALLEEGLAB  Download and install the latest EEGLAB, then start it.
            this.installFromZip( ...
                'https://sccn.ucsd.edu/eeglab/currentversion/eeglab_current.zip', ...
                'eeglab', 'eeglab.m');
            eeglab;
        end

        function installFromZip(~, url, targetName, probeFile)
        %INSTALLFROMZIP  Download a zip, unzip under Documents/MATLAB, add to path.
        %   Downloads the archive at URL into a temporary file, unzips it under
        %   <home>/Documents/MATLAB/<targetName>, locates PROBEFILE in the
        %   unzipped tree and adds that folder to the MATLAB path. Errors if the
        %   download, unzip or probe-file lookup fails. We do not call savepath.
            home = getenv('USERPROFILE');
            if isempty(home)
                home = char(java.lang.System.getProperty('user.home'));
            end
            target = fullfile(home, 'Documents', 'MATLAB', targetName);
            if ~exist(target, 'dir')
                mkdir(target);
            end

            zipPath = fullfile(tempdir, [targetName '.zip']);
            try
                fprintf('Downloading %s ...\n', url);
                websave(zipPath, url, weboptions('Timeout', 600));
                fprintf('Unzipping into %s ...\n', target);
                unzip(zipPath, target);
            catch downloadError
                error('Alakazam:download', ...
                    'Could not download or unzip %s: %s', url, downloadError.message);
            end

            % The archive usually unzips into a versioned subfolder; locate the
            % probe file within it and add that folder to the path.
            found = dir(fullfile(target, '**', probeFile));
            if isempty(found)
                error('Alakazam:installMissing', ...
                    '%s was not found under %s after unzipping %s.', ...
                    probeFile, target, url);
            end
            addpath(found(1).folder);
        end

        function setupDirectories(this)
        %SETUPDIRECTORIES  Put the authored source tree on the path.
        %   All paths are resolved absolutely, so the app does not depend on the
        %   current working directory. RootDir (src) now also holds the +Tools,
        %   +TMSi and +uiextras packages and mlapptools, so adding it puts those
        %   on the path too. The Transformations and the copyright helper
        %   functions (kept at the repository root) are added as well.
            close all;
            warning("off", "MATLAB:ui:javacomponent:FunctionToBeRemoved");
            addpath(this.RootDir, '-end');
            addpath(genpath(fullfile(this.RootDir, 'Transformations')), ...
                    fullfile(this.RootDir, 'mlapptools'), ...
                    genpath(fullfile(this.RepoRoot, 'copyrights')));
        end

        function setupToolGroup(this)
        %SETUPTOOLGROUP  Create and open the toolstrip document window.
        %   Builds the ToolGroup, wires its close listener, populates the tab
        %   group from BuildTabGroupAlakazam, and tiles the document area. The
        %   ToolGroup names and tags are char arrays, as that desktop API expects.
            this.ToolGroup = matlab.ui.internal.desktop.ToolGroup('Alakazam', 'AlakazamApp');
            addlistener(this.ToolGroup, 'GroupAction', @(src, event) this.onGroupAction(event));
            this.Figures = gobjects(1, 1);
            tabgroup = BuildTabGroupAlakazam(this);
            this.ToolGroup.addTabGroup(tabgroup);
            this.ToolGroup.SelectedTab = 'tabHome';
            this.ToolGroup.setPosition(100, 100, 1080, 720);
            this.ToolGroup.open();
            desktop = com.mathworks.mlservices.MatlabDesktopServices.getDesktop; %#ok<JAPIMATHWORKS>
            desktop.setDocumentArrangement(this.ToolGroup.Name, desktop.TILED, java.awt.Dimension(1, 1));
        end

        function [resultEEG, newNode] = persistResultNode(this, resultEEG, sourceFile, displayBase, transformId, parentTreeNode)
        %PERSISTRESULTNODE  Save a transformation result and add it to the tree.
        %   [RESULTEEG, NEWNODE] = PERSISTRESULTNODE(THIS, RESULTEEG, SOURCEFILE,
        %   DISPLAYBASE, TRANSFORMID, PARENTTREENODE) performs the persistence
        %   step shared by onTransformation and evaluateDroppedBranch:
        %     * derive a timestamped cache file next to SOURCEFILE (in a folder
        %       named after the source dataset), creating that folder if needed;
        %     * set RESULTEEG.File and RESULTEEG.id (DISPLAYBASE plus TRANSFORMID);
        %     * add a tree node under PARENTTREENODE with the matching icon,
        %       expand its parent and select it;
        %     * save RESULTEEG to disk and make it the workspace's current EEG.
        %   Returns the updated dataset and the new tree node.

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
            resultEEG.id   = [char(displayBase) ' - ' transformId];

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
        %   Resolves the application roots, sets up EEGLAB and the paths,
        %   opens the toolstrip window, creates the plotter and the workspace,
        %   and loads the data tree.
            this.RootDir  = fileparts(mfilename('fullpath'));
            this.RepoRoot = fileparts(this.RootDir);

            this.setupEEGLab();
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
                % Run from the repository root: individual plugins may resolve
                % resources relative to it (historic behaviour). Path resolution
                % elsewhere no longer depends on the working directory.
                cd(this.RepoRoot);

                figHandle = findobj("Type", "Figure", "Tag", this.Workspace.EEG.File);
                set(figHandle, "Pointer", "watch");

                % The gallery passes the entry file name (e.g. "Fourier.m"); its
                % stem is the transformation id and the function to call. The
                % '.' is a char so the element-wise comparison works, and the
                % call expression stays char because it is later sliced by index.
                entryName   = char(entry);
                transformId = entryName(1:find(entryName == '.', 1, "last") - 1);
                callExpr    = ['EEG=' transformId '(x.EEG);'];

                % Apply the transformation to the current dataset.
                [result.EEG, usedParams] = feval(transformId, this.Workspace.EEG);

                if ishandle(result.EEG)
                    % The plugin returned a graphics handle, not a dataset: it
                    % was a pure plot, so there is nothing to persist.
                    return;
                end

                % Record how the result was produced, so it can be re-applied
                % when this branch is later dragged onto another dataset.
                result.EEG.Call = callExpr;
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

                % Recover the transformation id from the stored call expression
                % "EEG=<id>(x.EEG);". Call is a char array, indexed by position.
                callExpr    = sourceStruct.EEG.Call;
                eqPos       = strfind(callExpr, "=");
                parenPos    = strfind(callExpr, "(");
                transformId = callExpr(eqPos + 1 : parenPos - 1);

                if this.isOverlayableAverage(targetStruct.EEG, sourceStruct.EEG)
                    % Overlay the dropped average on top of the target average.
                    this.overlayAverage(targetStruct.EEG, sourceStruct.EEG);
                    atLeaf = true;
                else
                    % General case: re-apply the stored transformation to the
                    % target, carrying over the source's call and parameters.
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

        function onNodeDropped(this, ~, eventData)
        %ONNODEDROPPED  Tree callback: handle a node dropped onto another node.
        %   A "copy" drop (no modifier key) moves the node within the tree; a
        %   "move" drop (Ctrl held) re-applies the dragged branch onto the
        %   target via evaluateDroppedBranch. Root nodes are ignored. The
        %   DropAction is a char array, so the case labels are char arrays too.
            % Run from the repository root: evaluateDroppedBranch triggers
            % plugins that may resolve resources relative to it.
            cd(this.RepoRoot);

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

        function onMouseClicked(this, tree, eventData, jmenu)
        %ONMOUSECLICKED  Tree callback: load/plot on click, context menu on right-click.
        %   A single left click loads and displays the clicked dataset; a double
        %   left click redisplays it; a right click shows the tear-off menu.
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
                case 3 % right button: show the tear-off context menu
                    jmenu.show(tree, 10, 10);
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
