function estimates = Attach(existing, fresh)
%ATTACH  Add a source estimate to whatever a dataset carries.
%
%   ESTIMATES = AttachSourceEstimate(EXISTING, FRESH) returns the array to
%   store on EEG.sourceEstimate: FRESH added to EXISTING, replacing any
%   entry that answers the same question.
%
%   SAME QUESTION MEANS SAME KEY. Two estimates differing in method,
%   orientation, mesh, regularisation, channels, window or rate are
%   different quantities and both are worth keeping; a consumer picks the
%   one it needs by key. Two with the SAME key are the same quantity
%   recomputed, so the newer one supersedes rather than accumulates -- and
%   its fingerprint is the current one, which matters when the data changed
%   underneath.
%
%   Used by the SourceEstimate transformation and by the report, which
%   attaches an estimate it had to compute so that the next report does not
%   compute it again.
%
%   See also SOURCEESTIMATE, TRANSTOOLS.STOREDSOURCEESTIMATE.
    if isempty(existing)
        estimates = fresh;
        return;
    end

    estimates = existing;
    for k = 1:numel(estimates)
        if isfield(estimates(k), 'key') && isequaln(estimates(k).key, fresh.key)
            estimates(k) = fresh;
            return;
        end
    end
    estimates(end + 1) = fresh;
end
