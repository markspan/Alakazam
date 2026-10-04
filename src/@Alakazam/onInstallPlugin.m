function onInstallPlugin(this, source)
%ONINSTALLPLUGIN  Install a plugin from a zip file or a link (see Plugins).
%   onInstallPlugin(this) asks where from (PluginSourceDialog);
%   onInstallPlugin(this, SOURCE) takes SOURCE as given, as Update in the
%   list of installed plugins does.
%
%   THREE THINGS THE USER SEES, IN ORDER: where it comes from, what was found
%   in it (Plugins.describe: each plugin, what it replaces, what it needs and
%   what was refused, with the warning that a plugin is code that runs with
%   the user's rights), and the result. Nothing is installed before the
%   second step has been answered with Install, and Cancel is the default
%   there, so a stray Enter installs nothing.
    if nargin < 2 || isempty(source)
        source = PluginSourceDialog(this.MainFigure);
        if isempty(source)
            return;   % cancelled
        end
    end
    source = char(source);

    progress = uiprogressdlg(this.MainFigure, 'Title', 'Install a plugin', ...
        'Message', sprintf('Fetching and checking %s...', source), 'Indeterminate', 'on');
    try
        candidate = Plugins.prepare(source);
    catch ME
        close(progress);
        uialert(this.MainFigure, ME.message, 'Could not install the plugin', 'Icon', 'warning');
        return;
    end
    close(progress);

    summary = Plugins.describe(candidate);
    if ~any(arrayfun(@(p) isempty(p.Problems), candidate.Plugins))
        Plugins.discard(candidate);
        uialert(this.MainFigure, summary, 'Nothing to install', 'Icon', 'warning');
        return;
    end
    choice = uiconfirm(this.MainFigure, summary, 'Install a plugin', ...
        'Options', {'Install', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
        'Icon', 'warning');
    if ~strcmp(choice, 'Install')
        Plugins.discard(candidate);
        return;
    end

    try
        names = Plugins.install(candidate);
    catch ME
        uialert(this.MainFigure, ME.message, 'Could not install the plugin', 'Icon', 'error');
        return;
    end
    this.refreshRibbon();
    if isscalar(names)
        message = sprintf('%s is installed; its button is on the Tools tab.', names{1});
    else
        message = sprintf('%s are installed; their buttons are on the Tools tab.', ...
            strjoin(names, ', '));
    end
    uialert(this.MainFigure, message, 'Plugin installed', 'Icon', 'success');
end
