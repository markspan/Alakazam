function space = Space(EEG, fallback)
%SPACE  Which template cortical sheet to work on for a dataset.
%
%   SPACE = StoredSourceSpace(EEG, FALLBACK) returns the sheet a stored
%   source estimate was computed on, or FALLBACK when the dataset carries
%   none (or carries something unrecognisable).
%
%   WHY A VIEW SHOULD FOLLOW THE STORED SHEET. A stored estimate is a vector
%   over ITS OWN vertices and can only be drawn on the sheet it was computed
%   for. A consumer that insisted on the full-resolution sheet would refuse
%   every estimate stored at a coarser one, which is the size most analysts
%   can actually afford to keep: a whole-epoch estimate is 499 MB per
%   subject at 20484 vertices and 128 MB at 5124, for a fit that differs by
%   0.04% (measured, not assumed -- the number of spatial patterns a forward
%   model can distinguish is bounded by the channel count, not the vertex
%   count).
%
%   THIS ONLY CHOOSES A MESH. It deliberately does not check the rest of the
%   estimate's key: whether the estimate may actually be USED is decided
%   afterwards, strictly, by SourceCache.Lookup. Choosing a
%   coarser mesh and then having to recompute on it costs a slightly slower
%   inverse; accepting an estimate that does not match would cost a wrong
%   picture, so the two decisions are kept apart.
%
%   Only the sheets FieldTrip actually ships are accepted, so a malformed or
%   hand-edited estimate cannot send a caller looking for a mesh file that
%   does not exist.
%
%   See also TRANSTOOLS.STOREDSOURCEESTIMATE, TRANSTOOLS.SOURCEESTIMATEKEY,
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL.
    if nargin < 2 || isempty(fallback)
        fallback = 20484;
    end
    space = fallback;

    if ~isstruct(EEG) || ~isfield(EEG, 'sourceEstimate') || isempty(EEG.sourceEstimate)
        return;
    end
    % A dataset may carry several estimates. They normally share a sheet,
    % since it is the analyst's setting rather than the method's; when they
    % genuinely disagree there is no right answer, so the fallback is used
    % rather than picking one arbitrarily and rendering at a resolution
    % nobody chose.
    estimates = EEG.sourceEstimate;
    found = [];
    for k = 1:numel(estimates)
        estimate = estimates(k);
        if ~isfield(estimate, 'key') || ~isstruct(estimate.key) || ...
                ~isfield(estimate.key, 'sourceSpace')
            continue;
        end
        candidate = estimate.key.sourceSpace;
        if isnumeric(candidate) && isscalar(candidate) && ...
                ismember(candidate, [20484, 8196, 5124])
            found(end + 1) = double(candidate); %#ok<AGROW>
        end
    end
    if ~isempty(found) && all(found == found(1))
        space = found(1);
    end
end
