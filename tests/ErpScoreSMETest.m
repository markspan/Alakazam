classdef ErpScoreSMETest < matlab.unittest.TestCase
%ERPSCORESMETEST  Unit tests for src/IO/erpScoreSME.m.
%
%   The tests that matter most here are the AGREEMENT ones. erpScoreSME
%   carries its own scoring implementation rather than calling into
%   Measure.m (see its header for why), so the standing risk is that the
%   two silently drift apart and the report starts quoting an SME for a
%   measurement nobody actually made. scorerAgreesWithMeasureFor* pins that
%   down directly: score the average with this scorer, run Measure.m on the
%   same average with the same window, and require the same number.
%
%   Run with: runtests('tests/ErpScoreSMETest.m').
%
%   See also DATAQUALITYTEST, MEASURETEST, MAKETESTEEG.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Measure')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'fixtures')));
        end
    end

    methods (Test)
        % ---- agreement with Measure.m -----------------------------------
        function scorerAgreesWithMeasureForMeanAmplitude(testCase)
            testCase.verifyScorerMatchesMeasure('Mean Amplitude', 'amplitude');
        end

        function scorerAgreesWithMeasureForPeakAmplitude(testCase)
            testCase.verifyScorerMatchesMeasure('Peak', 'amplitude');
        end

        function scorerAgreesWithMeasureForPeakLatency(testCase)
            testCase.verifyScorerMatchesMeasure('Peak', 'latency', 'Peak Latency');
        end

        function scorerAgreesWithMeasureForArea(testCase)
            testCase.verifyScorerMatchesMeasure('Area', 'area');
        end

        function scorerAgreesWithMeasureForFractionalAreaLatency(testCase)
            testCase.verifyScorerMatchesMeasure('Fractional Area Latency', 'latency');
        end

        % ---- estimator choice -------------------------------------------
        function meanAmplitudeUsesTheAnalyticEstimator(testCase)
            [~, method] = erpScoreSME(testCase.noisyTrials(), testCase.times(), ...
                testCase.window('Mean Amplitude'));
            testCase.verifyEqual(method, "analytic");
        end

        function nonLinearScoresUseTheBootstrap(testCase)
            for measure = {'Peak', 'Peak Latency', 'Area', 'Fractional Area Latency'}
                [~, method] = erpScoreSME(testCase.noisyTrials(), testCase.times(), ...
                    testCase.window(measure{1}));
                testCase.verifyEqual(method, "bootstrap", ...
                    sprintf('%s should be bootstrapped, not analytic.', measure{1}));
            end
        end

        % ---- the analytic estimator is exactly Luck's closed form -------
        function analyticSmeIsSdOverSqrtN(testCase)
        %ANALYTICSMEISSDOVERSQRTN  SME for mean amplitude is defined as
        %   SD(per-trial mean amplitudes)/sqrt(n). Computed here
        %   independently, from the same trials, and required to match
        %   exactly rather than approximately.
            trials = testCase.noisyTrials();
            times = testCase.times();
            win = testCase.window('Mean Amplitude');

            sme = erpScoreSME(trials, times, win);

            inWin = times >= win.start & times <= win.stop;
            perTrial = squeeze(mean(trials(1, inWin, :), 2));
            expected = std(perTrial) / sqrt(numel(perTrial));
            testCase.verifyEqual(sme(1), expected, 'RelTol', 1e-12);
        end

        function analyticSmeShrinksAsTrialsAreAdded(testCase)
        %ANALYTICSMESHRINKSASTRIALSAREADDED  The 1/sqrt(n) that makes SME
        %   worth reporting: more trials, less measurement error.
            times = testCase.times();
            win = testCase.window('Mean Amplitude');
            rng(7);
            few  = erpScoreSME(testCase.noisyTrials(20), times, win);
            many = erpScoreSME(testCase.noisyTrials(200), times, win);

            testCase.verifyLessThan(many(1), few(1));
        end

        % ---- rejection handling -----------------------------------------
        function rejectedTrialsAreExcludedFromN(testCase)
        %REJECTEDTRIALSAREEXCLUDEDFROMN  A NaN (rejected) trial must not
        %   count towards n, or SME would be reported as better than the
        %   surviving data actually supports.
            trials = testCase.noisyTrials(40);
            withRejections = trials;
            withRejections(:, :, 1:20) = NaN;

            times = testCase.times();
            win = testCase.window('Mean Amplitude');
            full = erpScoreSME(trials(:, :, 21:40), times, win);
            rejected = erpScoreSME(withRejections, times, win);

            testCase.verifyEqual(rejected(1), full(1), 'RelTol', 1e-12);
        end

        function tooFewTrialsGivesNaN(testCase)
            trials = testCase.noisyTrials(1);
            sme = erpScoreSME(trials, testCase.times(), testCase.window('Mean Amplitude'));
            testCase.verifyTrue(isnan(sme(1)));
        end

        % ---- bootstrap behaviour ----------------------------------------
        function bootstrapSmeIsSmallForACleanSignalAndLargeForANoisyOne(testCase)
        %BOOTSTRAPSMEISSMALLFORACLEANSIGNALANDLARGEFORANOISYONE  The whole
        %   claim of the measure: a subject whose trials agree gives a
        %   stable peak, one whose trials do not gives an unstable one.
            times = testCase.times();
            win = testCase.window('Peak');
            rng(11);
            clean = testCase.noisyTrials(40, 0.05);
            noisy = testCase.noisyTrials(40, 5);

            smeClean = erpScoreSME(clean, times, win);
            smeNoisy = erpScoreSME(noisy, times, win);

            testCase.verifyLessThan(smeClean(1), smeNoisy(1));
        end

        function bootstrapAgreesWithTheAnalyticFormOnMeanAmplitude(testCase)
        %BOOTSTRAPAGREESWITHTHEANALYTICFORMONMEANAMPLITUDE  A correctness
        %   check on the bootstrap machinery itself, using the one score
        %   where the right answer is independently known: bootstrapping
        %   mean amplitude must land near its closed form. Forced down the
        %   bootstrap path by relabelling the measure, since erpScoreSME
        %   would otherwise (rightly) take the analytic shortcut.
            trials = testCase.noisyTrials(60);
            times = testCase.times();
            rng(3);

            analytic = erpScoreSME(trials, times, testCase.window('Mean Amplitude'));

            win = testCase.window('Mean Amplitude');
            win.measure = 'Area';   % non-linear label -> bootstrap path
            win.areaMode = 'signed';
            % Area over the window is the mean times the window span, so the
            % bootstrap SD of area, rescaled, estimates the same quantity.
            [bootArea, method] = erpScoreSME(trials, times, win);
            testCase.verifyEqual(method, "bootstrap");
            span = win.stop - win.start;
            testCase.verifyEqual(bootArea(1) / span, analytic(1), 'RelTol', 0.25);
        end

        function everyChannelIsScoredIndependently(testCase)
            times = testCase.times();
            trials = cat(1, testCase.noisyTrials(40, 0.05), testCase.noisyTrials(40, 5));
            sme = erpScoreSME(trials, times, testCase.window('Mean Amplitude'));

            testCase.verifySize(sme, [2 1]);
            testCase.verifyLessThan(sme(1), sme(2));
        end
    end

    % ==================================================================== %
    methods
        function t = times(~)
            t = linspace(-200, 596, 200);
        end

        function win = window(testCase, measure)
            win = struct('label', 'W', 'start', 100, 'stop', 300, 'measure', measure, ...
                'polarity', 'Positive', 'width', [], 'localPoints', 0, 'fraction', 0.5, ...
                'areaMode', 'signed', 'baseline', [], 'refChannel', '', 'channels', '');
            if nargin < 2
                win.measure = 'Mean Amplitude';
            end
            win.times = testCase.times(); %#ok<STRNU> -- harmless extra field, ignored
            win = rmfield(win, 'times');
        end

        function trials = noisyTrials(testCase, n, noiseSd)
        %NOISYTRIALS  One channel, N trials: a common deterministic signal
        %   (a positive bump inside the 100-300 ms window) plus per-trial
        %   Gaussian noise, so there is a real score AND a real
        %   trial-to-trial distribution for SME to describe.
            if nargin < 2 || isempty(n); n = 40; end
            if nargin < 3 || isempty(noiseSd); noiseSd = 1; end
            t = testCase.times();
            signal = 5 * exp(-((t - 200).^2) / (2 * 50^2));
            trials = zeros(1, numel(t), n);
            for k = 1:n
                trials(1, :, k) = signal + noiseSd * randn(1, numel(t));
            end
        end

        function verifyScorerMatchesMeasure(testCase, measure, field, measureName)
        %VERIFYSCORERMATCHESMEASURE  Score the average with erpScoreSME and
        %   with Measure.m, and require the same number. MEASURE is the
        %   window's measure type for Measure.m; MEASURENAME, when given,
        %   is the (different) label erpScoreSME expects for the same score
        %   -- Measure returns peak amplitude and peak latency together from
        %   one 'Peak' window, whereas this scorer produces one number per
        %   call and so needs them named apart.
            if nargin < 4; measureName = measure; end
            rng(5);
            trials = testCase.noisyTrials(30);
            t = testCase.times();
            avg = mean(trials, 3);

            EEG = struct('data', avg, 'times', t, 'srate', 250, ...
                'nbchan', 1, 'DataFormat', 'Averaged', ...
                'chanlocs', struct('labels', {'Ch1'}));
            win = testCase.window(measure);
            opts = struct('windows', {{win}}, 'derivations', '');
            m = Measure(EEG, opts);
            expected = m.measurements{1}.(field)(1);

            scoreWin = testCase.window(measureName);
            [~, ~, actual] = erpScoreSME(trials, t, scoreWin);

            testCase.verifyEqual(actual(1), expected, 'RelTol', 1e-9, ...
                sprintf('erpScoreSME disagrees with Measure.m on %s (%s).', measure, field));
        end
    end
end
