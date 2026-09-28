classdef FourierViewBinsTest < matlab.unittest.TestCase
%FOURIERVIEWBINSTEST  An averaged spectrum overlays its bins, as AverageView
%   overlays ERPs: a line per ticked bin in the bin's own colour, over a
%   band of standard errors where Average stored them; with two bins ticked,
%   their difference, their ratio in dB (10*log10 for a power, 20*log10 for
%   an amplitude) or, on a complex spectrum with the phase shown, the phase
%   of one relative to the other; and a log scale that is off until asked
%   for.
%
%   The fixture's spectra are flat, each at a level of its own, so that the
%   optional smoothing of the plotted spectrum (Settings) leaves them as
%   they are and every expected value is exact. The strip beside the plot is
%   rebuilt on every redraw, so each helper finds its control afresh.
%
%   Run with: runtests('tests/FourierViewBinsTest.m').
%
%   See also FOURIERVIEW, LINECOLOUR, FOURIERVIEWCONTROLSTEST.

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
        function everyBinIsALineInItsOwnColour(testCase)
            [view, cleanup] = testCase.openView(FourierViewBinsTest.spectra('Power')); %#ok<ASGLU>

            for b = 1:3
                curve = findobj(view.Axes, 'Tag', 'SpectrumLine', 'UserData', b);
                testCase.assertNumElements(curve, 1);
                testCase.verifyEqual(curve.Color, lineColour(b), ...
                    'A bin has the colour AverageView gives it.');
            end
            testCase.verifyEqual(string(view.Axes.Legend.String), ["Low", "Mid", "High"]);
        end

        function untickingABinTakesItsLineOff(testCase)
            [view, cleanup] = testCase.openView(FourierViewBinsTest.spectra('Power')); %#ok<ASGLU>

            tick(view, 'Mid', false);

            testCase.verifyEmpty(findobj(view.Axes, 'Tag', 'SpectrumLine', 'UserData', 2));
            testCase.verifyNumElements(findobj(view.Axes, 'Tag', 'SpectrumLine'), 2);
        end

        function differenceNeedsExactlyTwoBins(testCase)
            [view, cleanup] = testCase.openView(FourierViewBinsTest.spectra('Power')); %#ok<ASGLU>

            testCase.verifyEqual(char(control(view, 'DifferenceButton').Enable), 'off', 'Three ticked.');
            tick(view, 'High', false);
            testCase.verifyEqual(char(control(view, 'DifferenceButton').Enable), 'on', 'Two ticked.');
        end

        function differenceIsTheFirstMinusTheSecondAndSwapReversesIt(testCase)
            eeg = FourierViewBinsTest.spectra('Power');
            [view, cleanup] = testCase.openView(eeg); %#ok<ASGLU>

            tick(view, 'High', false);
            setState(control(view, 'DifferenceButton'), true);
            testCase.verifyEqual(differenceLine(view).YData, eeg.data(1, :, 1) - eeg.data(1, :, 2), ...
                'AbsTol', 1e-12);

            push(control(view, 'SwapButton'));
            testCase.verifyEqual(differenceLine(view).YData, eeg.data(1, :, 2) - eeg.data(1, :, 1), ...
                'AbsTol', 1e-12);
        end

        function aRatioOfPowersIsTenLog10AndOfAmplitudesTwentyLog10(testCase)
            for unit = {'Power', 'PSD', 'Volt', 'VoltDens'; 10, 10, 20, 20}
                eeg = FourierViewBinsTest.spectra(unit{1});
                [view, cleanup] = testCase.openView(eeg); %#ok<ASGLU>

                tick(view, 'High', false);
                setState(control(view, 'DifferenceButton'), true);
                setState(control(view, 'RatioCheckbox'), true);

                expected = unit{2} * log10(eeg.data(1, :, 1) ./ eeg.data(1, :, 2));
                testCase.verifyEqual(differenceLine(view).YData, expected, 'AbsTol', 1e-12, ...
                    sprintf('A ratio of %s spectra is %d*log10.', unit{1}, unit{2}));
                testCase.verifyEqual(char(view.Axes.YLabel.String), 'ratio (dB)');
            end
        end

        function withoutAUnitThereIsNoRatio(testCase)
        %WITHOUTAUNITTHEREISNORATIO  A spectrum computed before Fourier and
        %   Welch stamped their unit cannot say whether it is a power or an
        %   amplitude, and the factor in the dB would be a guess.
            [view, cleanup] = testCase.openView(FourierViewBinsTest.spectra('')); %#ok<ASGLU>

            tick(view, 'High', false);
            setState(control(view, 'DifferenceButton'), true);

            testCase.verifyEqual(char(control(view, 'RatioCheckbox').Enable), 'off');
        end

        function thePhaseDifferenceIsThePhaseOfOneRelativeToTheOther(testCase)
            eeg = FourierViewBinsTest.spectra('Complex');
            f = reshape(eeg.freqs, 1, []);
            for b = 1:3
                eeg.data(:, :, b) = eeg.data(:, :, b) .* exp(1i * b * f / 20);
            end
            [view, cleanup] = testCase.openView(eeg); %#ok<ASGLU>

            view.onKey(struct('Key', 'p'));
            tick(view, 'High', false);
            setState(control(view, 'DifferenceButton'), true);

            expected = angle(eeg.data(1, :, 1) .* conj(eeg.data(1, :, 2)));
            testCase.verifyEqual(differenceLine(view).YData, expected, 'AbsTol', 1e-12);
            testCase.verifyEqual(ylim(view.Axes), [-pi, pi], 'AbsTol', 1e-12);
        end

        function theLogScaleIsOffUntilTicked(testCase)
            [view, cleanup] = testCase.openView(FourierViewBinsTest.spectra('Power')); %#ok<ASGLU>

            testCase.verifyFalse(logical(view.LogScaleBox.Value));
            testCase.verifyEqual(char(view.Axes.YScale), 'linear');

            setState(view.LogScaleBox, true);

            testCase.verifyEqual(char(view.Axes.YScale), 'log');
            testCase.verifyEqual(ylim(view.Axes), [11, 13], 'RelTol', 1e-12, ...
                'From the smallest level drawn to the largest.');
        end

        function aDifferenceIsNeverOnALogScale(testCase)
            [view, cleanup] = testCase.openView(FourierViewBinsTest.spectra('Power')); %#ok<ASGLU>
            setState(view.LogScaleBox, true);

            tick(view, 'High', false);
            setState(control(view, 'DifferenceButton'), true);

            testCase.verifyEqual(char(view.Axes.YScale), 'linear', 'A difference can be negative.');
            testCase.verifyEqual(char(view.LogScaleBox.Enable), 'off');
        end

        function theStandardErrorIsABandAroundEachBin(testCase)
            eeg = FourierViewBinsTest.spectra('Power');
            eeg.stErr = ones(size(eeg.data));
            [view, cleanup] = testCase.openView(eeg); %#ok<ASGLU>

            % findall, not findobj, so that the test sees what is drawn
            % whatever its HandleVisibility.
            bands = findall(view.Axes, 'Type', 'patch', 'Tag', 'ErrorBand');
            if AlakazamSettings.get('graphics', 'erpPlot', 'showConfInt')
                n = AlakazamSettings.get('graphics', 'erpPlot', 'confIntN');
                testCase.verifyNumElements(bands, 3, 'One band per bin.');
                limits = ylim(view.Axes);
                testCase.verifyEqual(limits(2), 13 + n, 'AbsTol', 1e-12, ...
                    'The axis makes room for the top of the highest band.');
            else
                testCase.verifyEmpty(bands, 'The bands are off in the Settings.');
            end
        end

        function severalLinesGetTheBandsAsStripesBehindThem(testCase)
            testCase.assumeNotEmpty(AlakazamSettings.getBands(), 'No frequency bands are set.');
            eeg = FourierViewBinsTest.spectra('Power');
            eeg.stErr = ones(size(eeg.data));   % error bands too, where the Settings draw them
            [view, cleanup] = testCase.openView(eeg); %#ok<ASGLU>

            % allchild, not Children: the stacking order of everything drawn,
            % bottom last, hidden handles included.
            stack = allchild(view.Axes);
            stripes = findall(view.Axes, 'Tag', 'BandStripe');
            testCase.assertNotEmpty(stripes);
            testCase.verifyTrue(all(ismember(stripes, stack(end - numel(stripes) + 1:end))), ...
                'The stripes are drawn behind everything else.');
            testCase.verifyEmpty(findall(view.Axes, 'Tag', 'BandFill'), ...
                'Several lines have no one curve to fill under.');
        end

        function oneLineIsFilledUnderItsCurveAsItAlwaysWas(testCase)
            testCase.assumeNotEmpty(AlakazamSettings.getBands(), 'No frequency bands are set.');
            [view, cleanup] = testCase.openView(FourierViewBinsTest.spectra('Power')); %#ok<ASGLU>

            tick(view, 'Mid', false);
            tick(view, 'High', false);

            fills = findall(view.Axes, 'Tag', 'BandFill');
            testCase.assertNotEmpty(fills);
            testCase.verifyEmpty(findall(view.Axes, 'Tag', 'BandStripe'));
            testCase.verifyEqual(unique([fills.YData]), 11, ...
                'Filled up to the one curve drawn (channel 1, bin 1).');
            testCase.verifyEqual(unique([fills.BaseValue]), 0, 'From 0 on a linear axis.');
            stack = allchild(view.Axes);
            testCase.verifyTrue(all(ismember(fills, stack(end - numel(fills) + 1:end))), ...
                'The fills are drawn behind the curve.');
        end

        function onALogScaleTheFillStartsAtTheBottomOfTheAxis(testCase)
        %ONALOGSCALETHEFILLSTARTSATTHEBOTTOMOFTHEAXIS  0 cannot be drawn on a
        %   log axis, so the fill starts where the axis does. The curve rises
        %   through four decades, so the axis has a range to span.
            testCase.assumeNotEmpty(AlakazamSettings.getBands(), 'No frequency bands are set.');
            eeg = FourierViewBinsTest.spectra('Power');
            eeg.data(1, :, 1) = logspace(0, 4, size(eeg.data, 2));
            [view, cleanup] = testCase.openView(eeg); %#ok<ASGLU>
            tick(view, 'Mid', false);
            tick(view, 'High', false);

            setState(view.LogScaleBox, true);

            testCase.assertEqual(char(view.Axes.YScale), 'log');
            limits = ylim(view.Axes);
            fills = findall(view.Axes, 'Tag', 'BandFill');
            testCase.assertNotEmpty(fills);
            testCase.verifyEqual(unique([fills.BaseValue]), limits(1), 'AbsTol', 1e-12);
        end
    end

    methods (Access = private)
        function [view, cleanup] = openView(testCase, eeg)
            try
                fig = uifigure('Visible', 'off');
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            cleanup = onCleanup(@() delete(fig));
            view = FourierView(uitab(uitabgroup(fig)), eeg);
        end
    end

    methods (Static)
        function EEG = spectra(unit)
        %SPECTRA  An averaged spectrum of two channels and three bins, each
        %   flat at level 10*channel + bin, stamped with UNIT ('' for none).
            freqs = linspace(0, 125, 129);
            data = zeros(2, numel(freqs), 3);
            for ch = 1:2
                for b = 1:3
                    data(ch, :, b) = 10 * ch + b;
                end
            end
            EEG = struct('data', data, 'freqs', freqs, 'srate', 250, 'nbchan', 2, ...
                'trials', 3, 'pnts', numel(freqs), 'DataType', 'FrequencyDomain', ...
                'DataFormat', 'Averaged', 'chanlocs', struct('labels', {'Fz', 'Cz'}), ...
                'bindesc', struct('label', {'Low', 'Mid', 'High'}));
            if ~isempty(unit)
                EEG.SpectrumUnit = unit;
            end
        end
    end
end

function tick(view, name, value)
%TICK  Tick or untick the bin called NAME, as a user would.
    boxes = findall(view.Strip, 'Type', 'uicheckbox');
    setState(boxes(strcmp({boxes.Text}, name)), value);
end

function h = control(view, tag)
%CONTROL  The strip's control tagged TAG, as it is now.
    h = findall(view.Strip, 'Tag', tag);
end

function setState(h, value)
%SETSTATE  Set a checkbox or state button to VALUE and fire its callback,
%   which a programmatic Value change does not.
    h.Value = value;
    h.ValueChangedFcn(h, []);
end

function push(h)
%PUSH  Push a button, as a click would.
    h.ButtonPushedFcn(h, []);
end

function h = differenceLine(view)
    h = findobj(view.Axes, 'Tag', 'DifferenceLine');
end
