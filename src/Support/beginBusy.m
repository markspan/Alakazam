function [restoreFcn, updateFcn] = beginBusy(fig, message)
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
%   The optional second output UPDATEFCN(newMessage) re-labels that same
%   indicator part-way through, for an operation made of phases whose
%   durations are wildly different and whose slowest phase is not the one
%   the opening message names. Report generation is the case this exists
%   for: gathering the data takes a moment, but rendering the .qmd shells
%   out to quarto and R, which on a first run installs R packages and can
%   sit there for a minute or more. Left saying "Exporting..." throughout,
%   that reads as a hang rather than as progress.
%
%       [restoreBusy, setBusy] = beginBusy(this.MainFigure, "Exporting...");
%       setBusy("Rendering the report...");
%
%   UPDATEFCN calls drawnow itself: the phase it announces is invariably
%   about to block, and without a repaint first the new message would only
%   appear once that blocking call had already finished, which is exactly
%   too late to be of use. It is a no-op on the watch-cursor fallback
%   below, so callers never need to check which one they got.
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
        updateFcn  = @(newMessage) setMessage(dlg, newMessage);
    else
        fig.Pointer = "watch";
        restoreFcn = onCleanup(@() set(fig, "Pointer", "arrow"));
        updateFcn  = @(~) [];
    end
end

function setMessage(dlg, newMessage)
%SETMESSAGE  Re-label a live progress dialog. Guarded on isvalid: the
%   caller holds the closing onCleanup, so an error path can perfectly
%   well have already closed DLG by the time a later phase tries to
%   announce itself, and a stale update must not turn a real error into a
%   second, unrelated one about a deleted handle.
    if isvalid(dlg)
        dlg.Message = newMessage;
        drawnow;
    end
end
