function ok = confirmAction(fig, message, title, affirmative, negative, varargin)
%CONFIRMACTION  Ask the analyst to confirm something, keyboard-first.
%   OK = confirmAction(FIG, MESSAGE, TITLE, AFFIRMATIVE, NEGATIVE) shows a
%   modal two-button confirmation over FIG and returns true only when
%   AFFIRMATIVE was chosen. Closing the dialog, pressing Escape, or picking
%   NEGATIVE all return false, so a caller that ignores everything except a
%   true answer is behaving correctly.
%
%   Name-value arguments:
%     'Icon'    'question' (default), 'warning', 'info', ... as uiconfirm.
%
%   WHY THIS EXISTS. Every confirmation in the application used questdlg, a
%   Java/AWT dialog (the LEGACY-JAVA-GUI markers through @Alakazam and
%   @WorkSpace, and migration.md's own checklist), and the reported symptom
%   was that the keyboard did not reach it: Return and Tab did nothing, so a
%   yes/no question needed the mouse. The underlying cause was not
%   established -- a Java dialog raised from a uifigure app not taking
%   keyboard focus is the obvious suspect, but that was inferred from the
%   symptom, not confirmed.
%
%   uiconfirm is the uifigure-native dialog and does not have the problem
%   either way: it is app-modal, so Tab moves between the buttons and Return
%   activates the default one. It also removes the LEGACY-JAVA-GUI debt at
%   these sites, which migration.md's checklist already wanted.
%
%   THE DEFAULT IS THE AFFIRMATIVE, which is worth stating plainly because
%   several of these confirmations guard something irreversible: Return now
%   confirms a delete rather than cancelling it. That is the requested
%   behaviour and the ordinary convention for a dialog whose buttons say
%   what they do ("Yes, delete!" is not ambiguous about what Return will
%   do). Escape and the window's close button remain wired to NEGATIVE, so
%   there is still a keystroke that always means no.
%
%   FIG may be anything; when it is not a uifigure -- a startup path that
%   runs before the window exists, or a transformation with no handle to it
%   -- this falls back to questdlg with AFFIRMATIVE as its default answer.
%   The fallback cannot fix the focus behaviour, which is the whole reason
%   for preferring uiconfirm where a figure is available.
%
%   See also UICONFIRM, ALAKAZAM/ONDELETENODE, WORKSPACE/RAWCLEAR.
    icon = 'question';
    for k = 1:2:numel(varargin)
        if strcmpi(varargin{k}, 'Icon')
            icon = varargin{k + 1};
        end
    end

    if isUiFigure(fig)
        selection = uiconfirm(fig, message, title, ...
            'Options', {affirmative, negative}, ...
            'DefaultOption', affirmative, ...
            'CancelOption', negative, ...
            'Icon', icon);
    else
        selection = questdlg(message, title, affirmative, negative, affirmative);
    end

    % strcmp rather than a truthiness test: both dialogs return '' when the
    % window is dismissed without a choice, and '' must not read as yes.
    ok = strcmp(selection, affirmative);
end

% ======================================================================= %
function tf = isUiFigure(fig)
%ISUIFIGURE  Whether FIG is a live uifigure, which is what uiconfirm needs.
%   A uifigure has an empty Number, unlike a classic figure -- the standard
%   way to tell them apart, and cheaper than probing for a property only
%   one of them has.
    tf = false;
    try
        tf = ~isempty(fig) && isscalar(fig) && isgraphics(fig) && ...
            isa(fig, 'matlab.ui.Figure') && isempty(fig.Number);
    catch
        tf = false;   % a deleted or exotic handle is simply not usable
    end
end
