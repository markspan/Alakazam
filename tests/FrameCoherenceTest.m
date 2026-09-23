classdef FrameCoherenceTest < matlab.unittest.TestCase
%FRAMECOHERENCETEST  TransTools.FrameCoherence, the estimator of record for the
%   coherence to a reference.
%
%   THE CHECKS. It must (1) be the same quantity CoherenceMap draws, which is
%   tested against a frame-by-frame FFT at a grid frequency, where a direct
%   transform and the FFT of the zero-padded frame are the same number; (2) have
%   the algebraic identities coherence has: exactly 1 against a scalar multiple of
%   the same signal, low for independent signals, a cross-spectrum phase equal to a
%   known lag; (3) leave a trial with NaN out exactly as if it were absent; and
%   (4) honour its averaging window.
%
%   Run with: runtests('tests/FrameCoherenceTest.m').
%
%   See also TRANSTOOLS.FRAMECOHERENCE, COHERENCEMAPSTFTTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'CoherenceMap')));   % ComputeCoherenceMap lives there
        end
    end

    methods (Test)
        function itIsTheCoherenceMapAtAGridFrequency(testCase)
        %ITISTHECOHERENCEMAPATAGRIDFREQUENCY  With a 200 ms window at 250 Hz (50
        %   samples) padded to 128, the grid spacing is 250/128 Hz. The transform
        %   of a frame at one of those frequencies is the same number by either
        %   route, so the frame-averaged coherence must equal the map's mean over
        %   the same frames.
            rng(5);
            srate = 250; nT = 250; nTr = 12;
            [X, R] = testCase.noisyPair(nT, nTr, 20, 0.6);
            input = struct('times', (0:nT - 1) / srate * 1000, 'nbchan', 2, 'srate', srate, ...
                'data', cat(1, reshape(X, 1, nT, nTr), reshape(R, 1, nT, nTr)), ...
                'bindesc', struct('label', {'A'}, 'trials', {1:nTr}, 'combo', {[]}));
            opts = struct('Method', 'STFT', 'RefIndex', 2, 'MinFreq', 10, 'MaxFreq', 40, ...
                'NumFreqs', 10, 'WindowMs', 200, 'PadRatio', 2, 'Taper', 'Hann');

            [coh, freqs] = ComputeCoherenceMap(input, opts);
            fi = find(freqs > 15, 1);                              % a grid frequency near 20 Hz
            fromMap = mean(coh(1, fi, :, 1), 3);

            got = TransTools.FrameCoherence(X, R, srate, freqs(fi), struct('WinSize', 50));

            testCase.verifyEqual(got, fromMap, 'AbsTol', 1e-10);
            testCase.verifyGreaterThan(got, 0.2, 'The comparison must not be between two near-zero numbers.');
        end

        function aScalarMultipleOfTheReferenceIsExactlyCoherent(testCase)
            rng(6);
            [~, R] = testCase.noisyPair(400, 10, 12, 0.5);

            [coh, lag] = TransTools.FrameCoherence(3 * R, R, 250, [12 30.5], struct('WinSize', 80));

            testCase.verifyEqual(coh, [1 1], 'AbsTol', 1e-9);
            testCase.verifyEqual(lag, [0 0], 'AbsTol', 1e-9);
        end

        function independentSignalsAreNearTheChanceLevel(testCase)
            rng(7);
            nTr = 40;
            X = randn(500, nTr);
            R = randn(500, nTr);

            coh = TransTools.FrameCoherence(X, R, 250, 20, struct('WinSize', 100));

            testCase.verifyLessThan(coh, 0.1, 'Chance for 40 trials is about 1/40.');
        end

        function theCrossSpectrumPhaseIsTheLag(testCase)
        %THECROSSSPECTRUMPHASEISTHELAG  X leads R by a constant phase at 20 Hz on every
        %   trial, whatever the trial's own start phase, so the circular mean of the
        %   cross-spectrum's phase is that lag.
            rng(8);
            srate = 250; nT = 500; nTr = 15; lagRad = 0.7;
            t = (0:nT - 1).' / srate;
            start = 2 * pi * rand(1, nTr);
            R = cos(2 * pi * 20 * t + start) + 0.05 * randn(nT, nTr);
            X = cos(2 * pi * 20 * t + start + lagRad) + 0.05 * randn(nT, nTr);

            [coh, lag] = TransTools.FrameCoherence(X, R, srate, 20, struct('WinSize', 100));

            testCase.verifyGreaterThan(coh, 0.9);
            testCase.verifyEqual(lag, lagRad, 'AbsTol', 0.05);
        end

        function aTrialWithNaNIsAsIfItWereAbsent(testCase)
            rng(9);
            [X, R] = testCase.noisyPair(400, 14, 15, 0.7);
            blanked = X;
            blanked(:, 5) = NaN;
            opts = struct('WinSize', 80);

            got = TransTools.FrameCoherence(blanked, R, 250, [15 22], opts);
            wanted = TransTools.FrameCoherence(X(:, [1:4 6:14]), R(:, [1:4 6:14]), 250, [15 22], opts);

            testCase.verifyEqual(got, wanted, 'AbsTol', 1e-12);
            testCase.verifyFalse(any(isnan(got)));
        end

        function fewerThanTwoUsableTrialsHaveNoCoherence(testCase)
            rng(10);
            [X, R] = testCase.noisyPair(300, 6, 15, 0.7);

            testCase.verifyTrue(isnan(TransTools.FrameCoherence(X(:, 1), R(:, 1), 250, 15, struct('WinSize', 80))), ...
                'One trial is coherent with anything by construction, so it has no coherence.');
            allBlank = X;
            allBlank(:, 2:end) = NaN;
            testCase.verifyTrue(isnan(TransTools.FrameCoherence(allBlank, R, 250, 15, struct('WinSize', 80))));
        end

        function onlyFramesCentredInTheWindowAreAveraged(testCase)
        %ONLYFRAMESCENTREDINTHEWINDOWAREAVERAGED  X follows R for the first second and
        %   is independent noise for the second. The window over the first second sees
        %   high coherence, the window over the second sees chance.
            rng(11);
            srate = 250; nT = 500; nTr = 25;
            t = (0:nT - 1).' / srate;
            R = cos(2 * pi * 20 * t + 2 * pi * rand(1, nTr)) + 0.2 * randn(nT, nTr);
            X = R + 0.2 * randn(nT, nTr);
            X(251:end, :) = randn(250, nTr);
            times = t.' * 1000;
            opts = struct('WinSize', 60, 'Times', times);
            earlyOpts = opts; earlyOpts.TimeStart = 0;    earlyOpts.TimeStop = 900;
            lateOpts  = opts; lateOpts.TimeStart = 1100;  lateOpts.TimeStop = 2000;

            early = TransTools.FrameCoherence(X, R, srate, 20, earlyOpts);
            late = TransTools.FrameCoherence(X, R, srate, 20, lateOpts);
            whole = TransTools.FrameCoherence(X, R, srate, 20, struct('WinSize', 60));

            testCase.verifyGreaterThan(early, 0.7);
            testCase.verifyLessThan(late, 0.2);
            testCase.verifyLessThan(whole, early);
            testCase.verifyGreaterThan(whole, late);
        end

        function aWindowThatHoldsNoFrameGivesNaNAndTheFrameCount(testCase)
            rng(12);
            [X, R] = testCase.noisyPair(300, 8, 15, 0.7);
            times = (0:299) * 4;
            [coh, ~, n] = TransTools.FrameCoherence(X, R, 250, 15, ...
                struct('WinSize', 60, 'Times', times, 'TimeStart', 5000, 'TimeStop', 6000));

            testCase.verifyTrue(isnan(coh));
            testCase.verifyEqual(n, 0);
        end

        function aResponseIsFoundAtItsOwnFrequencyNotNextDoor(testCase)
            rng(13);
            [X, R] = testCase.noisyPair(500, 20, 20, 0.4);

            coh = TransTools.FrameCoherence(X, R, 250, [20 45], struct('WinSize', 100));

            testCase.verifyGreaterThan(coh(1), 5 * coh(2));
        end

        function aSingleFrameIsTheCoherenceOfThatFrame(testCase)
        %ASINGLEFRAMEISTHECOHERENCEOFTHATFRAME  When only one frame fits, the
        %   frame index is a row vector, and the segment came out as a column: the
        %   product with the kernel failed, so SpectralMeasure could not run with
        %   the default 510-sample frame on any epoch shorter than about 640
        %   samples. Both ways of getting one frame are checked, a window longer
        %   than the epoch (shortened to it) and one a few samples shorter, against
        %   the formula written out for that one frame.
            rng(14);
            nT = 200;
            [X, R] = testCase.noisyPair(nT, 15, 20, 0.6);
            for win = [510 190]
                [coh, lag, n] = TransTools.FrameCoherence(X, R, 250, [20 33], struct('WinSize', win));

                used = min(win, nT);
                taper = 0.5 - 0.5 * cos(2 * pi * (0:used - 1).' / (used - 1));
                kernel = exp(-2i * pi * ((0:used - 1).' * [20 33]) / 250) .* taper;
                Cx = X(1:used, :).' * kernel;                 % trials x frequencies
                Cr = R(1:used, :).' * kernel;
                Sxy = sum(Cx .* conj(Cr), 1);
                want = abs(Sxy) .^ 2 ./ (sum(abs(Cx) .^ 2, 1) .* sum(abs(Cr) .^ 2, 1));

                testCase.verifyEqual(n, 1, sprintf('A %d-sample window on %d samples fits once.', win, nT));
                testCase.verifyEqual(coh, want, 'AbsTol', 1e-12);
                testCase.verifyEqual(lag, angle(Sxy), 'AbsTol', 1e-12);
            end
        end

        function anUnknownTaperIsRefused(testCase)
            [X, R] = testCase.noisyPair(300, 5, 15, 0.7);
            testCase.verifyError(@() TransTools.FrameCoherence(X, R, 250, 15, ...
                struct('WinSize', 60, 'Taper', 'Kaiser')), 'Alakazam:FrameCoherence');
        end
    end

    methods (Access = private)
        function [X, R] = noisyPair(~, nT, nTr, f0, noise)
        %NOISYPAIR  Two channels sharing a tone at F0 with a random start phase on
        %   every trial, each with its own independent noise.
            t = (0:nT - 1).' / 250;
            tone = cos(2 * pi * f0 * t + 2 * pi * rand(1, nTr));
            X = tone + noise * randn(nT, nTr);
            R = tone + noise * randn(nT, nTr);
        end
    end
end
