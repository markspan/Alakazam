classdef FourierViewPhaseTest < matlab.unittest.TestCase
%FOURIERVIEWPHASETEST  The Fourier view's P key shows the phase of a complex
%   spectrum wrapped to [-pi, pi], as points on an axis of exactly that
%   range, and P again gives the magnitude back with nothing of the phase
%   left on the axis.
%
%   The phase used to be unwrapped across frequency. Fourier measures phase
%   from the segment's first sample, so a spectrum carries a ramp of 2*pi*f
%   times the time its activity is centred on, and unwrapping summed that
%   ramp over every bin: on a long recording a straight line tens of
%   thousands of radians tall. It was drawn on an axis starting at 0, which
%   showed it only because Fourier stored the conjugate spectrum and the
%   ramp went up (FourierTest pins the sign now).
%
%   Run with: runtests('tests/FourierViewPhaseTest.m').
%
%   See also FOURIERVIEW, ZOOMPANBUTTONS, FOURIERTEST.

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
        function pShowsTheWrappedPhaseFromMinusPiToPi(testCase)
            [view, cleanup] = testCase.openView(); %#ok<ASGLU>

            view.onKey(struct('Key', 'p'));

            points = findobj(view.Axes, 'Type', 'line');
            testCase.assertNumElements(points, 1);
            testCase.verifyEqual(char(points.LineStyle), 'none', 'Points, not a line.');
            testCase.verifyLessThanOrEqual(max(abs(points.YData)), pi + 1e-12, ...
                'Wrapped: unwrapped, this ramp reaches about 3.8e4 rad by 100 Hz.');
            testCase.verifyEqual(ylim(view.Axes), [-pi, pi], 'AbsTol', 1e-12, ...
                'The whole circle is in view, not just its upper half.');
            testCase.verifyEqual(char(view.Axes.YLabel.String), 'phase (rad)');
        end

        function pAgainGivesTheMagnitudeBack(testCase)
            [view, cleanup] = testCase.openView(); %#ok<ASGLU>

            view.onKey(struct('Key', 'p'));
            view.onKey(struct('Key', 'p'));

            limits = ylim(view.Axes);
            testCase.verifyEqual(limits(1), 0, 'A magnitude axis starts at 0.');
            testCase.verifyEmpty(view.Axes.YLabel.String, 'The phase label does not linger.');
            testCase.verifyEqual(char(view.Axes.YTickMode), 'auto', 'Nor do the multiples of pi.');
        end
    end

    methods (Access = private)
        function [view, cleanup] = openView(testCase)
            try
                fig = uifigure('Visible', 'off');
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            cleanup = onCleanup(@() delete(fig));
            view = FourierView(uitab(uitabgroup(fig)), FourierViewPhaseTest.spectrum());
        end
    end

    methods (Static)
        function EEG = spectrum()
        %SPECTRUM  A complex spectrum like Fourier's for a long recording: unit
        %   magnitude, and the phase ramp of activity centred 60 s after the
        %   segment's first sample, exp(-i*2*pi*f*60), on two channels.
            srate = 250;
            freqs = linspace(0, srate / 2, 4097);
            ramp = exp(-1i * 2 * pi * freqs * 60);
            EEG = struct('data', [ramp; ramp], 'freqs', freqs, 'srate', srate, ...
                'nbchan', 2, 'trials', 1, 'pnts', numel(freqs), ...
                'DataType', 'FrequencyDomain', 'DataFormat', 'CONTINUOUS', ...
                'chanlocs', struct('labels', {'Fz', 'Cz'}));
        end
    end
end
