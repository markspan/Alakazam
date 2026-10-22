classdef BusyOverlayTest < matlab.unittest.TestCase
%BUSYOVERLAYTEST  Unit tests for src/Support/BusyOverlay.m and busyDialog.m:
%   Alakazam's own "please wait" layer, which shows the wait cursor over the
%   whole window where MATLAB's uiprogressdlg always shows the arrow.
%
%   The layer is a page, which loads only in a visible window; the tests
%   that need it loaded are skipped where MATLAB cannot show one. That the
%   cursor really is the wait cursor was measured on screen (see
%   BusyOverlay's header); here the page is checked for its rule.
%
%   Run with: runtests('tests/BusyOverlayTest.m').
%
%   See also BUSYOVERLAY, BUSYDIALOG, BUSYGATETEST, BUSYCURSORTEST.

    properties
        Figure
        Grid
        Layer
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Support'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodTeardown)
        function closeFigure(testCase)
            busyGate('close');
            if ~isempty(testCase.Figure) && isvalid(testCase.Figure)
                delete(testCase.Figure);
            end
            testCase.Figure = [];
        end
    end

    methods (Test)
        function theLayerLeavesTheGridAsItWas(testCase)
        %THELAYERLEAVESTHEGRIDASITWAS  A new component in a full grid is
        %   first put in a row of its own; a span that took that row in kept
        %   it, at half the height of the main window's '1x' row. The layer
        %   spans the grid as it was and adds no row.
            testCase.Figure = uifigure('Visible', 'off');
            grid = testCase.appShapedGrid(testCase.Figure);
            rows = grid.RowHeight;
            columns = grid.ColumnWidth;
            layer = BusyOverlay(grid);
            testCase.verifyEqual(grid.RowHeight, rows);
            testCase.verifyEqual(grid.ColumnWidth, columns);
            testCase.verifyEqual(layer.Component.Layout.Row, [1 2]);
            testCase.verifyEqual(layer.Component.Layout.Column, [1 3]);
            testCase.verifyEqual(char(layer.Component.Visible), 'off', 'The layer starts hidden.');
        end

        function aWindowWithoutAReadyLayerGetsTheDialog(testCase)
        %AWINDOWWITHOUTAREADYLAYERGETSTHEDIALOG  An undocked plot's window,
        %   the Install plugins window, or the first moments after startup.
            testCase.visibleFigure();
            testCase.verifyEmpty(BusyOverlay.of(testCase.Figure));
            dlg = busyDialog(testCase.Figure, "Word copy", "Converting...");
            closeDlg = onCleanup(@() close(dlg));
            testCase.verifyClass(dlg, 'matlab.ui.dialog.ProgressDialog');
            testCase.verifyEqual(string(dlg.Title), "Word copy");
        end

        function aReadyLayerIsWhatBusyDialogGives(testCase)
            testCase.readyLayer();
            dlg = busyDialog(testCase.Figure, "Install a plugin", "Fetching...");
            testCase.verifySameHandle(dlg, testCase.Layer);
            testCase.verifyEqual(char(testCase.Layer.Component.Visible), 'on');
            testCase.verifyEqual(dlg.Title, "Install a plugin");
            testCase.verifyEqual(dlg.Message, "Fetching...");
            testCase.verifyEqual(string(dlg.Indeterminate), "on", 'It starts as a sliding bar.');

            close(dlg);
            testCase.verifyEqual(char(testCase.Layer.Component.Visible), 'off');
            testCase.verifyTrue(isvalid(testCase.Layer), 'Closing hides the layer; it is used again.');
            testCase.verifySameHandle(BusyOverlay.of(testCase.Figure), testCase.Layer);
        end

        function itAnswersAsUiprogressdlgDoes(testCase)
        %ITANSWERSASUIPROGRESSDLGDOES  The properties Alakazam sets, read back
        %   as uiprogressdlg gives them, and what the page is sent.
            testCase.readyLayer();
            dlg = busyDialog(testCase.Figure, "Alakazam", "Applying...");
            dlg.Indeterminate = "off";
            dlg.ShowPercentage = "on";
            dlg.Value = 0.4;
            dlg.Message = ["Applying to sub-07 (3 of 5)..."; "About 12 s left"];

            testCase.verifyEqual(string(dlg.Indeterminate), "off");
            testCase.verifyEqual(string(dlg.ShowPercentage), "on");
            testCase.verifyEqual(dlg.Value, 0.4);
            testCase.verifyEqual(splitlines(dlg.Message), ...
                ["Applying to sub-07 (3 of 5)..."; "About 12 s left"]);
            sent = testCase.Layer.Component.Data;
            testCase.verifyEqual(sent.value, 0.4);
            testCase.verifyFalse(sent.indeterminate);
            testCase.verifyTrue(sent.showPercentage);
            testCase.verifyEqual(sent.message, sprintf('Applying to sub-07 (3 of 5)...\nAbout 12 s left'));

            close(dlg);
            dlg = busyDialog(testCase.Figure, "Alakazam", "Next");
            testCase.verifyEqual(string(dlg.Indeterminate), "on", 'A new indicator starts afresh.');
            testCase.verifyEqual(dlg.Value, 0);
        end

        function theGateUsesTheLayer(testCase)
        %THEGATEUSESTHELAYER  beginBusy's gate shows the layer, fills it with
        %   a transformation's progress, takes it down while an options
        %   dialog is up, and hides it at the end.
            testCase.readyLayer();
            layer = testCase.Layer;
            busyGate('open', testCase.Figure, 'Running Something...');
            testCase.verifySameHandle(busyGate('dialog'), layer);
            testCase.verifyEqual(char(layer.Component.Visible), 'on');

            busyGate('progress', 0);
            pause(0.2);
            busyGate('progress', 0.25);
            testCase.verifyEqual(layer.Value, 0.25, 'AbsTol', 1e-12);

            busyGate('suspend');
            testCase.verifyEqual(char(layer.Component.Visible), 'off');
            busyGate('resume');
            testCase.verifyEqual(char(layer.Component.Visible), 'on');
            busyGate('close');
            testCase.verifyEqual(char(layer.Component.Visible), 'off');
        end

        function thePageShowsTheWaitCursorEverywhere(testCase)
            page = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                'src', 'Support', 'BusyOverlay.html'));
            testCase.verifySubstring(page, 'html, html * { cursor: wait !important; }');
            testCase.verifySubstring(page, 'sendEventToMATLAB(''ready''');
        end
    end

    methods
        function grid = appShapedGrid(~, fig)
        %APPSHAPEDGRID  The main window's grid, every cell in use: a ribbon
        %   row over a tree, a splitter and the plots.
            grid = uigridlayout(fig, [2 3], 'RowHeight', {90, '1x'}, 'ColumnWidth', {260, 3, '1x'});
            ribbon = uibutton(grid, 'Text', 'Ribbon');
            ribbon.Layout.Row = 1;
            ribbon.Layout.Column = [1 3];
            for column = 1:3
                slot = uipanel(grid);
                slot.Layout.Row = 2;
                slot.Layout.Column = column;
            end
        end

        function readyLayer(testCase)
        %READYLAYER  A visible window with a loaded layer, or a skip.
            testCase.visibleFigure();
            testCase.Grid = testCase.appShapedGrid(testCase.Figure);
            testCase.Layer = BusyOverlay(testCase.Grid);
            deadline = tic;
            while ~testCase.Layer.Ready && toc(deadline) < 30
                drawnow;
                pause(0.1);
            end
            testCase.assumeTrue(testCase.Layer.Ready, 'The layer''s page did not load here.');
        end

        function visibleFigure(testCase)
        %VISIBLEFIGURE  A visible window as testCase.Figure, or a skip.
            try
                testCase.Figure = uifigure('Visible', 'on');
            catch
                testCase.assumeFail('No visible window can be made in this MATLAB configuration.');
            end
        end
    end
end
