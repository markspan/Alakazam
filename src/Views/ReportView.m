classdef ReportView < AlakazamView
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
        %   THE ENGINE IS NOT THE PROBLEM, which took a while to establish.
        %   This comment used to say the embedded browser was an old CEF
        %   several versions behind, and used that to explain why Quarto's
        %   theme rendered differently here. A probe page loaded into a real
        %   uihtml reported Chrome 141, so that was wrong.
        %
        %   What differs is how the page is served. uihtml does not open a
        %   local file: MATLAB serves it from its own connector, over
        %   https://127.0.0.1:<port>/static/..., and that server's
        %   Content-Security-Policy refuses data: stylesheets and data:
        %   scripts, which is exactly the form a self-contained Quarto
        %   report ships its theme in. Every report was therefore rendering
        %   here with no Bootstrap at all. renderQuartoReport now inlines
        %   those resources (see inlineDataUriResources), and the theme
        %   applies here as it does in a browser.
        %
        %   "Open in browser" stays, for the reasons that remain true: the
        %   pane is narrower than a window, so a sticky table of contents
        %   and responsive margins have less to work with, and printing and
        %   saving belong to the browser anyway.
            this.Figure = fig;
            this.EEG    = eeg;
            fig.BackgroundColor = [1 1 1];
            this.Grid = uigridlayout(fig, [2 1], "RowHeight", {'1x', 28}, ...
                "Padding", [0 0 0 0], "RowSpacing", 2, "BackgroundColor", [1 1 1]);
            this.Component = uihtml(this.Grid, "HTMLSource", eeg.ReportHtmlFile);
            this.Component.Layout.Row = 1;

            buttonRow = uigridlayout(this.Grid, [1 3], "ColumnWidth", {'1x', 140, 140}, ...
                "Padding", [4 4 4 4], "BackgroundColor", [1 1 1]);
            buttonRow.Layout.Row = 2;
            wordBtn = uibutton(buttonRow, "Text", "Open in Word", ...
                "Tooltip", "Save a Word copy of this report beside it and open it", ...
                "ButtonPushedFcn", @(~, ~) this.onOpenInWord());
            wordBtn.Layout.Column = 2;
            openBtn = uibutton(buttonRow, "Text", "Open in browser", ...
                "Tooltip", "Open this report in your default web browser, for a wider view, printing and saving", ...
                "ButtonPushedFcn", @(~, ~) this.onOpenInBrowser());
            openBtn.Layout.Column = 3;
        end
    end

    methods (Access = private)
        function onOpenInWord(this)
        %ONOPENINWORD  "Open in Word" button: convert the report beside
        %   itself and hand the .docx to whatever opens Word documents.
        %
        %   THE DIALOG IS OWNED BY THE ANCESTOR FIGURE, not by this.Figure,
        %   which despite its name is the uitab this view was built into
        %   (see the constructor, which sets its BackgroundColor). uialert
        %   and uiprogressdlg both want a figure. Resolving it each time
        %   also means this keeps working when the plot has been moved into
        %   a window of its own (see Alakazam.undockTab).
            fig = ancestor(this.Grid, "figure");

            progress = uiprogressdlg(fig, "Title", "Word copy", ...
                "Message", "Converting the report for Word...", "Indeterminate", "on");
            [docxFile, errorMessage] = reportToWord(this.EEG.ReportHtmlFile);
            close(progress);

            if isempty(docxFile)
                uialert(fig, errorMessage, "No Word copy was made");
                return;
            end

            % winopen hands the file to whatever the desktop associates
            % with .docx, which is Word where it is installed and something
            % else where it is not. That is the user's choice to have made,
            % not this button's to second-guess.
            if ispc
                winopen(docxFile);
            else
                uialert(fig, sprintf('The Word copy is at %s.', docxFile), ...
                    "Word copy saved", "Icon", "success");
            end
        end

        function onOpenInBrowser(this)
        %ONOPENINBROWSER  "Open in browser" button: hand EEG.ReportHtmlFile
        %   to the user's own default web browser (see this class's own
        %   header comment for why -- uihtml's embedded browser does not
        %   render Quarto's theme identically).
            web(this.EEG.ReportHtmlFile, "-browser");
        end
    end
end
