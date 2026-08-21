function restoreFcn = beginBusy(fig, message)
%BEGINBUSY  Show a modal "please wait" indicator on FIG (a uifigure) with
%   an indeterminate spinner and MESSAGE, replacing this app's previous
%   bare watch-cursor convention (fig.Pointer = "watch") everywhere it was
%   used: uiprogressdlg is the uifigure-native equivalent of a busy
%   indicator (an animated spinner overlaid directly on the app's own
%   window, not a separate dialog), and -- unlike a cursor, which is
%   purely visual -- it is modal, so it also blocks interaction with the
%   rest of the app while a blocking operation (export, transformation,
%   cache clear, ...) is running, instead of just looking busy while
%   still accepting clicks.
%
%   Returns an onCleanup object that closes the dialog again -- assign it
%   to a variable at the call site (the same "restoreX = onCleanup(...)"
%   idiom the watch-cursor pattern already used), so it closes reliably
%   whichever way the calling function returns, success or error:
%
%       restoreBusy = beginBusy(this.MainFigure, "Exporting measurements...");
%
%   uiprogressdlg requires FIG to already be visible (confirmed: throws
%   "Figure handle 'Visible' value must be 'on'" otherwise) -- true for
%   every user-triggered action, but NOT during Alakazam's own startup
%   (Alakazam.m builds MainFigure with Visible "off" and only flips it on
%   AFTER WorkSpace.open has already loaded the default workspace's raw
%   files, so a loader calling this while it is still hidden would
%   otherwise crash app startup outright). Falls back to the old bare
%   watch-cursor in that case, so this is always safe to call regardless
%   of whether the window is showing yet.
    if strcmp(fig.Visible, "on")
        dlg = uiprogressdlg(fig, "Title", "Alakazam", "Message", message, "Indeterminate", "on");
        restoreFcn = onCleanup(@() close(dlg));
    else
        fig.Pointer = "watch";
        restoreFcn = onCleanup(@() set(fig, "Pointer", "arrow"));
    end
end
