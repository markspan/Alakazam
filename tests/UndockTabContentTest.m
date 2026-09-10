classdef UndockTabContentTest < matlab.unittest.TestCase
%UNDOCKTABCONTENTTEST  Moving a plot tab's content into a window of its own
%   and back again.
%
%   WHY THE MECHANISM LIVES IN src/Support AND IS TESTED HERE. The app's
%   own undockTab/dockTab need a running Alakazam, a workspace and a loaded
%   dataset. The move itself needs none of that, so it is a plain function
%   over a uitab, in the same spirit as buildHelpPageInto (extracted from
%   buildHelpPage so it could be tested without an application) and
%   nativeTransformCall.
%
%   WHAT ACTUALLY NEEDED ESTABLISHING. The app already reparents a tab's
%   content and puts it back: that is retile and untile. The new part is
%   that the destination is a different figure rather than a sibling
%   container in the same one, so the cases below carry one of everything
%   the views hold: a uiaxes with a line, a 3D surface, a uihtml (which is
%   ReportView), a uitable and a button. A view surviving in principle is
%   not the same as a uihtml surviving in practice.
%
%   Run with: runtests('tests/UndockTabContentTest.m').

    properties
        Figure
        Tab
        Content
        Axes
        Line
        Surface
        Html
        Table
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (TestMethodSetup)
        function buildATab(testCase)
        %BUILDATAB  A tab with a plot in it, which is all most cases need.
        %
        %   DELIBERATELY NOT ONE OF EVERYTHING. This built a uihtml, a 3D
        %   surface and a table for every case, and cost 23 seconds across
        %   the class, which put it fourth in the whole quick suite. A
        %   uihtml starts a browser, and paying for one to test that a Tag
        %   is unchanged is waste. The full complement is built by the one
        %   case that is about surviving the move (see addTheRestOfAView).
            testCase.Figure = uifigure('Visible', 'off', 'Position', [100 100 900 600], ...
                'Name', 'main');
            testCase.addTeardown(@() delete(testCase.Figure));

            group = uitabgroup(testCase.Figure, 'Position', [1 1 900 600]);
            testCase.Tab = uitab(group, 'Title', 'Average (051423)', 'Tag', 'sub01.mat');

            testCase.Content = uigridlayout(testCase.Tab, [2 2], 'Padding', [2 2 2 2]);
            testCase.Axes = uiaxes(testCase.Content);
            testCase.Line = plot(testCase.Axes, 1:10, (1:10).^2);

            % What dispatchToActiveView reads back off a tab.
            setappdata(testCase.Tab, 'AverageView', struct('marker', 42));
            drawnow;
        end
    end

    methods (Test)
        function theContentMovesToItsOwnWindow(testCase)
            fig = undockTabContent(testCase.Tab);
            testCase.addTeardown(@() testCase.deleteIfValid(fig));

            testCase.assertNotEmpty(fig);
            testCase.verifyEqual(ancestor(testCase.Axes, 'figure'), fig, ...
                'The axes should now belong to the new window.');
            testCase.verifyEqual(undockedFigureOf(testCase.Tab), fig);
        end

        function everythingAViewHoldsSurvivesTheRoundTrip(testCase)
        %EVERYTHINGAVIEWHOLDSSURVIVESTHEROUNDTRIP  The uihtml is the one
        %   that had to be checked rather than assumed: it is a browser
        %   component, not a drawn one, and it is what ReportView is made
        %   of.
            testCase.addTheRestOfAView();

            fig = undockTabContent(testCase.Tab);
            testCase.addTeardown(@() testCase.deleteIfValid(fig));

            testCase.verifyTrue(all(isvalid([testCase.Axes, testCase.Html, testCase.Table])));
            testCase.verifyTrue(isvalid(testCase.Line));
            testCase.verifyTrue(isvalid(testCase.Surface));
            testCase.verifyEqual(testCase.Line.YData(3), 9, ...
                'The plotted data should have moved with the axes.');

            dockTabContent(testCase.Tab);

            testCase.verifyTrue(all(isvalid([testCase.Axes, testCase.Html, testCase.Table])));
            testCase.verifyEqual(testCase.Line.YData(3), 9);
            testCase.verifyEqual(ancestor(testCase.Axes, 'figure'), testCase.Figure);
        end

        function theMovedAxesIsStillDrawable(testCase)
        %THEMOVEDAXESISSTILLDRAWABLE  Surviving the move is not the same as
        %   still working after it: every view redraws on interaction.
            fig = undockTabContent(testCase.Tab);
            testCase.addTeardown(@() testCase.deleteIfValid(fig));

            before = numel(testCase.Axes.Children);
            hold(testCase.Axes, 'on');
            plot(testCase.Axes, 1:10, 1:10);
            hold(testCase.Axes, 'off');
            drawnow;

            testCase.verifyEqual(numel(testCase.Axes.Children), before + 1);
        end

        function theTabKeepsItsIdentityAndItsView(testCase)
        %THETABKEEPSITSIDENTITYANDITSVIEW  The tab stays put on purpose: it
        %   is what the app finds a plot by (Tag) and where the view object
        %   lives, so undocking must not disturb either.
            fig = undockTabContent(testCase.Tab);
            testCase.addTeardown(@() testCase.deleteIfValid(fig));

            testCase.verifyEqual(testCase.Tab.Tag, 'sub01.mat');
            view = getappdata(testCase.Tab, 'AverageView');
            testCase.verifyEqual(view.marker, 42);
        end

        function theTabShowsAWayBack(testCase)
        %THETABSHOWSAWAYBACK  An empty tab would read as a plot that failed
        %   to draw.
            fig = undockTabContent(testCase.Tab);
            testCase.addTeardown(@() testCase.deleteIfValid(fig));

            labels = findall(testCase.Tab, 'Type', 'uilabel');
            buttons = findall(testCase.Tab, 'Type', 'uibutton');
            testCase.verifyNotEmpty(labels);
            testCase.verifyNotEmpty(buttons);
            testCase.verifySubstring(labels(1).Text, 'own window');
        end

        function dockingRemovesTheWindowAndThePlaceholder(testCase)
            fig = undockTabContent(testCase.Tab);

            testCase.verifyTrue(dockTabContent(testCase.Tab));

            testCase.verifyFalse(isvalid(fig), 'The window should be gone.');
            testCase.verifyEmpty(undockedFigureOf(testCase.Tab));
            testCase.verifyEqual(numel(testCase.Tab.Children), 1, ...
                'Only the content should be left in the tab.');
            testCase.verifyEqual(testCase.Tab.Children(1), testCase.Content);
        end

        function closingTheWindowDocksIt(testCase)
        %CLOSINGTHEWINDOWDOCKSIT  With no CloseFcn given, the window puts
        %   its own content back, so closing it cannot lose a plot.
        %
        %   THERE IS NO drawnow AFTER THIS, and that is not an oversight.
        %   A drawnow immediately after the undocked window is deleted
        %   hangs MATLAB outright under -batch: it sits at 4% of one core
        %   and never returns. It was bisected to that one line, and the
        %   reason it went unnoticed at first is worth recording, because
        %   it looks like nonsense: the hang only happens when no uihtml is
        %   alive in the tab. This class used to build one in every case,
        %   which kept the connector busy and the flush satisfied; trimming
        %   that for speed is what exposed it.
        %
        %   close() was suspected first and is innocent. Two scripted
        %   repros, one hand-rolled and one through these very functions,
        %   closed 24 windows this way in 0.01 s each.
            fig = undockTabContent(testCase.Tab);

            close(fig);

            testCase.verifyFalse(isvalid(fig));
            testCase.verifyEqual(ancestor(testCase.Axes, 'figure'), testCase.Figure);
        end

        function aGivenCloseFcnTakesOver(testCase)
        %AGIVENCLOSEFCNTAKESOVER  Which is how the app keeps its own
        %   bookkeeping in step: Alakazam.dockTab has a tab to select and a
        %   tile layout to recompute, neither of which this function knows
        %   about. The window is then that callback's to dispose of, and
        %   this checks it is left standing rather than closed underneath
        %   it.
            called = false;
            fig = undockTabContent(testCase.Tab, "CloseFcn", @() setCalled());
            testCase.addTeardown(@() testCase.deleteIfValid(fig));

            close(fig);

            testCase.verifyTrue(called, ...
                'The window should have called the CloseFcn it was given.');
            testCase.verifyTrue(isvalid(fig), ...
                'And left the window for that callback to deal with.');
            testCase.verifyNotEmpty(undockedFigureOf(testCase.Tab), ...
                'Nothing should have been docked without the callback asking.');

            function setCalled()
                called = true;
            end
        end

        function theWindowGetsItsOwnWheelAndKeyHandlers(testCase)
        %THEWINDOWGETSITSOWNWHEELANDKEYHANDLERS  Wheel and key events are
        %   figure-wide, so the main window's handlers never see them.
            seen = strings(0);
            fig = undockTabContent(testCase.Tab, ...
                "WheelFcn", @(~) record("wheel"), "KeyFcn", @(~) record("key"));
            testCase.addTeardown(@() testCase.deleteIfValid(fig));

            testCase.assertNotEmpty(fig.WindowScrollWheelFcn);
            testCase.assertNotEmpty(fig.KeyPressFcn);
            fig.WindowScrollWheelFcn(fig, struct('VerticalScrollCount', 1));
            fig.KeyPressFcn(fig, struct('Key', 'rightarrow'));

            testCase.verifyEqual(seen, ["wheel"; "key"]);
            function record(what)
                seen(end + 1, 1) = what;
            end
        end

        function undockingTwiceGivesOneWindow(testCase)
            first = undockTabContent(testCase.Tab);
            testCase.addTeardown(@() testCase.deleteIfValid(first));

            second = undockTabContent(testCase.Tab);

            testCase.verifyEmpty(second, ...
                'A second call should decline rather than build another window.');
            testCase.verifyEqual(undockedFigureOf(testCase.Tab), first);
        end

        function aTabWithNothingInItIsDeclined(testCase)
        %ATABWITHNOTHINGINITISDECLINED  Which is also the tiled case: the
        %   content has been reparented into TileGrid, so the tab is empty.
            delete(testCase.Tab.Children);

            testCase.verifyEmpty(undockTabContent(testCase.Tab));
        end

        function dockingSomethingNotUndockedDoesNothing(testCase)
            testCase.verifyFalse(dockTabContent(testCase.Tab));
        end

        function aWindowDeletedBehindTheTabReadsAsDocked(testCase)
        %AWINDOWDELETEDBEHINDTHETABREADSASDOCKED  closeTab and onDeleteNode
        %   delete the window outright, since the tab is going too.
            fig = undockTabContent(testCase.Tab);
            delete(fig);

            testCase.verifyEmpty(undockedFigureOf(testCase.Tab));
        end

        % ---- the app side, checked at source level -----------------------
        function theShellKnowsContentCanBeInAWindow(testCase)
        %THESHELLKNOWSCONTENTCANBEINAWINDOW  Every place that already knew
        %   a tab's content might be in the tile grid has to know about
        %   this third home too, or a window outlives its own tab. Weaker
        %   than driving a live app, but it fails if one is dropped.
            root = fileparts(fileparts(mfilename('fullpath')));
            expected = { ...
                fullfile('src', '@Alakazam', 'closeTab.m'), 'undockedFigureOf'; ...
                fullfile('src', '@Alakazam', 'onDeleteNode.m'), 'undockedFigureOf'; ...
                fullfile('src', '@Alakazam', 'retile.m'), 'undockedFigureOf'; ...
                fullfile('src', '@Alakazam', 'Alakazam.m'), 'undockedFigureOf'; ...
                fullfile('src', 'AlakazamPlotter.m'), 'app.undockTab'};

            for k = 1:size(expected, 1)
                source = fileread(fullfile(root, expected{k, 1}));
                testCase.verifySubstring(source, expected{k, 2}, ...
                    sprintf('%s no longer accounts for an undocked plot.', expected{k, 1}));
            end
        end

        function theDragHandlersResolveTheirFigureRatherThanCacheIt(testCase)
        %THEDRAGHANDLERSRESOLVETHEIRFIGURERATHERTHANCACHEIT  @cursor and
        %   @label used to keep a figure handle worked out in the
        %   constructor by going two levels up from the axes. That was
        %   already wrong (two levels up is the uitab, and a uitab has no
        %   Window*Fcn), and a plot that can move between windows makes any
        %   cached handle wrong as well.
            root = fileparts(fileparts(mfilename('fullpath')));

            for file = {fullfile('src', '@cursor', 'cursor.m'), ...
                        fullfile('src', '@label', 'label.m')}
                source = fileread(fullfile(root, file{1}));
                testCase.verifyEmpty(strfind(source, 'PFigure'), ...
                    sprintf('%s has gone back to caching its figure.', file{1})); %#ok<STREMP>
                testCase.verifySubstring(source, "ancestor(obj.PAxes, 'figure')");
            end
        end
    end

    methods (Access = private)
        function addTheRestOfAView(testCase)
        %ADDTHERESTOFAVIEW  The components that are expensive to build and
        %   only one case needs: a 3D surface, a uitable, and the uihtml
        %   that ReportView is made of. The uihtml is the one that has to
        %   be here rather than assumed, since it is a browser component
        %   and not a drawn one.
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            page = fullfile(folder, 'page.html');
            fid = fopen(page, 'w');
            fprintf(fid, '<p>plot</p>');
            fclose(fid);

            testCase.Surface = surf(uiaxes(testCase.Content), peaks(10));
            testCase.Html = uihtml(testCase.Content, 'HTMLSource', page);
            testCase.Table = uitable(testCase.Content, 'Data', magic(4));
            drawnow;
        end

        function deleteIfValid(~, h)
            if ~isempty(h) && isvalid(h)
                delete(h);
            end
        end
    end
end
