classdef ContinuousOverlayTest < matlab.unittest.TestCase
%CONTINUOUSOVERLAYTEST  One continuous recording drawn under another, and
%   their difference, in SignalView.
%
%   The same rule as ErpOverlayTest: channels by name and each recording on
%   its own time axis, never by position or shape. Every recording here is a
%   set of straight lines, CODE(label) * SCALE * t, so a drawn point says by
%   its value which electrode and which recording it came from, and linear
%   interpolation between two sampling rates is exact.
%
%   The view is zoomed in far enough to draw raw samples, so every drawn
%   point can be checked against that arithmetic; the zoomed-out path goes
%   through the same min/max pyramid redraw already uses for the recording
%   itself.
%
%   Run with: runtests('tests/ContinuousOverlayTest.m').
%
%   See also SIGNALVIEW, DATASETOVERLAYPROBLEM, ERPOVERLAYTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function centreChannelsByTheirMedians(testCase)
        %CENTRECHANNELSBYTHEIRMEDIANS  These cases are about which lane a
        %   channel is drawn in, read against its median-centred position;
        %   the view-on-screen baseline has a test of its own
        %   (SignalViewBaselineTest). In memory only, and put back.
            was = AlakazamSettings.get('graphics', 'signalPlot', 'viewBaseline');
            testCase.addTeardown(@() AlakazamSettings.set('graphics', 'signalPlot', 'viewBaseline', was));
            AlakazamSettings.set('graphics', 'signalPlot', 'viewBaseline', false);
        end
    end

    methods (Test)
        function eachChannelIsDrawnInTheLaneOfItsName(testCase)
        %EACHCHANNELISDRAWNINTHELANEOFITSNAME  The overlaid recording has the
        %   same channels in another order; by position, Fz's lane would get
        %   Pz's signal.
            [view, fig] = testCase.view(recording({'Fz', 'Cz', 'Pz'}, 'file', 'own'));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(recording({'Pz', 'Fz', 'Cz'}, 'file', 'other', 'scale', 2)));
            zoomIn(view);

            lanes = findobj(view.Axes, 'Tag', 'OverlayLine');
            testCase.assertNumElements(lanes, 3);
            for lane = lanes'
                c = lane.UserData;
                expected = 2 * code(view.ChannelLabels{c}) * lane.XData + view.StackOffset(c);
                testCase.verifyEqual(lane.YData, expected, 'AbsTol', 1e-9, ...
                    sprintf('The %s lane shows another channel.', view.ChannelLabels{c}));
            end
        end

        function aResampledRecordingIsDrawnOnItsOwnTimes(testCase)
            [view, fig] = testCase.view(recording({'Fz', 'Cz'}, 'file', 'own'));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(recording({'Fz', 'Cz'}, 'file', 'other', 'srate', 125)));
            zoomIn(view);

            lane = findobj(view.Axes, 'Tag', 'OverlayLine', 'UserData', 1);
            onItsGrid = abs(lane.XData * 125 - round(lane.XData * 125)) < 1e-6;
            testCase.verifyTrue(all(onItsGrid), 'The overlay''s points are its own samples.');
            testCase.verifyEqual(lane.YData, code('Fz') * lane.XData + view.StackOffset(1), 'AbsTol', 1e-9);
        end

        function whatCannotBeOverlaidIsRefusedWithTheReason(testCase)
            [view, fig] = testCase.view(recording({'Fz', 'Cz'}, 'file', 'own'));
            closeFig = onCleanup(@() delete(fig));

            testCase.verifySubstring(view.addDataset(recording({'EOG1'}, 'file', 'eog')), ...
                'no channel in common');
            testCase.verifySubstring(view.addDataset(recording({'Fz'}, 'file', 'late', 'start', 100)), ...
                'does not overlap');
            testCase.verifySubstring(view.addDataset(recording({'Fz'}, 'file', 'own')), 'own dataset');
            testCase.verifyEmpty(view.OverlaidDataset);
            testCase.verifyEqual(view.Grid.RowHeight{5}, 0, 'No controls without an overlay.');

            testCase.assertEmpty(view.addDataset(recording({'Fz'}, 'file', 'other')));
            testCase.verifySubstring(view.addDataset(recording({'Fz'}, 'file', 'other')), 'already');
        end

        function aSecondOverlayReplacesTheFirst(testCase)
            [view, fig] = testCase.view(recording({'Fz', 'Cz'}, 'file', 'own'));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(recording({'Fz', 'Cz'}, 'file', 'first')));
            testCase.assertEmpty(view.addDataset(recording({'Fz'}, 'file', 'second')));

            testCase.verifyEqual(view.OverlaidDataset.file, 'second');
            testCase.verifyNumElements(findobj(view.Axes, 'Tag', 'OverlayLine'), 1);
        end

        function theDifferenceIsThisRecordingMinusTheOther(testCase)
            [view, fig] = testCase.view(recording({'Fz', 'Cz'}, 'file', 'own', 'scale', 3));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(recording({'Cz', 'Fz'}, 'file', 'other')));
            zoomIn(view);

            view.setDifference(true);
            testCase.assertTrue(view.DifferenceOn);
            for c = 1:2
                own = view.Lines(c);
                expected = (3 - 1) * code(view.ChannelLabels{c}) * own.XData + view.StackOffset(c);
                testCase.verifyEqual(own.YData, expected, 'AbsTol', 1e-9);
            end
            testCase.verifyEqual(char(findobj(view.Axes, 'Tag', 'OverlayLine', 'UserData', 1).Visible), 'off', ...
                'The overlay itself is not drawn over its own difference.');
        end

        function aDifferenceAcrossSampleRatesIsInterpolated(testCase)
            [view, fig] = testCase.view(recording({'Fz', 'Cz'}, 'file', 'own', 'scale', 3));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(recording({'Fz', 'Cz'}, 'file', 'other', 'srate', 125)));
            zoomIn(view);

            view.setDifference(true);
            own = view.Lines(2);
            expected = (3 - 1) * code('Cz') * own.XData + view.StackOffset(2);
            testCase.verifyEqual(own.YData, expected, 'AbsTol', 1e-9);
        end

        function aChannelOnlyThisRecordingHasIsEmptyInTheDifference(testCase)
            [view, fig] = testCase.view(recording({'Fz', 'Cz', 'Oz'}, 'file', 'own'));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(recording({'Fz', 'Cz'}, 'file', 'other')));
            zoomIn(view);

            view.setDifference(true);
            testCase.verifyTrue(all(isnan(view.Lines(3).YData)), ...
                'Oz has nothing to be subtracted from it.');
            view.setDifference(false);
            testCase.verifyFalse(any(isnan(view.Lines(3).YData)), 'Oz is back without the difference.');
        end

        function removingTheOverlayRestoresTheRecording(testCase)
            [view, fig] = testCase.view(recording({'Fz', 'Cz'}, 'file', 'own'));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(recording({'Fz', 'Cz'}, 'file', 'other', 'scale', 2)));
            zoomIn(view);
            view.setDifference(true);
            testCase.assertEqual(view.Grid.RowHeight{5}, 24);

            remove = findobj(view.OverlayRow.Children, 'Tag', 'RemoveOverlayButton');
            remove.ButtonPushedFcn(remove, []);

            testCase.verifyEmpty(view.OverlaidDataset);
            testCase.verifyFalse(view.DifferenceOn);
            testCase.verifyEmpty(findobj(view.Axes, 'Tag', 'OverlayLine'));
            testCase.verifyEqual(view.Grid.RowHeight{5}, 0);
            own = view.Lines(1);
            testCase.verifyEqual(own.YData, code('Fz') * own.XData + view.StackOffset(1), 'AbsTol', 1e-9, ...
                'The recording''s own signal is drawn again.');
        end

        function theOverlayIsAGreyGhostSetByTheSlider(testCase)
            [view, fig] = testCase.view(recording({'Fz', 'Cz'}, 'file', 'own'));
            closeFig = onCleanup(@() delete(fig));
            view.Axes.Color = [1 1 1];
            testCase.assertEmpty(view.addDataset(recording({'Fz', 'Cz'}, 'file', 'other')));

            lane = findobj(view.Axes, 'Tag', 'OverlayLine', 'UserData', 1);
            testCase.verifyEqual(lane.Color, [0.5 0.5 0.5], 'AbsTol', 1e-12);
            children = view.Axes.Children;
            testCase.verifyGreaterThan(find(children == lane), find(children == view.Lines(1)), ...
                'The overlay must lie underneath the recording''s own lines.');

            view.setOverlayOpacity(1);
            testCase.verifyEqual(lane.Color, [0 0 0], 'AbsTol', 1e-12);
        end

        function theControlsNameTheRecordings(testCase)
            [view, fig] = testCase.view(recording({'Fz', 'Cz'}, 'file', 'own'));
            closeFig = onCleanup(@() delete(fig));
            view.setDatasetPath('own', {'S01', 'Filter'});
            testCase.assertEmpty(view.addDataset(recording({'Fz', 'Cz'}, 'file', 'other'), {'S01', 'No filter'}));

            testCase.verifyEqual(view.OverlayNameLabel.Text, 'No filter');
            view.setDifference(true);
            testCase.verifyEqual(view.OverlayNameLabel.Text, ['Filter ' char(8722) ' No filter']);
        end
    end

    methods (Access = private)
        function [view, fig] = view(testCase, eeg)
        %VIEW  A SignalView as AlakazamPlotter.plotContinuous builds one.
            fig = uifigure('Visible', 'off', 'Position', [100 100 900 500]);
            tab = uitab(uitabgroup(fig, 'Position', [0 0 900 500]));
            view = SignalView(tab, eeg.times, eeg, ...
                "ShowAxisTicks", true, "YLimMode", "fixed", "MmPerSec", 25, ...
                "AutoStackSignals", string({eeg.chanlocs.labels}));
            testCase.assertNotEmpty(view);
        end
    end
end

% ======================================================================= %
function eeg = recording(labels, varargin)
%RECORDING  A continuous dataset of straight lines: at the channel called L,
%   SCALE * CODE(L) * t, t in seconds from START.
    p = inputParser;
    p.addParameter('srate', 250);
    p.addParameter('seconds', 4);
    p.addParameter('start', 0);
    p.addParameter('scale', 1);
    p.addParameter('file', 'fixture');
    p.parse(varargin{:});
    o = p.Results;

    t = o.start + (0:round(o.seconds * o.srate) - 1) / o.srate;
    eeg = struct('srate', o.srate, 'nbchan', numel(labels), 'trials', 1, ...
        'pnts', numel(t), 'times', t, 'DataFormat', 'CONTINUOUS', 'DataType', 'TimeDomain', ...
        'chanlocs', struct('labels', labels), 'event', [], 'File', o.file, 'id', 'Filter');
    eeg.data = zeros(numel(labels), numel(t));
    for c = 1:numel(labels)
        eeg.data(c, :) = o.scale * code(labels{c}) * t;
    end
end

function c = code(label)
%CODE  A number per electrode name, the same in every recording.
    c = find(strcmpi({'Fz', 'Cz', 'Pz', 'Oz', 'EOG1'}, label), 1);
end

function zoomIn(view)
%ZOOMIN  Close enough that raw samples are drawn, not a min/max envelope,
%   and in the middle of the recording.
    view.ZoomSlider.Value = 0.9;
    view.ScrollSlider.Value = 0.5;
    view.redraw();
end
