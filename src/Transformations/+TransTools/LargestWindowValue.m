function m = LargestWindowValue(W, kind)
%LARGESTWINDOWVALUE  The largest of the per-window scores of moving windows
%   W (TransTools.MovingWindows), 0 when there are none.
%
%   KIND 'step' scores a window by |mean(first half) - mean(second half)|,
%   ERPLAB's step function; any other KIND by its peak-to-peak range.
%
%   A window holding NaN (a sample rejected or blanked upstream) scores NaN
%   for the step function and is passed over, exactly as the loop this
%   replaces passed over a NaN by testing "v > m"; max() ignores NaN, and
%   the 0 in front is the loop's own starting value.
%
%   See also TRANSTOOLS.MOVINGWINDOWS, ARTEFACTDETECT.
    if isempty(W)
        m = 0;
        return;
    end
    switch kind
        case 'step'
            half = floor(size(W, 2) / 2);
            v = abs(mean(W(:, 1:half), 2) - mean(W(:, half + 1:end), 2));
        otherwise
            v = max(W, [], 2) - min(W, [], 2);
    end
    m = max([0; v(:)]);
end
