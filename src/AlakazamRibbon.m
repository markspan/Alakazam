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
%     groupExpand {tabId, groupIndex, left, top, width, height} -- a
%                           collapsible group's title bar was clicked to
%                           unfold it; left/top/width/height is that group's
%                           own on-page rect (CSS pixels, top-left origin, as
%                           reported by getBoundingClientRect()).
%     groupCollapse {}    -- the open group's title bar was clicked again
%
%   Overflow groups (more items than fit in one row) used to unfold in
%   place, which meant growing the whole ribbon row height (and pushing
%   everything below it down) whenever any group unfolded. That is gone:
%   a group now opens as a small floating popup positioned directly under
%   it, drawn over the plots area rather than resizing anything (see
%   PopupComponent/Scrim below and showPopup/hidePopup). uihtml itself
%   clips to its own box like an iframe -- CSS alone can't make content
%   spill past AlakazamRibbon.html's own rectangle -- so the popup is a
%   second uihtml component, parented directly to the figure (not to
%   Grid/the ribbon's own uigridlayout cell) so it floats free of the grid
%   and can be positioned/sized in figure pixel coordinates on demand.
%
%   See also WORKSPACETREE, ALAKAZAM.

    properties (SetAccess = private)
        Component       % the uihtml component
        Grid            % 1x1 uigridlayout the component fills; see the constructor
        PopupComponent  % uihtml, the floating group-overflow popup (hidden until needed)
        Scrim           % uipanel covering the figure behind the popup; a click on it closes the popup
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

    properties (Access = private, Constant)
        % Popup grid metrics, kept in one place since MATLAB has to size and
        % position the popup itself (see showPopup) -- these must stay in
        % rough visual agreement with the .alz-item/.alz-group-title rules in
        % AlakazamRibbonPopup.html. Approximate by design (real row heights
        % depend on label wrapping); tune here first if the popup looks off
        % once seen live, before touching the HTML/CSS.
        PopupCols        = 4    % items per row in the popup (vs. ALZ_PER_ROW=6 in the main ribbon: narrower, taller)
        PopupItemRowPx   = 58   % px per row of items (item box + gaps)
        PopupTitleBarPx  = 24   % px for the popup's own title bar
        PopupPaddingPx   = 14   % px total (top+bottom) panel padding
        PopupColWidthPx  = 68   % px per column, for popup width
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

            this.buildPopup(parent);
        end
    end

    methods (Access = private)
        function buildPopup(this, parent)
        %BUILDPOPUP  Create the (hidden) Scrim + PopupComponent used by an
        %   overflow group's dropdown. Both are parented directly to the
        %   figure with an explicit pixel Position -- not to Grid, which is
        %   pinned inside the fixed-height ribbon row -- so they float free
        %   of the app's uigridlayout and can be positioned over the plots
        %   area on demand (see showPopup). A component parented straight to
        %   a uifigure with Position set is not grid-managed and can overlap
        %   whatever else is drawn there, which is exactly the "floats over
        %   the plots area" effect this replaces the old row-resize with.
        %   Built once up front rather than lazily on first use, so the
        %   first group-overflow click isn't slowed down by construction.
            fig = ancestor(parent, 'figure');

            % Scrim: an otherwise invisible panel, sized to the figure, that
            % sits directly behind the popup. Its only job is to catch the
            % next click anywhere outside the popup and close it -- the
            % standard click-away-to-dismiss behaviour for a dropdown.
            % NOTE: both this and PopupComponent are built here, i.e.
            % *before* setupMainWindow goes on to create TreeGrid and
            % PlotsTabGroup -- so creation order alone would leave them
            % sitting *behind* the tree/plots, not in front. showPopup
            % therefore explicitly uistacks both to the top on every open,
            % rather than relying on this constructor's ordering. Position
            % here is just a placeholder; showPopup re-fits it to the
            % figure's current size every time, in case the window was
            % resized meanwhile.
            this.Scrim = uipanel(fig, 'BorderType', 'none', ...
                'BackgroundColor', fig.Color, 'Visible', 'off', ...
                'Position', [1 1 fig.Position(3) fig.Position(4)], ...
                'ButtonDownFcn', @(~, ~) this.hidePopup());

            popupHtmlFile = fullfile(fileparts(mfilename('fullpath')), 'AlakazamRibbonPopup.html');
            this.PopupComponent = uihtml(fig, 'HTMLSource', popupHtmlFile, ...
                'Visible', 'off', 'Position', [1 1 200 100]);
            this.PopupComponent.HTMLEventReceivedFcn = @(~, evt) this.onPopupEvent(evt);
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
                    this.hidePopup();   % switching tabs closes any open group popup
                case 'groupExpand'
                    this.showPopup(d);
                case 'groupCollapse'
                    this.hidePopup();
            end
        end

        function onPopupEvent(this, evt)
        %ONPOPUPEVENT  Dispatch a bridge event from AlakazamRibbonPopup.html
        %   (the floating dropdown), a separate uihtml page from the main
        %   ribbon's -- see buildPopup.
            name = evt.HTMLEventName;
            d = evt.HTMLEventData;
            switch name
                case 'itemPushed'
                    this.hidePopup();          % close the dropdown, then act,
                    this.invoke(this.ItemPushedFcn, d.id);   % matching the main
                    % ribbon's own alzClosePopup-before-dispatch ordering in
                    % AlakazamRibbon.html, so a transformation firing and the
                    % popup closing never race visually.
                case 'closePopup'
                    this.hidePopup();
            end
        end

        function showPopup(this, d)
        %SHOWPOPUP  Position and reveal the floating dropdown for one
        %   overflowing group. D is the groupExpand payload from
        %   AlakazamRibbon.html: {tabId, groupIndex, left, top, width,
        %   height}, where left/top/width/height is that group's own
        %   on-page rect in CSS pixels (top-left origin), as measured by
        %   the ribbon HTML itself via getBoundingClientRect().
            tab = this.TabsData(cellfun(@(t) strcmp(t.id, char(d.tabId)), this.TabsData));
            if isempty(tab)
                return;
            end
            groups = tab{1}.groups;
            gi = double(d.groupIndex) + 1;   % JS is 0-based, MATLAB is 1-based
            if gi < 1 || gi > numel(groups)
                return;
            end
            group = groups{gi};
            items = group.items;

            % --- figure-relative position -------------------------------
            % getpixelposition(..., true) resolves the ribbon uihtml
            % component's actual on-screen rect relative to the figure,
            % correctly accounting for it being nested inside Grid inside
            % ToolbarGrid inside MainGrid -- this is the one MATLAB call
            % that understands nested uigridlayouts, so it is used instead
            % of reading Component.Position directly (which is not
            % meaningful for a grid-managed child).
            ribbonRect = getpixelposition(this.Component, true);   % [left bottom width height]
            fig = ancestor(this.Component, 'figure');

            % d.left/d.top are top-left-origin CSS pixels, measured within
            % the ribbon HTML page (which exactly fills Component, so this
            % is a 1:1 pixel match with no separate DPI/scroll correction
            % needed). Figure coordinates are bottom-left-origin, so the
            % group's bottom edge (where the dropdown should hang from) is:
            groupBottomFromPageTop = double(d.top) + double(d.height);
            anchorY = ribbonRect(2) + (ribbonRect(4) - groupBottomFromPageTop);
            anchorX = ribbonRect(1) + double(d.left);

            nCols = min(this.PopupCols, max(1, numel(items)));
            nRows = ceil(numel(items) / this.PopupCols);
            popupWidth  = max(double(d.width), nCols * this.PopupColWidthPx);
            popupHeight = this.PopupTitleBarPx + nRows * this.PopupItemRowPx + this.PopupPaddingPx;

            % Keep the popup on-screen if the group sits near the figure's
            % right/bottom edge (it opens downward from the group, so only
            % the right edge needs clamping in the common case; a group
            % near the very bottom of a very short window is not a
            % realistic layout here since the ribbon is always the top row).
            popupWidth = min(popupWidth, fig.Position(3) - 4);
            anchorX = min(anchorX, fig.Position(3) - popupWidth - 2);
            anchorX = max(anchorX, 2);

            this.PopupComponent.Data = struct('title', group.title, 'items', {items});
            this.PopupComponent.Position = [anchorX, anchorY - popupHeight, popupWidth, popupHeight];

            this.Scrim.Position = [1 1 fig.Position(3) fig.Position(4)];
            this.Scrim.Visible = 'on';
            this.PopupComponent.Visible = 'on';
            % Both were built before TreeGrid/PlotsTabGroup exist (see
            % buildPopup), so creation order alone would put them behind
            % those -- explicitly restack on every open instead. Scrim
            % first, then Popup, so Popup ends up above Scrim too.
            uistack(this.Scrim, 'top');
            uistack(this.PopupComponent, 'top');
        end

        function hidePopup(this)
        %HIDEPOPUP  Close the floating dropdown, if one is open. Safe to
        %   call unconditionally (tab changes, item pushes, and the scrim's
        %   own click-away all just call this without checking state first).
            if ~isempty(this.PopupComponent) && isvalid(this.PopupComponent)
                this.PopupComponent.Visible = 'off';
            end
            if ~isempty(this.Scrim) && isvalid(this.Scrim)
                this.Scrim.Visible = 'off';
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
                struct('title', 'Workspace', 'items', {this.workspaceItems(iconsDir)}), ...
                struct('title', 'Settings',  'items', {this.settingsItems(iconsDir)}), ...
                struct('title', 'View',      'items', {this.viewItems(iconsDir)})};

            grandAverageGroups = { ...
                struct('title', 'Group Averages', 'items', {this.grandAverageItems(iconsDir)})};

            measurementsGroups = { ...
                struct('title', 'Batch Export', 'items', {this.measurementsItems(iconsDir)})};

            tabs = { ...
                struct('id', 'home', 'title', 'Alakazam', 'groups', {homeGroups}), ...
                struct('id', 'tools', 'title', 'Tools', ...
                    'groups', {this.transformationGroups(transRoot)}), ...
                struct('id', 'grandAverage', 'title', 'Grand Average', ...
                    'groups', {grandAverageGroups}), ...
                struct('id', 'measurements', 'title', 'Measurements', ...
                    'groups', {measurementsGroups})};
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

        function items = measurementsItems(this, iconsDir)
        %MEASUREMENTSITEMS  The two workspace-wide batch exporters on the
        %   Measurements tab: "Export ERP Measures..." (time-domain Measure
        %   results, see Alakazam.onExportMeasurements) and "Export Spectral
        %   Measures..." (frequency-domain SpectralMeasure results, see
        %   Alakazam.onExportSpectral), each writing one R-compatible,
        %   long-format CSV -- the same "batch export everything I've
        %   computed" idea grandAverageItems' own Export Grand Averages
        %   implements. Not part of the auto-discovered Tools tab: like
        %   Grand Average's own actions, these are workspace-wide, not run on
        %   one selected dataset. Distinct icons (a ruler-tick table vs a
        %   spectrum), both sharing ExportGrandAverages.svg's export arrow so
        %   the batch-export buttons read as a family.
            items = {struct('id', 'exportMeasurements', 'label', 'ERP', ...
                'tooltip', ['Export every time-domain ERP Measure result (amplitude / latency / area) ' ...
                    'to one R-compatible, long-format CSV'], ...
                'icon', this.encodeSvgFile(fullfile(iconsDir, 'ExportMeasurements.svg'))), ...
                struct('id', 'exportSpectral', 'label', 'Spectral', ...
                'tooltip', ['Export every frequency-domain Spectral Measure result (power / SNR / ' ...
                    'phase-locking / coherence) to one R-compatible, long-format CSV'], ...
                'icon', this.encodeSvgFile(fullfile(iconsDir, 'ExportSpectral.svg')))};
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
                        'icon', this.encodeIcon(fullfile(transRoot, iTransForm.Folder, iTransForm.Icon)));
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

    % Record the transformation's own folder name (== the transform id /
    % EEG.Call), so the display Name can differ from the folder without
    % breaking the icon lookup or the dispatch id.
    info.Folder = TName;
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
