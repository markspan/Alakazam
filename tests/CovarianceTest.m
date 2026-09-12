classdef CovarianceTest < matlab.unittest.TestCase
%COVARIANCETEST  Unit tests for src/Transformations/Covariance/Covariance.m.
%
%   The three cases that carry the design, rather than merely covering it:
%   shrinkageMakesASingularEstimateInvertible (why shrinkage is offered at
%   all), completeObservationDeletionKeepsTheMatrixPositiveSemidefinite (why
%   NaNs are handled by dropping whole observations rather than pairwise),
%   and shrinkageLeavesAWellSampledEstimateAlone (that the cure is not worse
%   than the disease when it is not needed).
%
%   Run with: runtests('tests/CovarianceTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'Covariance'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Dialogs'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function itMatchesCovOnCleanData(testCase)
        %ITMATCHESCOVONCLEANDATA  With no shrinkage and nothing rejected,
        %   this must be the ordinary sample covariance -- checked against
        %   MATLAB's own cov(), not against the transform's own working.
            EEG = testCase.fixture();
            out = Covariance(EEG, testCase.opts('Covariance', 'None'));

            X = reshape(double(EEG.data), size(EEG.data, 1), []);
            expected = cov(X', 1);          % normalise by N, as the transform does
            testCase.verifyEqual(out.covariance(:, :, 1), expected, 'AbsTol', 1e-9);
        end

        function correlationHasAUnitDiagonalAndMatchesCorrcoef(testCase)
            EEG = testCase.fixture();
            out = Covariance(EEG, testCase.opts('Correlation', 'None'));

            R = out.covariance(:, :, 1);
            testCase.verifyEqual(diag(R), ones(size(R, 1), 1), 'AbsTol', 1e-12);
            X = reshape(double(EEG.data), size(EEG.data, 1), []);
            testCase.verifyEqual(R, corrcoef(X'), 'AbsTol', 1e-9);
        end

        function shrinkageMakesASingularEstimateInvertible(testCase)
        %SHRINKAGEMAKESASINGULARESTIMATEINVERTIBLE  The reason shrinkage is
        %   offered. With fewer observations than channels the sample
        %   covariance is singular by construction; shrinkage must return
        %   something positive definite and usably conditioned.
            EEG = testCase.wideFixture(12, 6);   % 12 channels, 6 observations

            raw    = Covariance(EEG, testCase.opts('Covariance', 'None'));
            shrunk = Covariance(EEG, testCase.opts('Covariance', 'Ledoit-Wolf'));

            rawEig = eig(raw.covariance(:, :, 1));
            shrunkEig = eig(shrunk.covariance(:, :, 1));

            testCase.verifyLessThan(min(rawEig), 1e-9, ...
                'The raw estimate should be singular here -- that is the premise.');
            testCase.verifyGreaterThan(min(shrunkEig), 1e-9, ...
                'The shrunk estimate must be positive definite.');
            testCase.verifyGreaterThan(shrunk.covShrinkage(1), 0, ...
                'Some shrinkage should have been applied.');
        end

        function shrinkageLeavesAWellSampledEstimateAlone(testCase)
        %SHRINKAGELEAVESAWELLSAMPLEDESTIMATEALONE  The estimator has to back
        %   off when it is not needed, or it would quietly bias every
        %   well-sampled dataset in exchange for helping the scarce ones.
        %
        %   THE DATA HERE IS DELIBERATELY CORRELATED. An earlier version of
        %   this case used plain randn, and the shrinkage came back as 1.0 --
        %   which is correct, not a bug: independent standard-normal
        %   channels have a spherical true covariance, so the shrinkage
        %   target IS the truth and going all the way to it is the right
        %   answer. Testing "the estimator leaves a good estimate alone"
        %   needs a covariance the target is wrong about, i.e. one with real
        %   structure, which is what the mixing below produces.
            EEG = testCase.correlatedFixture(3, 4000);

            raw    = Covariance(EEG, testCase.opts('Covariance', 'None'));
            shrunk = Covariance(EEG, testCase.opts('Covariance', 'Ledoit-Wolf'));

            testCase.verifyLessThan(shrunk.covShrinkage(1), 0.1, ...
                'With plenty of observations the shrinkage should be small.');

            % Compared as a whole matrix (Frobenius), not entry by entry
            % with a relative tolerance: the off-diagonals here are ~1e-3
            % around zero, where a per-entry RelTol is meaningless -- a
            % negligible absolute change reads as a huge relative one.
            A = raw.covariance(:, :, 1);
            B = shrunk.covariance(:, :, 1);
            relative = norm(B - A, 'fro') / norm(A, 'fro');
            testCase.verifyLessThan(relative, 0.1, sprintf( ...
                'A well-sampled estimate should barely move (moved %.3f).', relative));
        end

        function shrinkageStaysWithinZeroAndOne(testCase)
            EEG = testCase.wideFixture(8, 9);
            out = Covariance(EEG, testCase.opts('Covariance', 'Ledoit-Wolf'));

            testCase.verifyGreaterThanOrEqual(out.covShrinkage(1), 0);
            testCase.verifyLessThanOrEqual(out.covShrinkage(1), 1);
        end

        function completeObservationDeletionKeepsTheMatrixPositiveSemidefinite(testCase)
        %COMPLETEOBSERVATIONDELETIONKEEPSTHEMATRIXPOSITIVESEMIDEFINITE  The
        %   reason NaNs are handled by dropping whole time points. Pairwise
        %   deletion would compute each entry from a different sample set,
        %   which can yield a matrix with a negative eigenvalue -- not a
        %   covariance matrix at all.
            EEG = testCase.fixture();
            EEG.data(1, 10:80, 1) = NaN;      % a rejected stretch on one channel
            EEG.data(2, 90:150, 2) = NaN;     % and another elsewhere

            out = Covariance(EEG, testCase.opts('Covariance', 'None'));

            S = out.covariance(:, :, 1);
            testCase.verifyFalse(any(isnan(S(:))), 'NaNs must not reach the matrix.');
            testCase.verifyGreaterThan(min(eig(S)), -1e-9, ...
                'The estimate must be positive semidefinite.');
            testCase.verifyGreaterThan(out.covDropped(1), 0, ...
                'The dropped observations should be counted, not hidden.');
            testCase.verifyEqual(out.covN(1) + out.covDropped(1), ...
                size(EEG.data, 2) * size(EEG.data, 3));
        end

        function eachBinGetsItsOwnMatrixAndObservationCount(testCase)
            EEG = testCase.fixture();
            EEG.bindesc = struct( ...
                'label',  {'few', 'many'}, ...
                'index',  {1, 2}, ...
                'trials', {[1], [2 3 4]});   %#ok<NBRAK2>

            out = Covariance(EEG, testCase.opts('Covariance', 'None'));

            testCase.assertEqual(size(out.covariance, 3), 2);
            testCase.verifyEqual(out.covBinLabels, {'few', 'many'});
            testCase.verifyEqual(out.covN(2), 3 * out.covN(1), ...
                'Three trials should contribute three times the observations.');
        end

        function aBinWithNoTrialsOfItsOwnIsLeftAsNaN(testCase)
        %ABINWITHNOTRIALSOFITSOWNISLEFTASNAN  A combination/difference bin
        %   owns no trials, so there is nothing to estimate from; NaN says
        %   "not estimated" where zeros would claim a real, flat matrix.
            EEG = testCase.fixture();
            EEG.bindesc = struct('label', {'real', 'combo'}, 'index', {1, 2}, ...
                'trials', {[1 2 3 4], []});

            out = Covariance(EEG, testCase.opts('Covariance', 'None'));

            testCase.verifyTrue(all(isfinite(out.covariance(:, :, 1)), 'all'));
            testCase.verifyTrue(all(isnan(out.covariance(:, :, 2)), 'all'));
        end

        function theWindowRestrictsWhichSamplesAreUsed(testCase)
            EEG = testCase.fixture();
            o = testCase.opts('Covariance', 'None');
            o.Start = -200; o.Stop = 0;

            out = Covariance(EEG, o);

            inWindow = nnz(EEG.times >= -200 & EEG.times <= 0);
            testCase.verifyEqual(out.covN(1), inWindow * size(EEG.data, 3));
        end

        function fewerThanTwoChannelsIsAnError(testCase)
            EEG = testCase.fixture();
            o = testCase.opts('Covariance', 'None');
            o.Channels = {'Fz'};

            testCase.verifyError(@() Covariance(EEG, o), 'Alakazam:Covariance');
        end
    end

    methods (Access = private)
        function EEG = fixture(~)
            EEG = makeTestEEG('nbchan', 3, 'labels', {'Fz', 'Pz', 'Oz'});
            rng(11);
            EEG.data = EEG.data + randn(size(EEG.data));   % break exact collinearity
        end

        function EEG = wideFixture(~, nChan, nObs)
        %WIDEFIXTURE  nChan channels by nObs observations in ONE trial, so
        %   the observation count is exactly controllable.
            labels = arrayfun(@(k) sprintf('C%d', k), 1:nChan, 'UniformOutput', false);
            EEG = makeTestEEG('nbchan', nChan, 'labels', labels, ...
                'DataFormat', 'CONTINUOUS');
            rng(5);
            EEG.data = randn(nChan, nObs);
            EEG.pnts = nObs;
            EEG.times = (0:nObs - 1) / EEG.srate * 1000;
            EEG.trials = 1;
        end

        function EEG = correlatedFixture(testCase, nChan, nObs)
        %CORRELATEDFIXTURE  wideFixture, then mixed so the true covariance
        %   has genuine structure (strongly correlated channels, unequal
        %   variances) rather than being spherical.
            EEG = testCase.wideFixture(nChan, nObs);
            rng(9);
            Z = randn(nChan, nObs);
            A = eye(nChan) + 0.8 * tril(ones(nChan), -1);   % each channel loads on the earlier ones
            A(1, 1) = 2.5;                                   % and unequal variances
            EEG.data = A * Z;
        end

        function o = opts(~, statistic, shrinkage)
            o = struct('Channels', {{}}, 'Statistic', statistic, ...
                'Shrinkage', shrinkage, 'Start', 0, 'Stop', 0);
        end
    end
end
