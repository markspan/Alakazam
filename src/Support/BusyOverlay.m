classdef BusyOverlay < handle
%BUSYOVERLAY  Alakazam's own "please wait" layer over its window, shown in
%   place of MATLAB's uiprogressdlg (see busyDialog).
%
%   WHY. uiprogressdlg dims the window with a layer of its own, and that
%   layer always shows the arrow: the window's Pointer does not reach it,
%   whichever is set first (measured on screen, 2026-10-22). While Alakazam
%   computed behind the dialog, only its bar looked busy. This layer is a
%   page (BusyOverlay.html) laid over every cell of the window's grid. It
%   dims the window and takes its clicks as the dialog did, shows the same
%   title, message and bar, and shows the wait cursor wherever the pointer
%   is.
%
%   MADE ONCE, SHOWN MANY TIMES. The window makes it hidden
%   (Alakazam.setupMainWindow), long before it is needed, and busyDialog
%   uses it once its page has said it is ready (Ready). That word reaches
%   MATLAB only while MATLAB is idle, so a layer made when the work starts
%   would show but not count as ready until the work was done (measured).
%   Until it is ready, and in a window without one, busyDialog falls back
%   on uiprogressdlg.
%
%   It answers to the properties of uiprogressdlg that Alakazam sets, so
%   callers need not know which of the two they were given: Title, Message
%   (a string array is shown one element per line, and read back as one
%   string with line breaks, as uiprogressdlg does), Value, Indeterminate,
%   ShowPercentage; close(layer) hides it again.
%
%   See also BUSYDIALOG, BUSYGATE, BEGINBUSY.

    properties (SetAccess = private)
        Component      % the uihtml showing BusyOverlay.html
        Ready = false  % true once the page has loaded and can be shown
    end

    properties (Dependent)
        Title
        Message
        Value
        Indeterminate
        ShowPercentage
    end

    properties (Access = private)
        Content = struct('title', 'Alakazam', 'message', '', 'value', 0, ...
            'indeterminate', true, 'showPercentage', false)   % what the page shows
    end

    properties (Constant)
        Tag = 'AlakazamBusyOverlay'
    end

    methods
        function this = BusyOverlay(grid)
        %BUSYOVERLAY  The layer, hidden, over every cell of GRID (the
        %   window's top-level uigridlayout). Made last, so it lies above
        %   everything else in the grid.
        %
        %   The span is counted before the layer exists. A new component in
        %   a full grid is first put in a row of its own, which the grid
        %   drops again once nothing is in it; counted after, the span took
        %   that row in and kept it, and it took half the height of the
        %   window's '1x' row (measured, 2026-10-22).
            nRows = numel(grid.RowHeight);
            nColumns = numel(grid.ColumnWidth);
            this.Component = uihtml(grid, ...
                'HTMLSource', fullfile(fileparts(mfilename('fullpath')), 'BusyOverlay.html'), ...
                'Data', this.Content, 'Visible', 'off', 'Tag', BusyOverlay.Tag, ...
                'HTMLEventReceivedFcn', @(~, event) this.onEvent(event));
            this.Component.Layout.Row = [1 nRows];
            this.Component.Layout.Column = [1 nColumns];
            this.Component.UserData = this;   % how BusyOverlay.of finds it
        end

        function show(this, title, message)
        %SHOW  Put the layer up with TITLE, MESSAGE and a sliding bar.
            this.Content = BusyOverlay.blank(title, message);
            this.push();
            this.Component.Visible = 'on';
        end

        function close(this)
        %CLOSE  Take the layer down; it stays ready for the next time.
            if isvalid(this.Component)
                this.Component.Visible = 'off';
            end
        end

        function value = get.Title(this)
            value = string(this.Content.title);
        end
        function set.Title(this, value)
            this.Content.title = char(value);
            this.push();
        end

        function value = get.Message(this)
            value = string(this.Content.message);
        end
        function set.Message(this, value)
            this.Content.message = char(strjoin(string(value), newline));
            this.push();
        end

        function value = get.Value(this)
            value = this.Content.value;
        end
        function set.Value(this, value)
            this.Content.value = double(value);
            this.push();
        end

        function value = get.Indeterminate(this)
            value = matlab.lang.OnOffSwitchState(this.Content.indeterminate);
        end
        function set.Indeterminate(this, value)
            this.Content.indeterminate = logical(matlab.lang.OnOffSwitchState(value));
            this.push();
        end

        function value = get.ShowPercentage(this)
            value = matlab.lang.OnOffSwitchState(this.Content.showPercentage);
        end
        function set.ShowPercentage(this, value)
            this.Content.showPercentage = logical(matlab.lang.OnOffSwitchState(value));
            this.push();
        end
    end

    methods (Static)
        function layer = of(fig)
        %OF  The ready layer in FIG, or [] when it has none (yet).
            layer = [];
            if isempty(fig) || ~isvalid(fig)
                return;
            end
            found = findall(fig, 'Tag', BusyOverlay.Tag);
            for k = 1:numel(found)
                candidate = found(k).UserData;
                if isa(candidate, 'BusyOverlay') && candidate.Ready
                    layer = candidate;
                    return;
                end
            end
        end
    end

    methods (Access = private)
        function push(this)
            if isvalid(this.Component)
                this.Component.Data = this.Content;
            end
        end

        function onEvent(this, event)
            if strcmp(event.HTMLEventName, 'ready')
                this.Ready = true;
            end
        end
    end

    methods (Static, Access = private)
        function content = blank(title, message)
        %BLANK  What the page shows when the layer goes up: a sliding bar.
            content = struct('title', char(title), ...
                'message', char(strjoin(string(message), newline)), ...
                'value', 0, 'indeterminate', true, 'showPercentage', false);
        end
    end
end
