function [iv, record] = resolveValueWindow(test, values)
%RESOLVEVALUEWINDOW  A value test's window in plain numbers: each bound
%   taken from the statistics of VALUES, the values (after the test's
%   transform) of the trials it is about, NaN for one without a value.
%
%   The statistics, of the values that are numbers:
%     mean     the mean
%     median   the median
%     pNN      the NNth percentile as MATLAB's prctile defines it (Hazen's:
%              the sorted values are the 100(i - 0.5)/n percentiles, with
%              straight lines between them), so p50 is the median
%     sd       the sample standard deviation (n - 1)
%     iqr      p75 - p25
%     mad      the median absolute deviation from the median, times 1.4826,
%              which makes it estimate the standard deviation of normally
%              distributed values (Leys et al., 2013), so median + 2.5 mad
%              is comparable to mean + 2.5 sd but undisturbed by the
%              outliers it is meant to find
%   computed once: a single pass, not repeated until nothing falls outside.
%
%   IV has lo, hi, loOpen and hiOpen. RECORD says what the window came to,
%   for EEG.bindesc(b).filters and the summary: the test written out
%   (text), how many values (n), their mean, sd, median, iqr and mad, the
%   resolved lo and hi with loOpen and hiOpen, note ('' or why the window
%   can keep no trial) and removed (filled in by evaluateBins).
%
%   WHEN A BOUND CANNOT BE COMPUTED the window keeps no trial, and NOTE says
%   why: with no values there is no statistic, with one no standard
%   deviation. Keeping every trial would skip the rule the script asks for
%   without a word.
%
%   See also DEFINEBINSENGINE.SCANVALUETEST, DEFINEBINSENGINE.EVALUATEBINS.
    x = sort(values(~isnan(values)));
    n = numel(x);
    st = struct('mean', NaN, 'sd', NaN, 'median', NaN, 'iqr', NaN, 'mad', NaN);
    if n > 0
        st.mean = mean(x);
        st.median = median(x);
        st.iqr = percentile(x, 75) - percentile(x, 25);
        st.mad = 1.4826 * median(abs(x - st.median));
    end
    if n > 1
        st.sd = std(x);
    end

    lo = boundValue(test.window.lo, x, st);
    hi = boundValue(test.window.hi, x, st);
    usesStats = strcmp(test.window.lo.kind, 'stat') || strcmp(test.window.hi.kind, 'stat');
    note = '';
    if usesStats && n == 0
        note = 'no values to compute its statistics from';
    elseif isnan(lo) || isnan(hi)
        note = 'a single value has no standard deviation';
    elseif lo > hi
        note = sprintf('the low bound (%g) came out above the high bound (%g)', lo, hi);
    end
    if ~isempty(note)
        lo = NaN;   % in no window: inInterval is false against NaN
    end

    iv = struct('lo', lo, 'hi', hi, 'loOpen', logical(test.window.loOpen), ...
        'hiOpen', logical(test.window.hiOpen));
    record = struct('text', test.text, 'n', n, 'mean', st.mean, 'sd', st.sd, ...
        'median', st.median, 'iqr', st.iqr, 'mad', st.mad, 'lo', lo, 'hi', hi, ...
        'loOpen', iv.loOpen, 'hiOpen', iv.hiOpen, 'note', note, 'removed', 0);
end

% ======================================================================= %
function v = boundValue(b, x, st)
    switch b.kind
        case 'num'
            v = double(b.value);
        case 'inf'
            v = double(b.value) * Inf;
        otherwise
            if isempty(x)
                v = NaN;
                return;
            end
            switch b.stat
                case 'mean'
                    v = st.mean;
                case 'median'
                    v = st.median;
                otherwise
                    v = percentile(x, double(b.pct));
            end
            if b.k ~= 0
                v = v + double(b.k) * st.(b.spread);
            end
    end
end

function q = percentile(x, p)
%PERCENTILE  The Pth percentile of the sorted values X, as prctile has it:
%   x(i) is the 100(i - 0.5)/n percentile, straight lines between, the
%   smallest and largest beyond.
    n = numel(x);
    position = n * p / 100 + 0.5;
    if position <= 1
        q = x(1);
    elseif position >= n
        q = x(n);
    else
        below = floor(position);
        q = x(below) + (position - below) * (x(below + 1) - x(below));
    end
end
