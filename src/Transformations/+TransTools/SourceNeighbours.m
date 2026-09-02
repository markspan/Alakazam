function [neighbours, labels, adjacency] = SourceNeighbours(sourcemodel)
%SOURCENEIGHBOURS  FieldTrip neighbour structure for a cortical sheet.
%   [NEIGHBOURS, LABELS] = SourceNeighbours(SOURCEMODEL) returns the
%   adjacency FieldTrip's cluster/TFCE correction needs in source space:
%   one entry per vertex, listing the vertices it shares a triangle with.
%   LABELS are the synthetic vertex names ('v1', 'v2', ...) both the
%   neighbour structure and the timelock data use. ADJACENCY is the same
%   graph as a sparse nVertex x nVertex matrix, in LABELS order: FieldTrip
%   derives exactly this from NEIGHBOURS via its own channelconnectivity,
%   but that lives in its private/ folder and cannot be called from here,
%   and rebuilding it from the label strings would be both slower and a
%   second chance to get the ordering wrong.
%
%   THIS IS THE ONE PIECE THAT MAKES A SOURCE CLUSTER TEST DIFFERENT FROM A
%   SCALP ONE. ft_timelockstatistics does not care what a "channel" is: it
%   clusters over whatever adjacency graph it is handed. ClusterStats builds
%   that graph from electrode positions (ft_prepare_neighbours, method
%   'triangulation'); here it comes from the cortical mesh's OWN
%   triangulation, which is the correct neighbourhood for activity spreading
%   across a folded sheet. Everything else -- the design, the permutation,
%   the correction -- is identical, and is shared rather than copied.
%
%   MESH ADJACENCY, NOT EUCLIDEAN PROXIMITY, and the difference is the whole
%   point. Two vertices on opposite banks of a sulcus can be a millimetre
%   apart in space while being far apart along the cortical surface, and
%   they are not functionally contiguous. A distance-based neighbourhood
%   would merge them into one cluster and manufacture spatial extent that
%   the data does not support; sharing a triangle is the honest criterion.
%
%   SYNTHETIC LABELS, deliberately. FieldTrip identifies rows by label
%   string, so the 20484 vertices need names. They carry no meaning and are
%   never shown to an analyst -- a vertex is reported by its position and
%   its atlas region, not by "v13407" -- but they must be generated the same
%   way here and in the timelock data, which is why this function returns
%   them rather than leaving each caller to invent its own scheme.
%
%   Cached: the template sheet is identical for every subject and every
%   session, and building the adjacency walks ~40000 triangles.
%
%   See also SOURCECLUSTERSTATS, CLUSTERSTATS,
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL.
    persistent cache
    if ~isstruct(sourcemodel) || ~isfield(sourcemodel, 'pos') || ~isfield(sourcemodel, 'tri')
        throw(MException('Alakazam:SourceNeighbours', ...
            ['Problem in SourceNeighbours: I need a surface with .pos and .tri. A ' ...
             'volumetric grid has no triangulation, so it has no mesh adjacency.']));
    end

    nVertex = size(sourcemodel.pos, 1);
    key = sprintf('%d|%d', nVertex, size(sourcemodel.tri, 1));
    if ~isempty(cache) && strcmp(cache.key, key)
        neighbours = cache.neighbours;
        labels     = cache.labels;
        adjacency  = cache.adjacency;
        return;
    end

    labels = TransTools.SourceVertexLabels(nVertex);
    tri = double(sourcemodel.tri);

    % Every triangle contributes its three edges, in both directions. Built
    % as one sparse adjacency matrix rather than by growing 20484 cell
    % arrays: the sparse route is a single pass over the triangles, and the
    % per-vertex neighbour lists then fall out of its columns.
    edgesFrom = [tri(:, 1); tri(:, 2); tri(:, 3); tri(:, 2); tri(:, 3); tri(:, 1)];
    edgesTo   = [tri(:, 2); tri(:, 3); tri(:, 1); tri(:, 1); tri(:, 2); tri(:, 3)];
    adjacency = sparse(edgesFrom, edgesTo, true, nVertex, nVertex);
    adjacency = adjacency - diag(diag(adjacency));   % a vertex is not its own neighbour

    neighbours = struct('label', labels(:)', 'neighblabel', cell(1, nVertex));
    for v = 1:nVertex
        neighbours(v).neighblabel = labels(find(adjacency(:, v)))'; %#ok<FNDSB>
    end

    cache = struct('key', key, 'neighbours', neighbours, 'labels', {labels}, ...
        'adjacency', adjacency);
end
