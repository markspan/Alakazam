function n = resolveNumRandomization(requested, mode, nSubjects)
%RESOLVENUMRANDOMIZATION  REQUESTED permutation count, upgraded to 'all'
%   when it is already close enough to the exhaustive count that
%   FieldTrip would print its own "close to the maximum number of unique
%   permutations, better use cfg.numrandomization='all'" warning anyway
%   (see resampledesign.m's own "requested/max > 0.5" threshold -- matched
%   here exactly, not a separately-chosen number, so this fires at
%   precisely the point that warning would have).
%
%   Only for a WITHIN-subject design (MODE 'vsZero'/'paired', ClusterStats'
%   own contrast.mode values): every subject there contributes exactly one
%   pair (real condition, comparison condition -- see pairedDesign.m), so
%   the exhaustive set is a bounded, cheap 2^NSUBJECTS sign-flips, and
%   FieldTrip's own 'all' path explicitly supports exactly that shape
%   (resampledesign.m errors if it does not). An 'independent' (between-
%   groups) design's own exhaustive count is NSUBJECTS! (FieldTrip's
%   generic "no unit variable" resampling permutes every subject
%   individually, not just the group re-splits that actually matter) --
%   infeasible to ever generate for a realistic sample size, so is left
%   untouched here regardless of how large REQUESTED is relative to it.
%
%   REQUESTED already being 'all' (or "all", a string) passes through
%   unchanged.
    if ischar(requested) || isstring(requested)
        n = char(requested);
        return;
    end
    if ~any(strcmp(mode, {'vsZero', 'paired'}))
        n = requested;
        return;
    end
    maxPerms = 2 ^ nSubjects;
    if requested / maxPerms > 0.5
        n = 'all';
    else
        n = requested;
    end
end
