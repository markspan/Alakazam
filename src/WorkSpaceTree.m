classdef WorkSpaceTree < handle
%WORKSPACETREE  A uihtml-based data-browser tree, replacing uiextras.jTree.
%   WorkSpaceTree wraps a self-contained uihtml page (WorkSpaceTree.html,
%   built from src/webtree/ -- see src/webtree/README.md) that renders a
%   drag-and-drop tree via yy-tree, with per-node icons, a context menu
%   (List events / Rename / Recalculate / Delete), double-click detection
%   and Ctrl-aware drop semantics (see src/webtree/README.md for exactly what
%   "Ctrl-aware" means here). uiextras.jTree was Java-Swing-based and could
%   be docked directly into the old Java ToolGroup desktop; the new
%   AppContainer shell is web/CEF-based, so the data-browser tree needed a
%   web-native replacement, not just a port.
%
%   The MATLAB-side node model is a flat id -> struct map (id, label,
%   parentId, icon, file, canListEvents, canRecalculate, isRoot); the whole
%   set is pushed to the JS side as one Data snapshot on every change (via
%   uihtml's Data property). Callback function handles
%   (SelectionChangedFcn, NodeDroppedFcn, NodeDoubleClickedFcn,
%   ContextMenuActionFcn), settable as constructor name-value pairs,
%   mirror uiextras.jTree.Tree's own construction style so callers barely
%   change shape.
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
    end

    properties (Access = private)
        Nodes       % containers.Map: id (char) -> struct(id,label,parentId,icon,file,canListEvents,canRecalculate,isRoot)
        NextId = 1
        SelectedId  = ''
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
        %   isRoot (all default false).
            if nargin < 6; opts = struct(); end
            if ~isfield(opts, 'canListEvents');  opts.canListEvents  = false; end
            if ~isfield(opts, 'canRecalculate'); opts.canRecalculate = false; end
            if ~isfield(opts, 'isRoot');         opts.isRoot         = false; end

            id = sprintf('n%d', this.NextId);
            this.NextId = this.NextId + 1;
            this.Nodes(id) = struct('id', id, 'label', char(label), ...
                'parentId', char(parentId), 'icon', char(icon), 'file', char(file), ...
                'canListEvents', logical(opts.canListEvents), ...
                'canRecalculate', logical(opts.canRecalculate), ...
                'isRoot', logical(opts.isRoot));
            this.push();
            node = this.nodeStruct(id);
        end

        function removeNode(this, id)
        %REMOVENODE  Remove one node (and, implicitly, its JS-side subtree
        %   display) by Id. Does not touch anything on disk; callers remove
        %   descendant nodes explicitly first if the whole branch is going.
            id = this.resolveId(id);
            if isKey(this.Nodes, id)
                remove(this.Nodes, id);
            end
            if strcmp(this.SelectedId, id)
                this.SelectedId = '';
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

        function clear(this)
        %CLEAR  Remove every node (used when reopening a workspace).
            this.Nodes = containers.Map('KeyType', 'char', 'ValueType', 'any');
            this.SelectedId = '';
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
        %   DataFormat/etc.GrandAverage fields. 'List events' only makes
        %   sense for continuous (non-epoched) data; 'Recalculate' only for
        %   a Grand Average node -- both are baked into the node once, here,
        %   rather than toggled reactively on right-click (as the old
        %   Java context menu did).
            opts = struct( ...
                'canListEvents',  isfield(EEG, 'DataFormat') && strcmpi(EEG.DataFormat, 'CONTINUOUS'), ...
                'canRecalculate', isfield(EEG, 'etc') && isfield(EEG.etc, 'GrandAverage'));
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
            this.Component.Data = this.buildData();
        end

        function data = buildData(this)
            ids = keys(this.Nodes);
            nodes = repmat(struct('id', '', 'label', '', 'icon', '', 'parentId', [], ...
                'canListEvents', false, 'canRecalculate', false), 1, numel(ids));
            for i = 1:numel(ids)
                n = this.Nodes(ids{i});
                parentId = n.parentId;
                if isempty(parentId)
                    parentId = []; % top-level: JS treats [] the same as omitted
                end
                nodes(i) = struct('id', n.id, 'label', n.label, 'icon', n.icon, ...
                    'parentId', parentId, 'canListEvents', n.canListEvents, ...
                    'canRecalculate', n.canRecalculate);
            end
            selId = this.SelectedId;
            if isempty(selId); selId = []; end
            data = struct('nodes', nodes, 'selectedId', selId);
        end

        function s = nodeStruct(this, id)
            n = this.Nodes(id);
            s = struct('Id', n.id, 'Name', n.label, 'UserData', n.file, 'IsRoot', n.isRoot);
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
            end
        end

        function handleDropped(this, d)
            sourceId = d.sourceId;
            targetId = d.targetId;
            if isempty(targetId); targetId = ''; end
            if ~isKey(this.Nodes, sourceId)
                return;
            end
            if d.reparented
                % The JS side has already reparented on its own; mirror it
                % here so this.Nodes (id -> parentId) stays the source of
                % truth for any later addNode/removeNode calls, and push so
                % Component.Data reflects it immediately rather than only
                % after some later, unrelated mutation happens to push.
                n = this.Nodes(sourceId);
                n.parentId = targetId;
                this.Nodes(sourceId) = n;
                this.push();
            end
            src = this.nodeStruct(sourceId);
            if isempty(targetId) || ~isKey(this.Nodes, targetId)
                tgt = [];
            else
                tgt = this.nodeStruct(targetId);
            end
            this.invoke(this.NodeDroppedFcn, ...
                struct('Source', src, 'Target', tgt, 'Reparented', d.reparented));
        end

        function invoke(~, fcn, eventData)
            if ~isempty(fcn)
                fcn(eventData);
            end
        end
    end
end
