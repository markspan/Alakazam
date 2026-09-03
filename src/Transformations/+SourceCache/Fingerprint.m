function fingerprint = Fingerprint(EEG)
%FINGERPRINT  A cheap identity for the data a result was computed from.
%
%   Compared with isequaln. Not a cryptographic hash and not trying to be:
%   its job is to notice that a stored result no longer belongs to the data
%   sitting beside it, which is an accident, not an attack.
%
%   WHY A STORED SOURCE ESTIMATE NEEDS ONE. EEG.sourceEstimate rides in the
%   struct, and every transformation downstream of it copies the struct
%   forward. Run SourceEstimate and then Baseline, and the new node carries
%   an estimate computed from the PREVIOUS node's data, while its settings
%   key still matches perfectly. Without this check a group analysis would
%   reuse that estimate and quietly report results for data that no longer
%   exists.
%
%   The tree does recompute descendants when a node changes, so in the
%   normal case the estimate is regenerated. This is the defence for the
%   cases where it is not: a node that acquired the field by inheritance
%   rather than by computing it, an older node from before a change, a
%   dataset edited outside the usual path. Reuse must prove itself; the
%   settings key alone proves only half of it.
%
%   Several independent summaries rather than one, because any single
%   statistic has changes it cannot see: a sign flip preserves the absolute
%   total, a permutation preserves both totals, and a baseline shift
%   preserves neither but could in principle preserve a sum over a
%   symmetric window.
%
%   See also SOURCEESTIMATE, SOURCECLUSTERSTATS, TRANSTOOLS.SOURCEESTIMATEKEY.
    fingerprint = struct('size', [], 'total', NaN, 'absTotal', NaN, ...
        'corners', [], 'times', []);
    if ~isfield(EEG, 'data') || isempty(EEG.data)
        return;
    end

    data = double(EEG.data);
    fingerprint.size     = size(data);
    fingerprint.total    = sum(data(:));
    fingerprint.absTotal = sum(abs(data(:)));
    fingerprint.corners  = [data(1), data(end)];

    if isfield(EEG, 'times') && ~isempty(EEG.times)
        t = double(EEG.times);
        fingerprint.times = [numel(t), t(1), t(end)];
    end
end
