classdef TimeFrequencyTest < matlab.unittest.TestCase
%TIMEFREQUENCYTEST  Unit tests for
%   src/Transformations/+TransTools/ComputeErsp.m -- the wavelet ERSP
%   engine TimeFrequency.m's dialog-driven wrapper calls, tested directly
%   (per its own header comment: "so this can be called and verified
%   directly, without going through TimeFrequency.m's own blocking
%   options dialog").
%
%   Exact Morlet-wavelet convolution output is hard to hand-derive
%   safely, so most tests here lean on two properties that hold
%   EXACTLY, by construction, regardless of the input signal:
%     1. The mean ERSP value over the baseline window's own samples is
%        exactly 0 for every frequency -- ersp = logPower - mean(logPower
%        over the baseline), so subtracting a segment's own mean from
%        itself and averaging again is 0 by definition.
%     2. A combination (difference) bin's ERSP is the coefficient-
%        weighted sum of the referenced bins' own (already computed)
%        ERSP -- a direct, code-visible summation (see ComputeErsp.m's
%        own "acc = acc + combo(t).coeff * ersp(...)" line), not
%        something that needs re-deriving the wavelet maths at all.
%   One test (burstAfterBaselineIncreasesPowerAtItsOwnFrequency) checks a
%   qualitative, generously-margined property instead (power goes up
%   where/when a real burst was injected) rather than an exact value.
%
%   Run with: runtests('tests/TimeFrequencyTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        function shapeAndFrequencyGridAreCorrect(testCase)
            EEG = erspFixture(3);
            opts = defaultOpts();

            [ersp, freqs] = TransTools.ComputeErsp(EEG, opts);

            % Checked dimension-by-dimension, not via a single size(ersp)
            % comparison: MATLAB always collapses a trailing singleton
            % dimension away (size() never reports a trailing 1), so with
            % numel(EEG.bindesc) == 1 here, size(ersp) is 3-element, not
            % 4-element -- a fact about MATLAB's own size(), not something
            % ComputeErsp can avoid.
            testCase.verifyEqual(size(ersp, 1), EEG.nbchan);
            testCase.verifyEqual(size(ersp, 2), opts.NumFreqs);
            testCase.verifyEqual(size(ersp, 3), numel(EEG.times));
            testCase.verifyEqual(size(ersp, 4), numel(EEG.bindesc));
            testCase.verifyEqual(numel(freqs), opts.NumFreqs);
            testCase.verifyEqual(freqs(1), opts.MinFreq, 'AbsTol', 1e-9);
            testCase.verifyEqual(freqs(end), opts.MaxFreq, 'AbsTol', 1e-9);
            % log-spaced: consecutive ratios are all equal
            ratios = freqs(2:end) ./ freqs(1:end - 1);
            testCase.verifyEqual(ratios, repmat(ratios(1), 1, numel(ratios)), 'RelTol', 1e-9);
        end

        function meanErspOverBaselineWindowIsZero(testCase)
            EEG = erspFixture(3);
            opts = defaultOpts();

            [ersp, ~] = TransTools.ComputeErsp(EEG, opts);

            baseIdx = EEG.times >= opts.BaselineStart & EEG.times <= opts.BaselineStop;
            meanOverBaseline = mean(ersp(:, :, baseIdx, 1), 3);
            testCase.verifyEqual(meanOverBaseline, zeros(EEG.nbchan, opts.NumFreqs), 'AbsTol', 1e-9);
        end

        function combinationBinIsTheWeightedSumOfReferencedBins(testCase)
            EEG = erspFixture(3, 2); % 2 ordinary bins, different burst content
            EEG.bindesc(3) = struct('index', 3, 'label', 'A-B', 'trials', [], ...
                'combo', struct('bin', {1, 2}, 'coeff', {1, -1}));
            opts = defaultOpts();

            [ersp, ~] = TransTools.ComputeErsp(EEG, opts);

            testCase.verifyEqual(ersp(:, :, :, 3), ersp(:, :, :, 1) - ersp(:, :, :, 2), 'AbsTol', 1e-9);
        end

        function binWithNoTrialsProducesNaN(testCase)
            EEG = erspFixture(3);
            EEG.bindesc(2) = struct('index', 2, 'label', 'Empty', 'trials', [], 'combo', []);
            opts = defaultOpts();

            [ersp, ~] = TransTools.ComputeErsp(EEG, opts);

            testCase.verifyTrue(all(isnan(ersp(:, :, :, 2)), 'all'));
            testCase.verifyFalse(any(isnan(ersp(:, :, :, 1)), 'all'));
        end

        function burstAfterBaselineIncreasesPowerAtItsOwnFrequency(testCase)
        %BURSTAFTERBASELINEINCREASESPOWERATITSOWNFREQUENCY  A 20 Hz burst
        %   injected only in [100,400] ms, well clear of the [-500,-200]
        %   ms baseline window (a 300 ms gap, comfortably wider than the
        %   20 Hz wavelet's own temporal support at these cycle settings,
        %   so the baseline itself should not be contaminated by it):
        %   ERSP at the nearest computed frequency to 20 Hz, evaluated
        %   during the burst, should be clearly higher than during the
        %   (burst-free) baseline.
            EEG = erspFixture(3);
            opts = defaultOpts();

            [ersp, freqs] = TransTools.ComputeErsp(EEG, opts);

            [~, fi] = min(abs(freqs - 20));
            burstIdx = EEG.times >= 150 & EEG.times <= 350; % well inside the injected burst
            baseIdx  = EEG.times >= opts.BaselineStart & EEG.times <= opts.BaselineStop;

            duringBurst = mean(ersp(1, fi, burstIdx, 1));
            duringBaseline = mean(ersp(1, fi, baseIdx, 1));
            testCase.verifyGreaterThan(duringBurst, duringBaseline + 3); % clearly higher, generous margin (dB)
        end

        function rejectsBaselineWindowOutsideEpochRange(testCase)
            EEG = erspFixture(3);
            opts = defaultOpts();
            opts.BaselineStart = 10000; opts.BaselineStop = 20000; % nowhere near EEG.times
            testCase.verifyError(@() TransTools.ComputeErsp(EEG, opts), 'Alakazam:TimeFrequency');
        end
    end
end

function EEG = erspFixture(nTrialsPerBin, nBins)
%ERSPFIXTURE  A 1-channel, 250 Hz, -500..496 ms epoched EEG. Each trial in
%   bin 1 carries a 20 Hz burst active only in [100,400] ms (silence
%   elsewhere); bin 2 (when NBINS >= 2) carries a DIFFERENT burst (10 Hz,
%   also [100,400] ms), so the two bins' ERSP genuinely differ -- needed
%   for the combination-bin test, which would be trivially satisfied (and
%   not actually testing anything) if both bins were identical.
    if nargin < 2; nBins = 1; end
    srate = 250; nT = 250;
    times = ((0:nT - 1) - 125) / srate * 1000; % -500 to 496 ms
    t = times / 1000;
    burstMask = times >= 100 & times <= 400;

    EEG = struct();
    EEG.DataFormat = 'EPOCHED';
    EEG.times  = times;
    EEG.nbchan = 1;
    EEG.srate  = srate;

    % A tiny, deterministic broadband noise floor, present throughout the
    % WHOLE epoch (not just outside the burst): without it, the baseline
    % segment is exactly zero, and wavelet convolution of an exactly-zero
    % signal can land on essentially-exact-zero power at isolated
    % frequency/time points -- 10*log10(0) is -Inf, and -Inf - (-Inf) is
    % NaN, which is exactly what broke this fixture's first version (real
    % EEG always has broadband noise, so this edge case never arises in
    % practice; it's an artefact of an idealised, too-clean synthetic
    % signal, not a ComputeErsp bug). Amplitude (0.001-0.0007) is far
    % below the burst's own (5), so it does not disturb the "burst raises
    % power" comparison.
    noiseFloor = 0.001 * sin(2 * pi * 13.7 * t) + 0.0007 * sin(2 * pi * 7.3 * t + 0.3);

    bindesc = struct('index', {}, 'label', {}, 'trials', {}, 'combo', {});
    data = zeros(1, nT, nTrialsPerBin * nBins);
    trialCursor = 0;
    burstFreqs = [20, 10];
    for b = 1:nBins
        trialsThisBin = trialCursor + (1:nTrialsPerBin);
        for k = 1:nTrialsPerBin
            sig = noiseFloor;
            sig(burstMask) = sig(burstMask) + 5 * sin(2 * pi * burstFreqs(b) * t(burstMask));
            data(1, :, trialCursor + k) = sig;
        end
        bindesc(b) = struct('index', b, 'label', sprintf('Bin%d', b), ...
            'trials', trialsThisBin, 'combo', []);
        trialCursor = trialCursor + nTrialsPerBin;
    end
    EEG.data = data;
    EEG.bindesc = bindesc;
end

function opts = defaultOpts()
    opts = struct('MinFreq', 4, 'MaxFreq', 40, 'NumFreqs', 10, ...
        'MinCycles', 3, 'MaxCycles', 6, 'BaselineStart', -500, 'BaselineStop', -200);
end
