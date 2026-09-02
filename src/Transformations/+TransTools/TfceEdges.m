function edges = TfceEdges(connmat, dim)
%TFCEEDGES  The vertex-by-time lattice a TFCE component tree runs over.
%   EDGES = TfceEdges(CONNMAT, DIM) returns an M x 2 int32 list of
%   undirected edges over the DIM = [nSpace nTime] volume, given the
%   nSpace x nSpace spatial adjacency CONNMAT.
%
%   Two kinds of edge: each point is joined to the same location at the
%   next sample, and to its spatial neighbours at the same sample. That is
%   what makes a "cluster" a space-time object rather than two separate
%   things that happen to coincide.
%
%   A PORT OF local_build_edges IN FieldTrip's private/tfcestat.m, kept
%   deliberately close to it: the compiled kernel this feeds
%   (TransTools.TfceScore) has to produce the same answer FieldTrip would,
%   and an edge list that differed even slightly would change results
%   without changing anything a reader could see.
%
%   Built once per analysis and passed to every permutation, since it
%   depends only on the geometry and not on the data.
%
%   See also TRANSTOOLS.TFCESCORE, TRANSTOOLS.ENSURETFCEMEX.
    nSpace = dim(1);
    nTime  = dim(2);
    A = reshape(int32(1:prod(dim)), dim);

    if nTime >= 2
        a = A(:, 1:end-1);
        b = A(:, 2:end);
        temporal = [a(:), b(:)];
    else
        temporal = zeros(0, 2, 'int32');
    end

    M = (connmat ~= 0);
    M = triu(M | M', 1);
    [c1, c2] = find(M);
    if isempty(c1)
        spatial = zeros(0, 2, 'int32');
    else
        offset  = int32((0:nTime-1) * nSpace);
        a = int32(c1(:)) + offset;
        b = int32(c2(:)) + offset;
        spatial = [a(:), b(:)];
    end

    edges = [temporal; spatial];
end
