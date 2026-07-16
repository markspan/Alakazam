classdef AlakazamRibbon < handle
%ALAKAZAMRIBBON  A uihtml-based control strip (Home / Tools / Grand Average),
%   replacing the Toolstrip ribbon (see migration.md): a real MathWorks
%   Toolstrip cannot attach to anything but the undocumented
%   matlab.ui.container.internal.AppContainer, which Alakazam no longer
%   uses. uihtml is already a proven pattern in this app -- see
%   WorkSpaceTree, which wraps a full JS tree component the same way -- and
%   a ribbon is a much simpler case (static layout, no drag gestures), so
%   this is hand-written directly (AlakazamRibbon.html) rather than built
%   with the npm/esbuild tooling src/webtree/ needed for its third-party tree
%   library.
%
%   The MATLAB-side node model (tabs -> groups -> items) is built once from
%   Transformations/*.json at construction and pushed to the JS side as a
%   single Data snapshot (via uihtml's Data property); it does not change
%   afterwards. Icons are embedded as base64 data URIs so the HTML page
%   stays fully self-contained (no relative file-path resolution).
%
%   Data shape (see AlakazamRibbon.html for the JS side):
%     { tabs: [ { id, title, groups: [ { title, items: [
%           {id, label, tooltip, icon}, ... ] }, ... ] }, ... ],
%       activeTab: <id> }
%   Events sent to MATLAB (htmlComponent.sendEventToMATLAB):
%     itemPushed  {id}   -- a button was clicked; id is either a fixed
%                           action string or "transform:<Entry>"
%     tabChanged  {id}   -- the active tab changed
%
%   See also WORKSPACETREE, ALAKAZAM.

    properties (SetAccess = private)
        Component   % the uihtml component
        Grid        % 1x1 uigridlayout the component fills; see the constructor
    end

    properties
        % Callback function handle: fcn(id). Mirrors WorkSpaceTree's
        % *Fcn callback-property style.
        ItemPushedFcn = function_handle.empty
    end

    properties (Access = private)
        TabsData    % cell array of tab structs, built once from Transformations/*.json
        ActiveTab = "home"
    end

    methods
        function this = AlakazamRibbon(parent, transRoot, varargin)
        %ALAKAZAMRIBBON  Build the ribbon inside PARENT (a figure or uipanel),
        %   discovering transformations from TRANSROOT (the Transformations
        %   directory). Remaining NAME,VALUE pairs set the *Fcn callback
        %   properties.
            for k = 1:2:numel(varargin)
                this.(varargin{k}) = varargin{k + 1};
            end

            this.TabsData = this.buildTabsData(transRoot);

            % uihtml has no Units property and does not auto-fill its parent
            % (see WorkSpaceTree for the same note): a 1x1 uigridlayout is
            % the standard way to make it fill and track its container.
            this.Grid = uigridlayout(parent, [1 1], 'Padding', [0 0 0 0]);

            htmlFile = fullfile(fileparts(mfilename('fullpath')), 'AlakazamRibbon.html');
            this.Component = uihtml(this.Grid, 'HTMLSource', htmlFile, 'Data', this.buildData());
            this.Component.HTMLEventReceivedFcn = @(~, evt) this.onEvent(evt);
        end
    end

    methods (Access = private)
        function data = buildData(this)
            data = struct('tabs', {this.TabsData}, 'activeTab', char(this.ActiveTab));
        end

        function onEvent(this, evt)
        %ONEVENT  Dispatch one bridge event from the JS side. See
        %   AlakazamRibbon.html for the exact event/payload shapes.
            name = evt.HTMLEventName;
            d = evt.HTMLEventData;
            switch name
                case 'itemPushed'
                    this.invoke(this.ItemPushedFcn, d.id);
                case 'tabChanged'
                    this.ActiveTab = string(d.id);
            end
        end

        function invoke(~, fcn, varargin)
        %INVOKE  Call FCN(VARARGIN{:}) if it is set, matching WorkSpaceTree's
        %   own guarded-callback idiom.
            if ~isempty(fcn)
                fcn(varargin{:});
            end
        end

        function tabs = buildTabsData(this, transRoot)
        %BUILDTABSDATA  Assemble the tabs->groups->items data: Home
        %   (WorkSpace + Settings), Tools (one group per Transformations
        %   Section, one item per uniquely-named transformation within it --
        %   the Category sub-grouping the old Toolstrip Gallery had is
        %   flattened here, same simplification the uibutton-grid toolbar
        %   this replaces already made), and Grand Average.
        %
        %   Every list (tabs/groups/items) is built as a CELL array of
        %   structs, not a struct array: jsonencode (and uihtml's Data
        %   serialization, which uses the same conversion) collapses a
        %   scalar/single-element struct array to a bare JSON object rather
        %   than a one-element array, which would break the JS side's
        %   .forEach calls for any single-item group (Settings, Grand
        %   Average) -- confirmed empirically before writing this. Cell
        %   arrays always serialize as JSON arrays regardless of element
        %   count, so every list here uses one.
            % Hand-drawn SVG source for every ribbon-only icon (View/
            % WorkSpace/Settings/Grand Average) lives in src/Icons/, next to
            % this file -- see encodeSvgFile.
            iconsDir = fullfile(fileparts(mfilename('fullpath')), 'Icons');

            homeGroups = { ...
                struct('title', 'WORKSPACE', 'items', {this.workspaceItems(iconsDir)}), ...
                struct('title', 'SETTINGS',  'items', {this.settingsItems(iconsDir)}), ...
                struct('title', 'VIEW',      'items', {this.viewItems(iconsDir)})};

            grandAverageGroups = { ...
                struct('title', 'Group Averages', 'items', {this.grandAverageItems(iconsDir)})};

            tabs = { ...
                struct('id', 'home', 'title', 'Alakazam', 'groups', {homeGroups}), ...
                struct('id', 'tools', 'title', 'Tools', ...
                    'groups', {this.transformationGroups(transRoot)}), ...
                struct('id', 'grandAverage', 'title', 'Grand Average', ...
                    'groups', {grandAverageGroups})};
        end

        function items = workspaceItems(this, iconsDir)
        %WORKSPACEITEMS  Open/Save/Edit/Clear for the current WorkSpace
        %   session. Hand-drawn SVG read from src/Icons/ (encodeSvgFile),
        %   matching viewItems' style (fill="none", #4a7fc9 stroke) rather
        %   than the encodeIcon(pngPath) MathWorks toolstrip icons used
        %   elsewhere in this file -- Open/Save previously borrowed
        %   mismatched mpcdesigner icons, and Edit/Clear both incorrectly
        %   reused the Save icon (there was no distinct pair available in
        %   the bundled sets); one clean, consistent icon per action now.
            items = { ...
                struct('id', 'openWorkspace', 'label', 'Open WorkSpace', ...
                    'tooltip', 'Open a Workspace', ...
                    'icon', this.encodeSvgFile(fullfile(iconsDir, 'OpenWorkspace.svg'))), ...
                struct('id', 'saveWorkspace', 'label', 'Save WorkSpace', ...
                    'tooltip', 'Save current WorkSpace into a session for future use', ...
                    'icon', this.encodeSvgFile(fullfile(iconsDir, 'SaveWorkspace.svg'))), ...
                struct('id', 'editWorkspace', 'label', 'Edit WorkSpace', ...
                    'tooltip', 'Edit current WorkSpace', ...
                    'icon', this.encodeSvgFile(fullfile(iconsDir, 'EditWorkspace.svg'))), ...
                struct('id', 'clearWorkspace', 'label', 'Clear WorkSpace', ...
                    'tooltip', 'Rawload current WorkSpace', ...
                    'icon', this.encodeSvgFile(fullfile(iconsDir, 'ClearWorkspace.svg')))};
        end

        function items = settingsItems(this, iconsDir)
        %SETTINGSITEMS  Global settings dialog launcher. Hand-drawn SVG gear
        %   read from src/Icons/ (see workspaceItems for why: matches
        %   viewItems' style instead of the mismatched control_app_24.png
        %   bundled icon).
            icon = this.encodeSvgFile(fullfile(iconsDir, 'Settings.svg'));
            items = {struct('id', 'settings', 'label', 'Global', ...
                'tooltip', 'Edit the global Alakazam settings', 'icon', icon)};
        end

        function items = viewItems(this, iconsDir)
        %VIEWITEMS  Tabs/Grid/Stack toggle for the plots area (see
        %   Alakazam.setPlotsViewMode). No tile/grid icon exists in the
        %   bundled MathWorks toolstrip icon sets, so these are hand-drawn
        %   SVG read from src/Icons/ (encodeSvgFile) rather than the
        %   encodeIcon(pngPath) used elsewhere in this file -- an <img>
        %   inside this uihtml page renders an SVG data URI fine (ordinary
        %   web behaviour; this is unrelated to
        %   matlab.ui.control.Button.Icon, which does NOT accept an SVG data
        %   URI, only a real file path -- checked separately, not a concern
        %   here since the ribbon is HTML, not MATLAB uicomponents).
            items = { ...
                struct('id', 'viewTabs', 'label', 'Tabs', ...
                    'tooltip', 'Show one open dataset at a time', ...
                    'icon', this.encodeSvgFile(fullfile(iconsDir, 'ViewTabs.svg'))), ...
                struct('id', 'viewGrid', 'label', 'Grid', ...
                    'tooltip', 'Show every open dataset at once, arranged in a grid', ...
                    'icon', this.encodeSvgFile(fullfile(iconsDir, 'ViewGrid.svg'))), ...
                struct('id', 'viewStack', 'label', 'Stack', ...
                    'tooltip', 'Show every open dataset at once, stacked in one column', ...
                    'icon', this.encodeSvgFile(fullfile(iconsDir, 'ViewStack.svg')))};
        end

        function items = grandAverageItems(this, iconsDir)
        %GRANDAVERAGEITEMS  "Define Grand Average..." launcher and "Export
        %   Grand Averages..." exporter. Hand-drawn SVGs read from
        %   src/Icons/ (see workspaceItems for why: matches the rest of the
        %   ribbon's own icon set instead of a borrowed, mismatched
        %   MathWorks toolstrip icon -- Define Grand Average used to reuse
        %   control_app_24.png, an unrelated generic "app" icon). Define
        %   Grand Average's icon: three thin mini-waveforms (individual
        %   subjects' averages) converge into one bold waveform (the grand
        %   average), the same visual idea the feature itself implements.
        %   Export's icon: a small data table with an arrow breaking out of
        %   it, matching the tabular CSV format it writes.
            defineIcon = this.encodeSvgFile(fullfile(iconsDir, 'GrandAverage.svg'));
            exportIcon = this.encodeSvgFile(fullfile(iconsDir, 'ExportGrandAverages.svg'));
            items = {struct('id', 'defineGrandAverage', 'label', 'Define Grand Average...', ...
                'tooltip', 'Combine several subjects'' Average results into one grand average', ...
                'icon', defineIcon), ...
                struct('id', 'exportGrandAverages', 'label', 'Export Grand Averages...', ...
                'tooltip', 'Export every Grand Average to one R-compatible, long-format CSV', ...
                'icon', exportIcon)};
        end

        function groups = transformationGroups(this, transRoot)
            transInfo = getTransInfos(transRoot);
            uniqueSections = unique({transInfo.Section});

            groups = cell(1, numel(uniqueSections));
            for si = 1:numel(uniqueSections)
                tS = uniqueSections{si};
                sectionForms = transInfo(strcmp({transInfo.Section}, tS));
                names = unique({sectionForms.Name});

                items = cell(1, numel(names));
                for ti = 1:numel(names)
                    iTransForm = sectionForms(strcmp({sectionForms.Name}, names{ti}));
                    items{ti} = struct( ...
                        'id', ['transform:' iTransForm.Entry], ...
                        'label', iTransForm.Name, ...
                        'tooltip', iTransForm.Description, ...
                        'icon', this.encodeIcon(fullfile(transRoot, iTransForm.Name, iTransForm.Icon)));
                end
                groups{si} = struct('title', tS, 'items', {items});
            end
        end

        function uri = encodeIcon(~, pngPath)
        %ENCODEICON  A PNG file as a base64 data URI, keeping the ribbon's
        %   HTML page fully self-contained (no relative-asset resolution --
        %   the same reasoning src/webtree/assemble.mjs gives for inlining
        %   everything into one file).
            fid = fopen(pngPath, 'r');
            if fid < 0
                uri = '';
                return;
            end
            bytes = fread(fid, inf, '*uint8')';
            fclose(fid);
            uri = ['data:image/png;base64,' char(matlab.net.base64encode(bytes))];
        end

        function uri = encodeSvgIcon(~, svgMarkup)
        %ENCODESVGICON  Hand-drawn SVG markup as a base64 data URI -- used
        %   where no suitable PNG exists in MATLAB's bundled icon sets (see
        %   viewItems). An <img> inside this uihtml page renders an SVG data
        %   URI the same as any web page would; unrelated to
        %   matlab.ui.control.Button.Icon, which does not accept one.
            uri = ['data:image/svg+xml;base64,' char(matlab.net.base64encode(svgMarkup))];
        end

        function uri = encodeSvgFile(this, svgPath)
        %ENCODESVGFILE  An SVG file's markup as a base64 data URI -- the SVG
        %   counterpart of encodeIcon, reading src/Icons/<Name>.svg instead
        %   of embedding the markup as a literal string. Keeps the ribbon's
        %   icon set backed by one real, editable source file per icon
        %   rather than a copy duplicated inline here that could silently
        %   drift from it.
            fid = fopen(svgPath, 'r');
            if fid < 0
                uri = '';
                return;
            end
            markup = fread(fid, inf, '*char')';
            fclose(fid);
            uri = this.encodeSvgIcon(markup);
        end
    end
end

function info = getIndividualTransInfos(TName, transRoot)
    % Retrieve individual transformation information from a JSON file.
    %
    % Args:
    %     TName: The name of the transformation.
    %     transRoot: Absolute path to the Transformations directory.
    %
    % Returns:
    %     info: A structure containing the transformation information.

    % Convert TName to a character array
    TName = char(TName);

    % Locate and read the JSON file containing the transformation information
    json = dir(fullfile(transRoot, TName, [TName '.json']));
    json = fullfile(json.folder, json.name);
    jsonfile = fopen(json);
    jsonraw = fread(jsonfile, inf);
    fclose(jsonfile);

    % Decode the JSON file content
    info = jsondecode(char(jsonraw'));
end

function transInfo = getTransInfos(transRoot)
    % Retrieve information for all transformations.
    %
    % Args:
    %     transRoot: Absolute path to the Transformations directory.
    %
    % Returns:
    %     transInfo: A structure array containing information for all transformations.

    % List directories within the 'Transformations' folder
    fL = dir(fullfile(transRoot, '.'));

    % Filter out unwanted directory names (keep real sub-directories only)
    tF = {fL([fL.isdir]).name};
    tF = tF(~ismember(tF, {'.', '..', '+TransTools'}));

    % Initialize an empty cell array to store transformation information
    transInfo = {};

    % Retrieve and store information for each transformation
    for Trans = tF
        transInfo{end+1} = getIndividualTransInfos(Trans{1}, transRoot); %#ok<AGROW>
    end

    % Convert the cell array to a structure array
    transInfo = [transInfo{:}];
end
