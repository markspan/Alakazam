function choice = chooseAction(fig, message, title, options, defaultOption, cancelOption, varargin)
%CHOOSEACTION  Ask the analyst to pick one of several actions, keyboard-first.
%   CHOICE = chooseAction(FIG, MESSAGE, TITLE, OPTIONS, DEFAULTOPTION,
%   CANCELOPTION) shows a modal dialog over FIG with one button per entry of
%   the cellstr OPTIONS and returns the text of the button chosen.
%   DEFAULTOPTION is the one Return activates; CANCELOPTION is the one Escape
%   and the window's close button stand for. Dismissing the dialog in any way
%   returns CANCELOPTION, so a caller that acts only on the options it
%   recognises, and treats CANCELOPTION as "do nothing", behaves correctly.
%
%   Name-value arguments:
%     'Icon'    'question' (default), 'warning', 'info', ... as uiconfirm.
%
%   This is the general form of confirmAction, which is a yes/no question
%   built on it. See confirmAction for why a uifigure dialog is used in
%   preference to questdlg.
%
%   FIG may be anything. When it is not a uifigure (a startup path that runs
%   before the window exists, or a transformation with no handle to it) this
%   falls back to questdlg, which offers at most three buttons; more than
%   three options is then an error rather than a silently truncated dialog.
%
%   See also CONFIRMACTION, UICONFIRM, WORKSPACE/RAWCLEAR.
    icon = 'question';
    for k = 1:2:numel(varargin)
        if strcmpi(varargin{k}, 'Icon')
            icon = varargin{k + 1};
        end
    end
    options = cellstr(options);
    if ~any(strcmp(defaultOption, options)) || ~any(strcmp(cancelOption, options))
        throw(MException('Alakazam:chooseAction', ...
            'I''m afraid the default and cancel options must both be among the options offered.'));
    end

    if isUiFigure(fig)
        choice = uiconfirm(fig, message, title, ...
            'Options', options, ...
            'DefaultOption', defaultOption, ...
            'CancelOption', cancelOption, ...
            'Icon', icon);
    else
        if numel(options) > 3
            throw(MException('Alakazam:chooseAction', ...
                'I''m afraid questdlg offers at most three buttons, and %d were requested.', numel(options)));
        end
        choice = questdlg(message, title, options{:}, defaultOption);
    end

    % questdlg returns '' when the window is closed without a choice, and
    % that must read as a cancel, not as an unrecognised answer.
    if ~any(strcmp(choice, options))
        choice = cancelOption;
    end
end

% ======================================================================= %
function tf = isUiFigure(fig)
%ISUIFIGURE  Whether FIG is a live uifigure, which is what uiconfirm needs.
%   A uifigure has an empty Number, unlike a classic figure: the standard
%   way to tell them apart, and cheaper than probing for a property only
%   one of them has.
    try
        tf = ~isempty(fig) && isscalar(fig) && isgraphics(fig) && ...
            isa(fig, 'matlab.ui.Figure') && isempty(fig.Number);
    catch
        tf = false;   % a deleted or exotic handle is simply not usable
    end
end
