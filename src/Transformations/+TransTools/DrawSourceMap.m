function brainPatch = DrawSourceMap(ax, sourcePower, sourcemodel, mapLimit, brainPatch)
%DRAWSOURCEMAP  Draw (or update) a per-vertex source-power estimate on
%   FieldTrip's own cortical-sheet mesh -- Brain3DView's Source-estimate
%   mode, the counterpart of TransTools.DrawBrainMap's scalp-projection
%   mode.
%
%   SOURCEPOWER is one value per SOURCEMODEL vertex (a single column of
%   TransTools.ComputeSourceEstimate's own nVertex x nTime output, already
%   sliced to the instant being drawn -- same "caller slices, this just
%   draws" contract as DrawBrainMap). SOURCEMODEL is
%   BuildSourceForwardModel's own second return value (.pos/.tri).
%   MAPLIMIT is the shared upper colour limit across the whole session
%   (source power is non-negative, so the scale is [0, MAPLIMIT], a
%   sequential colormap -- NOT DrawBrainMap's signed diverging scale,
%   matching how CoherenceTopographyView/CoherenceView already treat
%   their own non-negative quantities).
%
%   BRAINPATCH, if given and still a valid patch graphics object, is
%   updated in place instead of rebuilt (a cortical sheet is tens of
%   thousands of vertices; rebuilding it from scratch on every slider tick
%   would not stay smooth) -- the actual create-vs-update/lighting/
%   starting-view drawing is TransTools.DrawBrainPatch, shared with
%   DrawBrainMap's own scalp-topography mesh; see its own header comment
%   for the full reasoning. Returns the (possibly newly created) patch handle.
%
%   See also TRANSTOOLS.COMPUTESOURCEESTIMATE, TRANSTOOLS.DRAWBRAINMAP,
%   TRANSTOOLS.DRAWBRAINPATCH.
    if nargin < 5
        brainPatch = [];
    end
    brainPatch = TransTools.DrawBrainPatch(ax, sourcemodel.pos, sourcemodel.tri, sourcePower, ...
        parula, [0, mapLimit], brainPatch);
end
