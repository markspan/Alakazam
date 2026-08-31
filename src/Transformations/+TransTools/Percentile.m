function v = Percentile(x, p)
%PERCENTILE  One percentile of X, without the Statistics Toolbox.
%   V = TransTools.Percentile(X, P) returns the P-th percentile (P in
%   0..100) of X, ignoring NaNs. X need not be sorted.
%
%   TOOLBOX-FREE ON PURPOSE. prctile lives in the Statistics and Machine
%   Learning Toolbox, and these callers run in ordinary preprocessing: a
%   transformation that could not look at a channel without a licensed
%   toolbox would be a poor trade for one line of indexing.
%
%   The nearest-rank definition, which is what the callers want: a
%   threshold and an interquartile range both describe where real observed
%   values sit, and interpolating between two of them would invent a value
%   the signal never took.
%
%   Written twice before it lived here -- once as prctileOf taking 0..100
%   and once as quantileOf taking 0..1 and a pre-sorted input, which is the
%   sort of divergence two copies produce on their own.
%
%   See also DETECTDIODEONSETS, DIODETRIGGERDELAY.
    x = sort(x(~isnan(x)));
    if isempty(x)
        v = NaN;
        return;
    end
    v = x(max(1, min(numel(x), round(p / 100 * (numel(x) - 1)) + 1)));
end
