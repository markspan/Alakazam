classdef WelchTest < matlab.unittest.TestCase
%WELCHTEST  Unit tests for src/Transformations/Welch/Welch.m and for
%   Fourier's calibrated 'PSD' output, which shares its normalisation.
%
%   THE POINT OF BOTH IS THAT THE NUMBER MEANS SOMETHING, so these tests
%   check the number against something independent rather than against
%   another Alakazam code path: MATLAB's own pwelch, and closed-form
%   answers (a sinusoid of amplitude A carries power A^2/2; a spectral
%   density integrates to the signal's mean square). Comparing two of our
%   own routes would agree happily while both were wrong, which is exactly
%   how the existing Power/PowerDens scaling went unnoticed.
%
%   Run with: runtests('tests/WelchTest.m').
%
%   See also FOURIERTEST, AVERAGETEST.

    properties (Constant)
        Srate = 256
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Welch')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Fourier')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Access = private)
        function EEG = continuousEEG(testCase, x)
            n = size(x, 2);
            EEG = struct('data', x, 'srate', testCase.Srate, ...
                'DataFormat', 'CONTINUOUS', 'DataType', 'TimeDomain', ...
                'nbchan', size(x, 1), 'pnts', n, 'trials', 1, ...
                'times', (0:n-1) / testCase.Srate * 1000, ...
                'chanlocs', struct('labels', 'A'));
        end
    end

    methods (Test)
        function matchesPwelchExactly(testCase)
        %MATCHESPWELCHEXACTLY  Same segmentation, same taper, same answer.
        %   An independent implementation, not another of ours.
            testCase.assumeTrue(exist('pwelch', 'file') == 2, ...
                'Signal Processing Toolbox not available.');
            rng(3);
            n = testCase.Srate * 30;
            x = 3 * randn(1, n);
            EEG = testCase.continuousEEG(x);

            W = Welch(EEG, struct('SegmentSeconds', 4, 'Overlap', 50, ...
                'Window', 'Hanning'));

            segLen = 4 * testCase.Srate;
            % hanning(), not hann(): Alakazam's 'Hanning' is the variant
            % whose endpoints are non-zero, and comparing against the wrong
            % one shows a spurious 9% disagreement that is purely the
            % window definition.
            expected = reshape(pwelch(x, hanning(segLen), segLen/2, segLen, ...
                testCase.Srate), 1, []);

            testCase.verifyEqual(W.data(1, :), expected, 'RelTol', 1e-10);
        end

        function integratesToTheSignalsMeanSquare(testCase)
        %INTEGRATESTOTHESIGNALSMEANSQUARE  The defining property of a
        %   density, and the one Power/PowerDens misses by a factor 2.
            rng(5);
            n = testCase.Srate * 30;
            x = 2.5 * randn(1, n);
            W = Welch(testCase.continuousEEG(x), ...
                struct('SegmentSeconds', 4, 'Overlap', 50, 'Window', 'Hanning'));

            df = W.freqs(2) - W.freqs(1);
            testCase.verifyEqual(sum(W.data(1, :)) * df, mean(x .^ 2), ...
                'RelTol', 0.02, ...
                'A PSD must integrate to the mean square of the signal.');
        end

        function resolutionIsOneOverTheSegmentLength(testCase)
            x = randn(1, testCase.Srate * 40);
            for seconds = [2 4 8]
                W = Welch(testCase.continuousEEG(x), ...
                    struct('SegmentSeconds', seconds, 'Overlap', 50, 'Window', 'Hanning'));
                testCase.verifyEqual(W.freqs(2) - W.freqs(1), 1/seconds, ...
                    'AbsTol', 1e-12, ...
                    'Frequency resolution is 1/segment length: the whole trade-off.');
            end
        end

        function moreOverlapMeansMoreSegments(testCase)
            x = randn(1, testCase.Srate * 40);
            base = struct('SegmentSeconds', 4, 'Overlap', 0, 'Window', 'Hanning');
            none = Welch(testCase.continuousEEG(x), base);
            base.Overlap = 50;
            half = Welch(testCase.continuousEEG(x), base);
            testCase.verifyGreaterThan(half.WelchSegments, none.WelchSegments);
        end

        function segmentsWithNonFiniteSamplesAreSkipped(testCase)
        %SEGMENTSWITHNONFINITESAMPLESARESKIPPED  One bad stretch must cost
        %   its own segments, not the whole estimate.
            rng(7);
            n = testCase.Srate * 30;
            x = randn(1, n);
            opts = struct('SegmentSeconds', 4, 'Overlap', 50, 'Window', 'Hanning');
            clean = Welch(testCase.continuousEEG(x), opts);

            x(1:4*testCase.Srate) = NaN;
            holed = Welch(testCase.continuousEEG(x), opts);

            testCase.verifyLessThan(holed.WelchSegments, clean.WelchSegments);
            testCase.verifyTrue(all(isfinite(holed.data(:))), ...
                'A NaN stretch must not poison the averaged spectrum.');
        end

        function refusesEpochedData(testCase)
        %REFUSESEPOCHEDDATA  Epoched data already has this estimate through
        %   Fourier + Average, at better resolution.
            EEG = testCase.continuousEEG(randn(1, testCase.Srate * 30));
            EEG.DataFormat = 'EPOCHED';
            testCase.verifyError(@() Welch(EEG, struct('SegmentSeconds', 4, ...
                'Overlap', 50, 'Window', 'Hanning')), 'Alakazam:Welch');
        end

        function refusesASegmentLongerThanTheRecording(testCase)
            EEG = testCase.continuousEEG(randn(1, testCase.Srate * 3));
            testCase.verifyError(@() Welch(EEG, struct('SegmentSeconds', 10, ...
                'Overlap', 50, 'Window', 'Hanning')), 'Alakazam:Welch');
        end

        function refusesStoredSettingsItDidNotProduce(testCase)
            EEG = testCase.continuousEEG(randn(1, testCase.Srate * 30));
            testCase.verifyError(@() Welch(EEG, struct('Nonsense', 1)), ...
                'Alakazam:Welch');
        end

        function fourierPsdIsCalibratedWhereTheOlderOutputsAreNot(testCase)
        %FOURIERPSDISCALIBRATEDWHERETHEOLDEROUTPUTSARENOT  The measurement
        %   that motivated adding 'PSD' at all.
        %
        %   A sinusoid of amplitude A carries power A^2/2. 'PSD' integrates
        %   to exactly that. 'Power' misses by exactly 2x, because
        %   FullSpectrum doubles the AMPLITUDE and Power then squares it,
        %   turning a fold of 2 into a fold of 4. Both are pinned here: the
        %   first so it stays right, the second so the discrepancy stays
        %   documented rather than being rediscovered.
            n = 256;
            t = (0:n-1) / testCase.Srate;
            x = 5 * sin(2*pi*10*t);
            EEG = struct('data', reshape(x, 1, n, 1), 'srate', testCase.Srate);
            base = struct('FullSpectrum', true, 'Window', 'No', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1);

            psdOpts = base; psdOpts.Output = 'PSD';
            P = Fourier(EEG, psdOpts);
            df = P.freqs(2) - P.freqs(1);
            testCase.verifyEqual(sum(P.data(1, :)) * df, 12.5, 'RelTol', 1e-9, ...
                'PSD must integrate to A^2/2 for a pure sinusoid.');

            powOpts = base; powOpts.Output = 'Power';
            W = Fourier(EEG, powOpts);
            testCase.verifyEqual(sum(W.data(1, :)), 25, 'RelTol', 1e-9, ...
                ['Power is left exactly 2x high by the amplitude fold. This is ' ...
                 'the documented legacy behaviour, kept so existing analyses ' ...
                 'reproduce; PSD is the calibrated one.']);
        end

        function fourierPsdIgnoresFullSpectrum(testCase)
        %FOURIERPSDIGNORESFULLSPECTRUM  A density is one-sided by
        %   definition, so there is no second convention to offer and the
        %   flag must not silently change the answer.
            rng(9);
            n = 256;
            EEG = struct('data', reshape(randn(1, n), 1, n, 1), 'srate', testCase.Srate);
            base = struct('Output', 'PSD', 'Window', 'Hanning', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1);

            on  = base; on.FullSpectrum  = true;
            off = base; off.FullSpectrum = false;
            testCase.verifyEqual(Fourier(EEG, on).data, Fourier(EEG, off).data, ...
                'AbsTol', 1e-12);
        end
    end
end
