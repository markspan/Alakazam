function dlg = busyDialog(fig, title, message)
%BUSYDIALOG  Put a "please wait" indicator on FIG, with TITLE, MESSAGE and a
%   sliding bar: the window's own layer (BusyOverlay) where it has one ready,
%   which shows the wait cursor over the whole window, and MATLAB's
%   uiprogressdlg otherwise (an undocked plot's window, the Install plugins
%   window, or the first moments after startup). Either answers to Title,
%   Message, Value, Indeterminate and ShowPercentage, and close(DLG) takes it
%   down, so the caller need not know which it got:
%
%       dlg = busyDialog(this.MainFigure, "Alakazam", "Exporting...");
%       dlg.Value = 0.5;
%       close(dlg);
%
%   See also BUSYOVERLAY, BEGINBUSY, BUSYGATE.
    dlg = BusyOverlay.of(fig);
    if isempty(dlg)
        dlg = uiprogressdlg(fig, "Title", title, "Message", message, "Indeterminate", "on");
    else
        dlg.show(title, message);
    end
end
