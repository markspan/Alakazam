classdef SpectralMeasureCoherenceMethodTest < matlab.unittest.TestCase
%SPECTRALMEASURECOHERENCEMETHODTEST  Which estimator SpectralMeasure uses for
%   coherence, and that an old node's options keep meaning what they did.
%
%   Three estimators exist (see SpectralMeasure's header): 'frames' (the
%   estimator of record), 'window' (one DFT bin per trial, biased upwards) and
%   'newcrossf' (EEGLAB's). Options saved before the method existed have only the
%   older crossf.enabled flag, and replaying or recalculating such a node has to
%   reproduce its numbers, so no flag means 'window' and enabled means 'newcrossf'.
%
%   Run with: runtests('tests/SpectralMeasureCoherenceMethodTest.m').
%
%   See also SPECTRALMEASURE, TRANSTOOLS.FRAMECOHERENCE, SPECTRALMEASURETEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'SpectralMeasure'), ...
                     fullfile(root, 'src', 'Transformations', 'Measure'), ...
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'src', 'Support')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function framesIsTheFrameCoherenceOfTheChannelAndTheReference(testCase)
            EEG = testCase.recording(20, 30);
            opts = testCase.options(struct('Method', 'frames', 'WinSize', 100));

            [result, stored] = SpectralMeasure(EEG, opts);

            m = result.spectralMeasures{1};
            X = squeeze(EEG.data(1, :, :));
            R = squeeze(EEG.data(2, :, :));
            [want, wantLag] = TransTools.FrameCoherence(X, R, EEG.srate, 20, ...
                struct('WinSize', 100, 'Times', EEG.times));
            testCase.verifyEqual(m.coherence, want, 'AbsTol', 1e-12);
            testCase.verifyEqual(m.phaselag, wantLag, 'AbsTol', 1e-12);
            testCase.verifyEqual(stored.coherenceMethod, 'frames');
            testCase.verifyEqual(stored.crossf.Method, 'frames');
            testCase.verifyFalse(stored.crossf.enabled, 'The older flag means newcrossf and only that.');
        end

        function optionsWithNoMethodKeepTheSingleWindow(testCase)
        %OPTIONSWITHNOMETHODKEEPTHESINGLEWINDOW  What a node made before the method
        %   existed holds. Recalculating it must give what it gave, so it is the
        %   single window, and the method is now recorded as such.
            EEG = testCase.recording(20, 30);
            legacy = testCase.options([]);
            explicit = testCase.options(struct('Method', 'window'));

            [a, storedLegacy] = SpectralMeasure(EEG, legacy);
            b = SpectralMeasure(EEG, explicit);

            testCase.verifyEqual(a.spectralMeasures{1}.coherence, b.spectralMeasures{1}.coherence);
            testCase.verifyEqual(storedLegacy.coherenceMethod, 'window');
            frames = SpectralMeasure(EEG, testCase.options(struct('Method', 'frames', 'WinSize', 100)));
            testCase.verifyGreaterThan(a.spectralMeasures{1}.coherence, frames.spectralMeasures{1}.coherence, ...
                'The single window reads higher than the frame average on the same data.');
        end

        function theOlderEnabledFlagMeansNewcrossf(testCase)
            testCase.assumeTrue(testCase.haveNewcrossf(), 'EEGLAB''s newcrossf is not available.');
            EEG = testCase.recording(20, 30);
            opts = testCase.options(struct('enabled', true, 'WinSize', 100, 'PadRatio', 4, ...
                'TimesOut', 100, 'MinFreq', 10, 'MaxFreq', 40));

            [~, stored] = SpectralMeasure(EEG, opts);

            testCase.verifyEqual(stored.coherenceMethod, 'newcrossf');
            testCase.verifyTrue(stored.crossf.enabled);
        end

        function anExplicitMethodBeatsTheOlderFlag(testCase)
            EEG = testCase.recording(20, 30);
            opts = testCase.options(struct('enabled', true, 'Method', 'frames', 'WinSize', 100));

            [~, stored] = SpectralMeasure(EEG, opts);

            testCase.verifyEqual(stored.coherenceMethod, 'frames');
            testCase.verifyFalse(stored.crossf.enabled);
        end

        function aRowOutsideAnyBandIsStillReadByTheFrameEstimator(testCase)
        %AROWOUTSIDEANYBANDISSTILLREADBYTHEFRAMEESTIMATOR  A 20 Hz tag with a crossf
        %   band of 52 to 68 Hz left in the options (as the RIFT template once had):
        %   the frame estimator has no band, so the 20 Hz row is read at 20 Hz.
            EEG = testCase.recording(20, 30);
            opts = testCase.options(struct('Method', 'frames', 'WinSize', 100, 'MinFreq', 52, 'MaxFreq', 68));

            result = SpectralMeasure(EEG, opts);

            testCase.verifyGreaterThan(result.spectralMeasures{1}.coherence, 0.5);
        end

        function newcrossfLeavesARowOutsideItsBandMissingWithAWarning(testCase)
        %NEWCROSSFLEAVESAROWOUTSIDEITSBANDMISSINGWITHAWARNING  The row was read at the
        %   band edge and reported as its own coherence (0.065 for a value that was
        %   about 0.39 on real data). It is missing, and the warning says why.
            testCase.assumeTrue(testCase.haveNewcrossf(), 'EEGLAB''s newcrossf is not available.');
            EEG = testCase.recording(20, 30);
            opts = testCase.options(struct('Method', 'newcrossf', 'WinSize', 100, 'PadRatio', 4, ...
                'TimesOut', 60, 'MinFreq', 52, 'MaxFreq', 68));

            result = [];
            testCase.verifyWarning(@() assignResult(), 'Alakazam:SpectralMeasure:outsideCrossfBand');
            function assignResult()
                result = SpectralMeasure(EEG, opts);
            end

            testCase.verifyTrue(isnan(result.spectralMeasures{1}.coherence));
            testCase.verifyTrue(isnan(result.spectralMeasures{1}.phaselag));
        end

        function newcrossfStillReadsARowInsideItsBand(testCase)
            testCase.assumeTrue(testCase.haveNewcrossf(), 'EEGLAB''s newcrossf is not available.');
            EEG = testCase.recording(20, 30);
            opts = testCase.options(struct('Method', 'newcrossf', 'WinSize', 100, 'PadRatio', 4, ...
                'TimesOut', 60, 'MinFreq', 12, 'MaxFreq', 30));

            result = SpectralMeasure(EEG, opts);

            testCase.verifyGreaterThan(result.spectralMeasures{1}.coherence, 0.5);
        end

        function theSavedSettingsKeepABlankWindowBlank(testCase)
        %THESAVEDSETTINGSKEEPABLANKWINDOWBLANK  The node's settings used to hold
        %   the resolved values, NaN for a blank window, and recalculating the
        %   node then failed in the dialog: a numeric edit field refuses NaN.
        %   The choice is now saved as made, blank as [], and what the estimator
        %   used is recorded beside it, the frame here shortened to the epoch.
            EEG = testCase.recording(20, 30);
            blank = testCase.options(struct('Method', 'frames', 'WinSize', 510));
            legacy = testCase.options(struct('Method', 'frames', 'WinSize', 510, 'TimeStart', NaN, 'TimeStop', NaN));

            [a, stored] = SpectralMeasure(EEG, blank);
            [~, storedLegacy] = SpectralMeasure(EEG, legacy);
            replayed = SpectralMeasure(EEG, stored);

            for s = {stored, storedLegacy}
                testCase.verifyEmpty(s{1}.crossf.TimeStart);
                testCase.verifyEmpty(s{1}.crossf.TimeStop);
                testCase.verifyEmpty(s{1}.crossfUsed.TimeStart, 'The whole epoch is recorded as [], not NaN.');
                testCase.verifyEmpty(s{1}.crossfUsed.TimeStop);
            end
            testCase.verifyEqual(stored.crossf.WinSize, 510, 'The choice is what the user asked for.');
            testCase.verifyEqual(stored.crossfUsed.WinSize, 500, ...
                'A 510-sample frame on a 500-sample epoch is shortened to the epoch, and the record says so.');
            testCase.verifyEqual(replayed.spectralMeasures{1}.coherence, a.spectralMeasures{1}.coherence, ...
                'Replaying the saved choice reproduces the numbers.');
        end

        function aWindowWithOneEndIsRecordedAsTheWholeEpoch(testCase)
        %AWINDOWWITHONEENDISRECORDEDASTHEWHOLEEPOCH  Both estimators average every
        %   frame unless both ends are given, so the record must not claim a range.
            EEG = testCase.recording(20, 30);
            [~, stored] = SpectralMeasure(EEG, testCase.options(struct('Method', 'frames', 'WinSize', 100, ...
                'TimeStart', 200)));

            testCase.verifyEqual(stored.crossf.TimeStart, 200);
            testCase.verifyEmpty(stored.crossfUsed.TimeStart);
            testCase.verifyEmpty(stored.crossfUsed.TimeStop);
        end

        function anAutomaticBandFollowsTheRowsOnRecalculation(testCase)
        %ANAUTOMATICBANDFOLLOWSTHEROWSONRECALCULATION  A blank newcrossf band is
        %   worked out from the rows. It used to be saved over the choice, so a
        %   node recalculated after its row moved kept the old band, and the row,
        %   now outside it, came back missing.
            testCase.assumeTrue(testCase.haveNewcrossf(), 'EEGLAB''s newcrossf is not available.');
            opts = testCase.options(struct('Method', 'newcrossf', 'WinSize', 100, 'PadRatio', 4, 'TimesOut', 60));

            [~, stored] = SpectralMeasure(testCase.recording(20, 30), opts);
            testCase.verifyEmpty(stored.crossf.MinFreq, 'An automatic band stays automatic.');
            testCase.verifyEmpty(stored.crossf.MaxFreq);
            testCase.verifyEqual([stored.crossfUsed.MinFreq stored.crossfUsed.MaxFreq], [12 28]);

            stored.rows{1}.freq = '40';
            result = [];
            testCase.verifyWarningFree(@() recalculate());
            function recalculate()
                [result, stored] = SpectralMeasure(testCase.recording(40, 30), stored);
            end
            testCase.verifyEqual([stored.crossfUsed.MinFreq stored.crossfUsed.MaxFreq], [32 48]);
            testCase.verifyGreaterThan(result.spectralMeasures{1}.coherence, 0.5);
        end

        function anUnknownMethodIsRefused(testCase)
            EEG = testCase.recording(20, 30);
            opts = testCase.options(struct('Method', 'wavelet'));

            testCase.verifyError(@() SpectralMeasure(EEG, opts), 'Alakazam:SpectralMeasure');
        end
    end

    methods (Access = private)
        function tf = haveNewcrossf(~)
            try
                EEGLabEnvironment.ensure();
            catch
                % Fall through to the check on the function itself.
            end
            tf = exist('newcrossf', 'file') == 2;
        end

        function opts = options(~, crossf)
        %OPTIONS  One 20 Hz row on Ch1 against ChRef, with CROSSF as given ([] = none).
            opts = struct('rows', {{struct('label', 'R', 'freq', '20', 'channels', 'Ch1')}}, ...
                'fundamentals', '', 'refChannel', 'ChRef', 'method', 'Hann', 'tapers', 3, ...
                'snrNeighbours', 10, 'snrGuard', 1);
            if ~isempty(crossf)
                opts.crossf = crossf;
            end
        end

        function EEG = recording(~, f0, nTrials)
        %RECORDING  Ch1 and ChRef share a tone at F0 with a random start phase on
        %   every trial and each has independent noise: real, but not perfect,
        %   coherence, over two seconds at 250 Hz.
            rng(31);
            srate = 250; nsamp = 500;
            t = (0:nsamp - 1) / srate;
            data = zeros(2, nsamp, nTrials);
            for tr = 1:nTrials
                tone = cos(2 * pi * f0 * t + 2 * pi * rand());
                data(1, :, tr) = tone + 0.5 * randn(1, nsamp);
                data(2, :, tr) = tone + 0.5 * randn(1, nsamp);
            end
            EEG = struct('DataFormat', 'EPOCHED', 'srate', srate, 'times', t * 1000, ...
                'chanlocs', struct('labels', {'Ch1', 'ChRef'}), 'data', data, ...
                'bindesc', struct('index', 1, 'label', 'Bin1', 'trials', 1:nTrials));
        end
    end
end
