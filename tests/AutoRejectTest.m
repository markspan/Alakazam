classdef AutoRejectTest < matlab.unittest.TestCase
%AUTOREJECTTEST  AutoReject, Alakazam's implementation of local autoreject
%   (Jas et al., 2017, NeuroImage 159:417).
%
%   Two halves. The ALGORITHM is tested without EEGLAB, against its
%   definition: the folds are scikit-learn's KFold, each channel's threshold
%   is the exact minimum of autoreject's cross-validation error (checked
%   against a brute-force evaluation of that error written out here), the
%   repair takes the worst channels, and the consensus search keeps
%   autoreject's two rules and its tie-break. The TRANSFORMATION is tested
%   on a synthetic recording on a real montage (makeScalpEEG), where epochs
%   wrecked on every channel must be rejected and epochs with one bad
%   channel repaired, whatever consensus the cross-validation settles on.
%
%   Run with: runtests('tests/AutoRejectTest.m').
%
%   See also AUTOREJECT, AUTOREJECTTHRESHOLDS, AUTOREJECTCONSENSUS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'AutoReject'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- the algorithm ----------------------------------------------
        function theFoldsAreScikitLearnsKFold(testCase)
        %THEFOLDSARESCIKITLEARNSKFOLD  Contiguous, in order, the first
        %   mod(n, k) folds one larger: KFold(n_splits=10) with no shuffle,
        %   which is what autoreject's cv=10 becomes.
            folds = autorejectFolds(47, 10);

            testCase.verifyEqual(cellfun(@numel, folds), [5 5 5 5 5 5 5 4 4 4]);
            testCase.verifyEqual([folds{:}], 1:47);
        end

        function tooFewEpochsForTheFoldsIsRefused(testCase)
            testCase.verifyError(@() autorejectFolds(7, 10), 'Alakazam:AutoReject');
        end

        function theThresholdSearchIsExact(testCase)
        %THETHRESHOLDSEARCHISEXACT  The running-mean search scores every
        %   candidate exactly as autoreject's own objective does (keep the
        %   training epochs at or below the threshold, never fewer than the
        %   smallest; RMS distance of their mean from the held-out median;
        %   averaged over folds), and picks its minimum.
            [X, folds] = testCase.channelsWithArtefacts();

            [thresholds, curves] = autorejectThresholds(X, folds);

            for c = 1:size(X, 1)
                [expected, curve] = bruteForceThreshold(X, c, folds);
                testCase.verifyEqual(curves(c).error, curve, 'AbsTol', 1e-9);
                testCase.verifyEqual(thresholds(c), expected, ...
                    sprintf('Channel %d: not the minimum of the criterion.', c));
            end
        end

        function aChannelsArtefactsFallAboveItsThreshold(testCase)
            [X, folds, artefacts] = testCase.channelsWithArtefacts();

            thresholds = autorejectThresholds(X, folds);

            ptp = reshape(max(X, [], 2) - min(X, [], 2), size(X, 1), []);
            testCase.verifyTrue(all(ptp(2, artefacts) > thresholds(2)));
            testCase.verifyLessThan(nnz(ptp(2, :) > thresholds(2)), numel(artefacts) + 5, ...
                'The threshold should not throw away most of the clean epochs as well.');
        end

        function theRepairPlanTakesTheWorstChannels(testCase)
            ptp = [10 50 30 90 70]';
            bad = logical([0 1 1 1 1]');

            plan = autorejectRepairPlan(ptp, bad, 2);

            testCase.verifyEqual(find(plan)', [4 5], 'The two largest peak-to-peak values.');
            testCase.verifyEqual(autorejectRepairPlan(ptp, bad, 4), bad, ...
                'With room for all of them, every bad channel is interpolated.');
        end

        function aConsensusAtOrBelowRhoIsNeverChosen(testCase)
        %ACONSENSUSATORBELOWRHOISNEVERCHOSEN  autoreject's rule: when
        %   kappa * nChan <= rho, an epoch would be repaired and rejected by
        %   the same channels, so the pair scores infinity.
            [X, bad, ptp, folds] = testCase.consensusProblem();
            kappaGrid = linspace(0, 1, 11);
            rhoGrid = [1 4 7];

            [~, ~, loss] = autorejectConsensus(X, bad, ptp, folds, kappaGrid, rhoGrid, @(plan) meanOfOthers(X, plan));

            forbidden = kappaGrid(:) * size(X, 1) <= rhoGrid;
            testCase.verifyTrue(all(isinf(loss(forbidden))));
            testCase.verifyTrue(all(isfinite(loss(~forbidden))), ...
                'Every allowed pair should leave epochs to average here.');
        end

        function theChosenPairIsTheFirstMinimum(testCase)
        %THECHOSENPAIRISTHEFIRSTMINIMUM  The minimum mean loss, and on a tie
        %   the first in (kappa, rho) order, which is numpy's argmin over
        %   autoreject's kappa x rho array.
            [X, bad, ptp, folds] = testCase.consensusProblem();
            kappaGrid = linspace(0, 1, 11);
            rhoGrid = [1 4 7];

            [kappa, rho, loss] = autorejectConsensus(X, bad, ptp, folds, kappaGrid, rhoGrid, @(plan) meanOfOthers(X, plan));

            best = min(loss(:));
            [i, j] = find(loss == best);
            first = sortrows([i j]);
            testCase.verifyEqual([kappa, rho], [kappaGrid(first(1, 1)), rhoGrid(first(1, 2))]);
        end

        function theLossIsTheDistanceFromTheHeldOutMedian(testCase)
            [X, bad, ptp, folds] = testCase.consensusProblem();
            kappaGrid = 0.5;
            rhoGrid = 1;
            interpolate = @(plan) meanOfOthers(X, plan);

            [~, ~, loss] = autorejectConsensus(X, bad, ptp, folds, kappaGrid, rhoGrid, interpolate);

            repaired = interpolate(autorejectRepairPlan(ptp, bad, 1));
            counts = sum(bad, 1);
            expected = 0;
            for f = 1:numel(folds)
                train = setdiff(1:size(X, 3), folds{f});
                kept = train(counts(train) < 0.5 * size(X, 1));
                difference = median(X(:, :, folds{f}), 3) - mean(repaired(:, :, kept), 3);
                expected = expected + sqrt(mean(difference(:) .^ 2));
            end
            testCase.verifyEqual(loss, expected / numel(folds), 'AbsTol', 1e-9);
        end

        % ---- the transformation ------------------------------------------
        function wreckedEpochsAreRejectedAndOneBadChannelIsRepaired(testCase)
        %WRECKEDEPOCHSAREREJECTEDANDONEBADCHANNELISREPAIRED  An epoch wrecked
        %   on every scalp channel cannot be repaired (at most all but one
        %   channel is interpolated) and is rejected, whatever consensus the
        %   cross-validation settles on. An epoch with one bad channel is
        %   rejected only if a few clean channels also crossed their
        %   thresholds and the consensus is low; where it is kept, its bad
        %   channel, the largest of its epoch, is always among those
        %   interpolated. The seed is fixed, so which case each epoch falls
        %   in does not change from run to run.
            testCase.requireEeglab();
            [EEG, wrecked, oneBad, badChannel] = testCase.recording();

            out = AutoReject(EEG, struct('Folds', 10, 'Interpolate', ''));
            record = out.etc.alz.autoreject;

            testCase.verifyTrue(all(record.rejected(wrecked)));
            testCase.verifyTrue(all(isnan(out.data(:, :, wrecked)), 'all'), ...
                'Every channel of a rejected epoch, the peripheral included, is NaN.');
            kept = oneBad(~record.rejected(oneBad));
            testCase.assertNotEmpty(kept, ...
                'Epochs with one bad channel should mostly be repaired, not rejected.');
            testCase.verifyFalse(any(isnan(out.data(:, :, kept)), 'all'));
            testCase.verifyTrue(all(out.etc.alz.interpolated(badChannel, kept)), ...
                'The repaired channel-epochs are recorded as interpolated.');
            testCase.verifyLessThan(max(abs(out.data(badChannel, :, kept)), [], 'all'), 100, ...
                'The 200 uV noise is gone: the channel is rebuilt from its neighbours.');
        end

        function thePeripheralIsNeverTestedOrRepaired(testCase)
            testCase.requireEeglab();
            [EEG, wrecked] = testCase.recording();
            veog = strcmp({EEG.chanlocs.labels}, 'VEOG');

            out = AutoReject(EEG, struct('Folds', 10));

            kept = setdiff(1:EEG.trials, wrecked);
            kept = kept(~any(isnan(out.data(:, :, kept)), [1 2]));
            testCase.verifyEqual(out.data(veog, :, kept), EEG.data(veog, :, kept));
            testCase.verifyFalse(any(strcmp(out.etc.alz.autoreject.channels, 'VEOG')));
        end

        function aReplayReproducesTheResult(testCase)
        %AREPLAYREPRODUCESTHERESULT  No random split and no random search,
        %   so the stored options give the same thresholds and the same data.
            testCase.requireEeglab();
            EEG = testCase.recording();

            [first, options] = AutoReject(EEG, struct('Folds', 10));
            second = AutoReject(EEG, options);

            testCase.verifyTrue(isequaln(first.data, second.data));
            testCase.verifyEqual(first.etc.alz.autoreject.thresholds, second.etc.alz.autoreject.thresholds);
        end

        function alreadyRejectedEpochsAreLeftAlone(testCase)
            testCase.requireEeglab();
            EEG = testCase.recording();
            EEG.data(:, :, 30) = NaN;

            out = AutoReject(EEG, struct('Folds', 10));

            testCase.verifyTrue(all(isnan(out.data(:, :, 30)), 'all'));
            testCase.verifyFalse(out.etc.alz.autoreject.examined(30));
            testCase.verifyFalse(out.etc.alz.autoreject.rejected(30), ...
                'An epoch already rejected is not counted as AutoReject''s.');
        end

        function continuousDataIsRefused(testCase)
            EEG = makeTestEEG('DataFormat', 'CONTINUOUS');
            testCase.verifyError(@() AutoReject(EEG, struct('Folds', 10)), 'Alakazam:AutoReject');
        end
    end

    methods (Access = private)
        function requireEeglab(testCase)
            try
                EEGLabEnvironment.ensure();
            catch
            end
            testCase.assumeTrue(exist('eeg_interp', 'file') == 2 && exist('pop_chanedit', 'file') == 2, ...
                'EEGLAB is not on the path, so the transformation cannot be exercised.');
        end

        function [X, folds, artefacts] = channelsWithArtefacts(~)
        %CHANNELSWITHARTEFACTS  Three channels of noise, 47 epochs; channel 2
        %   carries three large artefacts and channel 3 a single spike.
            stream = RandStream('mt19937ar', 'Seed', 3);
            X = 10 * randn(stream, 3, 40, 47);
            artefacts = [5 9 30];
            X(2, :, artefacts) = 20 * X(2, :, artefacts);
            X(3, 10, 12) = 300;
            folds = autorejectFolds(47, 10);
        end

        function [X, bad, ptp, folds] = consensusProblem(~)
        %CONSENSUSPROBLEM  Eight channels sharing one waveform plus noise;
        %   five epochs wrecked on six channels, ten with one bad channel.
            stream = RandStream('mt19937ar', 'Seed', 5);
            nChan = 8; nSamples = 50; nEpochs = 60;
            waveform = 10 * sin(2 * pi * (1:nSamples) / 25);
            X = repmat(waveform, [nChan 1 nEpochs]) + 2 * randn(stream, nChan, nSamples, nEpochs);
            X(1:6, :, 1:5) = X(1:6, :, 1:5) + 200 * randn(stream, 6, nSamples, 5);
            for e = 20:29
                c = mod(e, nChan) + 1;
                X(c, :, e) = X(c, :, e) + 150 * randn(stream, 1, nSamples);
            end
            folds = autorejectFolds(nEpochs, 10);
            thresholds = autorejectThresholds(X, folds);
            ptp = reshape(max(X, [], 2) - min(X, [], 2), nChan, nEpochs);
            bad = ptp > thresholds(:);
        end

        function [EEG, wrecked, oneBad, badChannel] = recording(~)
        %RECORDING  60 epochs on the 19 channels of the 10-20 system plus a
        %   VEOG: four wrecked on every scalp channel, six with 200 uV of
        %   noise on C3 alone.
            EEG = makeScalpEEG('extra', {'VEOG'}, 'trials', 60, 'seed', 11);
            stream = RandStream('mt19937ar', 'Seed', 12);
            scalp = 1:19;
            wrecked = [3 17 41 52];
            EEG.data(scalp, :, wrecked) = EEG.data(scalp, :, wrecked) ...
                + 300 * randn(stream, numel(scalp), EEG.pnts, numel(wrecked));
            badChannel = find(strcmp({EEG.chanlocs.labels}, 'C3'));
            oneBad = [8 21 26 33 45 58];
            EEG.data(badChannel, :, oneBad) = EEG.data(badChannel, :, oneBad) ...
                + 200 * randn(stream, 1, EEG.pnts, numel(oneBad));
        end
    end
end

% ======================================================================= %
function [best, curve] = bruteForceThreshold(X, c, folds)
%BRUTEFORCETHRESHOLD  autoreject's _compute_thresh objective, evaluated
%   literally at every candidate: no running means, no sorting tricks.
    nEpochs = size(X, 3);
    x = reshape(X(c, :, :), size(X, 2), nEpochs).';
    delta = max(x, [], 2) - min(x, [], 2);
    candidates = unique(delta);
    curve = zeros(numel(candidates), 1);
    for j = 1:numel(candidates)
        for f = 1:numel(folds)
            train = setdiff(1:nEpochs, folds{f});
            keep = delta(train) <= max(candidates(j), min(delta(train)));
            average = mean(x(train(keep), :), 1);
            target = median(x(folds{f}, :), 1);
            curve(j) = curve(j) + sqrt(mean((target - average) .^ 2));
        end
    end
    curve = curve / numel(folds);
    [~, i] = min(curve);
    best = candidates(i);
end

function Y = meanOfOthers(X, plan)
%MEANOFOTHERS  A stand-in interpolation for the algorithm tests: each
%   planned channel-epoch becomes the mean of that epoch's other channels,
%   which is exact when every channel shares one waveform.
    Y = X;
    for e = 1:size(X, 3)
        badChannels = find(plan(:, e));
        if isempty(badChannels)
            continue;
        end
        good = setdiff(1:size(X, 1), badChannels);
        Y(badChannels, :, e) = repmat(mean(X(good, :, e), 1), numel(badChannels), 1);
    end
end
