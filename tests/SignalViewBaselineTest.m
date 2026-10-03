classdef SignalViewBaselineTest < matlab.unittest.TestCase
%SIGNALVIEWBASELINETEST  Where a continuous recording's channels are drawn:
%   starting at their labels on the left (the view-on-screen baseline), or,
%   with it off, centred by their medians; and magnified about that point.
%
%   Drifting channels used to wander across the screen as the view was
%   zoomed and scrolled, since each was centred by its median over the whole
%   recording, and the mag slider scaled the samples but not the offset that
%   centred them. The recording here is straight lines with a DC level, so
%   every channel's value at the left edge of any window is known exactly.
%
%   Run with: runtests('tests/SignalViewBaselineTest.m').
%
%   See also SIGNALVIEW, CONTINUOUSOVERLAYTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function eachChannelStartsAtItsLabelWhereverTheViewIs(testCase)
            testCase.pinViewBaseline(true);
            eeg = recording({'Fz', 'Cz', 'Pz'});
            [view, fig] = testCase.view(eeg);
            closeFig = onCleanup(@() delete(fig));

            for position = [0.5, 0.2, 0.8]
                show(view, 0.9, position);
                for c = 1:3
                    line = view.Lines(c);
                    testCase.verifyEqual(line.YData(1), view.StackTick(c), 'AbsTol', 1e-9, ...
                        sprintf('%s does not start at its label (scroll %.1f).', eeg.chanlocs(c).labels, position));
                    expected = valueOf(eeg, c, line.XData) - valueOf(eeg, c, line.XData(1)) + view.StackTick(c);
                    testCase.verifyEqual(line.YData, expected, 'AbsTol', 1e-9);
                end
            end
        end

        function magnifyingKeepsTheStartAtTheLabel(testCase)
            testCase.pinViewBaseline(true);
            eeg = recording({'Fz', 'Cz'});
            [view, fig] = testCase.view(eeg);
            closeFig = onCleanup(@() delete(fig));
            view.ScaleSlider.Value = 3;
            show(view, 0.9, 0.5);

            line = view.Lines(2);
            testCase.verifyEqual(line.YData(1), view.StackTick(2), 'AbsTol', 1e-9);
            expected = 3 * (valueOf(eeg, 2, line.XData) - valueOf(eeg, 2, line.XData(1))) + view.StackTick(2);
            testCase.verifyEqual(line.YData, expected, 'AbsTol', 1e-9);
        end

        function zoomedOutTheFirstPixelSitsAtTheLabel(testCase)
        %ZOOMEDOUTTHEFIRSTPIXELSITSATTHELABEL  A long recording, drawn as a
        %   min/max envelope: the first pixel's samples straddle the label.
            testCase.pinViewBaseline(true);
            eeg = recording({'Fz', 'Cz'}, 'seconds', 120);
            [view, fig] = testCase.view(eeg);
            closeFig = onCleanup(@() delete(fig));
            show(view, 0, 0);
            testCase.assumeLessThan(numel(view.Lines(1).YData), eeg.pnts, ...
                'The recording is not long enough to be drawn as an envelope here.');

            for c = 1:2
                testCase.verifyLessThan(abs(view.Lines(c).YData(1) - view.StackTick(c)), ...
                    0.01 * view.LaneSpacing, sprintf('%s does not start at its label.', eeg.chanlocs(c).labels));
            end
        end

        function aRejectedStartIsPassedOver(testCase)
        %AREJECTEDSTARTISPASSEDOVER  A channel whose first samples in view are
        %   rejected (NaN) starts at its label at its first sample that is not.
            testCase.pinViewBaseline(true);
            eeg = recording({'Fz', 'Cz'});
            eeg.data(1, 1:20) = NaN;
            [view, fig] = testCase.view(eeg);
            closeFig = onCleanup(@() delete(fig));
            show(view, 0.7, 0);   % about 38 samples in view, the first 20 rejected

            y = view.Lines(1).YData;
            testCase.assertTrue(isnan(y(1)), 'The view does not start in the rejected samples.');
            first = find(isfinite(y), 1);
            testCase.assertNotEmpty(first);
            testCase.verifyEqual(y(first), view.StackTick(1), 'AbsTol', 1e-9);
            testCase.verifyEqual(view.Lines(2).YData(1), view.StackTick(2), 'AbsTol', 1e-9, ...
                'The other channel is not affected.');
        end

        function offEachChannelIsCentredByItsMedianAndMagnifiedAboutIt(testCase)
        %OFFEACHCHANNELISCENTREDBYITSMEDIANANDMAGNIFIEDABOUTIT  The median
        %   comes off before the magnification: the trace stays on its row.
            testCase.pinViewBaseline(false);
            eeg = recording({'Fz', 'Cz'});
            [view, fig] = testCase.view(eeg);
            closeFig = onCleanup(@() delete(fig));
            view.ScaleSlider.Value = 3;
            show(view, 0.9, 0.5);

            line = view.Lines(2);
            centre = median(eeg.data(2, :));
            testCase.verifyEqual(line.YData, 3 * (valueOf(eeg, 2, line.XData) - centre) + view.StackTick(2), ...
                'AbsTol', 1e-9);
        end

        function theOverlayAndTheDifferenceStartAtTheLabelsToo(testCase)
            testCase.pinViewBaseline(true);
            eeg = recording({'Fz', 'Cz'});
            other = recording({'Fz', 'Cz'}, 'dc', -400, 'file', 'other');
            [view, fig] = testCase.view(eeg);
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(other, {'S01', 'Other'}));
            show(view, 0.9, 0.5);

            for c = 1:2
                ghost = findobj(view.Axes, 'Tag', 'OverlayLine', 'UserData', c);
                testCase.verifyEqual(ghost.YData(1), view.StackTick(c), 'AbsTol', 1e-9, ...
                    'The overlaid recording starts at the label.');
            end
            view.setDifference(true);
            for c = 1:2
                testCase.verifyEqual(view.Lines(c).YData(1), view.StackTick(c), 'AbsTol', 1e-9, ...
                    'The difference starts at the label.');
            end
        end
    end

    methods (Access = private)
        function pinViewBaseline(testCase, on)
        %PINVIEWBASELINE  The setting these cases assume, in memory only, and
        %   put back afterwards.
            was = AlakazamSettings.get('graphics', 'signalPlot', 'viewBaseline');
            testCase.addTeardown(@() AlakazamSettings.set('graphics', 'signalPlot', 'viewBaseline', was));
            AlakazamSettings.set('graphics', 'signalPlot', 'viewBaseline', on);
        end

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
%RECORDING  A continuous recording of drifting lines: at the channel called L,
%   DC + 100 * CODE(L) + 20 * CODE(L) * t, t in seconds, so each has its own
%   DC level and drift.
    p = inputParser;
    p.addParameter('srate', 250);
    p.addParameter('seconds', 8);
    p.addParameter('dc', 0);
    p.addParameter('file', 'fixture');
    p.parse(varargin{:});
    o = p.Results;

    t = (0:round(o.seconds * o.srate) - 1) / o.srate;
    eeg = struct('srate', o.srate, 'nbchan', numel(labels), 'trials', 1, ...
        'pnts', numel(t), 'times', t, 'DataFormat', 'CONTINUOUS', 'DataType', 'TimeDomain', ...
        'chanlocs', struct('labels', labels), 'event', [], 'File', o.file, 'id', 'Filter');
    eeg.data = zeros(numel(labels), numel(t));
    for c = 1:numel(labels)
        eeg.data(c, :) = o.dc + 100 * code(labels{c}) + 20 * code(labels{c}) * t;
    end
end

function v = valueOf(eeg, c, t)
%VALUEOF  Channel C of RECORDING at times T.
    k = code(eeg.chanlocs(c).labels);
    v = eeg.data(c, 1) + 20 * k * t;   % its value at t = 0, plus its drift
end

function c = code(label)
    c = find(strcmpi({'Fz', 'Cz', 'Pz', 'Oz'}, label), 1);
end

function show(view, zoom, position)
%SHOW  The view at ZOOM (0 the whole recording, 0.9 close enough to draw raw
%   samples) and scrolled to POSITION (0 the start, 1 the end).
    view.ZoomSlider.Value = zoom;
    view.ScrollSlider.Value = position;
    view.redraw();
end
