function onInstallPlugin(this, source, repo, host)
%ONINSTALLPLUGIN  Install a plugin from a zip file or a link (see Plugins).
%   onInstallPlugin(this) asks where from (PluginSourceDialog);
%   onInstallPlugin(this, SOURCE) takes SOURCE as given, as Install and
%   Upgrade in the plugin list do; onInstallPlugin(this, SOURCE, REPO) says,
%   when the repository REPO turns out to hold no plugin, so in the warmest
%   terms (Plugins.notAPluginMessage), since it is listed whatever it holds.
%   onInstallPlugin(this, SOURCE, REPO, HOST) shows its progress, questions
%   and alerts in the window HOST (the Install plugins window, which Install
%   was pressed in) rather than in the main window, which is behind it there
%   and would hide them, so the application would seem stuck.
%
%   THREE THINGS THE USER SEES, IN ORDER: where it comes from, what was found
%   in it (Plugins.describe: each plugin, what it replaces, what it needs and
%   what was refused, with the warning that a plugin is code that runs with
%   the user's rights), and the result. Nothing is installed before the
%   second step has been answered with Install, and Cancel is the default
%   there, so a stray Enter installs nothing.
    if nargin < 3
        repo = '';
    end
    if nargin < 4 || isempty(host) || ~isvalid(host)
        host = this.MainFigure;
    end
    if nargin < 2 || isempty(source)
        source = PluginSourceDialog(host);
        if isempty(source)
            return;   % cancelled
        end
    end
    source = char(source);

    progress = busyDialog(host, 'Install a plugin', sprintf('Fetching and checking %s...', source));
    try
        candidate = Plugins.prepare(source);
    catch ME
        close(progress);
        if ~isempty(repo) && strcmp(ME.identifier, 'Alakazam:Plugins:noPlugin')
            uialert(host, Plugins.notAPluginMessage(repo, ...
                'I looked everywhere inside it and could not find a single plugin folder'), ...
                'Not quite a plugin yet', 'Icon', 'info');
            return;
        end
        uialert(host, ME.message, 'Could not install the plugin', 'Icon', 'warning');
        return;
    end
    close(progress);

    summary = Plugins.describe(candidate);
    if ~any(arrayfun(@(p) isempty(p.Problems), candidate.Plugins))
        Plugins.discard(candidate);
        uialert(host, summary, 'Nothing to install', 'Icon', 'warning');
        return;
    end
    choice = uiconfirm(host, summary, 'Install a plugin', ...
        'Options', {'Install', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
        'Icon', 'warning');
    if ~strcmp(choice, 'Install')
        Plugins.discard(candidate);
        return;
    end

    try
        names = Plugins.install(candidate);
    catch ME
        uialert(host, ME.message, 'Could not install the plugin', 'Icon', 'error');
        return;
    end
    this.refreshRibbon();
    if isscalar(names)
        message = sprintf('%s is installed; its button is on the Tools tab.', names{1});
    else
        message = sprintf('%s are installed; their buttons are on the Tools tab.', ...
            strjoin(names, ', '));
    end
    uialert(host, message, 'Plugin installed', 'Icon', 'success');
end
