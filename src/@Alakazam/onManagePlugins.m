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
%   takes some seconds, and without it the press seemed to do nothing.
    dialog = [];
    showBusy(this, true);
    try
        dialog = PluginsDialog(this.MainFigure, ...
            'UninstallFcn', @(name) uninstallPlugin(this, name), ...
            'InstallFcn', @install);
    catch err
        showBusy(this, false);
        rethrow(err);
    end
    showBusy(this, false);

    function install(link, repo)
        % Nested, so DIALOG is the window made above, not the [] an
        % anonymous function would have captured before it existed.
        this.onInstallPlugin(link, repo, dialog);
    end
end

function showBusy(this, busy)
%SHOWBUSY  The busy cursor over the main window and its ribbon (BUSY true),
%   or the usual ones again. Not an onCleanup in onManagePlugins: its
%   nested INSTALL keeps that function's workspace, and so a cleanup object
%   in it, alive as long as the Install plugins window is open.
    pointers = ["arrow", "watch"];
    if ~isempty(this.MainFigure) && isvalid(this.MainFigure)
        this.MainFigure.Pointer = pointers(busy + 1);
    end
    if isprop(this, 'Ribbon') && ~isempty(this.Ribbon)
        this.Ribbon.setBusy(busy);
    end
    drawnow;   % shown now, before the wait, not after it
end

function uninstallPlugin(this, name)
    Plugins.uninstall(name);
    this.refreshRibbon();
end
