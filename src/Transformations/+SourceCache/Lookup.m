function [values, info] = Lookup(EEG, binLabel, wantedKey)
%LOOKUP  A stored source estimate for one bin, if and only if
%   it is usable.
%
%   Returns [] for VALUES whenever anything does not line up. Every one of
%   those cases is a situation where reusing would answer a different
%   question than the one asked, so none is treated as a near-miss worth
%   salvaging: the cost of recomputing is time, the cost of a wrong reuse is
%   a result nobody can tell is wrong.
%
%   TWO INDEPENDENT GATES, because they catch different mistakes. The key
%   (SourceCache.Key) says the settings agree. The fingerprint
%   (SourceCache.Fingerprint) says the data is still the data the
%   estimate was computed from, which the key cannot know: every
%   transformation downstream of SourceEstimate copies the field forward, so
%   a node can inherit an estimate belonging to its parent while the
%   settings still match perfectly.
%
%   Shared by SourceClusterStats and Brain3DView so that the two cannot
%   drift into asking slightly different questions of the same stored data.
%
%   See also SOURCEESTIMATE, TRANSTOOLS.SOURCEESTIMATEKEY,
%   TRANSTOOLS.DATAFINGERPRINT.
    values = [];
    info = struct();
    if ~isfield(EEG, 'sourceEstimate') || isempty(EEG.sourceEstimate)
        return;
    end
    % AN ARRAY, because one dataset can legitimately carry several
    % estimates: dSPM and sLORETA are different quantities, signed and
    % magnitude are not convertible, and a report renders more than one
    % while Brain3D switches between them. A single slot would let each
    % new one silently evict the last.
    estimates = EEG.sourceEstimate;
    fingerprint = SourceCache.Fingerprint(EEG);

    for k = 1:numel(estimates)
        estimate = estimates(k);
        if ~hasEveryField(estimate)
            continue;   % written by an older version: skip rather than guess
        end
        if ~isequaln(estimate.key, wantedKey)
            continue;
        end
        if ~isequaln(estimate.dataFingerprint, fingerprint)
            continue;   % inherited from an earlier node, or the data changed
        end
        bin = find(strcmp(estimate.bins, binLabel), 1);
        if isempty(bin) || size(estimate.values, 3) < bin
            continue;
        end

        values = estimate.values(:, :, bin);
        info = struct('times', estimate.times);
        if isfield(estimate, 'info') && numel(estimate.info) >= bin
            stored = estimate.info(bin);
            names = fieldnames(stored);
            for i = 1:numel(names)
                info.(names{i}) = stored.(names{i});
            end
        end
        return;
    end
end

% ======================================================================= %
function ok = hasEveryField(estimate)
    ok = true;
    for field = {'values', 'times', 'bins', 'key', 'dataFingerprint'}
        if ~isfield(estimate, field{1})
            ok = false;
            return;
        end
    end
end
