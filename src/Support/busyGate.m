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
%   while the app is in fact waiting for the user to fill a form in.
%
%   HOW IT IS DRIVEN. TransTools.InitGuard suspends the indicator whenever a
%   transformation is entered interactively, i.e. exactly when a dialog is
%   about to open; TransformSettings.set resumes it, which every options
%   dialog reaches once the user has accepted its settings and real work is
%   starting. Both are no-ops when nothing is armed, so transformations
%   stay callable headlessly and from tests.
%
%   PROGRESS. A transformation whose computation is a long loop reports how
%   far it has got, through TransTools.BusyGate('progress', fraction), and
%   the indicator becomes a bar filled to that fraction, with the
%   percentage and an estimate of the time left under its message. Zero
%   starts the clock (the estimate is the time taken so far, scaled up to
%   the whole), and one turns the bar back into the spinner, since the app
%   still has work of its own to do before the result is shown. Redraws are
%   at most ten a second, so a loop can report on every pass without being
%   slowed by it, and the estimate is left out until a second of work has
%   given it something to go on. This replaces the separate classic-figure
%   progress bar (TransTools.progressbar) the transformations used to open:
%   the progress is shown on the app's own window, in the dialog that is
%   already up.
%
%   ACTIONS
%     busyGate('open', fig, message)  arm and show; returns an onCleanup
%     busyGate('suspend')             take it down, remember it was up
%     busyGate('resume')              put it back if it was suspended
%     busyGate('message', text)       relabel (see beginBusy's updateFcn)
%     busyGate('progress', fraction)  fill to FRACTION (0 to 1), see above
%     busyGate('close')               take it down and disarm
%     busyGate('isArmed')             true while a gate is armed
%     busyGate('isShowing')           true while its dialog is on screen
%     busyGate('dialog')              that dialog, or [] (for tests)
%
%   See also BEGINBUSY, TRANSTOOLS.BUSYGATE, TRANSTOOLS.INITGUARD,
%   TRANSFORMSETTINGS.
    persistent state
    if isempty(state)
        state = emptyState();
    end
    varargout = {};

    switch lower(action)
        case 'open'
            state = emptyState();
            state.fig = varargin{1};
            state.message = varargin{2};
            state.armed = true;
            state.dlg = showDialog(state.fig, state.message);
            varargout{1} = onCleanup(@() busyGate('close'));

        case 'suspend'
            if state.armed && ~state.suspended
                closeDialog(state.dlg);
                state.dlg = [];
                state.suspended = true;
                % 'resume' puts back a spinner, so a later progress report
                % has to start its bar, and its clock, afresh.
                state = clearProgress(state);
            end

        case 'resume'
            if state.armed && state.suspended && isvalid(state.fig)
                state.dlg = showDialog(state.fig, state.message);
                state.suspended = false;
            end

        case 'message'
            state.message = varargin{1};
            if isShowing(state)
                state.dlg.Message = state.message;
                drawnow;
            end

        case 'progress'
            state = showProgress(state, varargin{1});

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
            varargout{1} = isShowing(state);

        case 'dialog'
            % The ProgressDialog itself, for the same reason as isShowing:
            % a test can read its Value and Message nowhere else.
            varargout{1} = [];
            if isShowing(state)
                varargout{1} = state.dlg;
            end

        otherwise
            error('Alakazam:busyGate', 'Unknown busyGate action "%s".', action);
    end
end

function s = emptyState()
%EMPTYSTATE  A disarmed gate, with no progress being reported.
    s = struct('fig', [], 'message', '', 'dlg', [], 'suspended', false, 'armed', false);
    s = clearProgress(s);
end

function state = clearProgress(state)
%CLEARPROGRESS  Forget a progress report. While one runs, PROGRESSSTARTED
%   and PROGRESSDRAWN are the tic values of its first report and of the
%   last redraw, and PROGRESSFROM the fraction its first report gave.
    state.progressStarted = [];
    state.progressDrawn = [];
    state.progressFrom = 0;
end

function tf = isShowing(state)
    tf = state.armed && ~state.suspended && ~isempty(state.dlg) && isvalid(state.dlg);
end

function state = showProgress(state, fraction)
%SHOWPROGRESS  Fill the dialog to FRACTION with the time left, start the
%   clock at 0, or turn it back into the spinner at 1 (see PROGRESS in this
%   file's header). Nothing happens while no dialog is on screen, so a
%   transformation can report progress whether or not the app is there.
    MIN_REDRAW_INTERVAL = 0.1;   % seconds; a loop may report on every pass
    MIN_ESTIMATE_TIME = 1;       % seconds of work before the time left is shown
    if ~isShowing(state)
        return;
    end
    dlg = state.dlg;
    fraction = min(max(double(fraction), 0), 1);

    if fraction >= 1
        dlg.Indeterminate = "on";
        dlg.ShowPercentage = "off";
        dlg.Message = state.message;
        state = clearProgress(state);
        drawnow;
        return;
    end

    if fraction == 0 || isempty(state.progressStarted)
        state.progressStarted = tic;
        state.progressFrom = fraction;
        dlg.Indeterminate = "off";
        dlg.ShowPercentage = "on";
        dlg.Message = state.message;
    elseif toc(state.progressDrawn) < MIN_REDRAW_INTERVAL
        return;
    else
        % The time left, at the rate the work has gone since the first
        % report: all of it when that report was 0, as it normally is.
        elapsed = toc(state.progressStarted);
        done = fraction - state.progressFrom;
        if done > 0 && elapsed >= MIN_ESTIMATE_TIME
            dlg.Message = [string(state.message); timeLeftText(elapsed * (1 - fraction) / done)];
        end
    end
    dlg.Value = fraction;
    state.progressDrawn = tic;
    drawnow;
end

function text = timeLeftText(seconds)
%TIMELEFTTEXT  "About 42 s left", "About 3 min 5 s left" or "About 1 h 20 min left".
    seconds = round(seconds);
    if seconds < 60
        text = sprintf("About %d s left", seconds);
    elseif seconds < 3600
        text = sprintf("About %d min %d s left", floor(seconds / 60), mod(seconds, 60));
    else
        text = sprintf("About %d h %d min left", floor(seconds / 3600), floor(mod(seconds, 3600) / 60));
    end
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
