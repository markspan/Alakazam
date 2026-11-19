classdef ErpScoreAgainstMeasureTest < matlab.unittest.TestCase
%ERPSCOREAGAINSTMEASURETEST  The SME beside a value is the standard error of
%   that value: for every kind of window, the score erpScoreSME works from is the
%   number Measure reports for the same average.
%
%   The two used to be separate implementations, and drifted: 5.0 against 266 on
%   a peak-band area, 385 against 299 on a fractional area latency, and a window
%   measured on a pool got SMEs for every channel but the pool.
%
%   See also ERPSCORESME, MEASURE, TRANSTOOLS.MEASURESCORER, ERPSCORESMETEST.
    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            import matlab.unittest.fixtures.PathFixture
            testCase.applyFixture(PathFixture(fullfile(root, 'src', 'Reports')));
            testCase.applyFixture(PathFixture(fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(PathFixture(fullfile(root, 'src', 'Transformations', 'Measure')));
            testCase.applyFixture(PathFixture(fullfile(root, 'src', 'Transformations', 'Average')));
            testCase.applyFixture(PathFixture(fullfile(root, 'src', 'Support')));
            testCase.applyFixture(PathFixture(fullfile(root, 'src')));
        end
    end

    properties (TestParameter)
        scored = struct( ...
            'offGridWindow', {{struct('measure', 'Mean Amplitude', 'start', 201.3, 'stop', 603.7), 'amplitude'}}, ...
            'windowBaseline', {{struct('measure', 'Mean Amplitude', 'baseline', '-200 0'), 'amplitude'}}, ...
            'wholeWindowArea', {{struct('measure', 'Area'), 'area'}}, ...
            'rectifiedArea', {{struct('measure', 'Area', 'areaMode', 'rectified'), 'area'}}, ...
            'peakBandArea', {{struct('measure', 'Area', 'width', 50), 'area'}}, ...
            'bandAreaByOldName', {{struct('measure', 'Peak Area', 'width', 50), 'area'}}, ...
            'areaLatencySigned', {{struct('measure', 'Fractional Area Latency', 'areaMode', 'signed'), 'latency'}}, ...
            'areaLatencyPositive', {{struct('measure', 'Fractional Area Latency', 'areaMode', 'positive'), 'latency'}}, ...
            'areaLatencyNegative', {{struct('measure', 'Fractional Area Latency', 'areaMode', 'negative'), 'latency'}}, ...
            'localPeak', {{struct('measure', 'Peak', 'localPoints', 5, 'start', 200, 'stop', 280), 'amplitude'}}, ...
            'negativePeak', {{struct('measure', 'Peak', 'polarity', 'Negative'), 'amplitude'}}, ...
            'fractionalPeak', {{struct('measure', 'Fractional Peak Latency'), 'latency'}}, ...
            'unreachableFraction', {{struct('measure', 'Fractional Peak Latency', 'start', 430, 'stop', 480), 'latency'}});
    end

    methods (Test)
        function theScoreIsMeasuresOwn(testCase, scored)
            [EEG, avg] = biphasic();
            win = baseWindow();
            over = scored{1};
            for f = fieldnames(over)'
                win.(f{1}) = over.(f{1});
            end
            r = Measure(avg, struct('windows', {{win}}, 'derivations', ''));
            m = r.measurements{1};
            [~, ~, score] = erpScoreSME(EEG.data, EEG.times, m, 10);
            testCase.verifyEqual(score, m.(scored{2}), 'AbsTol', 1e-9);
        end

        function aPeakLatencyVariantReadsTheLatency(testCase)
            [EEG, avg] = biphasic();
            win = baseWindow();
            win.measure = 'Peak';
            r = Measure(avg, struct('windows', {{win}}, 'derivations', ''));
            m = r.measurements{1};
            m.measure = 'Peak Latency';
            [~, method, score] = erpScoreSME(EEG.data, EEG.times, m, 10);
            testCase.verifyEqual(score, r.measurements{1}.latency, 'AbsTol', 1e-9);
            testCase.verifyEqual(method, "bootstrap");
        end

        function theAnalyticSmeIncludesTheBaselinesNoise(testCase)
            [EEG, avg] = biphasic();
            win = baseWindow();
            win.measure = 'Mean Amplitude';
            win.baseline = '-200 0';
            r = Measure(avg, struct('windows', {{win}}, 'derivations', ''));
            sme = erpScoreSME(EEG.data, EEG.times, r.measurements{1});
            [lo, hi] = TransTools.WindowSamples(EEG.times, 200, 600, 'Alakazam:Test', 'window');
            [bl, bh] = TransTools.WindowSamples(EEG.times, -200, 0, 'Alakazam:Test', 'window');
            perTrial = squeeze(mean(EEG.data(1, lo:hi, :), 2) - mean(EEG.data(1, bl:bh, :), 2));
            testCase.verifyEqual(sme, std(perTrial) / sqrt(numel(perTrial)), 'AbsTol', 1e-12);
        end

        function aResultCarriesItsBaselineAndAreaMode(testCase)
            [~, avg] = biphasic();
            win = baseWindow();
            win.measure = 'Fractional Area Latency';
            win.areaMode = 'positive';
            win.baseline = '-200 0';
            r = Measure(avg, struct('windows', {{win}}, 'derivations', ''));
            testCase.verifyEqual(r.measurements{1}.baseline, [-200 0]);
            testCase.verifyEqual(r.measurements{1}.areaMode, 'positive');
        end

        function theBootstrapIsSeededAndLeavesTheStreamAlone(testCase)
            [EEG, avg] = biphasic();
            win = baseWindow();
            win.measure = 'Peak';
            r = Measure(avg, struct('windows', {{win}}, 'derivations', ''));
            rng(3, 'twister');
            before = rng;
            a = erpScoreSME(EEG.data, EEG.times, r.measurements{1}, 20);
            testCase.verifyEqual(rng, before);
            rng(4, 'twister');
            b = erpScoreSME(EEG.data, EEG.times, r.measurements{1}, 20);
            testCase.verifyEqual(a, b);
        end

        function aPartlyRejectedTrialIsNotCountedAsZero(testCase)
        %   A NaN sample used to enter a bootstrap average as 0, pulling the score
        %   towards zero, where the actual average leaves it out.
            [EEG, avg] = biphasic();
            bad = EEG;
            bad.data(1, 150:end, 1:30) = NaN;
            win = baseWindow();
            win.measure = 'Peak';
            win.start = 400;
            win.stop = 600;
            win.polarity = 'Negative';
            full = Measure(avg, struct('windows', {{win}}, 'derivations', ''));
            a = erpScoreSME(EEG.data, EEG.times, full.measurements{1}, 200);
            b = erpScoreSME(bad.data, bad.times, full.measurements{1}, 200);
            testCase.verifyLessThan(b, 2 * a, ...
                'Half the trials gone raises the SME by about sqrt(2), not by the swing to zero.');
        end

        function aPoolGetsItsOwnSmeAndNoOthers(testCase)
            rng(9, 'twister');
            labels = {'Fz', 'Cz', 'Pz'};
            EEG = epochs(labels, 128, [-200 800], 30);
            EEG.data = randn(size(EEG.data));
            avg = Average(EEG, struct());
            win = baseWindow();
            win.measure = 'Mean Amplitude';
            win.channels = {'{Cz Pz}'};
            r = Measure(avg, struct('windows', {{win}}, 'derivations', ''));
            testCase.verifyEqual(r.measurements{1}.channels, {'{Cz+Pz}'});
            q = dataQualityMetrics(EEG, r, r.measurements, true);
            testCase.verifyEqual(unique({q.byWindowChannel.channel}), {'{Cz+Pz}'});
            pool = mean(EEG.data(2:3, :, :), 1);
            [lo, hi] = TransTools.WindowSamples(EEG.times, 200, 600, 'Alakazam:Test', 'window');
            perTrial = squeeze(mean(pool(1, lo:hi, :), 2));
            testCase.verifyEqual(q.byWindowChannel(1).sme_uv, std(perTrial) / sqrt(30), 'AbsTol', 1e-12);
            testCase.verifyEqual(q.byWindowChannel(1).score, r.measurements{1}.amplitude, 'AbsTol', 1e-9);
        end

        function aWindowOnNamedChannelsEmitsOnlyThem(testCase)
            rng(10, 'twister');
            EEG = epochs({'Fz', 'Cz', 'Pz'}, 128, [-200 800], 12);
            EEG.data = randn(size(EEG.data));
            avg = Average(EEG, struct());
            win = baseWindow();
            win.measure = 'Mean Amplitude';
            win.channels = {'Cz'};
            r = Measure(avg, struct('windows', {{win}}, 'derivations', ''));
            q = dataQualityMetrics(EEG, r, r.measurements, true);
            testCase.verifyEqual(unique({q.byWindowChannel.channel}), {'Cz'});
        end

        function aChannelDerivedAfterAveragingHasNoSme(testCase)
            rng(11, 'twister');
            EEG = epochs({'Fz', 'Cz', 'Pz'}, 128, [-200 800], 12);
            EEG.data = randn(size(EEG.data));
            avg = Average(EEG, struct());
            win = baseWindow();
            win.measure = 'Mean Amplitude';
            win.channels = {'Diff', 'Cz'};
            r = Measure(avg, struct('windows', {{win}}, 'derivations', 'let Diff = Fz - Cz'));
            q = dataQualityMetrics(EEG, r, r.measurements, true);
            testCase.verifyEqual(unique({q.byWindowChannel.channel}), {'Cz'});
        end

        function aPoolsOwnNameParsesBack(testCase)
            specs = measureChannelSpecs('{Cz+Pz}', ["Fz", "Cz", "Pz"], 'w');
            testCase.verifyEqual(specs.members, [2 3]);
            testCase.verifyEqual(specs.label, '{Cz+Pz}');
        end

        function aLabelHoldingAPlusIsStillOneChannel(testCase)
            specs = measureChannelSpecs('{A+B C}', ["A+B", "C"], 'w');
            testCase.verifyEqual(specs.members, [1 2]);
        end
    end
end

function win = baseWindow()
    win = struct('label', 'W', 'start', 200, 'stop', 600, 'measure', 'Mean Amplitude', ...
        'polarity', 'Positive', 'width', [], 'localPoints', 0, 'fraction', 0.5, 'areaMode', 'signed', ...
        'baseline', '', 'refChannel', '', 'channels', {{'A'}});
end

function [EEG, avg] = biphasic()
    rng(21, 'twister');
    EEG = epochs({'A'}, 256, [-200 800], 60);
    t = EEG.times;
    wave = 6 * exp(-((t - 300) / 60) .^ 2) - 6 * exp(-((t - 480) / 60) .^ 2);
    for tr = 1:60
        EEG.data(1, :, tr) = wave + 2 * randn(1, numel(t));
    end
    avg = Average(EEG, struct());
end

function EEG = epochs(labels, srate, epochMs, nTrials)
    nSamp = round(diff(epochMs) / 1000 * srate) + 1;
    EEG = struct('srate', srate, 'nbchan', numel(labels), 'DataFormat', 'EPOCHED', 'DataType', 'TimeDomain', ...
        'trials', nTrials, 'pnts', nSamp, 'times', linspace(epochMs(1), epochMs(2), nSamp), 'id', 't', 'setname', 't');
    EEG.chanlocs = struct('labels', labels);
    EEG.data = zeros(numel(labels), nSamp, nTrials);
    EEG.bindesc = struct('index', 1, 'label', 'A', 'combo', [], 'n', nTrials);
    EEG.epoch = repmat(struct('bini', 1, 'binrt', NaN), 1, nTrials);
    EEG.event = struct('type', {}, 'latency', {});
end
