classdef NoiseCovarianceTest < matlab.unittest.TestCase
%NOISECOVARIANCETEST  The baseline noise covariance: what Average stores,
%   how it follows the channels, and how dSPM uses it.
%
%   Average stores, per bin, the covariance of a single trial's baseline
%   (FieldTrip's ft_timelockanalysis definition, pooled over every clean
%   trial) divided by the trials that bin's average holds. dSPM then
%   prewhitens with it, by FieldTrip's own ft_inverse_mne, and divides by
%   the noise it implies. The cases that need FieldTrip skip without it.
%
%   See also AVERAGE, TRANSTOOLS.BINNOISECOVARIANCE, TRANSTOOLS.INVERSESOLUTION.

    properties (Constant)
        NChan = 12
        NSrc  = 25
        NTime = 10
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'Average'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- what Average stores ----------------------------------------
        function eachBinCarriesTheNoiseOfItsAverage(testCase)
            EEG = epochs(4, 6);
            EEG.bindesc(1) = struct('index', 1, 'label', 'A', 'trials', [1 2 3], 'combo', []);
            EEG.bindesc(2) = struct('index', 2, 'label', 'B', 'trials', [4 5 6], 'combo', []);
            EEG.bindesc(3) = struct('index', 3, 'label', 'A-B', 'trials', [], ...
                'combo', struct('bin', {1, 2}, 'coeff', {1, -1}));
            result = Average(EEG);

            C1 = byHand(EEG.data(:, EEG.times <= 0, :));
            testCase.verifyEqual(result.noiseCov(:, :, 1), C1 / 3, 'AbsTol', 1e-12, ...
                'Pooled over every trial, divided by the trials the average holds.');
            testCase.verifyEqual(result.noiseCov(:, :, 2), C1 / 3, 'AbsTol', 1e-12);
            testCase.verifyEqual(result.noiseCov(:, :, 3), C1 / 3 + C1 / 3, 'AbsTol', 1e-12, ...
                'A difference of independent averages adds their noise.');
            testCase.verifyEqual(result.noiseCovInfo.nTrials, 6);
            testCase.verifyEqual(result.noiseCovInfo.windowMs, [-200 0], ...
                'The baseline is FieldTrip''s prestim: up to and including zero.');
        end

        function aRejectedTrialIsLeftOutOfTheCovariance(testCase)
            EEG = epochs(4, 6);
            EEG.data(1, 3, 2) = NaN;      % one rejected sample, in the baseline
            EEG.bindesc(1) = struct('index', 1, 'label', 'A', 'trials', 1:6, 'combo', []);
            result = Average(EEG);
            clean = [1 3 4 5 6];
            C1 = byHand(EEG.data(:, EEG.times <= 0, clean));
            testCase.verifyEqual(result.noiseCovInfo.nTrials, 5);
            testCase.verifyEqual(result.noiseCov(:, :, 1), C1 / result.bindesc(1).n, 'AbsTol', 1e-12);
        end

        function noBaselineNoCovariance(testCase)
            EEG = epochs(3, 4, [0 400]);
            EEG.bindesc(1) = struct('index', 1, 'label', 'A', 'trials', 1:4, 'combo', []);
            result = Average(EEG);
            testCase.verifyEmpty(result.noiseCov, ...
                'With nothing before the event there is no noise to estimate.');
            testCase.verifyEmpty(TransTools.BinNoiseCovariance(result, 1, {'Ch1', 'Ch2'}));
        end

        % ---- following the channels -------------------------------------
        function aBinsCovarianceIsReadByLabel(testCase)
            result = averagedWithBins();
            full = result.noiseCov(:, :, 1);
            C = TransTools.BinNoiseCovariance(result, 1, {'ch3', 'Ch1'});
            testCase.verifyEqual(C, full([3 1], [3 1]), 'In the order asked for, by label.');
            testCase.verifyEmpty(TransTools.BinNoiseCovariance(result, 1, {'Ch1', 'Cz'}), ...
                'A channel the average did not have: no covariance.');
            testCase.verifyEmpty(TransTools.BinNoiseCovariance(result, 9, {'Ch1'}));
        end

        function aChannelEditKeepsItInStep(testCase)
            result = averagedWithBins();
            before = result.noiseCov;

            dropped = result;
            dropped.data = dropped.data([1 3 4], :, :);
            dropped.chanlocs = dropped.chanlocs([1 3 4]);
            dropped = TransTools.AlignChannelCompanions(dropped, result.chanlocs);
            testCase.verifyEqual(dropped.noiseCov, before([1 3 4], [1 3 4], :));

            derived = result;
            derived.data(end + 1, :, :) = 0;
            derived.chanlocs(end + 1).labels = 'Derived';
            derived = TransTools.AlignChannelCompanions(derived, result.chanlocs);
            testCase.verifyEqual(derived.noiseCov(1:4, 1:4, :), before);
            testCase.verifyTrue(all(isnan(derived.noiseCov(5, :, 1))));
            testCase.verifyEmpty(TransTools.BinNoiseCovariance(derived, 1, {'Ch1', 'Derived'}), ...
                'A derived channel has no noise covariance of its own.');
            testCase.verifyNotEmpty(TransTools.BinNoiseCovariance(derived, 1, {'Ch1', 'Ch2'}));
        end

        function aGrandAverageCarriesNone(testCase)
            folder = tempname;
            mkdir(folder);
            cleanUp = onCleanup(@() rmdir(folder, 's'));
            files = cell(1, 2);
            for s = 1:2
                EEG = averagedWithBins(s);
                files{s} = fullfile(folder, sprintf('s%d.mat', s));
                save(files{s}, 'EEG');
            end
            grand = GrandAverage(files, false);
            testCase.verifyEmpty(grand.noiseCov, ...
                'Not the first subject''s: a grand average has no trials of its own.');
        end

        % ---- the model and the key ---------------------------------------
        function theNoiseModelIsResolvedAsAsked(testCase)
            id = 'Test:noise';
            testCase.verifyEqual(TransTools.ResolveNoiseModel('auto', 'mne', true, id), 'baseline');
            testCase.verifyEqual(TransTools.ResolveNoiseModel('auto', 'mne', false, id), 'identity');
            testCase.verifyEqual(TransTools.ResolveNoiseModel('identity', 'mne', true, id), 'identity');
            testCase.verifyEqual(TransTools.ResolveNoiseModel('baseline', 'sloreta', true, id), 'identity', ...
                'Only dSPM uses a noise covariance.');
            testCase.verifyError(@() TransTools.ResolveNoiseModel('baseline', 'mne', false, id), id);
        end

        function theKeySaysWhichNoiseModel(testCase)
            labels = {'Fz', 'Cz'};
            identity = SourceCache.Key(labels, struct('Method', 'mne', 'NoiseModel', 'identity'));
            baseline = SourceCache.Key(labels, struct('Method', 'mne', 'NoiseModel', 'baseline', 'SNR', 3));
            other    = SourceCache.Key(labels, struct('Method', 'mne', 'NoiseModel', 'baseline', 'SNR', 5));
            testCase.verifyFalse(isequaln(identity, baseline));
            testCase.verifyFalse(isequaln(baseline, other), 'The SNR is part of the baseline estimate.');
            testCase.verifyTrue(isequaln(identity, SourceCache.Key(labels, ...
                struct('Method', 'mne', 'NoiseModel', 'identity', 'SNR', 7))), ...
                'The SNR means nothing without the baseline model.');
        end

        % ---- against FieldTrip -------------------------------------------
        function theCovarianceIsFieldTrips(testCase)
            FieldTripFixtures.require(testCase);
            EEG = epochs(5, 8);
            EEG.bindesc(1) = struct('index', 1, 'label', 'A', 'trials', 1:8, 'combo', []);
            result = Average(EEG);
            raw = struct('label', {{EEG.chanlocs.labels}'}, 'fsample', EEG.srate);
            for k = 1:8
                raw.trial{k} = EEG.data(:, :, k);
                raw.time{k}  = EEG.times / 1000;
            end
            cfg = struct('covariance', 'yes', 'covariancewindow', [-inf 0]);
            tl = FieldTripFixtures.quietly(@() ft_timelockanalysis(cfg, raw));
            testCase.verifyEqual(result.noiseCov(:, :, 1) * 8, tl.cov, 'RelTol', 1e-10, ...
                'Average''s single-trial covariance is ft_timelockanalysis''s.');
        end

        function dspmIsFieldTripsPrewhitenedMinimumNorm(testCase)
            FieldTripFixtures.require(testCase);
            [lf, elec, headmodel, values, C] = testCase.forwardFixture();
            out = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, headmodel, ...
                'mne', struct('NoiseCov', C, 'SNR', 3)));

            n = testCase.NChan;
            H = eye(n) - 1 / n;
            Cn = H * C * H;
            Cn = (Cn + Cn') / 2;
            v = values - mean(values, 1);
            est = FieldTripFixtures.quietly(@() ft_inverse_mne(lf, elec, headmodel, v, ...
                'noisecov', Cn, 'prewhiten', 'yes', 'scalesourcecov', 'yes', 'snr', 3, ...
                'keepfilter', 'yes'));
            M = cell2mat(cellfun(@(w) w, est.filter(:), 'UniformOutput', false));
            J = (M * v) ./ sqrt(sum((M * Cn) .* M, 2));
            expected = reshape(sqrt(sum(reshape(J, 3, testCase.NSrc, []) .^ 2, 1)), testCase.NSrc, []);
            testCase.verifyEqual(out, expected, 'RelTol', 1e-9, ...
                'The filter is FieldTrip''s, and dSPM divides by the noise it implies.');

            [~, info] = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, ...
                headmodel, 'mne', struct('NoiseCov', C, 'SNR', 3)));
            testCase.verifyEqual(info.NoiseModel, 'baseline');
            testCase.verifyEqual(info.Lambda, 1 / 9, 'AbsTol', 1e-15);
        end

        function fewerTrialsGiveTheSameFilterAndALowerDspm(testCase)
        %   An average of N trials carries C/N. With prewhitening and the
        %   source covariance scaled to it, the filter does not change, and
        %   dSPM grows by sqrt(N): the same response is that much further
        %   above the noise of a cleaner average.
            FieldTripFixtures.require(testCase);
            [lf, elec, headmodel, values, C] = testCase.forwardFixture();
            one = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, headmodel, ...
                'mne', struct('NoiseCov', C)));
            four = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, headmodel, ...
                'mne', struct('NoiseCov', C / 4)));
            testCase.verifyEqual(four, 2 * one, 'RelTol', 1e-8);
        end

        function theCovarianceChangesTheEstimate(testCase)
            FieldTripFixtures.require(testCase);
            [lf, elec, headmodel, values, C] = testCase.forwardFixture();
            white = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, headmodel, 'mne'));
            coloured = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, ...
                headmodel, 'mne', struct('NoiseCov', C)));
            testCase.verifyGreaterThan(norm(normalise(coloured) - normalise(white)), 0.05, ...
                'A non-white noise covariance whitens a different map.');
            sl  = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, headmodel, 'sloreta'));
            [slNoise, info] = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, ...
                headmodel, 'sloreta', struct('NoiseCov', C)));
            testCase.verifyEqual(slNoise, sl, 'sLORETA is FieldTrip''s, on the data covariance.');
            testCase.verifyEqual(info.NoiseModel, 'identity');
        end
    end

    methods (Access = private)
        function [lf, elec, headmodel, values, C] = forwardFixture(testCase)
        %FORWARDFIXTURE  SourceInverseTest's synthetic forward model, with a
        %   noise covariance far from white: correlated, and unequal across
        %   channels.
            rng(23);
            n = testCase.NChan;
            elecPos = randn(n, 3);
            elecPos = 9 * elecPos ./ vecnorm(elecPos, 2, 2);
            srcPos  = randn(testCase.NSrc, 3) * 2;
            labels = arrayfun(@(k) sprintf('E%d', k), 1:n, 'UniformOutput', false);
            elec = struct('label', {labels(:)}, 'elecpos', elecPos, 'chanpos', elecPos, 'unit', 'cm');
            headmodel = struct('type', 'singlesphere', 'o', [0 0 0], 'r', 9, 'cond', 0.33, 'unit', 'cm');
            gain = cell(1, testCase.NSrc);
            for i = 1:testCase.NSrc
                d = elecPos - srcPos(i, :);
                gain{i} = d ./ (vecnorm(d, 2, 2) .^ 3);
            end
            lf = struct('pos', srcPos, 'inside', true(testCase.NSrc, 1), 'leadfield', {gain}, ...
                'label', {labels(:)}, 'unit', 'cm');
            values = randn(n, testCase.NTime) * 1e-6;
            A = randn(n) .* (1 + (1:n)' / 2);
            C = (A * A') * 1e-13 / n;
        end
    end
end

% ======================================================================= %
function EEG = epochs(nChan, nTrials, epochMs)
    if nargin < 3
        epochMs = [-200 596];
    end
    EEG = makeTestEEG('nbchan', nChan, 'trials', nTrials, 'epochMs', epochMs);
    rng(7);
    EEG.data = randn(size(EEG.data)) .* (1:nChan)';
end

function result = averagedWithBins(seed)
    if nargin < 1
        seed = 1;
    end
    EEG = epochs(4, 6);
    rng(seed);
    EEG.data = randn(size(EEG.data));
    EEG.bindesc(1) = struct('index', 1, 'label', 'A', 'trials', [1 2 3], 'combo', []);
    EEG.bindesc(2) = struct('index', 2, 'label', 'B', 'trials', [4 5 6], 'combo', []);
    result = Average(EEG);
end

function C = byHand(baseline)
%BYHAND  FieldTrip's definition, written out: each trial demeaned in the
%   window, x*x' summed over trials, divided by the summed samples less one
%   per trial. The clean trials only.
    clean = squeeze(all(all(isfinite(baseline), 1), 2));
    baseline = baseline(:, :, clean);
    [nChan, nSmp, n] = size(baseline);
    C = zeros(nChan);
    for k = 1:n
        x = baseline(:, :, k) - mean(baseline(:, :, k), 2);
        C = C + x * x';
    end
    C = C / (n * (nSmp - 1));
end

function y = normalise(x)
    x = x(isfinite(x));
    y = x / max(abs(x));
end
