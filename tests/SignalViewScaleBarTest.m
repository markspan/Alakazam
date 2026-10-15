classdef SignalViewScaleBarTest < matlab.unittest.TestCase
%SIGNALVIEWSCALEBARTEST  The scale bar left of a continuous recording's
%   channel labels: an I as long as the microvolts its label gives, at the
%   current magnification, and never more than a tenth of the plot's height.
%
%   Run with: runtests('tests/SignalViewScaleBarTest.m').
%
%   See also SIGNALVIEW, SIGNALVIEWBASELINETEST.

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
        function itStandsForANiceNumberWithinATenth(testCase)
            testCase.verifyEqual(SignalView.scaleMicrovolts(1000, 0.1), 100);
            testCase.verifyEqual(SignalView.scaleMicrovolts(999, 0.1), 50);
            testCase.verifyEqual(SignalView.scaleMicrovolts(30, 0.1), 2);
            testCase.verifyEqual(SignalView.scaleMicrovolts(0.07, 0.1), 0.005, 'AbsTol', 1e-15);
            testCase.verifyEqual(SignalView.scaleMicrovolts(45000, 0.1), 2000);
        end

        function itsLabelIsPrettyPrinted(testCase)
            testCase.verifyEqual(SignalView.scaleLabel(50), ['50 ' char(181) 'V']);
            testCase.verifyEqual(SignalView.scaleLabel(0.5), ['0.5 ' char(181) 'V']);
            testCase.verifyEqual(SignalView.scaleLabel(2000), '2 mV');
        end

        function theBarIsAsLongAsItsLabelSaysAndFollowsTheMagnification(testCase)
            [view, fig] = testCase.view(recording());
            testCase.addTeardown(@() delete(fig));
            view.redraw();
            drawnow;
            view.redraw();
            first = testCase.verifyBar(view);

            view.ScaleSlider.Value = view.ScaleSlider.Value * 4;
            view.redraw();
            second = testCase.verifyBar(view);
            testCase.verifyLessThan(second, first, 'Magnified four times, the bar stands for fewer microvolts.');
        end
    end

    methods (Access = private)
        function microvolts = verifyBar(testCase, view)
        %VERIFYBAR  The bar is an I, its length in the plot's units is its
        %   microvolts at the magnification, no more than a tenth of the
        %   plot's height, and its label says so.
            microvolts = view.ScaleMicrovolts;
            testCase.assertTrue(isfinite(microvolts), 'The bar stands for nothing.');
            testCase.verifyEqual(char(view.ScaleText.String), SignalView.scaleLabel(microvolts));
            y = view.ScaleBar.YData;
            testCase.verifyNumElements(y, 8, 'Two caps and a stem, as an I.');
            barPx = max(y) - min(y);
            plotPx = view.Axes.InnerPosition(4);
            expectedPx = microvolts * view.ScaleSlider.Value / diff(view.Axes.YLim) * plotPx;
            testCase.verifyEqual(barPx, expectedPx, 'RelTol', 1e-9);
            testCase.verifyLessThanOrEqual(barPx, 0.1 * plotPx + 1e-9);
            testCase.verifyGreaterThan(barPx, 0.02 * plotPx, 'A bar too short to read.');
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

function eeg = recording()
%RECORDING  Four channels of 8 s at 250 Hz: sines of 20 to 80 uV.
    srate = 250;
    t = (0:8 * srate - 1) / srate;
    labels = {'Fz', 'Cz', 'Pz', 'Oz'};
    eeg = struct('srate', srate, 'nbchan', 4, 'trials', 1, 'pnts', numel(t), 'times', t, ...
        'DataFormat', 'CONTINUOUS', 'DataType', 'TimeDomain', ...
        'chanlocs', struct('labels', labels), 'event', [], 'File', 'fixture', 'id', 'Filter');
    eeg.data = (20:20:80)' .* sin(2 * pi * [3; 5; 7; 9] .* t);
end
