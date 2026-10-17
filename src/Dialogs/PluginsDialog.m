function fig = PluginsDialog(parentFig, varargin)
%PLUGINSDIALOG  Install plugins: every plugin repository on offer, and every
%   plugin installed, with Install, Upgrade, Uninstall, Show folder and
%   Manual (the plugin's manual in the web browser, installed or not).
%
%   The repositories are the account's whose names start with "Alakazam"
%   (Plugins.available), so a new one is listed as soon as it exists, and a
%   malformed one is listed too, saying what is wrong with it. A plugin
%   installed from anywhere else (a zip, another link) is listed as well.
%   Each row names the plugin (a repository with none in it yet goes by its
%   own name) and says what is installed, the latest release, and what can
%   be done: not installed, installed, an update available, or not a plugin
%   yet.
%
%   FIG = PluginsDialog(PARENTFIG, Name, Value):
%     'Repos'         the repositories, as Plugins.available returns them,
%                     or a function returning them (@(refresh) ...); the
%                     default asks GitHub, once a session unless refreshed
%     'InstallFcn'    @(link, repo) installs from LINK through the usual
%                     confirmation; REPO names the repository ('' for a link
%                     or zip asked for here, LINK then [])
%     'UninstallFcn'  @(name) removes the plugin NAME (and the ribbon button)
%     'Confirm'       @(message, title) asks before uninstalling (default:
%                     uiconfirm on this dialog); the tests pass their own
%     'Visible'       default true, for the tests
%
%   See also PLUGINS, ALAKAZAM.ONMANAGEPLUGINS, ALAKAZAM.ONINSTALLPLUGIN.
    p = inputParser();
    p.addParameter('Repos', @(refresh) Plugins.available('Refresh', refresh));
    p.addParameter('InstallFcn', [], @(f) isempty(f) || isa(f, 'function_handle'));
    p.addParameter('UninstallFcn', @Plugins.uninstall, @(f) isa(f, 'function_handle'));
    p.addParameter('UpdateFcn', [], @(f) isempty(f) || isa(f, 'function_handle'));   % older name
    p.addParameter('Confirm', [], @(f) isempty(f) || isa(f, 'function_handle'));
    p.addParameter('Visible', true, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    o = p.Results;
    if isempty(o.InstallFcn) && ~isempty(o.UpdateFcn)
        o.InstallFcn = @(link, ~) o.UpdateFcn(link);
    end

    accentColor = [0.290 0.498 0.788];   % AlakazamRibbon.html's .alz-tab-home (#4a7fc9)
    bgColor     = [0.9608 0.9608 0.9608];
    position = [360 240 980 460];
    if nargin >= 1 && ~isempty(parentFig) && isvalid(parentFig)
        parentPos = parentFig.Position;
        position(1) = parentPos(1) + (parentPos(3) - position(3)) / 2;
        position(2) = parentPos(2) + (parentPos(4) - position(4)) / 2;
    end
    fig = uifigure('Name', 'Install plugins', 'Position', fitOnScreen(position), ...
        'Color', bgColor, 'Tag', 'PluginsDialog', 'Visible', o.Visible);
    if isempty(o.Confirm)
        o.Confirm = @(message, title) uiconfirm(fig, message, title, ...
            'Options', {'Uninstall', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
            'Icon', 'warning');
    end

    outer = uigridlayout(fig, [4, 1], 'RowHeight', {40, 'fit', '1x', 46}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);
    header = uilabel(outer, 'Text', '  Install plugins', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    header.Layout.Row = 1;

    where = uilabel(outer, 'WordWrap', 'on', 'Tag', 'Where', 'Text', '');
    where.Layout.Row = 2;

    tableGrid = uigridlayout(outer, [2, 1], 'RowHeight', {'fit', '1x'}, ...
        'Padding', [16 8 16 4], 'RowSpacing', 6);
    tableGrid.Layout.Row = 3;
    emptyLabel = uilabel(tableGrid, 'Tag', 'NoPlugins', 'FontAngle', 'italic', ...
        'Text', 'No plugins are on offer or installed.');
    emptyLabel.Layout.Row = 1;
    table = uitable(tableGrid, 'Tag', 'PluginTable', 'RowName', {}, ...
        'ColumnName', {'Plugin', 'Installed', 'Latest', 'Status'}, ...
        'ColumnWidth', {190, 70, 70, 'auto'}, 'SelectionType', 'row', ...
        'Multiselect', 'off', 'SelectionChangedFcn', @(~, ~) updateButtons());
    table.Layout.Row = 2;

    buttonRow = uigridlayout(outer, [1, 9], ...
        'ColumnWidth', {90, 90, 90, 100, 80, 80, 150, '1x', 90}, 'Padding', [16 6 16 10]);
    buttonRow.Layout.Row = 4;
    installButton = uibutton(buttonRow, 'Text', 'Install', 'Tag', 'Install', ...
        'Tooltip', 'Install the plugin from its repository''s latest release', ...
        'ButtonPushedFcn', @(~, ~) onInstall());
    upgradeButton = uibutton(buttonRow, 'Text', 'Upgrade', 'Tag', 'Upgrade', ...
        'Tooltip', 'Install its latest release in place of the one installed', ...
        'ButtonPushedFcn', @(~, ~) onInstall());
    uninstallButton = uibutton(buttonRow, 'Text', 'Uninstall', 'Tag', 'Uninstall', ...
        'ButtonPushedFcn', @(~, ~) onUninstall());
    folderButton = uibutton(buttonRow, 'Text', 'Show folder', 'Tag', 'ShowFolder', ...
        'Tooltip', 'Open the plugin''s folder, to read its code', ...
        'ButtonPushedFcn', @(~, ~) onShowFolder());
    manualButton = uibutton(buttonRow, 'Text', 'Manual', 'Tag', 'Manual', ...
        'Tooltip', 'The plugin''s manual, in your web browser, installed or not', ...
        'ButtonPushedFcn', @(~, ~) onManual());
    uibutton(buttonRow, 'Text', 'Refresh', 'Tag', 'Refresh', ...
        'Tooltip', 'Ask GitHub again for the repositories and their releases', ...
        'ButtonPushedFcn', @(~, ~) fill(true));
    uibutton(buttonRow, 'Text', 'From a link or zip...', 'Tag', 'FromLink', ...
        'Tooltip', 'Install a plugin from a zip file or any other link', ...
        'ButtonPushedFcn', @(~, ~) onFromLink());
    closeButton = uibutton(buttonRow, 'Text', 'Close', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) delete(fig));
    closeButton.Layout.Column = 9;

    rows = struct([]);
    fill(false);

    function fill(refresh)
        % The busy cursor while GitHub is asked (the first time, and on
        % Refresh), which takes some seconds.
        fig.Pointer = "watch";
        drawnow;
        restorePointer = onCleanup(@() pointerBack(fig));
        [repos, problem] = listRepos(o.Repos, refresh);
        rows = pluginRows(repos, Plugins.installed());
        text = sprintf(['    Plugins come from the "Alakazam" repositories of github.com/%s, and ' ...
            'are kept in %s, outside the application, so an update of Alakazam leaves them ' ...
            'in place.'], Plugins.Account, Plugins.folder());
        if ~isempty(problem)
            text = sprintf('%s The repositories could not be listed just now (%s); the installed plugins are shown.', ...
                text, problem);
        end
        where.Text = text;
        emptyLabel.Visible = isempty(rows);
        if isempty(rows)
            table.Data = cell(0, 4);
        else
            table.Data = [{rows.Plugin}', {rows.Installed}', {rows.Latest}', {rows.Status}'];
        end
        table.Selection = [];
        updateButtons();
    end

    function k = selected()
        k = [];
        if ~isempty(table.Selection) && ~isempty(rows)
            k = table.Selection(1);
        end
    end

    function updateButtons()
        k = selected();
        canFetch = ~isempty(k) && ~isempty(o.InstallFcn) && ~isempty(rows(k).Link);
        installButton.Enable = canFetch && isempty(rows(k).Names);
        upgradeButton.Enable = canFetch && ~isempty(rows(k).Names);
        uninstallButton.Enable = ~isempty(k) && ~isempty(rows(k).Names);
        folderButton.Enable = ~isempty(k) && ~isempty(rows(k).Folders);
        manualButton.Enable = ~isempty(k) && ~isempty(manualOf(rows(k)));
    end

    function onManual()
        k = selected();
        if ~isempty(k)
            openInBrowser(manualOf(rows(k)));
        end
    end

    function onInstall()
        k = selected();
        if isempty(k)
            return;
        end
        o.InstallFcn(rows(k).Link, rows(k).RepoName);
        if isvalid(fig)
            fill(false);
        end
    end

    function onFromLink()
        if isempty(o.InstallFcn)
            return;
        end
        o.InstallFcn([], '');
        if isvalid(fig)
            fill(false);
        end
    end

    function onUninstall()
        k = selected();
        if isempty(k)
            return;
        end
        names = rows(k).Names;
        answer = o.Confirm(sprintf(['Uninstall %s? Its folder is deleted. Nodes made with it ' ...
            'stay in the tree, but cannot be recalculated or replayed until it is ' ...
            'installed again.'], strjoin(names, ', ')), 'Uninstall a plugin');
        if ~strcmp(answer, 'Uninstall')
            return;
        end
        try
            for n = names
                o.UninstallFcn(n{1});
            end
        catch ME
            uialert(fig, ME.message, 'Could not uninstall', 'Icon', 'warning');
        end
        if isvalid(fig)
            fill(false);
        end
    end

    function onShowFolder()
        k = selected();
        if isempty(k) || isempty(rows(k).Folders)
            return;
        end
        folder = rows(k).Folders{1};
        if ispc
            winopen(folder);
        elseif ismac
            system(sprintf('open "%s"', folder));
        else
            system(sprintf('xdg-open "%s"', folder));
        end
    end
end

% ----------------------------------------------------------------------- %
function url = manualOf(row)
%MANUALOF  Where a row's plugin keeps its manual: what the installed
%   plugin's own manifest or install link says (manualAddress), else the
%   GitHub Pages of the repository on offer, so a plugin's manual can be
%   read before it is installed. '' when neither says.
    url = '';
    if ~isempty(row.Names)
        url = manualAddress(row.Names{1});
    end
    if isempty(url)
        url = Plugins.pagesAddress(row.Link);
    end
end

function pointerBack(fig)
%POINTERBACK  The usual cursor again, unless the window was closed meanwhile.
    if isvalid(fig)
        fig.Pointer = "arrow";
    end
end

function [repos, problem] = listRepos(source, refresh)
%LISTREPOS  The repositories on offer, and '' or why they could not be had
%   (no network, GitHub's hourly limit): the dialog then lists the
%   installed plugins alone.
    problem = '';
    try
        if isa(source, 'function_handle')
            repos = source(refresh);
        else
            repos = source;
        end
    catch err
        repos = struct('Repo', {}, 'Link', {}, 'Description', {}, 'Release', {}, ...
            'Version', {}, 'Asset', {}, 'Tools', {}, 'Problem', {});
        problem = err.message;
    end
end

function rows = pluginRows(repos, installed)
%PLUGINROWS  One row per repository, with the plugins of it installed, and
%   one per installed plugin no listed repository holds.
    rows = struct('Repo', {}, 'RepoName', {}, 'Plugin', {}, 'Installed', {}, 'Latest', {}, ...
        'Status', {}, 'Link', {}, 'Names', {}, 'Folders', {});
    claimed = false(1, numel(installed));
    for k = 1:numel(repos)
        r = repos(k);
        mine = false(1, numel(installed));
        for j = 1:numel(installed)
            mine(j) = any(strcmp(r.Tools, installed(j).Name)) ...
                || strcmpi(installed(j).Link, r.Link);
        end
        claimed = claimed | mine;
        names = {installed(mine).Name};
        version = strjoin(unique({installed(mine).Version}, 'stable'), ', ');
        latest = r.Version;
        if isempty(latest)
            latest = '-';
        end
        plugin = strjoin(r.Tools, ', ');
        if isempty(plugin)
            plugin = r.Repo;    % no plugin in it yet: the repository is its only name
        end
        if isempty(names)
            status = 'Not installed';
            if ~isempty(r.Problem)
                status = ['Not a plugin yet: ' r.Problem];
            elseif isempty(r.Release)
                status = 'Not installed (no release yet: installs its newest source)';
            end
        elseif ~isempty(r.Version) && any(cellfun(@(v) versionBefore(v, r.Version), {installed(mine).Version}))
            status = sprintf('Update available: %s', r.Version);
        else
            status = 'Installed';
        end
        rows(end + 1) = struct('Repo', r.Repo, 'RepoName', r.Repo, 'Plugin', plugin, ...
            'Installed', version, 'Latest', latest, 'Status', status, 'Link', r.Link, ...
            'Names', {names}, 'Folders', {{installed(mine).Folder}}); %#ok<AGROW>
    end
    for j = find(~claimed)
        from = installed(j).Source;
        if isempty(from)
            from = '(installed from elsewhere)';
        end
        rows(end + 1) = struct('Repo', from, 'RepoName', '', 'Plugin', installed(j).Name, ...
            'Installed', installed(j).Version, 'Latest', '-', 'Status', 'Installed', ...
            'Link', installed(j).Link, 'Names', {{installed(j).Name}}, ...
            'Folders', {{installed(j).Folder}}); %#ok<AGROW>
    end
end

function tf = versionBefore(a, b)
%VERSIONBEFORE  Is version A older than B, part by number ("0.9.1" before
%   "0.10.0")? An unreadable version is never older.
    pa = str2double(strsplit(regexprep(char(a), '^[vV]', ''), '.'));
    pb = str2double(strsplit(regexprep(char(b), '^[vV]', ''), '.'));
    tf = false;
    if any(isnan(pa)) || any(isnan(pb))
        return;
    end
    n = max(numel(pa), numel(pb));
    pa(end + 1:n) = 0;
    pb(end + 1:n) = 0;
    d = find(pa ~= pb, 1);
    tf = ~isempty(d) && pa(d) < pb(d);
end
