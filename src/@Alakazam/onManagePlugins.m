function onManagePlugins(this)
%ONMANAGEPLUGINS  Install plugins: the plugin repositories on offer and the
%   plugins installed, with Install, Upgrade and Uninstall (see
%   PluginsDialog). Installing and upgrading go through the same
%   confirmation as any install (onInstallPlugin), shown in the Install
%   plugins window itself: in the main window, behind it, the question would
%   be hidden and the application would seem stuck. Uninstalling takes the
%   plugin's button off the ribbon at once.
    dialog = [];
    dialog = PluginsDialog(this.MainFigure, ...
        'UninstallFcn', @(name) uninstallPlugin(this, name), ...
        'InstallFcn', @install);

    function install(link, repo)
        % Nested, so DIALOG is the window made above, not the [] an
        % anonymous function would have captured before it existed.
        this.onInstallPlugin(link, repo, dialog);
    end
end

function uninstallPlugin(this, name)
    Plugins.uninstall(name);
    this.refreshRibbon();
end
