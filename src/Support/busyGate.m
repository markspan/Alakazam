function varargout = busyGate(action, varargin)
%BUSYGATE  Owns the one busy indicator beginBusy puts up, so that code
%   running underneath it can take it down again while a dialog needs the
%   screen, and put it back afterwards.
%
%   WHY THIS EXISTS. A transformation invoked as feval(id, EEG) runs its
%   OWN options dialog inside that call (TransTools.InitGuard returns
%   interactive = true for a one-argument call), so Alakazam.onTransformation
%   has already raised "Running <id>..." by the time the dialog appears. On
%   a local MATLAB the dialog is a separate window and the two coexist, so
%   this went unnoticed. In MATLAB Online the modal uiprogressdlg covers the
%   figure, and the settings underneath cannot be reached at all until it is
%   closed by hand. The indicator was always wrong there: it says "working"
%   while the app is in fact waiting for the analyst to fill a form in.
%
%   HOW IT IS DRIVEN. TransTools.InitGuard suspends the indicator whenever a
%   transformation is entered interactively, i.e. exactly when a dialog is
%   about to open; TransformSettings.set resumes it, which every options
%   dialog reaches once the user has accepted its settings and real work is
%   starting. Both are no-ops when nothing is armed, so transformations
%   stay callable headlessly and from tests.
%
%   ACTIONS
%     busyGate('open', fig, message)  arm and show; returns an onCleanup
%     busyGate('suspend')             take it down, remember it was up
%     busyGate('resume')              put it back if it was suspended
%     busyGate('message', text)       relabel (see beginBusy's updateFcn)
%     busyGate('close')               take it down and disarm
%     busyGate('isArmed')             true while a gate is armed
%
%   See also BEGINBUSY, TRANSTOOLS.INITGUARD, TRANSFORMSETTINGS.
    persistent state
    if isempty(state)
        state = emptyState();
    end
    varargout = {};

    switch lower(action)
        case 'open'
            state = struct('fig', varargin{1}, 'message', varargin{2}, ...
                'dlg', [], 'suspended', false, 'armed', true);
            state.dlg = showDialog(state.fig, state.message);
            varargout{1} = onCleanup(@() busyGate('close'));

        case 'suspend'
            if state.armed && ~state.suspended
                closeDialog(state.dlg);
                state.dlg = [];
                state.suspended = true;
            end

        case 'resume'
            if state.armed && state.suspended && isvalid(state.fig)
                state.dlg = showDialog(state.fig, state.message);
                state.suspended = false;
            end

        case 'message'
            state.message = varargin{1};
            if state.armed && ~state.suspended && ~isempty(state.dlg) && isvalid(state.dlg)
                state.dlg.Message = state.message;
                drawnow;
            end

        case 'close'
            closeDialog(state.dlg);
            state = emptyState();

        case 'isarmed'
            varargout{1} = state.armed;

        case 'isshowing'
            % Whether a dialog is actually on screen right now, as opposed
            % to armed but suspended. A ProgressDialog is not part of the
            % figure's HG tree and so cannot be found with findall, which
            % leaves no way to check this from outside; exposing it here
            % is what makes the suspend/resume behaviour testable.
            varargout{1} = state.armed && ~state.suspended ...
                && ~isempty(state.dlg) && isvalid(state.dlg);

        otherwise
            error('Alakazam:busyGate', 'Unknown busyGate action "%s".', action);
    end
end

function s = emptyState()
    s = struct('fig', [], 'message', '', 'dlg', [], 'suspended', false, 'armed', false);
end

function dlg = showDialog(fig, message)
    dlg = uiprogressdlg(fig, "Title", "Alakazam", "Message", message, "Indeterminate", "on");
end

function closeDialog(dlg)
%CLOSEDIALOG  Guarded: an error path may already have closed the dialog (or
%   deleted the figure under it) before a later suspend/close reaches it,
%   and a stale handle must not turn that error into a second, unrelated
%   one about a deleted object.
    if ~isempty(dlg) && isvalid(dlg)
        close(dlg);
    end
end
