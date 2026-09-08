classdef CentredOnTest < matlab.unittest.TestCase
%CENTREDONTEST  Dialogs must be centred where a dialog can be centred, and
%   reachable everywhere else.
%
%   Every dialog in the app is placed by centredOn, so a dialog centred
%   over a main window near the edge of a display, or one taller than a
%   laptop panel, put its own title bar and often its buttons out of
%   reach. Centring and reachability disagree in exactly those cases, and
%   reachability wins.
%
%   The parent is a plain struct with a Position field rather than a
%   figure: centredOn reads parent.Position inside a try, so no UI is
%   needed to exercise either branch, and a test that opened a real window
%   would be the slowest in the suite for no gain.
%
%   Run with: runtests('tests/CentredOnTest.m').
%
%   See also CENTREDON, FITONSCREEN.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function itCentresOverAParentThatLeavesRoom(testCase)
        %ITCENTRESOVERAPARENTTHATLEAVESROOM  The ordinary case has to stay
        %   exactly as it was: the clamp is a safety net, not a new layout
        %   rule that shifts every dialog.
            parent = struct('Position', [400 300 1000 700]);
            pos = centredOn(parent, 400, 300);

            testCase.verifyEqual(pos(1), 400 + (1000 - 400) / 2);
            testCase.verifyEqual(pos(2), 300 + (700 - 300) / 2);
            testCase.verifyEqual(pos(3:4), [400 300]);
        end

        function aDialogIsNeverPlacedOffTheScreen(testCase)
        %ADIALOGISNEVERPLACEDOFFTHESCREEN  Centred over a parent that is
        %   itself off the display, which is what the main window did
        %   before fitOnScreen existed.
            parent = struct('Position', [5000 4000 1000 700]);
            pos = centredOn(parent, 400, 300);

            areas = screenWorkAreas();
            testCase.verifyTrue(testCase.liesWithinSomeMonitor(pos, areas), ...
                'A dialog was placed outside every display this machine has.');
        end

        function aDialogTallerThanTheScreenIsBroughtBack(testCase)
            parent = struct('Position', [100 100 1000 700]);
            pos = centredOn(parent, 400, 20000);

            areas = screenWorkAreas();
            testCase.verifyTrue(testCase.liesWithinSomeMonitor(pos, areas), ...
                'A dialog taller than the display was left hanging off it.');
        end

        function theScreenFallbackIsAlsoClamped(testCase)
        %THESCREENFALLBACKISALSOCLAMPED  A transformation opens its options
        %   dialog with no parent at all, so the [] branch is the ordinary
        %   case there rather than an error path.
            pos = centredOn([], 500, 400);

            areas = screenWorkAreas();
            testCase.verifyTrue(testCase.liesWithinSomeMonitor(pos, areas));
        end
    end

    methods (Access = private)
        function tf = liesWithinSomeMonitor(~, pos, areas)
            tf = false;
            for k = 1:size(areas, 1)
                a = areas(k, :);
                if pos(1) >= a(1) && pos(2) >= a(2) && ...
                        pos(1) + pos(3) <= a(1) + a(3) && ...
                        pos(2) + pos(4) <= a(2) + a(4)
                    tf = true;
                    return;
                end
            end
        end
    end
end
