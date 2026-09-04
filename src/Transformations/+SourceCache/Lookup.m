function [values, info] = Lookup(EEG, binLabel, wantedKey, request)
%LOOKUP  A stored source estimate for one bin, if and only if it is usable.
%
%   [VALUES, INFO] = Lookup(EEG, BINLABEL, WANTEDKEY) returns the whole
%   stored estimate for that bin. With a fourth argument REQUEST, a struct
%   carrying TimeWindow and ResampleHz, the estimate is cropped and thinned
%   to what was asked for, and refused unless it can cover it.
%
%   Returns [] for VALUES whenever anything does not line up. Every one of
%   those cases is a situation where reusing would answer a different
%   question than the one asked, so none is treated as a near-miss worth
%   salvaging: the cost of recomputing is time, the cost of a wrong reuse is
%   a result nobody can tell is wrong.
%
%   TWO INDEPENDENT GATES, because they catch different mistakes. The key
%   (SourceCache.Key) says the settings agree. The fingerprint
%   (SourceCache.Fingerprint) says the data is still the data the estimate
%   was computed from, which the key cannot know: every transformation
%   downstream of SourceEstimate copies the field forward, so a node can
%   inherit an estimate belonging to its parent while the settings still
%   match perfectly.
%
%   WHY THE WINDOW IS NOT ONE OF THOSE GATES ANY MORE. It used to be. The
%   key carried timeWindow and resampleHz, on the stated grounds that a
%   data-covariance method such as sLORETA sees only the window under
%   analysis, so an estimate over a wider window was "a different fit rather
%   than a superset that could be cropped afterwards".
%
%   That is not what the code does. Every ft_inverse_* spatial filter is
%   data-independent: computing one from two entirely different datasets on
%   the same leadfield gives bit-identical operators, for mne, eloreta and
%   sloreta alike, so the data covariance never reaches the estimate. The
%   source value at an instant therefore depends only on the scalp data at
%   that instant, and cropping commutes with inverting. Measured directly:
%   max|crop(invert) - invert(crop)| is 9.1e-13 for mne, 3.6e-15 for
%   sloreta and 1.4e-14 for eloreta, relative to the values themselves
%   ~1.5e-16 in every case, and decimation commutes just as exactly.
%
%   The practical difference is large. Keyed on the window, an estimate over
%   a whole epoch could not serve an analysis of 200-400 ms, so every
%   subject re-inverted for each window tried. Checked for COVERAGE instead,
%   one whole-epoch estimate per subject serves every window and rate later
%   asked of it.
%
%   COVERAGE IS TESTED AGAINST THE LATENCIES THE COMPUTE PATH WOULD PICK,
%   not against the requested window's endpoints, and the difference is not
%   pedantry. Decimation drops the tail: restricting a 1000 Hz epoch of
%   -200..799 ms to the whole epoch and thinning to 200 Hz keeps samples
%   1:5:1000, which end at 795. A stored whole-epoch estimate therefore ends
%   at 795 too, and asking "does it reach 799?" refuses the very estimate
%   that recomputing would reproduce exactly -- which is the default case,
%   a whole-epoch node with the dialog's own default window.
%
%   Requiring the stored estimate to CONTAIN those latencies also settles
%   the alignment question. A group test stacks subjects, so a reused slice
%   and a recomputed one must carry the same latencies, not merely a similar
%   number of them. A tolerance would have let a stored estimate a sample
%   short stand in for a full one, and the two would have disagreed by a
%   column only when some subjects hit the cache and others missed.
%
%   AN OLDER ESTIMATE, whose key still carries the window fields, no longer
%   matches and is recomputed once. That is deliberate: comparing only the
%   fields both keys happen to share would be the kind of leniency this file
%   exists to refuse, and the cost is one rebuild.
%
%   Shared by SourceClusterStats, Brain3DView and the report assets, so the
%   three cannot drift into asking slightly different questions of the same
%   stored data.
%
%   See also SOURCEESTIMATE, SOURCECACHE.KEY, SOURCECACHE.FINGERPRINT,
%   TRANSTOOLS.RESTRICTANDDECIMATE.
    values = [];
    info = struct();
    % NO REQUEST MEANS NO CROPPING, which is a different thing from a
    % request whose fields are empty. Brain3DView and the report assets ask
    % for whatever the estimate holds and slice it themselves; a caller that
    % passes a request with TimeWindow [] is saying "the whole epoch", and a
    % stored estimate narrower than the epoch genuinely cannot answer that.
    hasRequest = nargin >= 4;
    if ~hasRequest
        request = struct();
    end
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

    window = TransTools.FieldOr(request, 'TimeWindow', []);
    rateHz = TransTools.FieldOr(request, 'ResampleHz', []);

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
        storedTimes = reshape(estimate.times, 1, []);
        if hasRequest
            [columns, times] = matchingColumns(EEG, storedTimes, window, rateHz);
            if isempty(columns)
                continue;   % stored too narrow, or too coarse, to answer this
            end
        else
            columns = 1:numel(storedTimes);
            times = storedTimes;
        end

        values = estimate.values(:, columns, bin);

        info = struct('times', times);
        if isfield(estimate, 'info') && numel(estimate.info) >= bin
            stored = estimate.info(bin);
            names = fieldnames(stored);
            for i = 1:numel(names)
                info.(names{i}) = stored.(names{i});
            end
        end
        if numel(times) ~= numel(storedTimes) && isfield(info, 'ResidualVariance')
            % RESIDUAL VARIANCE BELONGS TO THE WINDOW IT WAS MEASURED OVER.
            % It is the share of the scalp data this current estimate fails
            % to explain, summed across the samples it saw, so the stored
            % figure describes the whole epoch and not the slice being
            % returned. Reporting it against a narrower window would be a
            % number that looks like a measurement of this analysis and is
            % not. NaN rather than a recomputation because the report
            % already renders an absent RV (sLORETA has none by
            % construction, for its own units reason).
            info.ResidualVariance = NaN;
        end
        return;
    end
end

% ======================================================================= %
function [columns, times] = matchingColumns(EEG, storedTimes, window, rateHz)
%MATCHINGCOLUMNS  Which stored columns answer this request, or [] if it
%   cannot be answered from what is stored.
%
%   Works out the latencies the compute path would have produced -- the
%   dataset's own times, restricted and thinned by the very function that
%   path uses -- and then requires the stored estimate to carry every one of
%   them. Anything else is a miss.
    columns = [];
    times = [];
    if ~isfield(EEG, 'times') || isempty(EEG.times) || isempty(storedTimes)
        return;
    end

    epochTimes = reshape(double(EEG.times), 1, []);
    [~, wanted] = TransTools.RestrictAndDecimate(zeros(1, numel(epochTimes)), ...
        epochTimes, window, rateHz, 'Alakazam:SourceCache');
    if isempty(wanted)
        return;
    end

    % Both sides descend from the same times vector, so the values are
    % bit-identical and a tolerance is only insurance against a stored
    % estimate written by some other route. A tenth of the stored step is
    % far tighter than the gap between neighbouring samples, so it cannot
    % match the wrong one.
    if numel(storedTimes) > 1
        tol = 0.1 * median(diff(storedTimes));
    else
        tol = eps;
    end

    columns = zeros(1, numel(wanted));
    for i = 1:numel(wanted)
        [gap, at] = min(abs(storedTimes - wanted(i)));
        if gap > tol
            columns = [];
            return;     % a latency the stored estimate does not have
        end
        columns(i) = at;
    end
    times = storedTimes(columns);
end

function ok = hasEveryField(estimate)
    ok = true;
    for field = {'values', 'times', 'bins', 'key', 'dataFingerprint'}
        if ~isfield(estimate, field{1})
            ok = false;
            return;
        end
    end
end
