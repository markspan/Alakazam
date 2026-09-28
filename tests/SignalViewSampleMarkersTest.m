classdef SignalViewSampleMarkersTest < matlab.unittest.TestCase
%SIGNALVIEWSAMPLEMARKERSTEST  Zoomed in far enough, SignalView marks every
%   sample with a small filled circle.
%
%   The rule: fewer samples in view than half the axes' width in pixels, so
%   that every sample has two pixels or more to itself. Below that the marks
%   would merge into a thick line and hide the signal they mark. The cases
%   check the rule from both sides, and that an overlaid recording follows
%   it by its own sampling rate, not the plot's.
%
%   Run with: runtests('tests/SignalViewSampleMarkersTest.m').
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
        function zoomedInEverySampleIsAFilledCircle(testCase)
            [view, fig] = testCase.view(recording(250, 'own'));
            closeFig = onCleanup(@() delete(fig));
            showSamples(view, 20);

            for h = view.Lines
                testCase.verifyEqual(char(h.Marker), 'o');
                testCase.verifyEqual(h.MarkerFaceColor, h.Color, 'A mark is filled in its line''s colour.');
            end
        end

        function zoomedOutThereAreNoMarks(testCase)
            [view, fig] = testCase.view(recording(250, 'own'));
            closeFig = onCleanup(@() delete(fig));
            showSamples(view, 20);
            view.ZoomSlider.Value = 0;
            view.redraw();

            testCase.verifyTrue(all(arrayfun(@(h) strcmp(h.Marker, 'none'), view.Lines)));
        end

        function theThresholdIsHalfTheWidthInPixels(testCase)
            [view, fig] = testCase.view(recording(250, 'own'));
            closeFig = onCleanup(@() delete(fig));
            half = view.AxWidthPx / 2;

            showSamples(view, floor(half) - 3);
            testCase.verifyEqual(char(view.Lines(1).Marker), 'o', 'Just under half: marked.');
            showSamples(view, ceil(half) + 3);
            testCase.verifyEqual(char(view.Lines(1).Marker), 'none', 'Just over half: not.');
        end

        function anOverlaidRecordingIsMarkedByItsOwnSampling(testCase)
        %ANOVERLAIDRECORDINGISMARKEDBYITSOWNSAMPLING  At half the plot's
        %   sampling rate the overlay has half as many samples in view, so
        %   there is a zoom at which it is marked and the plot is not.
            [view, fig] = testCase.view(recording(250, 'own'));
            closeFig = onCleanup(@() delete(fig));
            testCase.assertEmpty(view.addDataset(recording(125, 'other')));
            showSamples(view, round(0.75 * view.AxWidthPx));

            ghost = findobj(view.Axes, 'Tag', 'OverlayLine');
            testCase.verifyEqual(char(view.Lines(1).Marker), 'none');
            testCase.verifyTrue(all(arrayfun(@(h) strcmp(h.Marker, 'o'), ghost)));

            view.setOverlayOpacity(1);
            testCase.verifyEqual(ghost(1).MarkerFaceColor, [0 0 0], 'AbsTol', 1e-12, ...
                'The marks follow the opacity.');
        end
    end

    methods (Access = private)
        function [view, fig] = view(testCase, eeg)
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
function eeg = recording(srate, file)
%RECORDING  Twenty seconds of three channels at SRATE.
    labels = {'Fz', 'Cz', 'Pz'};
    t = (0:20 * srate - 1) / srate;
    eeg = struct('srate', srate, 'nbchan', 3, 'trials', 1, 'pnts', numel(t), 'times', t, ...
        'DataFormat', 'CONTINUOUS', 'DataType', 'TimeDomain', ...
        'chanlocs', struct('labels', labels), 'event', [], 'File', file, 'id', 'Filter');
    eeg.data = [sin(2 * pi * 3 * t); cos(2 * pi * 5 * t); sin(2 * pi * 7 * t)];
end

function showSamples(view, n)
%SHOWSAMPLES  Zoom so that about N samples of the plot's recording are in
%   view (redraw shows the samples from startIndex to startIndex + numPoints).
    numPoints = max(2, n - 1);
    view.ZoomSlider.Value = min(1, max(0, log(numPoints / view.NumSamples) / view.ZoomDecay));
    view.ScrollSlider.Value = 0.5;
    view.redraw();
end
