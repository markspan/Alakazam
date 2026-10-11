function W = MovingWindows(sig, winN, stepN)
%MOVINGWINDOWS  A signal cut into its moving windows: an nWindows x WINN
%   matrix, one window per row, starting every STEPN samples; empty (0 x
%   WINN) when the signal is shorter than one window.
%
%   The last start is forced flush with the end of the signal. Stepping by
%   stepN alone stops at the last whole window that fits, leaving up to
%   winN + stepN - 2 samples at the tail that no window ever covers -- for a
%   -200..800 ms epoch at 256 Hz with ERPLAB's usual 200 ms / 100 ms
%   settings that is the last 90 ms, i.e. an artefact sitting on the P3 or
%   the LRP goes unseen. Found by validating against Luck's ch10 LRP data:
%   ERPLAB's artmwppth flagged trial 222 (FC4, 311 uV peak-to-peak at
%   602..797 ms) and this detector did not. See Docs/luck.md.
%
%   Shared by ArtefactDetect's step-function and moving-window peak-to-peak
%   detectors and by the data-quality report's blink count, so that a blink
%   is the same thing in both.
%
%   See also TRANSTOOLS.LARGESTWINDOWVALUE, ARTEFACTDETECT.
    sig = sig(:).';
    n = numel(sig);
    if n < winN
        W = zeros(0, winN);
        return;
    end
    starts = unique([1:stepN:(n - winN + 1), n - winN + 1]);
    W = sig(starts(:) + (0:winN - 1));
end
