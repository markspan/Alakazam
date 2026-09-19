classdef ReferenceSpectrumTest < matlab.unittest.TestCase
%REFERENCESPECTRUMTEST  Unit tests for
%   src/Transformations/+TransTools/ReferenceSpectrum.m.
%
%   The reason the function exists is that a condition tagged OUTSIDE the
%   coherence band (a 30 Hz SSVEP among 52 to 68 Hz RIFT conditions) is
%   otherwise invisible: the strongest reference frequency inside the band is
%   reported as the tag, though it is a 1% residual of the photodiode. So the
%   tests plant tones at known frequencies, some deliberately outside any
%   plausible band, and check what comes back.
%
%   Run with: runtests('tests/ReferenceSpectrumTest.m').
%
%   See also COHERENCEMAP, EXPORTCOHERENCECSVS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        function theStrongestFrequencyIsFoundWhereverItIs(testCase)
            input = toneInput(1000, 2000, 4, [30 3]);
            [~, ~, peakHz] = TransTools.ReferenceSpectrum(input, 1);
            testCase.verifyEqual(peakHz(1), 30, 'AbsTol', 1e-9);
        end

        function aToneAtAnyOtherFrequencyMovesThePeak(testCase)
        %   The same call on 64 Hz must not still say 30: guards a function
        %   that returns a constant or the first frequency it saw.
            input = toneInput(1000, 2000, 4, [64 3]);
            [~, ~, peakHz] = TransTools.ReferenceSpectrum(input, 1);
            testCase.verifyEqual(peakHz(1), 64, 'AbsTol', 1e-9);
        end

        function slowDriftBelowFiveHertzIsNotATag(testCase)
        %   DC, drift and onset transients are large and are not a flicker.
        %   A 2 Hz component ten times the tag's amplitude must not win.
            input = toneInput(1000, 2000, 4, [30 1; 2 10]);
            [~, ~, peakHz] = TransTools.ReferenceSpectrum(input, 1);
            testCase.verifyEqual(peakHz(1), 30, 'AbsTol', 1e-9);
        end

        function theAmplitudeIsInTheUnitsOfTheSignal(testCase)
        %   A sinusoid of amplitude 3 must read close to 3 (the Hann taper's
        %   coherent gain is corrected for), not some arbitrary scale.
            input = toneInput(1000, 2000, 4, [30 3]);
            [spec, specFreqs] = TransTools.ReferenceSpectrum(input, 1);
            [~, at] = min(abs(specFreqs - 30));
            testCase.verifyEqual(spec(at, 1), 3, 'RelTol', 0.02);
        end

        function aNarrowPeakKeepsItsHeightWhenTheSpectrumIsReducedToCells(testCase)
        %   8 s at 1000 Hz has 0.125 Hz resolution, finer than the 0.25 Hz
        %   cells, so the reduction takes a maximum within each cell. A mean
        %   would flatten a peak between two FFT bins.
            input = toneInput(1000, 8000, 3, [30.125 3]);
            [spec, specFreqs] = TransTools.ReferenceSpectrum(input, 1);
            testCase.verifyEqual(max(spec(:, 1)), 3, 'RelTol', 0.05);
            testCase.verifyEqual(specFreqs(2) - specFreqs(1), 0.25, 'AbsTol', 1e-12);
        end

        function theRangeStopsAtOneHundredAndFiftyHertzOrNyquist(testCase)
            wide = toneInput(1000, 2000, 2, [30 1]);
            narrow = toneInput(250, 500, 2, [30 1]);
            [~, wideFreqs] = TransTools.ReferenceSpectrum(wide, 1);
            [~, narrowFreqs] = TransTools.ReferenceSpectrum(narrow, 1);
            testCase.verifyEqual(wideFreqs(end), 150, 'AbsTol', 1e-9);
            testCase.verifyEqual(narrowFreqs(end), 125, 'AbsTol', 1e-9);
        end

        function aCombinationBinAndAnEmptyBinAreMissing(testCase)
            input = toneInput(1000, 2000, 4, [30 3]);
            input.bindesc(2) = struct('index', 2, 'label', 'Combo', 'trials', [], ...
                'combo', struct('bin', 1, 'coeff', 1));
            input.bindesc(3) = struct('index', 3, 'label', 'Empty', 'trials', [], 'combo', []);
            [spec, ~, peakHz] = TransTools.ReferenceSpectrum(input, 1);
            testCase.verifyTrue(all(isnan(spec(:, 2:3)), 'all'));
            testCase.verifyTrue(all(isnan(peakHz(2:3))));
            testCase.verifyFalse(isnan(peakHz(1)));
        end

        function eachBinHasItsOwnSpectrum(testCase)
        %   Two conditions with different tags (the RIFT 60 vs 64 case) must
        %   not be pooled into one.
            input = toneInput(1000, 2000, 4, [30 3]);
            input.data(:, :, 3:4) = toneInput(1000, 2000, 2, [64 3]).data;
            input.bindesc = struct( ...
                'index', {1, 2}, 'label', {'A', 'B'}, 'trials', {1:2, 3:4}, 'combo', {[], []});
            [~, ~, peakHz] = TransTools.ReferenceSpectrum(input, 1);
            testCase.verifyEqual(peakHz, [30 64], 'AbsTol', 1e-9);
        end
    end
end

function input = toneInput(srate, nT, nTrials, tones)
%TONEINPUT  An EPOCHED struct whose channel 1 is a sum of sinusoids, one
%   [frequency amplitude] per row of TONES, the same on every trial.
    t = (0:nT - 1) / srate;
    x = zeros(1, nT);
    for k = 1:size(tones, 1)
        x = x + tones(k, 2) * sin(2 * pi * tones(k, 1) * t);
    end
    input = struct();
    input.srate = srate;
    input.data = repmat(reshape(x, 1, nT), [1, 1, nTrials]);
    input.bindesc = struct('index', 1, 'label', 'A', 'trials', 1:nTrials, 'combo', []);
end
