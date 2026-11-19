classdef RejectedTrialSpectraTest < matlab.unittest.TestCase
%REJECTEDTRIALSPECTRATEST  The spectral steps after artefact rejection, and what
%   they compare: rejection writes NaN and leaves the trial in its bin, and one
%   rejected trial must take out that trial and no more.
%
%   Each case here gave a wrong number before: CoherenceTopography blank, or at
%   the wrong frequency; a Fourier spectrum blank on every channel for one
%   channel's rejection; a single-window coherence of .5 for identical signals.
%
%   See also FOURIER, SPECTRALMEASURE, COMPUTECOHERENCETOPOGRAPHY,
%   TRANSTOOLS.REFERENCESPECTRUM, TRANSTOOLS.EQUALISEDDRAWS.
    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            t = fullfile(root, 'src', 'Transformations');
            import matlab.unittest.fixtures.PathFixture
            testCase.applyFixture(PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(PathFixture(t));
            for folder = {'Fourier', 'SpectralMeasure', 'CoherenceTopography', 'CoherenceMap', ...
                    'Measure', 'Average', 'CrossCorrelation'}
                testCase.applyFixture(PathFixture(fullfile(t, folder{1})));
            end
            testCase.applyFixture(PathFixture(fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        % ---- Fourier
        function aRejectedChannelTakesOutOnlyItself(testCase)
            rng(1, 'twister');
            data = randn(3, 256, 2);
            data(2, :, 1) = NaN;
            EEG = struct('data', data, 'srate', 256, 'nbchan', 3, 'trials', 2, 'pnts', 256);
            for output = {'Volt', 'Power', 'VoltDens', 'PowerDens', 'Complex', 'PSD'}
                r = Fourier(EEG, voltOptions(output{1}));
                testCase.verifyEqual(reshape(all(isnan(r.data(:, :, 1)), 2), 1, []), [false true false], output{1});
                testCase.verifyFalse(any(isnan(r.data(:, :, 2)), 'all'), output{1});
            end
        end

        function aWhollyRejectedTrialStaysBlank(testCase)
            data = randn(3, 256, 2);
            data(:, :, 1) = NaN;
            r = Fourier(struct('data', data, 'srate', 256, 'nbchan', 3, 'trials', 2, 'pnts', 256), voltOptions('Volt'));
            testCase.verifyTrue(all(isnan(r.data(:, :, 1)), 'all'));
            testCase.verifyFalse(any(isnan(r.data(:, :, 2)), 'all'));
        end

        function cleanDataKeepsItsVoltNumbers(testCase)
        %   The Volt scale is under review separately: rejection handling must not
        %   move it. The formula here is the one in Fourier, written out.
            rng(2, 'twister');
            data = randn(3, 256);
            r = Fourier(struct('data', data, 'srate', 256, 'nbchan', 3, 'trials', 1, 'pnts', 256), voltOptions('Volt'));
            w = [hanning(256).'];
            w = [w(1:128), w(129:end)];
            norm = var(data) / var(w .* data);
            expected = abs(2 * fft((w / norm) .* data, 256, 2) / 256);
            testCase.verifyEqual(r.data, expected(:, 1:129), 'AbsTol', 1e-12);
        end

        function complexPhaseIsMeasuredFromTimeZero(testCase)
            EEG = epochs({'A'}, 256, [-200 800], 4);
            t = EEG.times / 1000;
            EEG.data = repmat(cos(2 * pi * 11 * t + 0.7), [1 1 4]);
            r = Fourier(EEG, struct('Output', 'Complex', 'FullSpectrum', true, 'Window', 'Hanning', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1));
            [~, k] = min(abs(r.freqs - 11));
            testCase.verifyEqual(angle(mean(r.data(1, k, :), 3)), 0.7, 'AbsTol', 1e-2);
        end

        function aContinuousAxisIsInSeconds(testCase)
            srate = 256;
            t = (0:511) / srate + 1;       % a recording cut to start at 1 s
            EEG = struct('data', cos(2 * pi * 11 * t + 0.7), 'srate', srate, 'nbchan', 1, 'trials', 1, ...
                'pnts', 512, 'times', t, 'DataFormat', 'CONTINUOUS');
            r = Fourier(EEG, struct('Output', 'Complex', 'FullSpectrum', true, 'Window', 'No', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 1));
            [~, k] = min(abs(r.freqs - 11));
            testCase.verifyEqual(angle(r.data(1, k)), 0.7, 'AbsTol', 1e-9);
        end

        % ---- SpectralMeasure
        function theWindowCoherenceUsesTheSameTrialsOnBothSides(testCase)
            EEG = sharedSignal(40);
            bad = EEG;
            bad.data(1, :, 1:20) = NaN;      % channel rejected, reference intact
            m = runRow(bad, 'A', 'Ref', 'window');
            testCase.verifyEqual(m.coherence, 1, 'AbsTol', 1e-9, 'The channel is the reference.');
        end

        function theSnrLeavesOtherRowsOutOfItsNeighbours(testCase)
            rng(4, 'twister');
            srate = 512; nT = 60; nSamp = srate + 1;
            t = (0:nSamp - 1) / srate;
            EEG = epochs({'Oz'}, srate, [0 1000], nT);
            for tr = 1:nT
                EEG.data(1, :, tr) = cos(2 * pi * 60 * t) + cos(2 * pi * 64 * t) + 2 * randn(1, nSamp);
            end
            rows = {struct('label', 'a', 'freq', '60', 'channels', 'Oz'), struct('label', 'b', 'freq', '64', 'channels', 'Oz')};
            both = SpectralMeasure(EEG, spectralOptions(rows, ''));
            alone = SpectralMeasure(EEG, spectralOptions(rows(1), ''));
            testCase.verifyGreaterThan(both.spectralMeasures{1}.snr, 20 * alone.spectralMeasures{1}.snr, ...
                'A tag among the neighbours caps the SNR near 20.');
            testCase.verifyGreaterThan(both.spectralMeasures{2}.snr, 100);
        end

        function aRowWithoutOthersKeepsEveryNeighbour(testCase)
            rng(6, 'twister');
            EEG = epochs({'Oz'}, 256, [0 1000], 10);
            EEG.data = randn(size(EEG.data));
            one = SpectralMeasure(EEG, spectralOptions({struct('label', 'a', 'freq', '40', 'channels', 'Oz')}, ''));
            far = SpectralMeasure(EEG, spectralOptions({struct('label', 'a', 'freq', '40', 'channels', 'Oz'), ...
                struct('label', 'b', 'freq', '100', 'channels', 'Oz')}, ''));
            testCase.verifyEqual(far.spectralMeasures{1}.snr, one.spectralMeasures{1}.snr, 'AbsTol', 1e-12);
        end

        % ---- Equalising trials
        function drawsAreOfOneSizeAndFromTheBin(testCase)
            EEG = twoBins(40, 10);
            sets = {1:40, 41:50};
            [draws, nEqual, counts] = TransTools.EqualisedDraws(EEG, sets, 5);
            testCase.verifyEqual(nEqual, 10);
            testCase.verifyEqual(counts, [40 10]);
            testCase.verifyEqual(numel(draws{1}), 5);
            testCase.verifyEqual(numel(draws{2}), 1);
            for k = 1:5
                testCase.verifyEqual(numel(unique(draws{1}{k})), 10);
                testCase.verifyTrue(all(ismember(draws{1}{k}, 1:40)));
            end
        end

        function drawsLeaveRejectedTrialsOutAndRepeat(testCase)
            EEG = twoBins(20, 10);
            EEG.data(:, :, 1:15) = NaN;
            [a, nEqual] = TransTools.EqualisedDraws(EEG, {1:20, 21:30}, 3);
            testCase.verifyEqual(nEqual, 5);
            testCase.verifyEqual(a{1}{1}, 16:20);
            rng(99, 'twister');
            before = rng;
            b = TransTools.EqualisedDraws(EEG, {1:20, 21:30}, 3);
            testCase.verifyEqual(b, a, 'A replay draws the same subsets.');
            testCase.verifyEqual(rng, before, 'The session''s random state is left alone.');
        end

        function equalisingRemovesTheTrialCountBias(testCase)
            rng(5, 'twister');
            EEG = twoBins(200, 20);
            rows = {struct('label', 'R', 'freq', '20', 'channels', 'A')};
            raw = SpectralMeasure(EEG, spectralOptions(rows, 'Ref', 'window'));
            opts = spectralOptions(rows, 'Ref', 'window');
            opts.crossf.EqualiseTrials = true;
            even = SpectralMeasure(EEG, opts);
            testCase.verifyGreaterThan(raw.spectralMeasures{1}.coherence(2), 2 * raw.spectralMeasures{1}.coherence(1), ...
                'The premise: unrelated signals read higher with fewer trials.');
            testCase.verifyEqual(even.spectralMeasures{1}.coherence(1), even.spectralMeasures{1}.coherence(2), ...
                'AbsTol', 0.03);
            testCase.verifyGreaterThan(even.spectralMeasures{1}.itc(1), 2 * raw.spectralMeasures{1}.itc(1) * 0.7);
            testCase.verifyEqual(even.etc.alz.spectralMeasure.equalisedTo, 20);
        end

        function aNoteSaysWhenTheCountsDiffer(testCase)
            out = evalc('TransTools.TrialCountNote([40 10], {''a'', ''b''}, ''Step'')');
            testCase.verifySubstring(out, 'different numbers of trials');
            testCase.verifyEmpty(evalc('TransTools.TrialCountNote([40 38], {''a'', ''b''}, ''Step'')'));
            testCase.verifyEmpty(evalc('TransTools.TrialCountNote([40 0], {''a'', ''combo''}, ''Step'')'));
        end

        function theCoherenceMapCanEqualiseToo(testCase)
            rng(7, 'twister');
            EEG = twoBins(100, 15);
            opts = struct('Method', 'STFT', 'RefIndex', 2, 'MinFreq', 15, 'MaxFreq', 25, 'WindowMs', 500, ...
                'PadRatio', 2, 'EqualiseTrials', true, 'EqualiseDraws', 5);
            even = ComputeCoherenceMap(EEG, opts);
            opts.EqualiseTrials = false;
            [~, raw] = evalc('ComputeCoherenceMap(EEG, opts)');
            evenA = mean(even(1, :, :, 1), 'all');
            evenB = mean(even(1, :, :, 2), 'all');
            testCase.verifyGreaterThan(mean(raw(1, :, :, 2), 'all'), 2 * mean(raw(1, :, :, 1), 'all'));
            testCase.verifyEqual(evenA, evenB, 'AbsTol', 0.04);
        end

        % ---- CoherenceTopography and the reference spectrum
        function theReferenceSpectrumLeavesARejectedTrialOut(testCase)
            EEG = tagged();
            [clean, ~, peak] = TransTools.ReferenceSpectrum(EEG, 3);
            bad = EEG;
            bad.data(:, :, 3) = NaN;
            [spec, ~, peakBad] = TransTools.ReferenceSpectrum(bad, 3);
            testCase.verifyEqual(peakBad, peak);
            testCase.verifyFalse(any(isnan(spec)));
            testCase.verifyEqual(max(spec), max(clean), 'RelTol', 0.01);
        end

        function everyTagSourceAndEstimatorSurvivesARejectedTrial(testCase)
            EEG = tagged();
            bad = EEG;
            bad.data(:, :, 3) = NaN;
            for source = {'reference', 'band'}
                for method = {'frames', 'window'}
                    opts = struct('RefIndex', 3, 'Frequency', 0, 'TimeStart', 0, 'TimeStop', 0, ...
                        'Method', method{1}, 'TagSource', source{1}, 'MinFreq', 55, 'MaxFreq', 68, ...
                        'FreqStep', 0.5, 'WindowMs', 500, 'Taper', 'Hann');
                    [c1, f1] = ComputeCoherenceTopography(EEG, opts);
                    [c2, f2] = ComputeCoherenceTopography(bad, opts);
                    name = [source{1} ' ' method{1}];
                    testCase.verifyEqual(f2, f1, 'AbsTol', 1e-9, name);
                    testCase.verifyEqual(c2(1), c1(1), 'AbsTol', 0.02, name);
                end
            end
        end

        function aWhollyRejectedBinHasNoTag(testCase)
            EEG = tagged();
            EEG.data(:, :, :) = NaN;
            opts = struct('RefIndex', 3, 'Frequency', 0, 'TimeStart', 0, 'TimeStop', 0, 'Method', 'frames', ...
                'TagSource', 'band', 'MinFreq', 55, 'MaxFreq', 68, 'FreqStep', 0.5, 'WindowMs', 500, 'Taper', 'Hann');
            [c, f] = ComputeCoherenceTopography(EEG, opts);
            testCase.verifyTrue(isnan(f));
            testCase.verifyTrue(all(isnan(c)));
        end

        function aChannelRejectedInOneTrialKeepsItsOtherTrialsInTheWindowEstimator(testCase)
            EEG = sharedSignal(10);
            EEG.data(1, :, 2) = NaN;
            opts = struct('RefIndex', 2, 'Frequency', 20, 'TimeStart', 0, 'TimeStop', 0, 'Method', 'window', ...
                'TagSource', 'band', 'MinFreq', 15, 'MaxFreq', 25, 'FreqStep', 0.5, 'WindowMs', 500, 'Taper', 'Hann');
            c = ComputeCoherenceTopography(EEG, opts);
            testCase.verifyEqual(c(1), 1, 'AbsTol', 1e-9);

            EEG = sharedSignal(10);
            EEG.data(2, :, 2) = NaN;      % the reference rejected, the channel intact
            c = ComputeCoherenceTopography(EEG, opts);
            testCase.verifyEqual(c(1), 1, 'AbsTol', 1e-9);
        end

        function theTopographyCanEqualise(testCase)
            rng(8, 'twister');
            EEG = twoBins(120, 15);
            opts = struct('RefIndex', 2, 'Frequency', 20, 'TimeStart', 0, 'TimeStop', 0, 'Method', 'window', ...
                'TagSource', 'band', 'MinFreq', 15, 'MaxFreq', 25, 'FreqStep', 0.5, 'WindowMs', 500, 'Taper', 'Hann');
            [~, raw] = evalc('ComputeCoherenceTopography(EEG, opts)');
            opts.EqualiseTrials = true;
            even = ComputeCoherenceTopography(EEG, opts);
            testCase.verifyGreaterThan(raw(1, 2), 2 * raw(1, 1));
            testCase.verifyGreaterThan(even(1, 1), 2 * raw(1, 1), ...
                'The larger bin now reads what the smaller one does, near 1/15.');
            testCase.verifyEqual(even(1, 1), even(1, 2), 'AbsTol', 0.03);
        end

        % ---- The filter-Hilbert edge
        function theFilterHilbertEdgesAreBlank(testCase)
            EEG = sharedSignal(4, 2000);
            opts = struct('Method', 'FilterHilbert', 'RefIndex', 2, 'MinFreq', 16, 'MaxFreq', 24, ...
                'NumFreqs', 9, 'BandwidthHz', 2, 'StepMs', 10);
            [coh, ~, t, power, info] = ComputeCoherenceMap(EEG, opts);
            sigma = 1000 / (2 * pi * 2 / (2 * sqrt(2 * log(2))));
            testCase.verifyEqual(info.halfWaveletMs(1), 3 * sigma, 'AbsTol', 10);
            testCase.verifyFalse(any(info.blankFrequencies));
            inside = t > info.halfWaveletMs(1) & t < t(end) - info.halfWaveletMs(1) + 10;
            testCase.verifyTrue(all(isnan(power(:, t < info.halfWaveletMs(1) - 10, 1)), 'all'));
            testCase.verifyTrue(all(isnan(coh(1, :, t < info.halfWaveletMs(1) - 10, 1)), 'all'));
            testCase.verifyTrue(any(~isnan(power(:, inside, 1)), 'all'));
        end

        function nothingFromTheEdgeLeaksIntoWhatIsLeft(testCase)
            EEG = sharedSignal(4, 2000, 60);
            opts = struct('Method', 'FilterHilbert', 'RefIndex', 2, 'MinFreq', 56, 'MaxFreq', 68, ...
                'NumFreqs', 13, 'BandwidthHz', 2, 'StepMs', 10);
            [~, freqs, ~, power] = ComputeCoherenceMap(EEG, opts);
            [~, k60] = min(abs(freqs - 60));
            [~, k64] = min(abs(freqs - 64));
            ratio = power(k64, :, 1) ./ power(k60, :, 1);
            testCase.verifyLessThan(max(ratio, [], 'omitnan'), 1e-3, ...
                'A pure 60 Hz signal reads 3e-2 at 64 Hz on the first sample.');
        end

        function aBandReachingPastTheEpochIsBlank(testCase)
            EEG = sharedSignal(4, 500);
            opts = struct('Method', 'FilterHilbert', 'RefIndex', 2, 'MinFreq', 16, 'MaxFreq', 24, ...
                'NumFreqs', 3, 'BandwidthHz', 2, 'StepMs', 10);
            [~, ~, ~, power, info] = ComputeCoherenceMap(EEG, opts);
            testCase.verifyTrue(all(info.blankFrequencies));
            testCase.verifyTrue(all(isnan(power), 'all'));
        end

        % ---- Small counts
        function oneTrialHasNoStandardError(testCase)
            EEG = epochs({'A'}, 100, [0 500], 2);
            EEG.data(1, :, 1) = randn(1, size(EEG.data, 2));
            EEG.data(1, :, 2) = NaN;
            r = Average(EEG, struct());
            testCase.verifyTrue(all(isnan(r.stErr(:))), 'One trial has no spread to describe.');
            testCase.verifyTrue(isnan(r.aSME));
        end

        function twoTrialsKeepTheirStandardError(testCase)
            EEG = epochs({'A'}, 100, [0 500], 2);
            EEG.data = randn(size(EEG.data));
            r = Average(EEG, struct());
            testCase.verifyEqual(r.stErr, std(EEG.data, 0, 3) / sqrt(2), 'AbsTol', 1e-12);
        end

        function theCrossCorrelationCountsTrialsItUsed(testCase)
            EEG = epochs({'A', 'Ref'}, 128, [0 1000], 10);
            EEG.data = randn(size(EEG.data));
            EEG.data(:, :, 1:4) = NaN;
            [~, r] = evalc(['CrossCorrelation(EEG, struct(''RefChannel'', ''Ref'', ''Channels'', {{}}, ' ...
                '''MaxLagMs'', 100, ''MinPairs'', 20, ''Start'', 0, ''Stop'', 0));']);
            testCase.verifyEqual(r.xcorrTrials, 6);
        end
    end
end

% ======================================================================= %
function opts = voltOptions(output)
    opts = struct('Output', output, 'FullSpectrum', true, 'Window', 'Hanning', 'Window_Length', 100, ...
        'Resolution', 'Max', 'ResVal', 1);
end

function opts = spectralOptions(rows, ref, method)
    opts = struct('rows', {rows}, 'fundamentals', '', 'refChannel', ref, 'method', 'Hann', ...
        'tapers', 3, 'snrNeighbours', 10, 'snrGuard', 1);
    if nargin > 2
        opts.coherenceMethod = method;
    end
end

function m = runRow(EEG, channel, ref, method)
    opts = spectralOptions({struct('label', 'R', 'freq', '20', 'channels', channel)}, ref, method);
    r = SpectralMeasure(EEG, opts);
    m = r.spectralMeasures{1};
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

function EEG = sharedSignal(nTrials, lengthMs, f)
%SHAREDSIGNAL  A channel identical to its reference, at a random phase per trial.
    if nargin < 2; lengthMs = 1000; end
    if nargin < 3; f = 20; end
    rng(11, 'twister');
    EEG = epochs({'A', 'Ref'}, 256, [0 lengthMs], nTrials);
    t = EEG.times / 1000;
    for tr = 1:nTrials
        x = cos(2 * pi * f * t + rand * 2 * pi);
        EEG.data(:, :, tr) = [x; x];
    end
end

function EEG = tagged()
    rng(13, 'twister');
    EEG = epochs({'A', 'B', 'Ref'}, 256, [0 2000], 20);
    t = EEG.times / 1000;
    for tr = 1:20
        x = cos(2 * pi * 60 * t);
        EEG.data(:, :, tr) = [x + 0.5 * randn(size(t)); 0.5 * x + 0.5 * randn(size(t)); x + 0.1 * randn(size(t))];
    end
end

function EEG = twoBins(nA, nB)
%TWOBINS  Unrelated channel and reference, with NA trials in one bin, NB in another.
    n = nA + nB;
    EEG = epochs({'A', 'Ref'}, 256, [0 1000], n);
    EEG.data = randn(size(EEG.data));
    EEG.bindesc = struct('index', {1, 2}, 'label', {'A', 'B'}, 'combo', {[], []}, 'n', {nA, nB});
    for tr = 1:n
        EEG.epoch(tr).bini = 1 + (tr > nA);
    end
end
