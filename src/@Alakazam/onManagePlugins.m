function onManagePlugins(this)
%ONMANAGEPLUGINS  The installed plugins, where each came from, and Update and
%   Uninstall (see PluginsDialog). Uninstalling takes the plugin's button
%   off the ribbon at once; Update installs again from where it came from,
%   through the same confirmation as a first install.
    PluginsDialog(this.MainFigure, ...
        'UninstallFcn', @(name) uninstallPlugin(this, name), ...
        'UpdateFcn', @(source) this.onInstallPlugin(source));
end

function uninstallPlugin(this, name)
    Plugins.uninstall(name);
    this.refreshRibbon();
end
