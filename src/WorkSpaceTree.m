classdef WorkSpaceTree < handle
%WORKSPACETREE  A uihtml-based data-browser tree, replacing uiextras.jTree.
%   WorkSpaceTree wraps a self-contained uihtml page (WorkSpaceTree.html,
%   built from src/webtree/ -- see src/webtree/README.md) that renders a
%   drag-and-drop tree via yy-tree, with per-node icons, a context menu
%   (List events / Rename / Recalculate / Apply to All Raw Files / Delete),
%   double-click detection and always-revert drop semantics: dropping one
%   node onto another never
%   moves it, it always means "apply this branch's transformations to the
%   dropped-on dataset" (see src/webtree/README.md). uiextras.jTree was
%   Java-Swing-based and could
%   be docked directly into the old Java ToolGroup desktop; the new
%   AppContainer shell is web/CEF-based, so the data-browser tree needed a
%   web-native replacement, not just a port.
%
%   The MATLAB-side node model is a flat id -> struct map (id, label,
%   parentId, icon, file, canListEvents, canRecalculate, canApplyToAll,
%   isRoot); the whole
%   set is pushed to the JS side as one Data snapshot on every change (via
%   uihtml's Data property). Callback function handles
%   (SelectionChangedFcn, NodeDroppedFcn, NodeDoubleClickedFcn,
%   ContextMenuActionFcn, RenderErrorFcn), settable as constructor
%   name-value pairs, mirror uiextras.jTree.Tree's own construction style
%   so callers barely change shape.
%
%   Node "handles" returned by SelectedNodes / addNode / event callbacks
%   are plain value structs (Id, Name, UserData, IsRoot), not object
%   handles: unlike the old TreeNode, they do not carry live Parent/
%   Children references, since the true node graph lives in this class's
%   own Nodes map (mirrored to JS), not in a MATLAB object graph.
%
%   See also: WorkSpace, CreateTreeComponent, Alakazam.

    properties (SetAccess = private)
        Component   % the uihtml component
        Grid        % 1x1 uigridlayout the component fills; see the constructor
    end

    properties (Dependent)
        SelectedNodes   % struct(Id,Name,UserData,IsRoot), or [] if none selected
    end

    properties
        % Callback function handles: fcn(eventData). Mirrors uiextras.jTree.
        % Tree's name-value callback-property style, simplified to one arg:
        % every current handler (onSelectionChanged, onNodeDropped, ...)
        % already discards the old two-arg form's source-object argument.
        SelectionChangedFcn  = function_handle.empty
        NodeDroppedFcn       = function_handle.empty
        NodeRenamedFcn       = function_handle.empty
        NodeDoubleClickedFcn = function_handle.empty
        ContextMenuActionFcn = function_handle.empty
        RenderErrorFcn       = function_handle.empty % fcn(struct(Message,Stack)); see onEvent's 'renderError' case
    end

    properties (Access = private)
        Nodes       % containers.Map: id (char) -> struct(id,label,parentId,icon,file,canListEvents,canRecalculate,isRoot)
        NextId = 1
        SelectedId  = ''
        PushSeq = 0 % see push(): included in every Data push so it never
                    % deep-equals the previous one, even when Nodes/
                    % SelectedId happen to be unchanged (e.g. notifyDropHandled
                    % after an ignored drop) -- guarantees the JS side's
                    % DataChanged listener fires every time, not just when
                    % content actually differs.
    end

    properties (Constant)
        % Transformation ids whose options dialog can be re-seeded with an
        % arbitrary (rather than just "last used in this workspace")
        % parameter struct -- see Alakazam.recalculateTransformNode, which
        % temporarily stands in for TransformSettings to reopen one of
        % these pre-filled with a specific node's own stored parameters.
        % Every one of these follows the same [EEG,opts] = Fn(input) /
        % [EEG,opts] = Fn(input,opts) contract and is already
        % TransformSettings-wired (see PROJECT_STRUCTURE.md). Deliberately
        % NOT exhaustive: Average/ScalpDistribution take no options at all
        % -- "Recalculate" stays disabled for nodes produced by any of
        % those (see optsFor), since offering an edit it cannot actually
        % perform would be worse than not offering it.
        RecalculableTransforms = {'ArtefactDetect', 'AutoEyeICA', 'AutoGEDAI', ...
            'Baseline', 'CoherenceMap', 'DefineBins', 'Filter', 'Fourier', 'Measure', ...
            'ReRef', 'SelectData', 'SpectralMeasure', 'TimeFrequency'}
    end

    methods
        function this = WorkSpaceTree(parent, varargin)
        %WORKSPACETREE  Build the tree inside PARENT (a figure or uipanel).
        %   Remaining NAME,VALUE pairs set the *Fcn callback properties.
        %
        %   uihtml has no Units property (unlike classic uicontrol/axes), so
        %   it does not auto-fill or auto-resize with its parent by default.
        %   A 1x1 uigridlayout is the standard, maintenance-free way to make
        %   a uifigure-family component fill and track its container: the
        %   grid (not this class's caller) owns tracking parent resizes.
            for k = 1:2:numel(varargin)
                this.(varargin{k}) = varargin{k + 1};
            end
            this.Nodes = containers.Map('KeyType', 'char', 'ValueType', 'any');

            this.Grid = uigridlayout(parent, [1 1], 'Padding', [0 0 0 0]);

            htmlFile = fullfile(fileparts(mfilename('fullpath')), 'WorkSpaceTree.html');
            this.Component = uihtml(this.Grid, 'HTMLSource', htmlFile, 'Data', this.buildData());
            this.Component.HTMLEventReceivedFcn = @(~, evt) this.onEvent(evt);
        end

        function value = get.SelectedNodes(this)
            if isempty(this.SelectedId) || ~isKey(this.Nodes, this.SelectedId)
                value = [];
            else
                value = this.nodeStruct(this.SelectedId);
            end
        end

        function set.SelectedNodes(this, value)
        %set.SelectedNodes  Accepts a node struct (Id field) or a raw id.
            if isempty(value)
                this.SelectedId = '';
            elseif isstruct(value)
                this.SelectedId = value.Id;
            else
                this.SelectedId = char(value);
            end
            this.push();
        end

        function node = addNode(this, label, parentId, icon, file, opts)
        %ADDNODE  Add a node, returning its struct(Id,Name,UserData,IsRoot).
        %   PARENTID is another node's Id, or '' for a top-level node. OPTS
        %   is a struct with optional fields canListEvents, canRecalculate,
        %   canApplyToAll, canExportErpset, isRoot (all default false).
            if nargin < 6; opts = struct(); end
            if ~isfield(opts, 'canListEvents');   opts.canListEvents   = false; end
            if ~isfield(opts, 'canRecalculate');  opts.canRecalculate  = false; end
            if ~isfield(opts, 'canApplyToAll');   opts.canApplyToAll   = false; end
            if ~isfield(opts, 'canExportErpset'); opts.canExportErpset = false; end
            if ~isfield(opts, 'isRoot');          opts.isRoot          = false; end

            id = sprintf('n%d', this.NextId);
            this.NextId = this.NextId + 1;
            this.Nodes(id) = struct('id', id, 'label', char(label), ...
                'parentId', char(parentId), 'icon', char(icon), 'file', char(file), ...
                'canListEvents', logical(opts.canListEvents), ...
                'canRecalculate', logical(opts.canRecalculate), ...
                'canApplyToAll', logical(opts.canApplyToAll), ...
                'canExportErpset', logical(opts.canExportErpset), ...
                'isRoot', logical(opts.isRoot));
            this.push();
            node = this.nodeStruct(id);
        end

        function removeNode(this, id)
        %REMOVENODE  Remove a node AND every descendant of it (walked via
        %   parentId, since Nodes is a flat id->struct map, not a real
        %   tree), in one push. Does not touch anything on disk; callers
        %   remove the corresponding files themselves (see
        %   Alakazam.onDeleteNode).
        %   Removing only the given id and leaving its descendants in
        %   Nodes used to orphan them: their parentId would point at an id
        %   that no longer exists, and setNodes (src/webtree/src/
        %   alakazam-tree.js) treats an unresolvable parentId as "top-level",
        %   so a deleted branch's children reappeared as new root nodes --
        %   still selectable, but their backing .mat files (deleted
        %   recursively by onDeleteNode's own rmdir) were already gone,
        %   crashing onSelectionChanged's load() the moment one was clicked.
            id = this.resolveId(id);
            ids = this.branchIds(id);
            for k = 1:numel(ids)
                if isKey(this.Nodes, ids{k})
                    remove(this.Nodes, ids{k});
                end
                if strcmp(this.SelectedId, ids{k})
                    this.SelectedId = '';
                end
            end
            this.push();
        end

        function renameNode(this, id, newLabel)
        %RENAMENODE  Update a node's displayed label.
            id = this.resolveId(id);
            if isKey(this.Nodes, id)
                n = this.Nodes(id);
                n.label = char(newLabel);
                this.Nodes(id) = n;
                this.push();
            end
        end

        function setUserData(this, id, file)
        %SETUSERDATA  Update the cache-file path a node points at (used when
        %   a Grand Average is recalculated in place).
            id = this.resolveId(id);
            if isKey(this.Nodes, id)
                n = this.Nodes(id);
                n.file = char(file);
                this.Nodes(id) = n;
            end
        end

        function nodes = allNodes(this)
        %ALLNODES  Every current node, in the same struct(Id,Name,UserData,
        %   IsRoot) shape as SelectedNodes/addNode -- e.g. for a bulk
        %   export that needs every Grand Average, not just the selected
        %   one. Empty (0x0) when the tree has no nodes, matching
        %   SelectedNodes' own empty-case shape.
            ids = keys(this.Nodes);
            if isempty(ids)
                nodes = [];
                return;
            end
            nodes = repmat(struct('Id', '', 'Name', '', 'UserData', '', 'IsRoot', false), 1, numel(ids));
            for i = 1:numel(ids)
                nodes(i) = this.nodeStruct(ids{i});
            end
        end

        function file = parentFile(this, id)
        %PARENTFILE  The cache file of ID's parent node, or '' if ID is a
        %   root node, unknown, or its parent is unknown. Nodes is a flat
        %   id -> struct map (see the class header), not a real object
        %   graph, so this is the only way to find a node's input dataset
        %   -- used by Alakazam.recalculateTransformNode to re-run a
        %   transformation against the same input it originally ran
        %   against.
            file = '';
            id = this.resolveId(id);
            if ~isKey(this.Nodes, id)
                return;
            end
            parentId = this.Nodes(id).parentId;
            if isempty(parentId) || ~isKey(this.Nodes, parentId)
                return;
            end
            file = this.Nodes(parentId).file;
        end

        function node = rootOf(this, id)
        %ROOTOF  The root ancestor of ID, walking parentId links up through
        %   the flat id->struct map (see the class header) -- [] if ID is
        %   unknown. Used by Alakazam.onApplyToAllRawFiles to find (and
        %   then exclude) the raw file a branch already descends from, so
        %   "apply to all" never re-applies a branch onto its own source
        %   recording.
            id = this.resolveId(id);
            if ~isKey(this.Nodes, id)
                node = [];
                return;
            end
            while true
                parentId = this.Nodes(id).parentId;
                if isempty(parentId) || ~isKey(this.Nodes, parentId)
                    break;
                end
                id = parentId;
            end
            node = this.nodeStruct(id);
        end

        function clear(this)
        %CLEAR  Remove every node (used when reopening a workspace).
            this.Nodes = containers.Map('KeyType', 'char', 'ValueType', 'any');
            this.SelectedId = '';
            this.push();
        end

        function notifyDropHandled(this)
        %NOTIFYDROPHANDLED  Tell the JS side a drop has finished being
        %   handled, whatever the outcome (a real transformation applied,
        %   an ignored root/empty-target drop, or an error). The JS side
        %   sets a busy/wait cursor the instant it sends nodeDropped (see
        %   src/webtree/src/alakazam-tree.js's _onMove) and only clears it
        %   once a fresh Data push arrives (see src/webtree/src/bridge.js's
        %   applyData); Alakazam.onNodeDropped calls this via onCleanup so
        %   it always runs when that callback returns, by any path.
            this.push();
        end
    end

    methods (Static)
        function key = iconFor(dataType)
        %ICONFOR  Map an EEG DataType to a WorkSpaceTree icon key ('time'/
        %   'freq'/'default' -- see src/webtree/src/alakazam-tree.js's ICONS map).
            if strcmpi(dataType, 'TIMEDOMAIN')
                key = 'time';
            elseif strcmpi(dataType, 'FREQUENCYDOMAIN')
                key = 'freq';
            else
                key = 'default';
            end
        end

        function icon = iconForResult(EEG, transRoot)
        %ICONFORRESULT  Icon for a dataset produced by a transformation: the
        %   transformation's own icon (Transformations/<id>/<id>.json's
        %   Icon field, the same PNG AlakazamRibbon's Tools tab buttons
        %   show), scaled down to the tree row's icon footprint. EEG.id is
        %   the transformation id (see Alakazam.persistResultNode/
        %   onTransformation: transformId, stored on the result as both
        %   EEG.id and EEG.Call). Falls back to iconFor(EEG.DataType) (the
        %   'time'/'freq'/'default' badge keys) when TRANSROOT is omitted
        %   or no matching Transformations/<id>/<id>.json exists -- e.g. a
        %   Grand Average, whose id is a user-chosen name, not a
        %   transformation id.
            icon = '';
            if nargin >= 2 && ~isempty(transRoot) && isfield(EEG, 'id') && ~isempty(EEG.id)
                icon = WorkSpaceTree.encodeTransformIcon(char(string(EEG.id)), transRoot);
            end
            if isempty(icon)
                icon = WorkSpaceTree.iconFor(EEG.DataType);
            end
        end

        function opts = optsFor(EEG)
        %OPTSFOR  Build an addNode opts struct from a loaded EEG's
        %   DataFormat/Call/etc.GrandAverage fields. 'List events' only
        %   makes sense for continuous (non-epoched) data. 'Recalculate' is
        %   offered for a Grand Average node (revisit its subject list --
        %   see Alakazam.onRecalculateNode), or for a node produced by one
        %   of RecalculableTransforms (revisit its parameters and
        %   recompute it and everything downstream -- see
        %   Alakazam.recalculateTransformNode); every other node (a raw
        %   root import, or one produced by a transform with no editable/
        %   re-seedable dialog, e.g. ReRef/SelectData/Average/
        %   ScalpDistribution) leaves it disabled rather than offering an
        %   edit it cannot actually perform. Both are baked into the node
        %   once, here, rather than toggled reactively on right-click (as
        %   the old Java context menu did). Does NOT set canApplyToAll:
        %   unlike the other two flags, that one depends on which tree the
        %   node is being added to (only Workspace.Tree, never
        %   Workspace.GrandAveragesTree), which this EEG-only function has
        %   no way to know -- see Alakazam.persistResultNode, which sets it
        %   itself after calling this.
            isGrandAverage = isfield(EEG, 'etc') && isfield(EEG.etc, 'GrandAverage');
            isEditableTransform = isfield(EEG, 'Call') && ~isempty(EEG.Call) && ...
                any(strcmp(char(string(EEG.Call)), WorkSpaceTree.RecalculableTransforms));
            opts = struct( ...
                'canListEvents',  isfield(EEG, 'DataFormat') && strcmpi(EEG.DataFormat, 'CONTINUOUS'), ...
                'canRecalculate', isGrandAverage || isEditableTransform, ...
                'canExportErpset', isfield(EEG, 'DataFormat') && strcmpi(EEG.DataFormat, 'Averaged'));
        end
    end

    methods (Static, Access = private)
        function uri = encodeTransformIcon(transformId, transRoot)
        %ENCODETRANSFORMICON  TRANSFORMID's own icon (Transformations/
        %   <transformId>/<transformId>.json's Icon field) as a base64 PNG
        %   data URI, or '' if TRANSFORMID does not name a real
        %   transformation folder (see iconForResult) -- mirrors
        %   AlakazamRibbon's own getIndividualTransInfos/encodeIcon, kept
        %   as a separate copy here rather than a shared dependency so
        %   WorkSpaceTree does not need to know about AlakazamRibbon. The
        %   JS side (alakazam-tree.js's _onRender) renders any 'data:'-
        %   prefixed icon string as a scaled-down <img> instead of looking
        %   it up in the fixed ICONS badge map.
            uri = '';
            jsonFile = fullfile(transRoot, transformId, [transformId '.json']);
            if exist(jsonFile, 'file') ~= 2
                return;
            end
            try
                info = jsondecode(fileread(jsonFile));
                iconPath = fullfile(transRoot, transformId, info.Icon);
                fid = fopen(iconPath, 'r');
                if fid < 0
                    return;
                end
                bytes = fread(fid, inf, '*uint8')';
                fclose(fid);
                uri = ['data:image/png;base64,' char(matlab.net.base64encode(bytes))];
            catch
                uri = '';
            end
        end
    end

    methods (Access = private)
        function id = resolveId(this, node) %#ok<INUSL>
            if isstruct(node); id = node.Id; else; id = char(node); end
        end

        function push(this)
            this.PushSeq = this.PushSeq + 1;
            data = this.buildData();
            data.seq = this.PushSeq;
            this.Component.Data = data;
        end

        function data = buildData(this)
        %BUILDDATA  Build the Data payload pushed to the JS side. NODES is
        %   built as a cell array, not a struct array: jsonencode (and
        %   uihtml's Data marshaling, built on the same machinery) collapses
        %   a 1x1 struct array to a bare JSON object instead of a
        %   single-element array (confirmed directly: jsonencode(repmat(
        %   struct(...),1,1)) gives '{"a":1}', not '[{"a":1}]' -- 2+ elements
        %   and 0 elements both serialize correctly, only exactly 1 does
        %   not). The JS side's setNodes does `for (const n of nodes)`,
        %   which throws ("nodes is not iterable") on a bare object, so a
        %   workspace with exactly one node (most commonly: exactly one
        %   Grand Average) rendered a silently-blank tree with no nodes at
        %   all. A cell array reliably serializes as a JSON array
        %   regardless of element count (confirmed: jsonencode({struct(
        %   'a',1)}) gives '[{"a":1}]'), so this sidesteps the collapse
        %   entirely rather than special-casing count==1.
            ids = keys(this.Nodes);
            nodes = cell(1, numel(ids));
            for i = 1:numel(ids)
                n = this.Nodes(ids{i});
                parentId = n.parentId;
                if isempty(parentId)
                    parentId = []; % top-level: JS treats [] the same as omitted
                end
                nodes{i} = struct('id', n.id, 'label', n.label, 'icon', n.icon, ...
                    'parentId', parentId, 'canListEvents', n.canListEvents, ...
                    'canRecalculate', n.canRecalculate, 'canApplyToAll', n.canApplyToAll, ...
                    'canExportErpset', n.canExportErpset);
            end
            selId = this.SelectedId;
            if isempty(selId); selId = []; end
            % Double-wrapped ({nodes}, not nodes): struct()'s own cell-value
            % convention treats an unwrapped cell array as "one struct per
            % cell" (struct-array broadcasting), which is not what is
            % wanted here -- the extra wrapping layer says "this whole cell
            % array is the single value of this one field on a scalar
            % struct".
            data = struct('nodes', {nodes}, 'selectedId', selId);
        end

        function s = nodeStruct(this, id)
            n = this.Nodes(id);
            s = struct('Id', n.id, 'Name', n.label, 'UserData', n.file, 'IsRoot', n.isRoot);
        end

        function ids = branchIds(this, id)
        %BRANCHIDS  ID plus every descendant of it, found by walking
        %   parentId links (Nodes is a flat id->struct map, not a real
        %   tree). Used by removeNode so a whole-branch delete removes
        %   every descendant node too, not just the one the user clicked.
            ids = {id};
            allIds = keys(this.Nodes);
            for k = 1:numel(allIds)
                if isKey(this.Nodes, allIds{k}) && strcmp(this.Nodes(allIds{k}).parentId, id)
                    ids = [ids, this.branchIds(allIds{k})]; %#ok<AGROW>
                end
            end
        end

        function onEvent(this, evt)
        %ONEVENT  Dispatch one bridge event from the JS side. See
        %   src/webtree/README.md for the exact event/payload shapes.
            name = evt.HTMLEventName;
            d = evt.HTMLEventData;
            switch name
                case 'nodeClicked'
                    if isKey(this.Nodes, d.id)
                        this.SelectedId = d.id;
                        this.push();
                        this.invoke(this.SelectionChangedFcn, this.nodeStruct(d.id));
                    end
                case 'nodeDoubleClicked'
                    if isKey(this.Nodes, d.id)
                        this.SelectedId = d.id;
                        this.push();
                        this.invoke(this.NodeDoubleClickedFcn, this.nodeStruct(d.id));
                    end
                case 'nodeDropped'
                    this.handleDropped(d);
                case 'nodeRenamed'
                    % Inline (press-and-hold) rename is disabled JS-side
                    % (holdTime:0); rename goes through the context menu's
                    % Rename item -> Alakazam.onRenameNode -> renameNode().
                    % Kept for completeness / future use.
                    this.invoke(this.NodeRenamedFcn, struct('Id', d.id, 'Name', d.name));
                case 'contextMenuAction'
                    if isKey(this.Nodes, d.id)
                        this.SelectedId = d.id;
                        this.invoke(this.ContextMenuActionFcn, ...
                            struct('Action', d.action, 'Node', this.nodeStruct(d.id)));
                    end
                case 'rendered'
                    % Diagnostic only (node/icon counts from the JS side); no-op.
                case 'renderError'
                    % A JS-side exception in bridge.js's applyData (e.g. the
                    % single-node-array/jsonencode bug this was added to
                    % catch) would otherwise die silently in the embedded
                    % CEF browser's own console and surface on the MATLAB
                    % side only as a vague, unactionable "HTMLSource may be
                    % referencing unsupported functionality or may have a
                    % JavaScript error" warning with no message or stack --
                    % see bridge.js's own catch block for the full story.
                    this.invoke(this.RenderErrorFcn, struct('Message', d.message, 'Stack', d.stack));
            end
        end

        function handleDropped(this, d)
        %HANDLEDROPPED  Tree callback: a node was dropped onto another (or
        %   onto empty space/root). The JS side (see src/webtree/README.md)
        %   always reverts its own visual move before this fires, so
        %   this.Nodes never needs updating here; just forward the event.
            sourceId = d.sourceId;
            targetId = d.targetId;
            if isempty(targetId); targetId = ''; end
            if ~isKey(this.Nodes, sourceId)
                return;
            end
            src = this.nodeStruct(sourceId);
            if isempty(targetId) || ~isKey(this.Nodes, targetId)
                tgt = [];
            else
                tgt = this.nodeStruct(targetId);
            end
            this.invoke(this.NodeDroppedFcn, struct('Source', src, 'Target', tgt));
        end

        function invoke(~, fcn, eventData)
            if ~isempty(fcn)
                fcn(eventData);
            end
        end
    end
end
