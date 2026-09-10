function fig = undockTabContent(tab, opts)
%UNDOCKTABCONTENT  Move a plot tab's content into a window of its own.
%   FIG = undockTabContent(TAB) reparents TAB's single content child into a
%   new uifigure, leaves a placeholder in the tab saying where it went, and
%   returns the window. FIG is empty if there was nothing to move: the tab
%   is already undocked, or its content is currently in the tile grid.
%
%   Name-value options: Title, Position, and CloseFcn / WheelFcn / KeyFcn,
%   which let the caller route the window's own events back into the app.
%   With no CloseFcn the window docks itself back when closed, which is
%   what makes this usable on its own in a test.
%
%   WHY REPARENTING RATHER THAN A NEW VIEW. The app already moves a tab's
%   content elsewhere and back: that is what Alakazam.retile and untile do
%   with the tile grid. Undocking is the same move to a different
%   destination, so it inherits a mechanism that already works rather than
%   introducing a second way for a plot to exist.
%
%   THE ONE THING THAT HAD TO BE ESTABLISHED was that a subtree can cross
%   figures, since the tile grid is a sibling in the same one. Measured on
%   a tab holding everything the views actually contain, a uiaxes with a
%   line, a 3D surface, a uihtml (that is ReportView), a uitable and
%   buttons: all survive the move out and back, the axes remains drawable,
%   and appdata on the tab is untouched. See UndockTabContentTest.
%
%   TWO THINGS DO NOT FOLLOW A REPARENT, and both are the caller's to
%   handle. A ContextMenu stays attached to the figure it was created on,
%   so a view that grows one must create it on its current ancestor figure
%   rather than caching one. And any code holding a figure handle it worked
%   out earlier is now holding the wrong one, which is why @cursor and
%   @label resolve theirs with ancestor() at the moment of the drag.
%
%   See also DOCKTABCONTENT, UNDOCKEDFIGUREOF, ALAKAZAM.UNDOCKTAB.
    arguments
        tab (1, 1) matlab.ui.container.Tab
        opts.Title (1, 1) string = "Alakazam"
        opts.Position (1, 4) double = [120 120 900 620]
        opts.CloseFcn = function_handle.empty
        opts.WheelFcn = function_handle.empty
        opts.KeyFcn = function_handle.empty
    end

    fig = matlab.ui.Figure.empty;
    if ~isempty(undockedFigureOf(tab))
        return;
    end

    content = tab.Children;
    if isempty(content)
        return;   % nothing in the tab: tiled, or never populated
    end
    content = content(1);

    background = tab.BackgroundColor;
    fig = uifigure( ...
        "Name", opts.Title, ...
        "Tag", "AlakazamUndockedPlot", ...
        "Position", opts.Position, ...
        "Color", background);

    % Same shape as ReportView's own window: the plot fills the figure, with
    % one short row under it for the way back.
    grid = uigridlayout(fig, [2 1], "RowHeight", {'1x', 28}, ...
        "Padding", [0 0 0 0], "RowSpacing", 2, "BackgroundColor", background);
    content.Parent = grid;
    content.Layout.Row = 1;

    buttonRow = uigridlayout(grid, [1 2], "ColumnWidth", {'1x', 120}, ...
        "Padding", [4 4 4 4], "BackgroundColor", background);
    buttonRow.Layout.Row = 2;
    dockButton = uibutton(buttonRow, "Text", "Dock", ...
        "Tooltip", "Put this plot back in its tab in the main window", ...
        "ButtonPushedFcn", @(~, ~) close(fig));
    dockButton.Layout.Column = 2;

    % The content handle is recorded rather than searched for on the way
    % back: the window has a button row of its own by then, so "the child
    % that is not the button row" would be a rule to keep in step with this
    % layout. Alakazam.untile has to do exactly that, by Layout.Row.
    setappdata(fig, 'DockContent', content);
    setappdata(fig, 'DockTab', tab);
    setappdata(tab, 'UndockedFigure', fig);

    placeholderInto(tab, fig);

    if isempty(opts.CloseFcn)
        fig.CloseRequestFcn = @(~, ~) dockTabContent(tab);
    else
        fig.CloseRequestFcn = @(~, ~) opts.CloseFcn();
    end
    % Wheel and key events are figure-wide, so an undocked window gets its
    % own pair rather than inheriting the main window's (see
    % Alakazam.dispatchWheel, which now takes the tab to deliver to).
    if ~isempty(opts.WheelFcn)
        fig.WindowScrollWheelFcn = @(~, e) opts.WheelFcn(e);
    end
    if ~isempty(opts.KeyFcn)
        fig.KeyPressFcn = @(~, e) opts.KeyFcn(e);
    end
end

% ======================================================================= %
function placeholderInto(tab, fig)
%PLACEHOLDERINTO  What the tab shows while its content is elsewhere.
%   An empty tab would read as a plot that failed to draw, which is the
%   wrong impression entirely, and it would leave no way back for someone
%   who has lost the window behind the main one.
    grid = uigridlayout(tab, [4 3], ...
        "RowHeight", {'1x', 22, 24, '1x'}, "ColumnWidth", {'1x', 260, '1x'}, ...
        "Padding", [0 0 0 0], "RowSpacing", 6);

    message = uilabel(grid, "Text", "This plot is open in its own window.", ...
        "HorizontalAlignment", "center");
    message.Layout.Row = 2;
    message.Layout.Column = 2;

    button = uibutton(grid, "Text", "Dock", ...
        "Tooltip", "Bring this plot back into its tab", ...
        "ButtonPushedFcn", @(~, ~) close(fig));
    button.Layout.Row = 3;
    button.Layout.Column = 2;
end
