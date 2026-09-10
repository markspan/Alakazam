classdef OtherTabTagsTest < matlab.unittest.TestCase
%OTHERTABTAGSTEST  Choosing which plots "Close others" closes.
%
%   WHY THIS IS SPLIT OUT AND TESTED ON ITS OWN. Closing the wrong set here
%   is the one mistake in this feature that a user cannot shrug off: it
%   takes every open plot at once. The decision is therefore a plain
%   function over a list of tabs, testable without a running application,
%   and Alakazam.closeOtherTabs is the loop that acts on it.
%
%   THE CASE THAT MATTERS is a keep-tag that is not there. "Everything
%   except this one" reads perfectly well and closes everything when
%   "this one" cannot be found. Returning nothing instead means a stale
%   tag shows up as a menu item that appears not to work, which is
%   visible and harmless.
%
%   Run with: runtests('tests/OtherTabTagsTest.m').

    properties
        Figure
        Group
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end

        function buildAFigure(testCase)
        %BUILDAFIGURE  One figure for the whole class: these cases only read
        %   Tags, and a uifigure costs over a second to build.
            testCase.Figure = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(testCase.Figure));
            testCase.Group = uitabgroup(testCase.Figure);
        end
    end

    methods (Test)
        function theOtherTabsAreReturnedInTabOrder(testCase)
            tabs = testCase.tabsWithTags(["a.mat", "b.mat", "c.mat"]);

            testCase.verifyEqual(otherTabTags(tabs, 'b.mat'), ["a.mat", "c.mat"]);
        end

        function theKeptTabIsNeverIncluded(testCase)
            tabs = testCase.tabsWithTags(["a.mat", "b.mat", "c.mat"]);

            testCase.verifyFalse(any(otherTabTags(tabs, 'a.mat') == "a.mat"));
        end

        function aSingleTabHasNoOthers(testCase)
            tabs = testCase.tabsWithTags("only.mat");

            testCase.verifyEmpty(otherTabTags(tabs, 'only.mat'));
        end

        function anAbsentKeepTagClosesNothing(testCase)
        %ANABSENTKEEPTAGCLOSESNOTHING  The case this function exists for.
        %   The plausible implementation returns all three here, which
        %   would close every open plot.
            tabs = testCase.tabsWithTags(["a.mat", "b.mat", "c.mat"]);

            testCase.verifyEmpty(otherTabTags(tabs, 'gone.mat'), ...
                'A keep-tag that is not present must close nothing, not everything.');
        end

        function noTabsAtAllIsNotAnError(testCase)
            testCase.verifyEmpty(otherTabTags(matlab.ui.container.Tab.empty, 'a.mat'));
        end

        function aStringKeepTagWorksAsWellAsChar(testCase)
        %ASTRINGKEEPTAGWORKSASWELLASCHAR  Tab Tags are char (they come from
        %   EEG.File), and callers are inconsistent about which they pass.
            tabs = testCase.tabsWithTags(["a.mat", "b.mat"]);

            testCase.verifyEqual(otherTabTags(tabs, "a.mat"), "b.mat");
            testCase.verifyEqual(otherTabTags(tabs, 'a.mat'), "b.mat");
        end

        function theMenuAndTheMethodAreWiredUp(testCase)
        %THEMENUANDTHEMETHODAREWIREDUP  Weaker than driving a live app,
        %   which needs a workspace and a loaded dataset, but it fails if
        %   either end is dropped.
            root = fileparts(fileparts(mfilename('fullpath')));

            plotter = fileread(fullfile(root, 'src', 'AlakazamPlotter.m'));
            testCase.verifySubstring(plotter, '"Close others"');
            testCase.verifySubstring(plotter, 'app.closeOtherTabs(eeg.File)');
            testCase.verifySubstring(plotter, 'ContextMenuOpeningFcn', ...
                'Close others should be greyed out when there is nothing else open.');

            method = fileread(fullfile(root, 'src', '@Alakazam', 'closeOtherTabs.m'));
            testCase.verifySubstring(method, 'otherTabTags(', ...
                'closeOtherTabs should decide what to close before closing any of it.');
            testCase.verifySubstring(method, 'this.closeTab(', ...
                'Tabs should go through closeTab, which knows about tiles and windows.');

            classdefText = fileread(fullfile(root, 'src', '@Alakazam', 'Alakazam.m'));
            testCase.verifySubstring(classdefText, 'closeOtherTabs(this, tag)', ...
                'An @Alakazam method not declared in Alakazam.m fails silently.');
        end
    end

    methods (Access = private)
        function tabs = tabsWithTags(testCase, tags)
        %TABSWITHTAGS  Tabs carrying TAGS, deleted again after the case.
            tabs = matlab.ui.container.Tab.empty(1, 0);
            for k = 1:numel(tags)
                tabs(k) = uitab(testCase.Group, 'Tag', char(tags(k)));
            end
            testCase.addTeardown(@() delete(tabs(isvalid(tabs))));
        end
    end
end
