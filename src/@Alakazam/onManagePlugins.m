function onManagePlugins(this)
%ONMANAGEPLUGINS  Install plugins: the plugin repositories on offer and the
%   plugins installed, with Install, Upgrade and Uninstall (see
%   PluginsDialog). Installing and upgrading go through the same
%   confirmation as any install (onInstallPlugin); uninstalling takes the
%   plugin's button off the ribbon at once.
    PluginsDialog(this.MainFigure, ...
        'UninstallFcn', @(name) uninstallPlugin(this, name), ...
        'InstallFcn', @(link, repo) this.onInstallPlugin(link, repo));
end

function uninstallPlugin(this, name)
    Plugins.uninstall(name);
    this.refreshRibbon();
end
