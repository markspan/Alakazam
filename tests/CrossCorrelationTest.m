classdef CrossCorrelationTest < matlab.unittest.TestCase
%CROSSCORRELATIONTEST  Unit tests for
%   src/Transformations/CrossCorrelation/CrossCorrelation.m.
%
%   THE CASE THAT MATTERS MOST is matchesANaivePerLagReference: the FFT
%   formulation computes all lags at once, and FFT lag indexing and sign
%   conventions are exactly where such code goes quietly wrong. So the
%   result is checked against an obviously-correct double loop written
%   independently below, not against the transform's own arithmetic.
%
%   Run with: runtests('tests/CrossCorrelationTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'CrossCorrelation'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Dialogs'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function matchesANaivePerLagReference(testCase)
        %MATCHESANAIVEPERLAGREFERENCE  One trial, so no Fisher-z averaging
        %   is involved and the output is directly a per-lag Pearson r --
        %   compared against a plain loop over lags using corr-by-hand.
            EEG = testCase.singleTrialFixture();
            o = testCase.opts('Fz', 40);

            out = CrossCorrelation(EEG, o);

            x = double(EEG.data(1, :, 1)).';        % Fz is the reference
            y = double(EEG.data(2, :, 1)).';        % Pz
            maxLag = round(40 * EEG.srate / 1000);
            expected = testCase.naiveLaggedPearson(x, y, maxLag);

            pz = find(strcmpi(out.xcorrLabels, 'Pz'), 1);
            testCase.verifyEqual(out.xcorr(pz, :, 1), expected, 'AbsTol', 1e-9);
        end

        function aKnownDelayShowsUpAtTheRightLagAndSign(testCase)
        %AKNOWNDELAYSHOWSUPATTHERIGHTLAGANDSIGN  The sign convention, pinned
        %   against a planted delay: Pz is Fz shifted LATER by 20 ms, so the
        %   peak must sit at +20 ms ("the channel follows the reference").
            EEG = testCase.singleTrialFixture();
            shiftSamples = round(20 * EEG.srate / 1000);
            base = double(EEG.data(1, :, 1));
            delayed = [zeros(1, shiftSamples), base(1:end - shiftSamples)];
            EEG.data(2, :, 1) = delayed;

            out = CrossCorrelation(EEG, testCase.opts('Fz', 80));

            pz = find(strcmpi(out.xcorrLabels, 'Pz'), 1);
            testCase.verifyEqual(out.xcorrPeakLagMs(pz, 1), 20, 'AbsTol', 4.1, ...
                'A channel delayed by 20 ms must peak at +20 ms.');
            testCase.verifyGreaterThan(out.xcorrPeakR(pz, 1), 0.9);
        end

        function selfCorrelationPeaksAtZeroLagWithRofOne(testCase)
            EEG = testCase.singleTrialFixture();
            out = CrossCorrelation(EEG, testCase.opts('Fz', 40));

            fz = find(strcmpi(out.xcorrLabels, 'Fz'), 1);
            zeroLag = find(abs(out.xcorrLags) < 1e-9, 1);
            testCase.verifyEqual(out.xcorr(fz, zeroLag, 1), 1, 'AbsTol', 1e-6, ...
                'A channel against itself is r = 1 at lag 0.');
            testCase.verifyEqual(out.xcorrPeakLagMs(fz, 1), 0, 'AbsTol', 1e-9);
        end

        function everyValueIsABoundedCorrelation(testCase)
        %EVERYVALUEISABOUNDEDCORRELATION  The point of normalising per lag on
        %   the overlap rather than by whole-segment statistics: every value
        %   is a real Pearson r, including at the largest lags where the
        %   overlap is shortest.
            EEG = testCase.fixture();
            out = CrossCorrelation(EEG, testCase.opts('Fz', 300));

            finite = out.xcorr(isfinite(out.xcorr));
            testCase.verifyLessThanOrEqual(max(finite), 1 + 1e-12);
            testCase.verifyGreaterThanOrEqual(min(finite), -1 - 1e-12);
        end

        function fisherZAveragingIsUsedAcrossTrials(testCase)
        %FISHERZAVERAGINGISUSEDACROSSTRIALS  Averaging r directly is biased
        %   toward zero; this checks the transform reports tanh(mean(atanh))
        %   rather than mean(r), which differ measurably once r is large and
        %   varies across trials.
            EEG = testCase.twoTrialFixture(0.95, 0.5);   % planted per-trial r
            out = CrossCorrelation(EEG, testCase.opts('Fz', 0));

            pz = find(strcmpi(out.xcorrLabels, 'Pz'), 1);
            zeroLag = find(abs(out.xcorrLags) < 1e-9, 1);
            got = out.xcorr(pz, zeroLag, 1);

            rPerTrial = zeros(1, 2);
            for t = 1:2
                x = double(EEG.data(1, :, t)).';
                y = double(EEG.data(2, :, t)).';
                rPerTrial(t) = testCase.pearson(x, y);
            end
            fisher = tanh(mean(atanh(rPerTrial)));
            plainMean = mean(rPerTrial);

            testCase.verifyEqual(got, fisher, 'AbsTol', 1e-9);
            testCase.verifyGreaterThan(abs(fisher - plainMean), 1e-4, ...
                'The fixture must actually distinguish the two averages.');
        end

        function rejectedSamplesAreExcludedPairwisePerLag(testCase)
        %REJECTEDSAMPLESAREEXCLUDEDPAIRWISEPERLAG  NaNs must not propagate,
        %   and the surviving value must match the same correlation computed
        %   from only the jointly-finite pairs.
            EEG = testCase.singleTrialFixture();
            EEG.data(2, 30:60, 1) = NaN;

            out = CrossCorrelation(EEG, testCase.opts('Fz', 40));

            testCase.verifyTrue(any(isfinite(out.xcorr(:))), 'NaNs swallowed everything.');
            x = double(EEG.data(1, :, 1)).';
            y = double(EEG.data(2, :, 1)).';
            maxLag = round(40 * EEG.srate / 1000);
            expected = testCase.naiveLaggedPearson(x, y, maxLag);
            pz = find(strcmpi(out.xcorrLabels, 'Pz'), 1);
            testCase.verifyEqual(out.xcorr(pz, :, 1), expected, 'AbsTol', 1e-9);
        end

        function aLagWithTooFewPairsIsNaNNotAConfidentNumber(testCase)
            EEG = testCase.singleTrialFixture();
            o = testCase.opts('Fz', 400);
            o.MinPairs = 150;       % most lags cannot meet this

            out = CrossCorrelation(EEG, o);

            testCase.verifyTrue(any(isnan(out.xcorr(:))), ...
                'Lags with too little overlap should be refused, not estimated.');
            zeroLag = find(abs(out.xcorrLags) < 1e-9, 1);
            testCase.verifyTrue(isfinite(out.xcorr(1, zeroLag, 1)), ...
                'Lag zero has the full overlap and must survive.');
        end

        function anUnknownReferenceChannelIsAnError(testCase)
            EEG = testCase.fixture();
            testCase.verifyError(@() CrossCorrelation(EEG, testCase.opts('NoSuchChannel', 40)), ...
                'Alakazam:CrossCorrelation');
        end

        function eachBinIsEstimatedSeparately(testCase)
            EEG = testCase.fixture();
            EEG.bindesc = struct('label', {'a', 'b'}, 'index', {1, 2}, ...
                'trials', {[1 2], [3 4]});

            out = CrossCorrelation(EEG, testCase.opts('Fz', 40));

            testCase.assertEqual(size(out.xcorr, 3), 2);
            testCase.verifyEqual(out.xcorrBinLabels, {'a', 'b'});
            testCase.verifyEqual(out.xcorrTrials, [2 2]);
        end
    end

    methods (Access = private)
        function EEG = fixture(~)
            EEG = makeTestEEG('nbchan', 3, 'labels', {'Fz', 'Pz', 'Oz'});
            rng(3);
            EEG.data = EEG.data + randn(size(EEG.data));
        end

        function EEG = singleTrialFixture(testCase)
            EEG = testCase.fixture();
            EEG.data = EEG.data(:, :, 1);
            EEG.trials = 1;
        end

        function EEG = twoTrialFixture(testCase, r1, r2)
        %TWOTRIALFIXTURE  Two trials whose Fz/Pz correlation is planted at
        %   approximately r1 and r2, so Fisher-z and plain averaging differ.
            EEG = testCase.fixture();
            EEG.data = EEG.data(:, :, 1:2);
            EEG.trials = 2;
            rng(21);
            n = size(EEG.data, 2);
            targets = [r1, r2];
            for t = 1:2
                target = targets(t);
                x = randn(n, 1);
                e = randn(n, 1);
                y = target * x + sqrt(1 - target^2) * e;
                EEG.data(1, :, t) = x;
                EEG.data(2, :, t) = y;
            end
        end

        function r = naiveLaggedPearson(testCase, x, y, maxLag)
        %NAIVELAGGEDPEARSON  The obvious implementation: for each lag, take
        %   the overlapping, jointly-finite pairs and correlate them. Slow,
        %   and independent of the code under test, which is the point.
            lags = -maxLag:maxLag;
            r = nan(1, numel(lags));
            n = numel(x);
            for k = 1:numel(lags)
                L = lags(k);
                t = max(1, 1 - L):min(n, n - L);
                a = x(t);
                b = y(t + L);
                ok = isfinite(a) & isfinite(b);
                if nnz(ok) < 20
                    continue;
                end
                r(k) = testCase.pearson(a(ok), b(ok));
            end
        end

        function r = pearson(~, a, b)
        %PEARSON  Pearson r of two equal-length finite vectors, by hand.
            a = a(:) - mean(a);
            b = b(:) - mean(b);
            den = sqrt(sum(a.^2) * sum(b.^2));
            if den <= 0
                r = NaN;
            else
                r = sum(a .* b) / den;
            end
        end

        function o = opts(~, refChannel, maxLagMs)
            o = struct('RefChannel', refChannel, 'Channels', {{}}, ...
                'MaxLagMs', maxLagMs, 'MinPairs', 20, 'Start', 0, 'Stop', 0);
        end
    end
end
