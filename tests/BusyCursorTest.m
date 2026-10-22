classdef BusyCursorTest < matlab.unittest.TestCase
%BUSYCURSORTEST  Unit tests for src/Support/busyCursor.m: the busy cursor over
%   the whole window while Alakazam works, not only over the tree a branch
%   was dropped on (until 2026-10-22 the only place it showed during a drop).
%
%   The window's Pointer stops at the edge of every web page in it (the
%   ribbon and the three trees draw their own cursors), so busyCursor also
%   sends each page a 'busy' event. That a page really receives it is checked
%   with a real page that answers back, which needs a visible window; the
%   test is skipped where MATLAB cannot show one. The tree page's own handling
%   of the event is tested in src/webtree/test_node.mjs.
%
%   Run with: runtests('tests/BusyCursorTest.m').
%
%   See also BUSYCURSOR, BUSYGATETEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Support'), fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theWindowPointerIsBusyUntilTurnedOff(testCase)
            fig = testCase.hiddenFigure();
            busyCursor(fig, true);
            testCase.verifyEqual(char(fig.Pointer), 'watch');
            busyCursor(fig, false);
            testCase.verifyEqual(char(fig.Pointer), 'arrow');
        end

        function theCleanupRestoresWhicheverWayTheCallerReturns(testCase)
        %THECLEANUPRESTORESWHICHEVERWAYTHECALLERRETURNS  RESTORE = BUSYCURSOR(FIG)
        %   turns it on, and the arrow is back when RESTORE goes, an error
        %   included.
            fig = testCase.hiddenFigure();
            restore = busyCursor(fig); %#ok<NASGU>
            testCase.verifyEqual(char(fig.Pointer), 'watch');
            clear restore;
            testCase.verifyEqual(char(fig.Pointer), 'arrow');

            testCase.verifyError(@() failWhileBusy(fig), 'BusyCursorTest:failed');
            testCase.verifyEqual(char(fig.Pointer), 'arrow', 'An error left the busy cursor on.');
        end

        function aWindowThatIsGoneIsIgnored(testCase)
            fig = uifigure('Visible', 'off');
            restore = busyCursor(fig);
            delete(fig);
            testCase.verifyWarningFree(@() busyCursor(fig, true));
            testCase.verifyWarningFree(@() busyCursor([], false));
            testCase.verifyWarningFree(@() delete(restore));
        end

        function beginBusyOnAHiddenWindowShowsTheBusyCursor(testCase)
        %BEGINBUSYONAHIDDENWINDOWSHOWSTHEBUSYCURSOR  At startup the window is
        %   still hidden and no dialog can be shown on it, so beginBusy falls
        %   back on the cursor alone.
            fig = testCase.hiddenFigure();
            restore = beginBusy(fig, 'Loading...'); %#ok<NASGU>
            testCase.verifyEqual(char(fig.Pointer), 'watch');
            clear restore;
            testCase.verifyEqual(char(fig.Pointer), 'arrow');
        end

        function everyPageInTheWindowIsTold(testCase)
        %EVERYPAGEINTHEWINDOWISTOLD  Two pages, one straight in the window and
        %   one inside a panel's grid as the trees are, each answering the
        %   'busy' event it receives.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            page = fullfile(folder, 'answer.html');
            fid = fopen(page, 'w');
            fprintf(fid, '%s\n', '<!doctype html><html><body><script>', ...
                'function setup(htmlComponent) {', ...
                '    htmlComponent.addEventListener(''busy'', function (event) {', ...
                '        htmlComponent.sendEventToMATLAB(''busySeen'', event.Data);', ...
                '    });', ...
                '    htmlComponent.sendEventToMATLAB(''ready'', true);', ...
                '}', '</script></body></html>');
            fclose(fid);

            try
                fig = uifigure('Visible', 'on');
            catch
                testCase.assumeFail('No visible window can be made in this MATLAB configuration.');
            end
            testCase.addTeardown(@() delete(fig));
            heard = {{}, {}};
            uihtml(fig, 'HTMLSource', page, 'Position', [10 10 100 100], ...
                'HTMLEventReceivedFcn', @(~, e) hear(1, e));
            grid = uigridlayout(uipanel(fig, 'Position', [120 10 120 120]), [1 1]);
            uihtml(grid, 'HTMLSource', page, 'HTMLEventReceivedFcn', @(~, e) hear(2, e));
            % The conditions call a nested function: an anonymous function
            % would see HEARD only as it was when it was made.
            testCase.assumeTrue(waitFor(@() all(answers() >= 1)), ...
                'The pages did not load here, so they cannot be told anything.');

            busyCursor(fig, true);
            testCase.verifyTrue(waitFor(@() all(answers() >= 2)), ...
                'Not every page heard that the app is busy.');
            busyCursor(fig, false);
            testCase.verifyTrue(waitFor(@() all(answers() >= 3)), ...
                'Not every page heard that the app is free again.');
            testCase.verifyEqual(heard{1}, {'ready', true, false});
            testCase.verifyEqual(heard{2}, {'ready', true, false});

            function n = answers()
                n = cellfun(@numel, heard);
            end

            function hear(k, event)
                if strcmp(event.HTMLEventName, 'ready')
                    heard{k}{end + 1} = 'ready';
                else
                    heard{k}{end + 1} = logical(event.HTMLEventData);
                end
            end
        end

        function theRibbonAndTreePagesListen(testCase)
        %THERIBBONANDTREEPAGESLISTEN  The pages busyCursor tells: each listens
        %   for 'busy', and its busy rule outranks its own cursors (the
        %   ribbon's hand over a button, the tree's over a node).
            source = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'src');
            ribbon = fileread(fullfile(source, 'AlakazamRibbon.html'));
            testCase.verifySubstring(ribbon, 'addEventListener(''busy''');
            testCase.verifySubstring(ribbon, 'body.alz-busy * { cursor: wait !important; }');
            tree = fileread(fullfile(source, 'WorkSpaceTree.html'));
            testCase.verifySubstring(tree, 'addEventListener(''busy''');
            testCase.verifySubstring(tree, 'html.alz-app-busy * { cursor: wait !important; }');
        end

        function aDroppedBranchShowsTheBusyCursorWhileItIsApplied(testCase)
        %ADROPPEDBRANCHSHOWSTHEBUSYCURSORWHILEITISAPPLIED  The complaint this
        %   file answers: while a dropped branch is applied (a copy) or moved
        %   (a Shift-drop), the whole window shows the busy cursor, and the
        %   arrow is back once it is done.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            MethodCopy.make(folder, '@Alakazam', 'onNodeDropped', 'dropCopy');
            testCase.addTeardown(@rehash);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            rehash;
            fig = testCase.hiddenFigure();
            seen = {};
            tree = FakeApp(struct('beginBatch', @() [], 'notifyDropHandled', @() []));
            app = FakeApp(struct('MainFigure', fig, 'Workspace', struct('ActiveTree', []), ...
                'enterRepoRoot', @() [], ...
                'evaluateDroppedBranch', @(~, ~) look(), ...
                'moveDroppedBranch', @(~, ~, ~) lookAndKeep()));
            drop = struct('Source', struct('IsRoot', false, 'UserData', 'branch.mat'), ...
                'Target', struct('Id', 'n2'), 'Move', false);

            dropCopy(app, drop, tree);
            testCase.verifyEqual(seen, {'watch'}, 'No busy cursor while the branch was applied.');
            testCase.verifyEqual(char(fig.Pointer), 'arrow');

            drop.Move = true;
            dropCopy(app, drop, tree);
            testCase.verifyEqual(seen, {'watch', 'watch'}, 'No busy cursor while the branch was moved.');
            testCase.verifyEqual(char(fig.Pointer), 'arrow');

            function look()
                seen{end + 1} = char(fig.Pointer);
            end

            function kept = lookAndKeep()
                look();
                kept = '';
            end
        end
    end

    methods
        function fig = hiddenFigure(testCase)
            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
        end
    end
end

function failWhileBusy(fig)
    restore = busyCursor(fig); %#ok<NASGU>
    error('BusyCursorTest:failed', 'Failed while busy.');
end

function tf = waitFor(condition)
%WAITFOR  True once CONDITION holds, false after 30 s: a page loads, and
%   answers, only while MATLAB processes events.
    deadline = tic;
    tf = condition();
    while ~tf && toc(deadline) < 30
        drawnow;
        pause(0.1);
        tf = condition();
    end
end
