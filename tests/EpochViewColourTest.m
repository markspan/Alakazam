classdef EpochViewColourTest < matlab.unittest.TestCase
%EPOCHVIEWCOLOURTEST  EpochView's colour scale: set automatically from the
%   98th percentile rather than the maximum, and settable per channel group
%   with "Colour ±" and "Auto".
%
%   THE REPORTED PROBLEM was an image in the palest few colours: the scale
%   ran to the group's single largest sample, so one blink or drift set it
%   for every trial. The fixture here has exactly that, one large spike in
%   otherwise ordinary data.
%
%   Run with: runtests('tests/EpochViewColourTest.m').
%
%   See also EPOCHVIEW.

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
        function oneLargeSampleDoesNotSetTheScale(testCase)
            data = 2 * ones(1, 1000);
            data(17) = 1000;

            testCase.verifyEqual(EpochView.robustColorLimit(data), 2);
        end

        function theScaleIsNeverEmpty(testCase)
            testCase.verifyEqual(EpochView.robustColorLimit(zeros(3, 4)), 1);
            testCase.verifyEqual(EpochView.robustColorLimit(nan(3, 4)), 1);
            mostlyZero = zeros(1, 1000);
            mostlyZero(1:5) = 7;
            testCase.verifyEqual(EpochView.robustColorLimit(mostlyZero), 7, ...
                'Where the percentile is zero, the largest value is used instead.');
        end

        function aLongRecordingIsReadFromASample(testCase)
        %ALONGRECORDINGISREADFROMASAMPLE  Evenly spaced samples give the same
        %   percentile, without copying every trial of every channel.
            rng(1);
            data = randn(40, 1250, 60);

            full = sort(abs(data(:)));
            testCase.verifyEqual(EpochView.robustColorLimit(data), ...
                full(ceil(0.98 * numel(full))), 'RelTol', 0.02);
        end
    end

    methods (Test, TestTags = {'Slow'})
        function aTypedRangeAndAutoChangeTheImageAndTheColourBar(testCase)
            try
                fig = uifigure('Visible', 'off');
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            closeFig = onCleanup(@() delete(fig));
            view = EpochView(uitab(uitabgroup(fig)), EpochViewColourTest.epoched());
            auto = view.HeatAxes.CLim(2);
            testCase.verifyLessThan(auto, 10, 'The 500 uV spike does not set the automatic scale.');
            testCase.verifyEqual(view.ColorField.Value, auto);

            before = view.ColorbarWrap;
            view.setColorLimit(3);
            testCase.verifyEqual(view.HeatAxes.CLim, [-3 3]);
            testCase.verifyEqual(view.ColorField.Value, 3);
            testCase.verifyFalse(isvalid(before), 'The colour bar was rebuilt for the new range.');

            view.applyFocus(struct('Channel', 'Pz'));
            testCase.verifyEqual(view.HeatAxes.CLim, [-3 3], ...
                'Another channel of the same group keeps the range, so the two stay comparable.');

            view.setColorLimit([]);
            testCase.verifyEqual(view.HeatAxes.CLim, [-auto auto], '"Auto" restores the automatic scale.');
            clear closeFig
        end
    end

    methods (Static)
        function EEG = epoched()
        %EPOCHED  Two EEG channels, twenty trials of unit noise, and one
        %   500 uV spike.
            rng(2);
            times = -100:10:490;
            data = randn(2, numel(times), 20);
            data(1, 30, 7) = 500;
            EEG = struct('data', data, 'srate', 100, 'times', times, 'pnts', numel(times), ...
                'trials', 20, 'nbchan', 2, 'xmin', times(1) / 1000, 'xmax', times(end) / 1000, ...
                'DataFormat', 'EPOCHED', 'chanlocs', struct('labels', {'Cz', 'Pz'}));
        end
    end
end
