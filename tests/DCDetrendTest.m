classdef DCDetrendTest < matlab.unittest.TestCase
%DCDETRENDTEST  Unit tests for src/Transformations/DCDetrend/DCDetrend.m.
%
%   Several of these are the case for the design rather than just coverage:
%   robustBeatsLeastSquaresOnASpike and theFitRangeIsSeparateFromTheSubtraction
%   are the two things a two-interval detrend (BrainVision Analyzer's) cannot
%   do, so they are checked against a known ground truth, not against
%   DCDetrend's own output.
%
%   Run with: runtests('tests/DCDetrendTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'DCDetrend'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Dialogs'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function aPureLinearDriftIsRemoved(testCase)
            EEG = testCase.flatFixture();
            n = size(EEG.data, 2);
            EEG.data(1, :, 1) = 3 + 0.02 * (1:n);

            out = DCDetrend(EEG, testCase.opts('1 - linear'));

            testCase.verifyEqual(double(out.data(1, :, 1)), zeros(1, n), 'AbsTol', 1e-8);
        end

        function orderZeroRemovesTheMeanAndLeavesTheSlope(testCase)
            EEG = testCase.flatFixture();
            n = size(EEG.data, 2);
            EEG.data(1, :, 1) = 3 + 0.02 * (1:n);

            out = DCDetrend(EEG, testCase.opts('0 - mean only'));

            row = double(out.data(1, :, 1));
            testCase.verifyEqual(mean(row), 0, 'AbsTol', 1e-8, 'The mean should be gone.');
            testCase.verifyGreaterThan(row(end) - row(1), 3, 'The slope should still be there.');
        end

        function aQuadraticDriftNeedsOrderTwo(testCase)
            EEG = testCase.flatFixture();
            n = size(EEG.data, 2);
            x = (1:n) / n;
            EEG.data(1, :, 1) = 2 + 4 * x + 9 * x.^2;

            linearOut = DCDetrend(EEG, testCase.opts('1 - linear'));
            quadOut   = DCDetrend(EEG, testCase.opts('2 - quadratic'));

            testCase.verifyGreaterThan(max(abs(double(linearOut.data(1, :, 1)))), 0.1, ...
                'A linear fit cannot absorb a quadratic drift.');
            testCase.verifyEqual(double(quadOut.data(1, :, 1)), zeros(1, n), 'AbsTol', 1e-7);
        end

        function robustBeatsLeastSquaresOnASpike(testCase)
        %ROBUSTBEATSLEASTSQUARESONASPIKE  The headline reason the robust
        %   option exists. One large transient inside the record should not
        %   be allowed to set the drift for the whole record.
            EEG = testCase.flatFixture();
            n = size(EEG.data, 2);
            trueLine = 3 + 0.02 * (1:n);
            withSpike = trueLine;
            withSpike(150:158) = withSpike(150:158) + 400;   % one big artefact
            EEG.data(1, :, 1) = withSpike;

            ls  = DCDetrend(EEG, testCase.opts('1 - linear', 'Least squares'));
            rob = DCDetrend(EEG, testCase.opts('1 - linear', 'Robust (Huber)'));

            clean = [1:149, 159:n];   % judge only where the truth is the line
            lsErr  = max(abs(double(ls.data(1, clean, 1))));
            robErr = max(abs(double(rob.data(1, clean, 1))));

            testCase.verifyLessThan(robErr, lsErr / 5, sprintf( ...
                ['The robust fit should recover the underlying line far better than ' ...
                 'least squares here (robust %.3g vs least squares %.3g).'], robErr, lsErr));
        end

        function theFitRangeIsSeparateFromTheSubtraction(testCase)
        %THEFITRANGEISSEPARATEFROMTHESUBTRACTION  Fit on the baseline,
        %   subtract across everything: the evoked response must not be
        %   allowed to pull on the drift estimate, and must survive intact.
            EEG = testCase.flatFixture();
            n = size(EEG.data, 2);
            trueLine = 1 + 0.01 * (1:n);
            response = zeros(1, n);
            bump = EEG.times >= 200 & EEG.times <= 400;
            response(bump) = 50;                      % a big sustained response
            EEG.data(1, :, 1) = trueLine + response;

            o = testCase.opts('1 - linear');
            o.FitStart = -200;                        % baseline only
            o.FitStop  = 0;
            out = DCDetrend(EEG, o);

            baseline = EEG.times <= 0;
            testCase.verifyEqual(max(abs(double(out.data(1, baseline, 1)))), 0, 'AbsTol', 1e-6, ...
                'The baseline drift should be gone.');
            testCase.verifyEqual(mean(double(out.data(1, bump, 1))), 50, 'AbsTol', 1, ...
                'The response should survive at its own amplitude, not be partly absorbed.');
        end

        function rejectedSamplesAreExcludedFromTheFitAndKept(testCase)
        %REJECTEDSAMPLESAREEXCLUDEDFROMTHEFITANDKEPT  A fit that does not
        %   skip NaNs returns NaN coefficients and destroys the channel.
            EEG = testCase.flatFixture();
            n = size(EEG.data, 2);
            EEG.data(1, :, 1) = 3 + 0.02 * (1:n);
            EEG.data(1, 40:60, 1) = NaN;

            out = DCDetrend(EEG, testCase.opts('1 - linear'));

            row = double(out.data(1, :, 1));
            testCase.verifyTrue(all(isnan(row(40:60))), 'Rejected samples must stay rejected.');
            finite = [1:39, 61:n];
            testCase.verifyEqual(row(finite), zeros(1, numel(finite)), 'AbsTol', 1e-8, ...
                'The drift should still have been removed from the surviving samples.');
        end

        function anEmptyChannelListMeansEveryChannel(testCase)
            EEG = testCase.flatFixture();
            n = size(EEG.data, 2);
            for c = 1:size(EEG.data, 1)
                EEG.data(c, :, 1) = c + 0.03 * (1:n);
            end

            out = DCDetrend(EEG, testCase.opts('1 - linear'));

            testCase.verifyEqual(double(out.data(:, :, 1)), zeros(size(EEG.data, 1), n), ...
                'AbsTol', 1e-8);
        end

        function aChannelTrialWithTooFewFiniteSamplesIsLeftAlone(testCase)
        %ACHANNELTRIALWITHTOOFEWFINITESAMPLESISLEFTALONE  A fully rejected
        %   channel-trial has nothing to fit; it must come back as it went
        %   in rather than as a degenerate solution.
            EEG = testCase.flatFixture();
            EEG.data(2, :, 1) = NaN;

            out = DCDetrend(EEG, testCase.opts('1 - linear'));

            testCase.verifyTrue(all(isnan(out.data(2, :, 1))));
        end
    end

    methods (Access = private)
        function EEG = flatFixture(~)
        %FLATFIXTURE  makeTestEEG's geometry (times/srate/trials), but with
        %   the data zeroed so each test can plant an exactly known trend.
            EEG = makeTestEEG('nbchan', 3, 'labels', {'Fz', 'Pz', 'Oz'});
            EEG.data = zeros(size(EEG.data));
        end

        function o = opts(~, order, method)
            if nargin < 3; method = 'Least squares'; end
            o = struct('Channels', {{}}, 'Order', order, 'Method', method, ...
                'FitStart', 0, 'FitStop', 0);
        end
    end
end
