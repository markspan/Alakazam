classdef MinMaxPyramid < handle
%MINMAXPYRAMID  Multi-resolution min/max pyramid for fast time-series plotting.
%
%   A MinMaxPyramid precomputes, once, a stack of increasingly coarse levels.
%   Each level holds the per-bucket minimum and maximum of the signal, where a
%   level-L bucket spans BaseFactor^L raw samples. A viewport query then reads
%   O(number of pixels) points from the nearest level instead of scanning
%   O(number of samples), so the cost of a redraw is independent of the length
%   of the signal. This is what lets huge recordings scroll and zoom smoothly.
%
%   Because min(min(x)) == min(x) and max(max(x)) == max(x), the per-bucket
%   extrema stored at every level are the exact minima and maxima of the raw
%   samples they cover: the decimated envelope never hides a spike.
%
%   The pyramid stores only the coarse levels (level 1 and up), each in single
%   precision. With the default BaseFactor of 8 the extra memory is roughly
%   0.3x the raw signal size. The finest, sample-for-sample view (when the
%   visible span is no larger than the axis is wide) is drawn from the raw data
%   by the caller and does not need the pyramid.
%
%   NO BUCKET IS WIDER THAN A COLUMN, and that is what keeps the drawing
%   honest. A min/max envelope is drawn as one line through each bucket's
%   minimum and then its maximum, so every bucket adds a zigzag as wide as
%   the bucket. Narrower than a pixel, the zigzags fill in to the band the
%   signal occupies; wider, they are a sawtooth that is not in the data.
%   Between 2 and BaseFactor samples per column, level 1 is too coarse (its
%   buckets span up to BaseFactor/2 columns), and that is exactly where a
%   sawtooth used to appear. There the envelope is reduced from the raw
%   samples, one bucket per column, which costs at most BaseFactor samples
%   per column: still O(pixels).
%
%   Construction:
%     pyr = MinMaxPyramid(Y)               % Y is samples x channels
%     pyr = MinMaxPyramid(Y, baseFactor)   % bucket ratio between levels
%
%   Query:
%     [sampleIdx, yEnv] = pyr.queryInterleaved(i0, i1, nBuckets)
%   returns, for the visible sample range [i0, i1] drawn into about nBuckets
%   screen columns, an interleaved min/max envelope: two rows per bucket (the
%   minimum then the maximum) at representative sample indices. The caller maps
%   sampleIdx to time (uniform: period*(idx-1)+t0; non-uniform: X(idx)).
%
%   See also ALAKAZAMPLOTTER, SIGNALVIEW.

    properties (SetAccess = private)
        NumSamples          % double, number of samples in the raw signal
        NumChannels         % double, number of channels (columns)
        BaseFactor          % double, samples-per-bucket ratio between levels
        Factor              % 1xL double, raw samples per bucket at each level
        Lo                  % 1xL cell, Lo{L} is nBuckets(L) x NumChannels single
        Hi                  % 1xL cell, Hi{L} is nBuckets(L) x NumChannels single
    end

    properties (Access = private)
        % The signal itself, samples x channels, for the finest envelopes (see
        % the class header). The caller's own array: MATLAB copies on write,
        % and neither side writes, so this costs no memory.
        Raw
    end

    methods
        function this = MinMaxPyramid(y, baseFactor)
        %MINMAXPYRAMID  Build the pyramid from a samples-by-channels signal.
        %   THIS = MINMAXPYRAMID(Y) builds with the default base factor of 8.
        %   THIS = MINMAXPYRAMID(Y, BASEFACTOR) uses a custom bucket ratio.
            if nargin < 2 || isempty(baseFactor)
                baseFactor = 8;
            end
            % validateattributes requires char class/attribute names.
            validateattributes(y, {'double', 'single'}, {'2d', 'nonempty'}, ...
                'MinMaxPyramid', 'Y', 1);
            validateattributes(baseFactor, {'double'}, ...
                {'scalar', 'integer', '>=', 2}, 'MinMaxPyramid', 'baseFactor', 2);

            if isrow(y)
                y = y(:);
            end
            this.Raw         = y;
            this.NumSamples  = size(y, 1);
            this.NumChannels = size(y, 2);
            this.BaseFactor  = baseFactor;

            % Build each coarse level from the previous one. Level 1 is reduced
            % from the raw samples; every further level from the level below,
            % so a level-L bucket covers BaseFactor^L raw samples exactly.
            levelLo = single(y);
            levelHi = levelLo;
            this.Lo     = {};
            this.Hi     = {};
            this.Factor = [];

            n = this.NumSamples;
            L = 0;
            while n > baseFactor
                [levelLo, levelHi] = this.reduce(levelLo, levelHi, baseFactor);
                L = L + 1;
                this.Lo{L}     = levelLo;
                this.Hi{L}     = levelHi;
                this.Factor(L) = baseFactor ^ L;   % raw samples per bucket
                n = size(levelLo, 1);
            end
        end

        function n = numLevels(this)
        %NUMLEVELS  Number of coarse levels stored in the pyramid.
            n = numel(this.Factor);
        end

        function level = pickLevel(this, bucketSize)
        %PICKLEVEL  Coarsest level whose bucket is no larger than BUCKETSIZE.
        %   Returns the largest level index L with Factor(L) <= BUCKETSIZE, so
        %   the drawn envelope is at least as fine as one bucket per requested
        %   column. Returns 1 when even level 1 is coarser than BUCKETSIZE.
            level = 1;
            for k = 1:numel(this.Factor)
                if this.Factor(k) <= bucketSize
                    level = k;
                else
                    break;
                end
            end
        end

        function [sampleIdx, yEnv] = queryInterleaved(this, i0, i1, nBuckets)
        %QUERYINTERLEAVED  Interleaved min/max envelope for a viewport.
        %   [SAMPLEIDX, YENV] = QUERYINTERLEAVED(THIS, I0, I1, NBUCKETS) returns
        %   an envelope of the raw sample range [I0, I1] decimated to about
        %   NBUCKETS columns. SAMPLEIDX is a (2*nb x 1) vector of representative
        %   sample indices and YENV is (2*nb x NumChannels); within each bucket
        %   the minimum row precedes the maximum row, matching the classic
        %   min/max decimation used for fast signal plots.
        %
        %   The caller should draw the raw samples directly when the visible
        %   span is already no wider than the axis; this method is for the
        %   decimated (zoomed-out) case. It reads the coarsest level whose
        %   buckets are no wider than a column, or the raw samples when even
        %   level 1 is wider (see the class header).
            i0   = max(1, round(i0));
            i1   = min(this.NumSamples, round(i1));
            span = i1 - i0 + 1;

            bucketSize = span / max(1, nBuckets);
            if isempty(this.Factor) || bucketSize < this.Factor(1)
                [sampleIdx, yEnv] = this.fromRaw(i0, i1, nBuckets);
                return;
            end
            L = this.pickLevel(bucketSize);
            f = this.Factor(L);

            % Buckets of level L that overlap the requested sample range,
            % merged G at a time so that each drawn bucket is as close to one
            % column as the level allows: a level's buckets can be up to
            % BaseFactor times narrower than a column, and drawing each of
            % them costs vertices without adding anything a pixel can show.
            b0 = max(1, floor((i0 - 1) / f) + 1);
            b1 = min(size(this.Lo{L}, 1), ceil(i1 / f));
            g = max(1, floor(bucketSize / f));
            [lo, hi] = MinMaxPyramid.reduce(this.Lo{L}(b0:b1, :), this.Hi{L}(b0:b1, :), g);

            % Representative sample index for the min (bucket start) and the max
            % (bucket end), so the envelope spans the correct time extent.
            nb = size(lo, 1);
            startIdx = (b0 - 1 + (0:nb - 1)' * g) * f + 1;
            endIdx   = min(startIdx + g * f - 1, min(b1 * f, this.NumSamples));   % the last group may be short

            sampleIdx = reshape([startIdx, endIdx]', [], 1);
            yEnv = zeros(2 * nb, this.NumChannels, 'single');
            yEnv(1:2:end, :) = lo;
            yEnv(2:2:end, :) = hi;
        end
    end

    methods (Access = private)
        function [sampleIdx, yEnv] = fromRaw(this, i0, i1, nBuckets)
        %FROMRAW  The envelope of raw samples [I0, I1] in buckets of equal
        %   length, as many as NBUCKETS allows and never longer than a column,
        %   in the same interleaved shape as queryInterleaved.
            span = i1 - i0 + 1;
            m = max(1, floor(span / max(1, nBuckets)));   % samples per bucket
            block = single(this.Raw(i0:i1, :));
            [lo, hi] = MinMaxPyramid.reduce(block, block, m);

            nb = size(lo, 1);
            startIdx = i0 + (0:nb - 1)' * m;
            endIdx   = min(startIdx + m - 1, i1);
            sampleIdx = reshape([startIdx, endIdx]', [], 1);
            yEnv = zeros(2 * nb, this.NumChannels, 'single');
            yEnv(1:2:end, :) = lo;
            yEnv(2:2:end, :) = hi;
        end
    end

    methods (Access = private, Static)
        function [outLo, outHi] = reduce(inLo, inHi, bf)
        %REDUCE  Combine BF adjacent buckets into one coarser bucket.
        %   Groups the rows of INLO / INHI into blocks of BF and takes the
        %   block minimum of the minima and maximum of the maxima. The final
        %   block is padded with NaN, which the omitnan reductions ignore.
            n   = size(inLo, 1);
            nch = size(inLo, 2);
            nb  = ceil(n / bf);
            pad = nb * bf - n;
            if pad > 0
                inLo = [inLo; nan(pad, nch, 'single')];
                inHi = [inHi; nan(pad, nch, 'single')];
            end
            inLo = reshape(inLo, bf, nb, nch);
            inHi = reshape(inHi, bf, nb, nch);
            outLo = reshape(min(inLo, [], 1, 'omitnan'), nb, nch);
            outHi = reshape(max(inHi, [], 1, 'omitnan'), nb, nch);
        end
    end
end
