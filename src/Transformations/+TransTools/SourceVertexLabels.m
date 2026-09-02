function labels = SourceVertexLabels(nVertex)
%SOURCEVERTEXLABELS  Synthetic 'v1'...'vN' names for cortical vertices.
%   LABELS = SourceVertexLabels(NVERTEX) returns an NVERTEX x 1 cellstr.
%
%   FieldTrip identifies every row of a timelock structure by a label
%   string, and matches the neighbour structure to the data by those same
%   strings. Cortical vertices have no names, so they need generated ones --
%   and the neighbour structure and the data must generate them IDENTICALLY,
%   or ft_timelockstatistics silently intersects the two label sets and
%   tests whatever survives. Two independent sprintf loops in two files is
%   exactly the kind of thing that agrees until someone pads a number.
%
%   The names are internal and never shown: a vertex is reported to an
%   analyst by its position and its anatomical region, never as "v13407".
%
%   See also TRANSTOOLS.SOURCENEIGHBOURS, SOURCECLUSTERSTATS.
    labels = compose('v%d', (1:nVertex)');
end
