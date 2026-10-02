classdef PlotTitleTest < matlab.unittest.TestCase
%PLOTTITLETEST  The title a dataset's plot is shown under, and a rename
%   reaching an open plot.
%
%   Renaming a node in the tree used to leave its plot tab under the old
%   name, and a renamed node opened afresh showed its file's name, not the
%   one it was given.
%
%   Run with: runtests('tests/PlotTitleTest.m').
%
%   See also TABTITLEFOR, RETITLEPLOT.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function aStepsResultIsItsTransformationAndTime(testCase)
            title = tabTitleFor(dataset('C:\cache\s1\Average051423.mat', 'Average', 'Average'));
            testCase.verifyEqual(title, 'Average (051423)');
        end

        function aRenamedResultIsItsNewName(testCase)
            title = tabTitleFor(dataset('C:\cache\s1\Average051423.mat', 'Late N400', 'Average'));
            testCase.verifyEqual(title, 'Late N400');
        end

        function aRecordingAReportAndAGrandAverageAreTheirFilesName(testCase)
            testCase.verifyEqual(tabTitleFor(dataset('C:\cache\s1.mat', 's1', '')), 's1');
            testCase.verifyEqual(tabTitleFor(dataset( ...
                'C:\exports\data_quality_20261002_node.mat', 'Report', '')), ...
                'data_quality_20261002_node', 'The generic "Report" would name every report alike.');
            testCase.verifyEqual(tabTitleFor(dataset('C:\cache\GrandAverages\b.mat', 'b', '')), 'b');
        end

        function aRenameReachesTheTabTheTileAndTheWindow(testCase)
            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
            file = 'C:\cache\s1\Average051423.mat';
            tab = uitab(uitabgroup(fig), 'Title', 'Average (051423)', 'Tag', file);
            tiles = uigridlayout(fig, [1 1]);
            tile = uigridlayout(tiles, [1 1], 'Tag', file);
            button = uibutton(tile, 'Text', 'Average (051423)', 'Tag', 'tileTitle');
            window = uifigure('Visible', 'off', 'Name', 'Alakazam - Average (051423)');
            testCase.addTeardown(@() delete(window));
            setappdata(tab, 'UndockedFigure', window);

            retitlePlot(tab.Parent, tiles, file, 'Late N400');

            testCase.verifyEqual(tab.Title, 'Late N400');
            testCase.verifyEqual(button.Text, 'Late N400');
            testCase.verifyEqual(char(window.Name), 'Alakazam - Late N400');
        end

        function aPlotThatIsNotOpenIsLeftAlone(testCase)
            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
            other = uitab(uitabgroup(fig), 'Title', 'Other', 'Tag', 'C:\cache\other.mat');

            retitlePlot(other.Parent, [], 'C:\cache\s1\Average051423.mat', 'Late N400');

            testCase.verifyEqual(other.Title, 'Other');
        end
    end
end

% ======================================================================= %
function EEG = dataset(file, id, call)
    EEG = struct('File', file, 'id', id, 'Call', call);
end
