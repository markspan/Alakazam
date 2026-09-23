classdef CoherenceMapStftTest < matlab.unittest.TestCase
%COHERENCEMAPSTFTTEST  The STFT coherence, taken frame by frame in a loop, against
%   the same coherence taken with every frame in one FFT.
%
%   ComputeCoherenceMap's STFT path used to call fft once per frame of every
%   channel of every trial, about 147,000 calls on the RIFT data, and now
%   builds a matrix of frames and transforms it in one call. The arithmetic is the
%   same, so the results must be. The loop below is written out independently, from
%   the formula in the function's header, rather than copied from it.
%
%   Run with: runtests('tests/CoherenceMapStftTest.m').
%
%   See also COMPUTECOHERENCEMAP.

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
        function everyFrameInOneCallEqualsOneCallPerFrame(testCase)
            for taperName = {'Hann', 'Boxcar'}
                [input, opts] = testCase.fixture(taperName{1});

                [coh, freqs, times, refPower] = ComputeCoherenceMap(input, opts);
                [wantCoh, wantFreqs, wantTimes, wantPower] = referenceStft(input, opts);

                label = taperName{1};
                testCase.verifyEqual(freqs, wantFreqs, 'AbsTol', 1e-12, label);
                testCase.verifyEqual(times, wantTimes, 'AbsTol', 1e-12, label);
                testCase.verifyEqual(coh, wantCoh, 'AbsTol', 1e-10, [label ': coherence']);
                testCase.verifyEqual(refPower, wantPower, 'RelTol', 1e-10, [label ': reference power']);
                testCase.verifyTrue(any(isfinite(coh(:))), 'The comparison must not be between NaNs.');
            end
        end
    end

    methods (Access = private)
        function [input, opts] = fixture(~, taper)
            rng(11);
            srate = 250; nT = 250; nTrials = 5;
            data = randn(3, nT, 2 * nTrials);
            t = (0:nT - 1) / srate;
            for tr = 1:2 * nTrials
                data(1, :, tr) = data(1, :, tr) + 2 * sin(2 * pi * 20 * t);
                data(2, :, tr) = data(2, :, tr) + 1.5 * sin(2 * pi * 20 * t);
            end
            input = struct('times', t * 1000, 'nbchan', 3, 'srate', srate, 'data', data, ...
                'bindesc', struct('label', {'A', 'B'}, 'trials', {1:nTrials, nTrials + 1:2 * nTrials}, ...
                    'combo', {[], []}));
            opts = struct('Method', 'STFT', 'RefIndex', 1, 'MinFreq', 10, 'MaxFreq', 40, ...
                'NumFreqs', 10, 'WindowMs', 200, 'PadRatio', 2, 'Taper', taper);
        end
    end
end

% ======================================================================= %
function [coh, freqs, cohTimes, refPower] = referenceStft(input, opts)
%REFERENCESTFT  Magnitude-squared coherence to the reference, one fft per frame.
    srate = input.srate;
    nT = numel(input.times);
    nChan = input.nbchan;
    win = max(4, round(opts.WindowMs / 1000 * srate));
    step = max(1, round(win / 4));
    nfft = 2 ^ nextpow2(win * max(1, round(opts.PadRatio)));
    if strcmpi(opts.Taper, 'boxcar')
        taper = ones(1, win);
    else
        taper = 0.5 - 0.5 * cos(2 * pi * (0:win - 1) / (win - 1));
    end
    fullFreqs = (0:nfft - 1) * srate / nfft;
    fsel = find(fullFreqs >= opts.MinFreq & fullFreqs <= opts.MaxFreq);
    freqs = fullFreqs(fsel);
    starts = 1:step:(nT - win + 1);
    cohTimes = input.times(min(starts + floor(win / 2), nT));

    nBins = numel(input.bindesc);
    coh = nan(nChan, numel(freqs), numel(starts), nBins);
    refPower = nan(numel(freqs), numel(starts), nBins);
    for b = 1:nBins
        trials = input.bindesc(b).trials;
        Sxy = zeros(nChan, numel(freqs), numel(starts));
        Sxx = zeros(nChan, numel(freqs), numel(starts));
        Syy = zeros(numel(freqs), numel(starts));
        for tr = trials
            R = frames(input.data(opts.RefIndex, :, tr));
            Syy = Syy + abs(R) .^ 2;
            for ch = setdiff(1:nChan, opts.RefIndex)
                X = frames(input.data(ch, :, tr));
                Sxy(ch, :, :) = squeeze(Sxy(ch, :, :)) + X .* conj(R);
                Sxx(ch, :, :) = squeeze(Sxx(ch, :, :)) + abs(X) .^ 2;
            end
        end
        for ch = setdiff(1:nChan, opts.RefIndex)
            coh(ch, :, :, b) = abs(squeeze(Sxy(ch, :, :))) .^ 2 ./ (squeeze(Sxx(ch, :, :)) .* Syy);
        end
        refPower(:, :, b) = Syy / numel(trials);
    end

    function A = frames(sig)
        sig = double(sig(:).');
        A = zeros(numel(freqs), numel(starts));
        for k = 1:numel(starts)
            F = fft(sig(starts(k):starts(k) + win - 1) .* taper, nfft);
            A(:, k) = F(fsel).';
        end
    end
end
