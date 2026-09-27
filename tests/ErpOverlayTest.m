classdef ErpOverlayTest < matlab.unittest.TestCase
%ERPOVERLAYTEST  Overlaying one ERP on another, and drawing their difference.
%
%   THE RULE IS "CHANNEL NAMES AND TIME, NOT SHAPE". Two averages worth
%   comparing differ in shape all the time: a resampled one has fewer
%   samples, a re-referenced one another montage. The overlay used to demand
%   equal array sizes, which refused the first and, for two montages of
%   equal size in different orders, drew different electrodes on one plot
%   without a sign of it. The cases below pin both: what may be overlaid
%   (erpOverlayProblem), and that every line shows the electrode named in
%   the title (AverageView).
%
%   The difference is checked against arithmetic, not appearance: the line
%   the view draws must be exactly the first ticked line minus the second,
%   interpolated when the two were sampled differently.
%
%   Views are real AverageViews in a hidden uifigure, and the tree case a
%   real WorkSpaceTree, as in ViewFocusTest and WorkSpaceTreeBatchTest.
%
%   Run with: runtests('tests/ErpOverlayTest.m').
%
%   See also AVERAGEVIEW, ERPOVERLAYPROBLEM, OVERLAYNAMES,
%   ALAKAZAMPLOTTER.VIEWCLASSFOR, ALAKAZAM.ONOVERLAYERP.

    properties
        Folder   % where MethodCopy puts copies of @Alakazam methods
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = folder.Folder;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Folder));
        end
    end

    methods (Test)
        % ---- what may be overlaid ----------------------------------------
        function aResampledAverageIsCompatible(testCase)
            a = erp({'Fz', 'Cz', 'Pz'}, 'srate', 250);
            b = erp({'Fz', 'Cz', 'Pz'}, 'srate', 125);
            testCase.verifyEmpty(erpOverlayProblem({a.chanlocs.labels}, a.times, ...
                {b.chanlocs.labels}, b.times));
        end

        function noChannelInCommonIsRefusedWithTheMontages(testCase)
            problem = erpOverlayProblem({'Fz', 'Cz'}, -200:4:596, {'EOG1', 'EOG2'}, -200:4:596);
            testCase.verifySubstring(problem, 'no channel in common');
            testCase.verifySubstring(problem, 'EOG1');
        end

        function channelNamesMatchWhateverTheirCase(testCase)
            testCase.verifyEmpty(erpOverlayProblem({'Fz', 'CZ'}, -200:4:596, {' cz'}, -200:4:596));
        end

        function timesThatDoNotOverlapAreRefused(testCase)
            problem = erpOverlayProblem({'Fz'}, -200:4:596, {'Fz'}, 1000:4:1500);
            testCase.verifySubstring(problem, 'does not overlap');
        end

        % ---- which datasets are ERPs --------------------------------------
        function theViewClassIsThePlottersRouting(testCase)
            average = erp({'Fz', 'Cz'});
            testCase.verifyEqual(AlakazamPlotter.viewClassFor(average), 'AverageView');

            epochs = makeTestEEG('nbchan', 2, 'trials', 4);
            testCase.verifyEqual(AlakazamPlotter.viewClassFor(epochs), 'EpochView');

            scalp = average;
            scalp.id = 'ScalpDistribution';
            testCase.verifyEqual(AlakazamPlotter.viewClassFor(scalp), 'ScalpDistributionView');

            grandTf = average;
            grandTf.id = 'My grand average';
            grandTf.ersp = ones(2, 3);
            testCase.verifyEqual(AlakazamPlotter.viewClassFor(grandTf), 'TimeFrequencyView', ...
                'A renamed grand average of maps is found by its field, not its id.');

            continuous = makeTestEEG('nbchan', 2, 'DataFormat', 'CONTINUOUS');
            testCase.verifyEmpty(AlakazamPlotter.viewClassFor(continuous), ...
                'Continuous data is plotContinuous''s, not an ERP.');

            single = erp({'Fz'});
            testCase.verifyEmpty(AlakazamPlotter.viewClassFor(single));
        end

        function aDropIsAnOverlayOnlyForAFreshAverageOnAnErp(testCase)
            isOverlay = testCase.copyMethod('isOverlayableAverage');
            target = erp({'Fz', 'Cz', 'Pz'});
            average = erp({'Fz', 'Cz'}, 'srate', 125);
            average.Call = 'Average';
            testCase.verifyTrue(feval(isOverlay, [], target, average), ...
                'A resampled average of another montage is an overlay (its problems are reported), not a replay.');

            measure = target;
            measure.Call = 'Measure';
            testCase.verifyFalse(feval(isOverlay, [], target, measure), ...
                'Dropping Measure onto an average must still add Measure there.');

            scalp = target;
            scalp.id = 'ScalpDistribution';
            testCase.verifyFalse(feval(isOverlay, [], scalp, average), ...
                'A scalp map is not an ERP to overlay on.');
        end

        % ---- the lines -----------------------------------------------------
        function everyLineShowsTheElectrodeInTheTitle(testCase)
        %EVERYLINESHOWSTHEELECTRODEINTHETITLE  The whole point, as a test.
        %   The overlaid dataset has the same three channels in another
        %   order; by position its line for Pz would be Cz's data.
            [view, fig] = testCase.view(erp({'Fz', 'Cz', 'Pz'}, 'file', 'a'));
            closeFig = onCleanup(@() delete(fig));
            other = erp({'Pz', 'Fz', 'Cz'}, 'file', 'b', 'scale', 2);
            testCase.assertEmpty(view.addDataset(other));

            view.applyFocus(struct('Channel', 'Pz'));
            overlaid = lineOf(view, 2);
            testCase.verifyEqual(overlaid.YData, 2 * code('Pz') * other.times / 1000, 'AbsTol', 1e-12);
        end

        function aResampledAverageIsDrawnOnItsOwnTimes(testCase)
            [view, fig] = testCase.view(erp({'Fz', 'Cz'}, 'file', 'a'));
            closeFig = onCleanup(@() delete(fig));
            other = erp({'Fz', 'Cz'}, 'file', 'b', 'srate', 125);

            testCase.assertEmpty(view.addDataset(other));
            testCase.verifyEqual(lineOf(view, 2).XData, other.times, 'AbsTol', 1e-9);
        end

        function aRefusedOverlayLeavesThePlotAlone(testCase)
            [view, fig] = testCase.view(erp({'Fz', 'Cz'}, 'file', 'a'));
            closeFig = onCleanup(@() delete(fig));

            problem = view.addDataset(erp({'EOG1'}, 'file', 'b'));
            testCase.verifySubstring(problem, 'no channel in common');
            testCase.verifyNumElements(view.Series, 1);

            testCase.verifySubstring(view.addDataset(erp({'Fz', 'Cz'}, 'file', 'a')), 'already');
            testCase.verifyNumElements(view.Series, 1);
        end

        function aDatasetWithoutTheChannelSaysSo(testCase)
            [view, fig] = testCase.view(erp({'Fz', 'Cz', 'Oz'}, 'file', 'a'));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(erp({'Fz', 'Cz'}, 'file', 'b')));

            view.applyFocus(struct('Channel', 'Oz'));
            testCase.verifyEmpty(findobj(view.Axes, 'Tag', 'ErpLine', 'UserData', 2), ...
                'A dataset without Oz has no line at Oz.');
            texts = get(findobj(view.CheckboxGrid.Children, 'Type', 'uicheckbox'), 'Text');
            testCase.verifyTrue(any(contains(texts, '(no Oz)')));
        end

        function overlaidDatasetsArePalerAndGoUnderneath(testCase)
            [view, fig] = testCase.view(erp({'Fz', 'Cz'}, 'file', 'a'));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(erp({'Fz', 'Cz'}, 'file', 'b')));
            view.Axes.Color = [1 1 1];

            view.setOverlayOpacity(0.5);
            testCase.verifyEqual(lineOf(view, 1).Color, [0 0 1], 'AbsTol', 1e-12, ...
                'The plot''s own line keeps its colour.');
            testCase.verifyEqual(lineOf(view, 2).Color, [1 0.5 0.5], 'AbsTol', 1e-12);
            children = view.Axes.Children;
            testCase.verifyLessThan(find(children == lineOf(view, 1)), ...
                find(children == lineOf(view, 2)), 'The own line must lie on top.');

            view.setOverlayOpacity(1);
            testCase.verifyEqual(lineOf(view, 2).Color, [1 0 0], 'AbsTol', 1e-12);
        end

        function removingTheOverlayKeepsThePlotsOwnLines(testCase)
            [view, fig] = testCase.view(erp({'Fz', 'Cz'}, 'bins', 2, 'file', 'a'));
            closeFig = onCleanup(@() delete(fig));
            testCase.verifyEmpty(findobj(view.CheckboxGrid.Children, 'Tag', 'RemoveOverlayButton'), ...
                'Nothing to remove before anything is overlaid.');
            testCase.assertEmpty(view.addDataset(erp({'Fz', 'Cz'}, 'file', 'b')));
            button = findobj(view.CheckboxGrid.Children, 'Tag', 'RemoveOverlayButton');
            testCase.assertNotEmpty(button);

            button.ButtonPushedFcn(button, []);

            testCase.verifyNumElements(view.Series, 2, 'The plot''s own two bins stay.');
            testCase.verifyTrue(all(cellfun(@(s) strcmp(s.file, 'a'), view.Series)));
            testCase.verifyNumElements(findobj(view.Axes, 'Tag', 'ErpLine'), 2);
            testCase.verifyEmpty(findobj(view.CheckboxGrid.Children, 'Tag', 'OverlayOpacity'));
            testCase.verifyEmpty(view.addDataset(erp({'Fz', 'Cz'}, 'file', 'b')), ...
                'A removed dataset can be overlaid again.');
        end

        function linesAreNamedByWhatSetsTheirDatasetsApart(testCase)
            [view, fig] = testCase.view(erp({'Fz', 'Cz'}, 'file', 'a'));
            closeFig = onCleanup(@() delete(fig));
            view.setDatasetPath('a', {'S01', 'Filter', 'Average'});
            testCase.assertEmpty(view.addDataset(erp({'Fz', 'Cz'}, 'file', 'b'), ...
                {'S02', 'Filter', 'Average'}));

            testCase.verifyEqual(string(view.Axes.Legend.String), ["S01: Average", "S02: Average"]);
        end

        % ---- the difference -----------------------------------------------
        function theDifferenceIsTheFirstTickedLineMinusTheSecond(testCase)
            eeg = erp({'Fz', 'Cz'}, 'bins', 2);
            [view, fig] = testCase.view(eeg);
            closeFig = onCleanup(@() delete(fig));
            view.applyFocus(struct('Channel', 'Cz'));

            view.setDifference(true);
            testCase.assertTrue(view.DifferenceOn);
            expected = eeg.data(2, :, 1) - eeg.data(2, :, 2);
            testCase.verifyEqual(differenceLine(view).YData, expected, 'AbsTol', 1e-12);

            view.swapDifference();
            testCase.verifyEqual(differenceLine(view).YData, -expected, 'AbsTol', 1e-12);
        end

        function aDifferenceNeedsExactlyTwoLines(testCase)
            [view, fig] = testCase.view(erp({'Fz', 'Cz'}, 'bins', 3));
            closeFig = onCleanup(@() delete(fig));
            button = findobj(view.CheckboxGrid.Children, 'Tag', 'DifferenceButton');
            testCase.verifyFalse(logical(button.Enable), 'Three lines ticked: no difference.');

            view.setDifference(true);
            testCase.verifyFalse(view.DifferenceOn);
        end

        function tickingAThirdLineReturnsToTheLines(testCase)
            [view, fig] = testCase.view(erp({'Fz', 'Cz'}, 'bins', 2));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(erp({'Fz', 'Cz'}, 'file', 'b')));
            click(overlaidBox(view), false);   % two bins left ticked
            view.setDifference(true);
            testCase.assertTrue(view.DifferenceOn);

            click(overlaidBox(view), true);    % and the third one back
            testCase.verifyFalse(view.DifferenceOn);
            testCase.verifyEmpty(findobj(view.Axes, 'Tag', 'DifferenceLine'));
        end

        function aDifferenceAcrossSampleRatesIsInterpolated(testCase)
        %ADIFFERENCEACROSSSAMPLERATESISINTERPOLATED  Linear signals, so
        %   linear interpolation is exact and the expected difference is
        %   known at every one of the first line's time points.
            a = erp({'Fz', 'Cz'}, 'file', 'a', 'scale', 3);
            [view, fig] = testCase.view(a);
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(erp({'Cz', 'Fz'}, 'file', 'b', 'srate', 125)));
            view.applyFocus(struct('Channel', 'Fz'));

            view.setDifference(true);
            expected = (3 - 1) * code('Fz') * a.times / 1000;
            testCase.verifyEqual(differenceLine(view).YData, expected, 'AbsTol', 1e-9);
        end

        % ---- the zoom ------------------------------------------------------
        function aToolbarZoomSurvivesARedraw(testCase)
        %ATOOLBARZOOMSURVIVESAREDRAW  Every channel step or tick redraws the
        %   plot and sets its limits; a zoom made with the axes toolbar (set
        %   here as the toolbar sets it) must come through that.
            [view, fig] = testCase.view(erp({'Fz', 'Cz', 'Pz'}, 'bins', 2));
            closeFig = onCleanup(@() delete(fig));
            view.Axes.XLim = [100 300];
            view.Axes.YLim = [-1 2];

            view.onKey(struct('Key', 'downarrow'));
            testCase.assertEqual(view.Channel, 2, 'The step must have redrawn the plot.');
            testCase.verifyEqual(view.Axes.XLim, [100 300]);
            testCase.verifyEqual(view.Axes.YLim, [-1 2]);

            view.setOverlayOpacity(0.7);   % any other redraw
            testCase.verifyEqual(view.Axes.YLim, [-1 2]);
        end

        function restoreViewReturnsToAutomaticScaling(testCase)
            [view, fig] = testCase.view(erp({'Fz', 'Cz'}, 'bins', 2));
            closeFig = onCleanup(@() delete(fig));
            automatic = [view.Axes.XLim; view.Axes.YLim];
            view.Axes.XLim = [100 300];
            view.Axes.YLim = [-1 2];
            view.onKey(struct('Key', 'downarrow'));
            view.onKey(struct('Key', 'uparrow'));

            restore = findobj(view.Axes.Toolbar.Children, 'Tag', 'RestoreView');
            testCase.assertNotEmpty(restore, 'Restore view must be the view''s own button.');
            restore.ButtonPushedFcn(restore, []);

            testCase.verifyEqual([view.Axes.XLim; view.Axes.YLim], automatic, 'AbsTol', 1e-9);
        end

        function theDifferenceHasItsOwnAmplitudeZoom(testCase)
            [view, fig] = testCase.view(erp({'Fz', 'Cz'}, 'bins', 2));
            closeFig = onCleanup(@() delete(fig));
            view.Axes.XLim = [100 300];
            view.Axes.YLim = [-100 100];

            view.setDifference(true);
            testCase.verifyEqual(view.Axes.XLim, [100 300], 'The time zoom is shared.');
            testCase.verifyNotEqual(view.Axes.YLim, [-100 100], ...
                'The lines'' amplitude zoom must not squash the difference.');

            view.setDifference(false);
            testCase.verifyEqual(view.Axes.YLim, [-100 100], 'The lines keep their own zoom.');
        end

        % ---- where a line's name comes from -----------------------------
        function namesKeepOnlyWhatDiffers(testCase)
            names = overlayNames({{'S01', 'Filter', 'Average'}, {'S02', 'Filter', 'Average'}});
            testCase.verifyEqual(names, ["S01", "S02"]);

            names = overlayNames({{'S01', 'Filter 30', 'DefineBins', 'Average'}, ...
                                  {'S01', 'Filter 40', 'DefineBins', 'Average'}});
            testCase.verifyEqual(names, ["Filter 30", "Filter 40"]);
        end

        function identicalPathsAreNumbered(testCase)
            names = overlayNames({{'S01', 'Filter', 'Average'}, {'S01', 'Filter', 'Average'}});
            testCase.verifyEqual(names, ["Average [1]", "Average [2]"]);
        end

        function aLongDifferenceIsShortenedAndTheFullPathKept(testCase)
            [names, full] = overlayNames({{'N400 grand'}, {'S01', 'Filter', 'ReRef', 'DefineBins', 'Average'}});
            testCase.verifyEqual(names(1), "N400 grand");
            testCase.verifyEqual(names(2), "S01 / " + char(8230) + " / Average");
            testCase.verifyEqual(full(2), "S01 / Filter / ReRef / DefineBins / Average");
        end

        function theTreeGivesANodesPath(testCase)
            try
                fig = uifigure('Visible', 'off');
                tree = WorkSpaceTree(fig);
            catch ME
                testCase.assumeFail(['A uifigure with a uihtml tree could not be created here: ' ME.message]);
            end
            closeFig = onCleanup(@() delete(fig));
            root = tree.addNode('S01', '', '', 'root.mat');
            filter = tree.addNode('Filter', root.Id, '', 'filter.mat');
            average = tree.addNode('Average', filter.Id, '', 'average.mat');

            testCase.verifyEqual(tree.findByFile('average.mat'), average.Id);
            testCase.verifyEqual(tree.pathOf(average.Id), {'S01', 'Filter', 'Average'});
            testCase.verifyEmpty(tree.findByFile('elsewhere.mat'));
        end
    end

    methods (Access = private)
        function [view, fig] = view(testCase, eeg)
            fig = uifigure('Visible', 'off');
            tab = uitab(uitabgroup(fig));
            view = AverageView(tab, eeg);
            testCase.assertNotEmpty(view);
        end

        function name = copyMethod(testCase, method)
            name = MethodCopy.make(testCase.Folder, '@Alakazam', method, ['copy_' method]);
            rehash;
        end
    end
end

% ======================================================================= %
function eeg = erp(labels, varargin)
%ERP  An averaged dataset whose every value is known: at the channel called
%   L, bin B holds SCALE * CODE(L) * t / B (t in s), so a line can be told
%   by its values which electrode and dataset it came from.
    p = inputParser;
    p.addParameter('srate', 250);
    p.addParameter('bins', 0);
    p.addParameter('file', 'fixture');
    p.addParameter('scale', 1);
    p.parse(varargin{:});
    o = p.Results;

    eeg = makeTestEEG('nbchan', numel(labels), 'labels', labels, 'trials', 1, 'srate', o.srate);
    eeg.DataFormat = 'Averaged';
    eeg.trials = 1;
    eeg.File = o.file;
    eeg.id = 'Average';
    t = eeg.times / 1000;
    nBins = max(o.bins, 1);
    eeg.data = zeros(numel(labels), numel(t), nBins);
    for b = 1:nBins
        for c = 1:numel(labels)
            eeg.data(c, :, b) = o.scale * code(labels{c}) * t / b;
        end
    end
    eeg.stErr = zeros(size(eeg.data));
    if o.bins > 0
        eeg.bindesc = struct('label', arrayfun(@(b) sprintf('Bin %d', b), 1:nBins, ...
            'UniformOutput', false));
    end
end

function c = code(label)
%CODE  A number per electrode name, the same in every dataset.
    c = find(strcmpi({'Fz', 'Cz', 'Pz', 'Oz', 'EOG1'}, label), 1);
end

function h = lineOf(view, series)
    h = findobj(view.Axes, 'Tag', 'ErpLine', 'UserData', series);
end

function h = differenceLine(view)
    h = findobj(view.Axes, 'Tag', 'DifferenceLine');
end

function box = overlaidBox(view)
%OVERLAIDBOX  The tickbox of the overlaid dataset's single line, the one not
%   named after a bin.
    boxes = findobj(view.CheckboxGrid.Children, 'Type', 'uicheckbox');
    box = boxes(~contains(get(boxes, 'Text'), 'Bin'));
    assert(isscalar(box), 'Expected one tickbox for the overlaid dataset.');
end

function click(box, value)
%CLICK  Tick or untick BOX as a user would, running its callback.
    box.Value = value;
    box.ValueChangedFcn(box, []);
end
