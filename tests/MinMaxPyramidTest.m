classdef MinMaxPyramidTest < matlab.unittest.TestCase
%MINMAXPYRAMIDTEST  The min/max envelope the continuous view draws
%   (MinMaxPyramid.queryInterleaved): exact, complete, and never coarser
%   than a column.
%
%   The reported symptom was a sawtooth in the continuous view that went
%   away at the next zoom. An envelope is drawn as one line through each
%   bucket's minimum and then its maximum, so a bucket wider than a pixel
%   draws a zigzag that is not in the data. Between 2 and 8 samples per
%   column the pyramid used its 8-sample level, up to 4 columns a bucket;
%   these cases pin that no bucket is wider than a column in any regime, and
%   that the envelope is still the exact minimum and maximum of what each
%   bucket covers.
%
%   Run with: runtests('tests/MinMaxPyramidTest.m').
%
%   See also MINMAXPYRAMID, SIGNALVIEW.

    properties (TestParameter)
        % Samples per column: just over the raw-drawing limit, inside level
        % 1's too-coarse range, at a level boundary, and far zoomed out.
        samplesPerColumn = struct('twoAndAHalf', 2.5, 'five', 5, 'eight', 8, ...
            'thirtySeven', 37, 'fourHundred', 400)
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function noBucketIsWiderThanAColumn(testCase, samplesPerColumn)
            [pyramid, ~] = signal();
            columns = 1000;
            span = round(samplesPerColumn * columns);

            [idx, ~] = pyramid.queryInterleaved(1001, 1000 + span, columns);

            widths = idx(2:2:end) - idx(1:2:end) + 1;
            testCase.verifyLessThanOrEqual(max(widths), span / columns, ...
                'A bucket wider than a column draws a sawtooth.');
        end

        function eachBucketHoldsTheExactExtremesOfWhatItCovers(testCase, samplesPerColumn)
            [pyramid, y] = signal();
            columns = 700;
            span = round(samplesPerColumn * columns);

            [idx, env] = pyramid.queryInterleaved(333, 332 + span, columns);

            first = idx(1:2:end);
            last = idx(2:2:end);
            for k = 1:numel(first)
                covered = y(first(k):last(k), :);
                testCase.verifyEqual(double(env(2 * k - 1, :)), min(covered, [], 1), 'AbsTol', 1e-3);
                testCase.verifyEqual(double(env(2 * k, :)), max(covered, [], 1), 'AbsTol', 1e-3);
            end
        end

        function theBucketsCoverTheWholeWindowInOrder(testCase, samplesPerColumn)
            [pyramid, ~] = signal();
            columns = 500;
            span = round(samplesPerColumn * columns);
            i0 = 4242;

            [idx, ~] = pyramid.queryInterleaved(i0, i0 + span - 1, columns);

            first = idx(1:2:end);
            last = idx(2:2:end);
            testCase.verifyLessThanOrEqual(first(1), i0);
            testCase.verifyGreaterThanOrEqual(last(end), i0 + span - 1);
            testCase.verifyEqual(first(2:end), last(1:end - 1) + 1, 'No gap and no overlap.');
        end

        function aShortSignalHasNoLevelsAndStillAnswers(testCase)
        %ASHORTSIGNALHASNOLEVELSANDSTILLANSWERS  Eight samples or fewer build
        %   no coarse level at all; the envelope comes from the samples.
            pyramid = MinMaxPyramid((1:8)');

            [idx, env] = pyramid.queryInterleaved(1, 8, 2);

            testCase.verifyEqual(idx', [1 4 5 8]);
            testCase.verifyEqual(double(env'), [1 4 5 8]);
        end
    end
end

% ======================================================================= %
function [pyramid, y] = signal()
%SIGNAL  Three channels of random walk, long enough for four levels and for
%   every window above to lie inside it: the widest, 400 samples a column
%   over 1000 columns, ends at sample 401 000. At 200 000 samples the
%   pyramid rightly stopped at the last one, and a window reaching past the
%   end was being tested as if it were complete.
    rng(7, 'twister');
    y = cumsum(randn(500000, 3));
    pyramid = MinMaxPyramid(y);
end
