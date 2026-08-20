classdef ReportView < handle
%REPORTVIEW  Displays a rendered Quarto/R statistics report (a static
%   HTML file) inside a tab, via uihtml -- the same "point uihtml
%   straight at a file" idiom WorkSpaceTree/AlakazamRibbon already use
%   for their own web content (see their own header comments), just
%   without a JS event bridge: this is read-only output, nothing to
%   send back to MATLAB.
%
%   Constructed by AlakazamPlotter.plotEpoched for any node whose
%   EEG.id is "Report" (see Alakazam.persistReportNode, which builds
%   the synthetic EEG-shaped struct this class is handed, with
%   EEG.ReportHtmlFile pointing at the file to show).
%
%   See also ALAKAZAMPLOTTER, ALAKAZAM.PERSISTREPORTNODE,
%   RENDERQUARTOREPORT.

    properties
        % Set uniformly by AlakazamPlotter alongside every other view's
        % own ActivatedFcn, for interface consistency with
        % Alakazam.registerTileClick -- not wired to anything inside this
        % class, since a static HTML report has no keyboard/wheel
        % interaction of its own that would need to activate a tile.
        ActivatedFcn = function_handle.empty
    end

    properties (SetAccess = private)
        Figure
        EEG
        Grid        % 2x1 uigridlayout: the uihtml component, then a button row
        Component   % the uihtml component
    end

    methods
        function this = ReportView(fig, eeg)
        %REPORTVIEW  Show EEG.ReportHtmlFile inside FIG, plus an "Open in
        %   browser" button.
        %   FIG (and this.Grid) are forced white: uihtml itself has no
        %   BackgroundColor property (checked directly -- matlab.ui.
        %   control.HTML exposes no such property at all), so the app's own
        %   theme (dark, on some setups) would otherwise show through
        %   around/behind the loaded page as a dark tab background, visible
        %   through anything in the report's own CSS that is not fully
        %   opaque (Quarto's floating table-of-contents sidebar, in
        %   particular -- see generateQuartoReport's own preamble for the
        %   matching fix on the page's own CSS side).
        %
        %   uihtml renders through MATLAB's own bundled embedded browser
        %   (CEF), not the system one -- typically several versions behind,
        %   and usually narrower than a real browser window, so Quarto's
        %   theme (position: sticky TOC, responsive margins) does not
        %   always render the same as it does in an actual up to date
        %   browser. Rather than chase parity with an engine this code has
        %   no visibility into, "Open in browser" hands the same file to
        %   the user's own default browser with one click.
            this.Figure = fig;
            this.EEG    = eeg;
            fig.BackgroundColor = [1 1 1];
            this.Grid = uigridlayout(fig, [2 1], "RowHeight", {'1x', 28}, ...
                "Padding", [0 0 0 0], "RowSpacing", 2, "BackgroundColor", [1 1 1]);
            this.Component = uihtml(this.Grid, "HTMLSource", eeg.ReportHtmlFile);
            this.Component.Layout.Row = 1;

            buttonRow = uigridlayout(this.Grid, [1 2], "ColumnWidth", {'1x', 140}, ...
                "Padding", [4 4 4 4], "BackgroundColor", [1 1 1]);
            buttonRow.Layout.Row = 2;
            openBtn = uibutton(buttonRow, "Text", "Open in browser", ...
                "Tooltip", "Open this report in your default web browser, where Quarto's styling renders fully", ...
                "ButtonPushedFcn", @(~, ~) this.onOpenInBrowser());
            openBtn.Layout.Column = 2;
        end
    end

    methods (Access = private)
        function onOpenInBrowser(this)
        %ONOPENINBROWSER  "Open in browser" button: hand EEG.ReportHtmlFile
        %   to the user's own default web browser (see this class's own
        %   header comment for why -- uihtml's embedded browser does not
        %   render Quarto's theme identically).
            web(this.EEG.ReportHtmlFile, "-browser");
        end
    end
end
