function button = manualButton(title, tool)
%MANUALBUTTON  A ? at the right of a dialog's title bar that opens a step's
%   manual in the web browser.
%
%   BUTTON = manualButton(TITLE, TOOL) puts a ? beside TITLE, the title bar's
%   uilabel, in the place TITLE had in its grid. TOOL is a transformation's
%   id (its manual from manualAddress: a built-in step's section of
%   Alakazam's manual, a plugin's own manual) or a web address. Where there
%   is no manual, or it cannot be looked up, nothing changes and BUTTON is
%   []: a dialog never fails for want of its ?.
%
%       title = uilabel(root, 'Text', '  Filter', ...);
%       manualButton(title, 'Filter');
%
%   A plugin with a dialog of its own calls it when it is there, so it still
%   runs in an Alakazam from before it:
%
%       if exist('manualButton', 'file') == 2
%           manualButton(title, 'MyPlugin');
%       end
%
%   TransformOptionsDialog puts it on every dialog it builds for a step.
%
%   See also MANUALADDRESS, OPENINBROWSER, TRANSFORMOPTIONSDIALOG.
    button = [];
    tool = char(string(tool));
    if isempty(regexp(tool, '^https?://', 'once'))
        try
            tool = manualAddress(tool);
        catch
            tool = '';   % the lookup not on the path (a test of the dialog alone): no ?
        end
    end
    if isempty(tool) || isempty(title) || ~isvalid(title)
        return;
    end
    url = tool;

    where = title.Layout;
    bar = uigridlayout(title.Parent, [1 2], 'ColumnWidth', {'1x', 30}, ...
        'Padding', [0 5 10 5], 'ColumnSpacing', 0, 'BackgroundColor', title.BackgroundColor);
    bar.Layout.Row = where.Row;
    bar.Layout.Column = where.Column;
    title.Parent = bar;
    title.Layout.Row = 1;
    title.Layout.Column = 1;
    button = uibutton(bar, 'Text', '?', 'Tag', 'Manual', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', title.BackgroundColor, 'BackgroundColor', [1 1 1], ...
        'Tooltip', 'The manual for this step, in your web browser', ...
        'ButtonPushedFcn', @(~, ~) openInBrowser(url));
    button.Layout.Row = 1;
    button.Layout.Column = 2;
end
