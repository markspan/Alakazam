classdef FourierTest < matlab.unittest.TestCase
%FOURIERTEST  Unit tests for src/Transformations/Fourier/Fourier.m.
%
%   Fourier's windowing/normalization pipeline (fullwin, the vunw/vwin
%   "norm" correction) makes an exact expected FFT magnitude hard to
%   hand-derive safely without running the code, so most tests here check
%   ROBUST RELATIONSHIPS instead (Power == Volt.^2, FullSpectrum exactly
%   doubles Volt, etc.), which hold regardless of that pipeline's exact
%   numeric behaviour, plus one exact test (peakLandsAtInputFrequency)
%   deliberately constructed to sidestep it entirely: Window='No' makes
%   the taper (and hence its normalization) a no-op (see the test's own
%   comment for the reasoning), and both the segment length and the
%   injected sine frequency are chosen so there is no zero-padding and no
%   spectral leakage at all.
%
%   Fourier takes INPUT as varargin{1}, not a named first parameter (see
%   TransTools.InitGuard's own header comment for why) -- called here the
%   same way the app itself calls it, Fourier(EEG, opts).
%
%   Run with: runtests('tests/FourierTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Fourier')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        function peakLandsAtInputFrequency(testCase)
        %PEAKLANDSATINPUTFREQUENCY  A single-channel, single-segment,
        %   exactly-256-sample sine at a frequency exactly aligned to the
        %   256-point FFT's own bin grid: Window='No' makes fullwin
        %   all-ones, which makes vwin == vunw exactly (norm == 1), so the
        %   whole windowing/normalisation pipeline is a no-op here -- a
        %   plain FFT magnitude of a clean, bin-aligned, zero-padding-free
        %   sinusoid, whose peak should land exactly at the input
        %   frequency's own bin.
            srate = 250;
            nsamp = 256; % a power of 2: Resolution='Max' -> NFFT == nsamp exactly, no zero-padding
            freq  = 20 * srate / nsamp; % bin-aligned: 20*250/256 = 19.53125 Hz
            t = (0:nsamp - 1) / srate;

            EEG = struct('data', sin(2 * pi * freq * t), 'srate', srate);
            opts = struct('Output', 'Volt', 'FullSpectrum', true, 'Window', 'No', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1);

            [result, ~] = Fourier(EEG, opts);

            [~, peakIdx] = max(result.data(1, :, 1));
            testCase.verifyEqual(result.freqs(peakIdx), freq, 'AbsTol', 1e-6);
        end

        function powerEqualsVoltSquared(testCase)
        %POWEREQUALSVOLTSQUARED  Power and Volt come from the same
        %   underlying per-segment computation (see Fourier.m's own
        %   comment: Volt is computed once and reshaped per Output, not
        %   recomputed per branch), so Power must equal Volt.^2 exactly,
        %   for any window/data, not just the leakage-free case above.
            EEG = struct('data', testSignal(), 'srate', 250);
            base = struct('FullSpectrum', true, 'Window', 'Hanning', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1);

            voltOpts = base; voltOpts.Output = 'Volt';
            powerOpts = base; powerOpts.Output = 'Power';

            [voltResult, ~]  = Fourier(EEG, voltOpts);
            [powerResult, ~] = Fourier(EEG, powerOpts);

            testCase.verifyEqual(powerResult.data, voltResult.data .^ 2, 'AbsTol', 1e-10);
        end

        function densityOutputsDivideByFrequencyResolution(testCase)
        %DENSITYOUTPUTSDIVIDEBYFREQUENCYRESOLUTION  VoltDens = Volt /
        %   (srate/NFFT); PowerDens = Power / (srate/NFFT) -- the same
        %   division applied to each of the two base quantities tested
        %   above.
            EEG = struct('data', testSignal(), 'srate', 250);
            base = struct('FullSpectrum', true, 'Window', 'Hanning', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1);

            voltOpts = base; voltOpts.Output = 'Volt';
            voltDensOpts = base; voltDensOpts.Output = 'VoltDens';
            powerOpts = base; powerOpts.Output = 'Power';
            powerDensOpts = base; powerDensOpts.Output = 'PowerDens';

            [voltResult, ~]      = Fourier(EEG, voltOpts);
            [voltDensResult, ~]  = Fourier(EEG, voltDensOpts);
            [powerResult, ~]     = Fourier(EEG, powerOpts);
            [powerDensResult, ~] = Fourier(EEG, powerDensOpts);

            NFFT = 2 * (voltResult.pnts - 1);
            freqRes = EEG.srate / NFFT;

            testCase.verifyEqual(voltDensResult.data, voltResult.data ./ freqRes, 'AbsTol', 1e-10);
            testCase.verifyEqual(powerDensResult.data, powerResult.data ./ freqRes, 'AbsTol', 1e-10);
        end

        function fullSpectrumExactlyDoublesTheMagnitude(testCase)
        %FULLSPECTRUMEXACTLYDOUBLESTHEMAGNITUDE  FullSpectrum multiplies
        %   the whole per-segment result by a fixed factor of 2 (fs = 2 in
        %   Fourier.m); everything else about the two runs below is
        %   identical, so the ratio should be exactly 2, elementwise.
            EEG = struct('data', testSignal(), 'srate', 250);
            base = struct('Output', 'Volt', 'Window', 'Hanning', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1);

            fullOpts = base; fullOpts.FullSpectrum = true;
            halfOpts = base; halfOpts.FullSpectrum = false;

            [fullResult, ~] = Fourier(EEG, fullOpts);
            [halfResult, ~] = Fourier(EEG, halfOpts);

            testCase.verifyEqual(fullResult.data, 2 * halfResult.data, 'AbsTol', 1e-10);
        end

        function resolutionOtherProducesTheRequestedNFFT(testCase)
        %RESOLUTIONOTHERPRODUCESTHEREQUESTEDNFFT  Resolution='Other' with
        %   a given ResVal (Hz) should size the FFT to
        %   2^nextpow2(floor(srate/ResVal)), reflected in output.pnts
        %   (== NFFT/2 + 1).
            EEG = struct('data', testSignal(), 'srate', 250);
            opts = struct('Output', 'Volt', 'FullSpectrum', true, 'Window', 'No', ...
                'Window_Length', 100, 'Resolution', 'Other', 'ResVal', 2);

            [result, ~] = Fourier(EEG, opts);

            expectedNFFT = 2 ^ nextpow2(floor(EEG.srate / opts.ResVal));
            testCase.verifyEqual(result.pnts, expectedNFFT / 2 + 1);
        end

        function outputMetadataIsPopulatedCorrectly(testCase)
        %OUTPUTMETADATAISPOPULATEDCORRECTLY  DataType, trials (segment
        %   count) and the freqs/pnts/data shape agreement.
            data = testSignal();
            data = cat(3, data, data, data); % 3 identical segments
            EEG = struct('data', data, 'srate', 250);
            opts = struct('Output', 'Volt', 'FullSpectrum', true, 'Window', 'No', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1);

            [result, ~] = Fourier(EEG, opts);

            testCase.verifyEqual(result.DataType, 'FrequencyDomain');
            testCase.verifyEqual(result.trials, 3);
            testCase.verifyEqual(numel(result.freqs), result.pnts);
            testCase.verifyEqual(size(result.data), [1, result.pnts, 3]);
            testCase.verifyEqual(result.freqs(1), 0);
            testCase.verifyEqual(result.freqs(end), EEG.srate / 2, 'AbsTol', 1e-9);
        end

        function noArgumentsThrowsAFriendlyError(testCase)
        %NOARGUMENTSTHROWSAFRIENDLYERROR  A regression test for the fix
        %   noted in Fourier.m's own header comment: calling Fourier()
        %   with no arguments at all used to fail much later, deep inside
        %   the function, with a raw "index exceeds array bounds" instead
        %   of the app's usual "Problem in Fourier: ..." message.
            testCase.verifyError(@() Fourier(), 'Alakazam:Fourier');
        end

        function complexOutputKeepsThePhase(testCase)
        %COMPLEXOUTPUTKEEPSTHEPHASE  'Complex' stores the raw coefficients,
        %   and its magnitude is exactly the 'Volt' output.
            EEG = struct('data', testSignal(), 'srate', 250);
            base = struct('FullSpectrum', true, 'Window', 'No', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1);

            cOpts = base; cOpts.Output = 'Complex';
            vOpts = base; vOpts.Output = 'Volt';
            [C, ~] = Fourier(EEG, cOpts);
            [V, ~] = Fourier(EEG, vOpts);

            testCase.verifyFalse(isreal(C.data), 'Complex output must keep phase.');
            testCase.verifyTrue(isreal(V.data), 'Volt output is a magnitude.');
            testCase.verifyEqual(abs(C.data), V.data, 'AbsTol', 1e-12, ...
                'abs(Complex) must reproduce Volt exactly: same quantity, one step earlier.');
        end

        function averagingComplexSpectraEqualsTransformingTheAverage(testCase)
        %AVERAGINGCOMPLEXSPECTRAEQUALSTRANSFORMINGTHEAVERAGE  The reason
        %   the option exists.
        %
        %   The DFT is linear, so a coherent (complex) average of per-trial
        %   spectra IS the spectrum of the averaged signal. That identity
        %   is unavailable from the magnitude outputs, where abs() has
        %   already discarded the phase the cancellation needs.
        %
        %   WINDOW='NO' IS LOAD-BEARING HERE, not incidental. Fourier's
        %   window correction divides by var(unwindowed)/var(windowed)
        %   computed from each segment's OWN data, so with a taper the
        %   per-trial and averaged runs apply different effective windows
        %   and the identity fails by ~15% on real data. Untapered, norm is
        %   1 and the two agree to machine precision, which is what this
        %   pins down.
            nTrials = 5;
            rng(42);
            trials = zeros(1, 128, nTrials);
            for k = 1:nTrials
                trials(1, :, k) = testSignal() + 0.3 * randn(1, 128);
            end

            base = struct('Output', 'Complex', 'FullSpectrum', true, ...
                'Window', 'No', 'Window_Length', 100, ...
                'Resolution', 'Max', 'ResVal', 1);

            perTrial = struct('data', trials, 'srate', 250);
            [C, ~] = Fourier(perTrial, base);
            coherent = mean(C.data, 3);

            averaged = struct('data', mean(trials, 3), 'srate', 250);
            [B, ~] = Fourier(averaged, base);

            testCase.verifyEqual(coherent, B.data, 'AbsTol', 1e-10, ...
                'mean(Fourier) and Fourier(mean) must agree for complex output.');
        end

        function magnitudeAveragingIsNotTheSameThing(testCase)
        %MAGNITUDEAVERAGINGISNOTTHESAMETHING  And the difference is not an
        %   error: mean(|X|) >= |mean(X)| by the triangle inequality, the
        %   gap being the induced, non-phase-locked part. This is why the
        %   two outputs both need to exist.
            nTrials = 5;
            rng(42);
            trials = zeros(1, 128, nTrials);
            for k = 1:nTrials
                trials(1, :, k) = testSignal() + 0.3 * randn(1, 128);
            end
            base = struct('FullSpectrum', true, 'Window', 'No', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1);

            cOpts = base; cOpts.Output = 'Complex';
            vOpts = base; vOpts.Output = 'Volt';
            C = Fourier(struct('data', trials, 'srate', 250), cOpts);
            V = Fourier(struct('data', trials, 'srate', 250), vOpts);

            incoherent = mean(V.data, 3);          % mean of magnitudes
            coherent   = abs(mean(C.data, 3));     % magnitude of the mean

            testCase.verifyGreaterThanOrEqual(incoherent + 1e-12, coherent, ...
                'mean(|X|) >= |mean(X)| everywhere.');
            testCase.verifyGreaterThan(max(incoherent(:) - coherent(:)), 1e-6, ...
                'With noise across trials the two must actually differ.');
        end
    end
end

function data = testSignal()
%TESTSIGNAL  A small, arbitrary single-channel, single-segment signal
%   shared by the relationship-style tests above (which never inspect its
%   exact spectral content, only relationships between different Output
%   settings run against the SAME signal).
    t = (0:127) / 250;
    data = sin(2 * pi * 10 * t) + 0.5 * sin(2 * pi * 37 * t);
end
