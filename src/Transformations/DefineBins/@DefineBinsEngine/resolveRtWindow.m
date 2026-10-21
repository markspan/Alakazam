function [iv, trim] = resolveRtWindow(iv, rts)
%RESOLVERTWINDOW  Turn an 'rt within' window with bounds relative to the
%   mean reaction time into a window in plain milliseconds.
%
%   [IV, TRIM] = resolveRtWindow(IV, RTS) takes the window rtWindowOf
%   compiled and RTS, the reaction times (ms) of every event the bin's
%   condition matched in this recording, before the window is applied. A
%   bound written as mean + k sd becomes mean(RTS) + k * std(RTS), with the
%   sample standard deviation (n - 1), computed once: a single trimming
%   pass, not repeated until nothing more falls outside.
%
%   TRIM is [] for a window whose bounds are both plain numbers, which
%   needs no resolving. Otherwise it records what the bounds were computed
%   from and came to, for the summary and for EEG.bindesc(b).rtTrim:
%       mean, sd   of the reaction times (ms)
%       nRt        how many reaction times they were computed from
%       lo, hi     the resolved bounds (ms), with loOpen and hiOpen
%       note       '' or why the window cannot keep any trial
%       removed    how many trials the window dropped (filled in by
%                  evaluateBins, which applies it)
%
%   The statistics are those of the recording being processed, which is
%   what lets one script trim every participant at their own cutoff when
%   it is replayed or applied to all raw files.
%
%   WHEN THE BOUNDS CANNOT BE COMPUTED the bin keeps no trial, and NOTE says
%   why. With no reaction times there is no mean; with one, no standard
%   deviation. Keeping every trial instead would quietly skip the rule the
%   script asks for, which is the larger surprise of the two.
%
%   A window compiled before relative bounds existed has no loSd/hiSd and
%   is returned unchanged.

    loSd = sdField(iv, 'loSd');
    hiSd = sdField(iv, 'hiSd');
    trim = [];
    if isnan(loSd) && isnan(hiSd)
        return;
    end

    rts = rts(~isnan(rts));
    nRt = numel(rts);
    if nRt > 0; m = mean(rts); else; m = NaN; end
    if nRt > 1; s = std(rts); else; s = NaN; end

    if ~isnan(loSd); iv.lo = relativeBound(m, s, loSd); end
    if ~isnan(hiSd); iv.hi = relativeBound(m, s, hiSd); end

    note = '';
    if nRt == 0
        note = 'no reaction times to compute the mean from';
    elseif isnan(iv.lo) || isnan(iv.hi)
        note = 'a single reaction time has no standard deviation';
    elseif iv.lo > iv.hi
        note = sprintf('the low bound (%.0f ms) came out above the high bound (%.0f ms)', ...
            iv.lo, iv.hi);
    end

    trim = struct('mean', m, 'sd', s, 'nRt', nRt, 'lo', iv.lo, 'hi', iv.hi, ...
                  'loOpen', iv.loOpen, 'hiOpen', iv.hiOpen, 'note', note, 'removed', 0);
end

function k = sdField(iv, name)
%SDFIELD  The multiplier of a relative bound, or NaN for a plain one. A
%   compiled plan that went through jsonencode/jsondecode (a template, say)
%   comes back with [] where it held NaN, which means plain just the same.
    k = NaN;
    if isfield(iv, name) && isnumeric(iv.(name)) && isscalar(iv.(name))
        k = double(iv.(name));
    end
end

function b = relativeBound(m, s, k)
%RELATIVEBOUND  mean + k sd. A bare mean (k = 0) needs no standard
%   deviation, so it stays defined with a single reaction time.
    if k == 0
        b = m;
    else
        b = m + k * s;
    end
end
