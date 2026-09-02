function description = DescribeCluster(vertexMask, sourcemodel, peakVertex, atlasName)
%DESCRIBECLUSTER  Where a significant cluster sits, in words and in mm.
%   DESCRIPTION = DescribeCluster(VERTEXMASK, SOURCEMODEL, PEAKVERTEX,
%   ATLASNAME) turns a logical mask over cortical vertices into something a
%   reader can act on.
%
%   DESCRIPTION fields:
%     .PeakRegion    the atlas region the peak vertex falls in
%     .PeakMni       that vertex's position, [x y z] in mm
%     .Regions       every region the cluster touches, most vertices first
%     .RegionShare   the fraction of the cluster in each of those regions
%     .Text          a one-line summary, e.g. "peak in Temporal_Mid_L
%                    (-56 -34 -2 mm), extending into Temporal_Sup_L"
%     .NVertices     how many vertices the cluster covers
%
%   BOTH A NAME AND A COORDINATE, deliberately. A region name is what makes
%   a result readable, and a coordinate is what makes its precision
%   checkable: "Temporal_Mid_L" sounds equally confident whether the peak
%   sits in the middle of that gyrus or one vertex inside its border, and
%   the millimetres say which. Reporting only the name would overstate what
%   a template-based estimate can support; reporting only the coordinate
%   would be unreadable.
%
%   THE REGION LIST IS NOT A CLAIM ABOUT EXTENT. A cluster-permutation test
%   establishes that an effect exists somewhere in a space-time region; it
%   does NOT establish that the effect covers the whole of that region, so
%   "extending into X" describes where the cluster's vertices lie, not
%   where the effect has been shown to be. This distinction is among the
%   most frequently misreported in the literature, which is why the report
%   built on this states it rather than assuming it is understood.
%
%   Vertices the atlas does not label are counted in .NVertices but named
%   as 'unlabelled', rather than being assigned to a nearest neighbour: on
%   the template sheet about 12% of vertices fall in unlabelled voxels,
%   mostly midline and boundary, and inventing a region for them would
%   quietly widen every reported cluster.
%
%   See also SOURCECLUSTERSTATS, TRANSTOOLS.ATLASVERTEXLABELS.
    if nargin < 4 || isempty(atlasName)
        atlasName = 'aal';
    end

    vertexMask = logical(vertexMask(:));
    description = struct('PeakRegion', 'unlabelled', 'PeakMni', [NaN NaN NaN], ...
        'Regions', {{}}, 'RegionShare', [], 'Text', '', 'NVertices', nnz(vertexMask));
    if ~any(vertexMask)
        description.Text = 'no vertices';
        return;
    end

    [vertexLabel, labels] = TransTools.AtlasVertexLabels(sourcemodel, atlasName);

    description.PeakMni = sourcemodel.pos(peakVertex, :);
    description.PeakRegion = regionNameOf(vertexLabel(peakVertex), labels);

    inCluster = vertexLabel(vertexMask);
    named = inCluster(inCluster > 0);
    if isempty(named)
        description.Text = sprintf('peak at %s, in unlabelled cortex (%d vertices)', ...
            mniText(description.PeakMni), description.NVertices);
        return;
    end

    counts = accumarray(named, 1, [numel(labels), 1]);
    [counts, order] = sort(counts, 'descend');
    keep = counts > 0;
    description.Regions     = labels(order(keep))';
    description.RegionShare = counts(keep) / numel(inCluster);

    others = description.Regions(~strcmp(description.Regions, description.PeakRegion));
    if isempty(others)
        description.Text = sprintf('peak in %s (%s), %d vertices', ...
            description.PeakRegion, mniText(description.PeakMni), description.NVertices);
    else
        description.Text = sprintf('peak in %s (%s), extending into %s; %d vertices', ...
            description.PeakRegion, mniText(description.PeakMni), ...
            strjoin(others(1:min(2, numel(others))), ' and '), description.NVertices);
    end
end

% ======================================================================= %
function name = regionNameOf(index, labels)
    if index > 0 && index <= numel(labels)
        name = labels{index};
    else
        name = 'unlabelled';
    end
end

function s = mniText(pos)
%MNITEXT  Rounded to whole millimetres, because the template forward model
%   does not support more precision than that and printing decimals would
%   imply it does.
    s = sprintf('%d %d %d mm', round(pos(1)), round(pos(2)), round(pos(3)));
end
