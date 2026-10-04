function fig = PluginsDialog(parentFig, varargin)
%PLUGINSDIALOG  The installed plugins: what each is, where it came from and
%   when, with Update, Uninstall and Show folder.
%
%   FIG = PluginsDialog(PARENTFIG, 'UninstallFcn', @(name) ..., 'UpdateFcn',
%   @(source) ...). UNINSTALLFCN removes the plugin NAME (and refreshes the
%   ribbon); UPDATEFCN installs again from SOURCE, through the usual
%   confirmation. 'Confirm' (default: uiconfirm on this dialog) asks before
%   uninstalling and returns the option chosen; the tests pass their own.
%   'Visible' (default true) is for the tests too.
%
%   The list is read from Plugins.installed each time it changes, not kept,
%   so it always shows what is on disk.
%
%   See also PLUGINS, ALAKAZAM.ONMANAGEPLUGINS, PLUGINSOURCEDIALOG.
    p = inputParser();
    p.addParameter('UninstallFcn', @Plugins.uninstall, @(f) isa(f, 'function_handle'));
    p.addParameter('UpdateFcn', [], @(f) isempty(f) || isa(f, 'function_handle'));
    p.addParameter('Confirm', [], @(f) isempty(f) || isa(f, 'function_handle'));
    p.addParameter('Visible', true, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    o = p.Results;

    accentColor = [0.290 0.498 0.788];   % AlakazamRibbon.html's .alz-tab-home (#4a7fc9)
    bgColor     = [0.9608 0.9608 0.9608];
    position = [400 280 780 420];
    if nargin >= 1 && ~isempty(parentFig) && isvalid(parentFig)
        parentPos = parentFig.Position;
        position(1) = parentPos(1) + (parentPos(3) - position(3)) / 2;
        position(2) = parentPos(2) + (parentPos(4) - position(4)) / 2;
    end
    fig = uifigure('Name', 'Installed plugins', 'Position', fitOnScreen(position), ...
        'Color', bgColor, 'Tag', 'PluginsDialog', 'Visible', o.Visible);
    if isempty(o.Confirm)
        o.Confirm = @(message, title) uiconfirm(fig, message, title, ...
            'Options', {'Uninstall', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
            'Icon', 'warning');
    end

    outer = uigridlayout(fig, [4, 1], 'RowHeight', {40, 'fit', '1x', 46}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);
    header = uilabel(outer, 'Text', '  Installed plugins', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    header.Layout.Row = 1;

    where = uilabel(outer, 'WordWrap', 'on', 'Tag', 'Where', 'Text', sprintf( ...
        ['    Plugins are kept in %s, outside the application, so an update of ' ...
         'Alakazam leaves them in place.'], Plugins.folder()));
    where.Layout.Row = 2;

    tableGrid = uigridlayout(outer, [2, 1], 'RowHeight', {'fit', '1x'}, ...
        'Padding', [16 8 16 4], 'RowSpacing', 6);
    tableGrid.Layout.Row = 3;
    emptyLabel = uilabel(tableGrid, 'Tag', 'NoPlugins', 'FontAngle', 'italic', ...
        'Text', 'No plugins are installed. Install one with Install on the Alakazam tab.');
    emptyLabel.Layout.Row = 1;
    table = uitable(tableGrid, 'Tag', 'PluginTable', 'RowName', {}, ...
        'ColumnName', {'Plugin', 'Name', 'Version', 'Installed', 'From'}, ...
        'ColumnWidth', {120, 150, 70, 120, 'auto'}, 'SelectionType', 'row', ...
        'Multiselect', 'off', 'SelectionChangedFcn', @(~, ~) updateButtons());
    table.Layout.Row = 2;

    buttonRow = uigridlayout(outer, [1, 5], 'ColumnWidth', {100, 100, 110, '1x', 90}, ...
        'Padding', [16 6 16 10]);
    buttonRow.Layout.Row = 4;
    updateButton = uibutton(buttonRow, 'Text', 'Update', 'Tag', 'Update', ...
        'Tooltip', 'Install again from where it came from', ...
        'ButtonPushedFcn', @(~, ~) onUpdate());
    uninstallButton = uibutton(buttonRow, 'Text', 'Uninstall', 'Tag', 'Uninstall', ...
        'ButtonPushedFcn', @(~, ~) onUninstall());
    folderButton = uibutton(buttonRow, 'Text', 'Show folder', 'Tag', 'ShowFolder', ...
        'Tooltip', 'Open the plugin''s folder, to read its code', ...
        'ButtonPushedFcn', @(~, ~) onShowFolder());
    closeButton = uibutton(buttonRow, 'Text', 'Close', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) delete(fig));
    closeButton.Layout.Column = 5;

    plugins = Plugins.installed();
    fill();

    function fill()
        plugins = Plugins.installed();
        emptyLabel.Visible = isempty(plugins);
        if isempty(plugins)
            table.Data = cell(0, 5);
        else
            table.Data = [{plugins.Name}', {plugins.Label}', {plugins.Version}', ...
                {plugins.Installed}', {plugins.Source}'];
        end
        table.Selection = [];
        updateButtons();
    end

    function k = selected()
        k = [];
        if ~isempty(table.Selection) && ~isempty(plugins)
            k = table.Selection(1);
        end
    end

    function updateButtons()
        k = selected();
        uninstallButton.Enable = ~isempty(k);
        folderButton.Enable = ~isempty(k);
        updateButton.Enable = ~isempty(k) && ~isempty(o.UpdateFcn) && ~isempty(plugins(k).Source);
    end

    function onUninstall()
        k = selected();
        if isempty(k)
            return;
        end
        name = plugins(k).Name;
        answer = o.Confirm(sprintf(['Uninstall %s? Its folder is deleted. Nodes made with it ' ...
            'stay in the tree, but cannot be recalculated or replayed until it is ' ...
            'installed again.'], name), 'Uninstall a plugin');
        if ~strcmp(answer, 'Uninstall')
            return;
        end
        try
            o.UninstallFcn(name);
        catch ME
            uialert(fig, ME.message, 'Could not uninstall', 'Icon', 'warning');
        end
        if isvalid(fig)
            fill();
        end
    end

    function onUpdate()
        k = selected();
        if isempty(k)
            return;
        end
        o.UpdateFcn(plugins(k).Source);
        if isvalid(fig)
            fill();
        end
    end

    function onShowFolder()
        k = selected();
        if isempty(k)
            return;
        end
        folder = plugins(k).Folder;
        if ispc
            winopen(folder);
        elseif ismac
            system(sprintf('open "%s"', folder));
        else
            system(sprintf('xdg-open "%s"', folder));
        end
    end
end
