function onManagePlugins(this)
%ONMANAGEPLUGINS  Install plugins: the plugin repositories on offer and the
%   plugins installed, with Install, Upgrade and Uninstall (see
%   PluginsDialog). Installing and upgrading go through the same
%   confirmation as any install (onInstallPlugin), shown in the Install
%   plugins window itself: in the main window, behind it, the question would
%   be hidden and the application would seem stuck. Uninstalling takes the
%   plugin's button off the ribbon at once.
%
%   The busy cursor shows from the press until the window is there: the
%   first opening asks GitHub for the repositories and their releases, which
%   takes some seconds, and without it the press seemed to do nothing. It is
%   not an onCleanup here: the nested INSTALL keeps this function's
%   workspace, and so a cleanup object in it, alive as long as the Install
%   plugins window is open.
    dialog = [];
    busyCursor(this.MainFigure, true);
    try
        dialog = PluginsDialog(this.MainFigure, ...
            'UninstallFcn', @(name) uninstallPlugin(this, name), ...
            'InstallFcn', @install);
    catch err
        busyCursor(this.MainFigure, false);
        rethrow(err);
    end
    busyCursor(this.MainFigure, false);

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
