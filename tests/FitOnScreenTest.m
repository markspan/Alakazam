classdef FitOnScreenTest < matlab.unittest.TestCase
%FITONSCREENTEST  A window must open somewhere the user can reach its title
%   bar, on every display arrangement.
%
%   WHY THE MONITOR LAYOUT IS INJECTED. The failure being prevented only
%   happens on a small display, or on a second display placed above or to
%   the left of the primary one, and neither can be arranged on the machine
%   running this suite. fitOnScreen therefore takes the work areas as an
%   argument, and every case below hands it a layout that a developer with
%   one 1920 x 1080 screen would never otherwise see.
%
%   The layouts are real ones: a 1366 x 768 laptop panel, a portrait
%   secondary, a display placed to the left of the primary (which gives
%   negative coordinates), and one placed above it.
%
%   Run with: runtests('tests/FitOnScreenTest.m').
%
%   See also FITONSCREEN, SCREENWORKAREAS.

    properties (Constant)
        % A title-bar allowance fixed for the tests, so a change to the
        % display-scaling guess in fitOnScreen cannot quietly move these
        % expected values.
        TitleBar = 40
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function theReportedCaseBecomesReachable(testCase)
        %THEREPORTEDCASEBECOMESREACHABLE  The app's own default position on
        %   a 1366 x 768 laptop panel. 100 + 720 = 820 puts the top of the
        %   drawable area 52 pixels above a 768-pixel screen, and the title
        %   bar above that, so the window cannot be moved or resized.
            laptop = [1 1 1366 728];        % 768 less a 40-pixel taskbar
            pos = fitOnScreen([100 100 1280 720], laptop, testCase.TitleBar);

            testCase.verifyReachable(pos, laptop);
            testCase.verifyLessThanOrEqual(pos(4), 728 - testCase.TitleBar, ...
                'The window is still taller than the space its title bar needs.');
        end

        function aWindowThatAlreadyFitsIsNotMoved(testCase)
        %AWINDOWTHATALREADYFITSISNOTMOVED  The common case must be inert:
        %   a user who has placed their window somewhere deliberate should
        %   not find it nudged on the next start.
            desktop = [1 49 1920 1032];
            pos = fitOnScreen([300 200 1280 720], desktop, testCase.TitleBar);
            testCase.verifyEqual(pos, [300 200 1280 720]);
        end

        function aWindowOverTheTopIsMovedDownNotShrunk(testCase)
        %AWINDOWOVERTHETOPISMOVEDDOWNNOTSHRUNK  Where the window fits but
        %   sits too high, moving is the right correction; shrinking a
        %   window that would fit is not.
            desktop = [1 49 1920 1032];
            pos = fitOnScreen([300 900 1280 720], desktop, testCase.TitleBar);

            testCase.verifyEqual(pos(3:4), [1280 720], 'The window should not have been resized.');
            testCase.verifyReachable(pos, desktop);
        end

        function aWindowOffTheRightIsMovedLeft(testCase)
            desktop = [1 49 1920 1032];
            pos = fitOnScreen([1800 200 1280 720], desktop, testCase.TitleBar);

            testCase.verifyEqual(pos(3:4), [1280 720]);
            testCase.verifyReachable(pos, desktop);
        end

        function aWindowOnASecondMonitorStaysThere(testCase)
        %AWINDOWONASECONDMONITORSTAYSTHERE  The distinction MATLAB's own
        %   movegui does not make. A window remembered on the second screen
        %   and hanging off its edge should be corrected on that screen,
        %   not relocated to the primary, which would move the application
        %   out from under the user's eyes.
            areas = [1 49 1920 1032; 1921 49 1920 1032];
            pos = fitOnScreen([3000 900 1280 720], areas, testCase.TitleBar);

            testCase.verifyGreaterThanOrEqual(pos(1), 1921, ...
                'The window was moved to the primary monitor instead of fixed on its own.');
            testCase.verifyReachable(pos, areas(2, :));
        end

        function aWindowOnAMonitorThatIsGoneComesBackToThePrimary(testCase)
        %AWINDOWONAMONITORTHATISGONECOMESBACKTOTHEPRIMARY  A position
        %   remembered from a docking station, opened on the laptop alone.
        %   Overlapping no display at all is the one case where relocating
        %   is correct.
            areas = [1 49 1920 1032];
            pos = fitOnScreen([4000 200 1280 720], areas, testCase.TitleBar);

            testCase.verifyReachable(pos, areas);
        end

        function aMonitorLeftOfThePrimaryHasNegativeCoordinates(testCase)
        %AMONITORLEFTOFTHEPRIMARYHASNEGATIVECOORDINATES  Windows allows a
        %   second display to the left of the primary, which puts its
        %   origin at a negative x. Clamping written for positive
        %   coordinates alone would push every window on it to the primary.
            areas = [1 49 1920 1032; -1920 49 1920 1032];
            pos = fitOnScreen([-2500 200 1280 720], areas, testCase.TitleBar);

            testCase.verifyGreaterThanOrEqual(pos(1), -1920);
            testCase.verifyReachable(pos, areas(2, :));
        end

        function aMonitorAboveThePrimaryIsHandled(testCase)
        %AMONITORABOVETHEPRIMARYISHANDLED  The arrangement most likely to
        %   produce the reported symptom: a second screen stacked above the
        %   primary, so its coordinates run past the primary's own height.
            areas = [1 49 1920 1032; 1 1081 1920 1080];
            pos = fitOnScreen([200 2000 1280 720], areas, testCase.TitleBar);

            testCase.verifyGreaterThanOrEqual(pos(2), 1081);
            testCase.verifyReachable(pos, areas(2, :));
        end

        function aWindowLargerThanTheScreenIsShrunkToFit(testCase)
        %AWINDOWLARGERTHANTHESCREENISSHRUNKTOFIT  A small screen cannot be
        %   satisfied by moving, so the window gives up size instead of
        %   reachability.
            small = [1 1 1024 600];
            pos = fitOnScreen([100 100 1280 720], small, testCase.TitleBar);

            testCase.verifyEqual(pos(3), 1024, 'Width should have been capped at the screen.');
            testCase.verifyEqual(pos(4), 560, 'Height should leave room for the title bar.');
            testCase.verifyReachable(pos, small);
        end

        function anUnusablePositionIsLeftAlone(testCase)
        %ANUNUSABLEPOSITIONISLEFTALONE  A NaN or a wrong-length vector is a
        %   caller's bug, and inventing a position would hide it.
            testCase.verifyEqual(fitOnScreen([1 2 3], [1 1 1920 1080], 40), [1 2 3]);
            testCase.verifyEqual(fitOnScreen([1 NaN 100 100], [1 1 1920 1080], 40), ...
                [1 NaN 100 100]);
        end

        function theRealScreenIsAcceptedWithoutArguments(testCase)
        %THEREALSCREENISACCEPTEDWITHOUTARGUMENTS  The one-argument form has
        %   to work against whatever this machine actually has, since that
        %   is how the application calls it.
            pos = fitOnScreen([100 100 1280 720]);

            testCase.verifySize(pos, [1 4]);
            testCase.verifyTrue(all(isfinite(pos)));
            testCase.verifyGreaterThan(pos(3), 0);
            testCase.verifyGreaterThan(pos(4), 0);

            areas = screenWorkAreas();
            fits = false(1, size(areas, 1));
            for k = 1:size(areas, 1)
                a = areas(k, :);
                fits(k) = pos(1) >= a(1) && pos(2) >= a(2) && ...
                    pos(1) + pos(3) <= a(1) + a(3) && pos(2) + pos(4) <= a(2) + a(4);
            end
            testCase.verifyTrue(any(fits), ...
                'The result does not lie within any monitor this machine reports.');
        end
    end

    methods (Access = private)
        function verifyReachable(testCase, pos, area)
        %VERIFYREACHABLE  Every edge inside the work area, and the title
        %   bar inside it too. The last clause is the one that matters:
        %   the rest can be satisfied by a window whose frame is still off
        %   the top of the display.
            testCase.verifyGreaterThanOrEqual(pos(1), area(1), 'Off the left edge.');
            testCase.verifyGreaterThanOrEqual(pos(2), area(2), 'Off the bottom edge.');
            testCase.verifyLessThanOrEqual(pos(1) + pos(3), area(1) + area(3), ...
                'Off the right edge.');
            testCase.verifyLessThanOrEqual(pos(2) + pos(4) + testCase.TitleBar, ...
                area(2) + area(4), 'The title bar is off the top of the display.');
        end
    end
end
