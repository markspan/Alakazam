function brainPatch = DrawBrainPatch(ax, vertices, faces, vertexData, cmap, climRange, brainPatch)
%DRAWBRAINPATCH  Draw (or update in place) a coloured, rotatable brain-mesh
%   patch in AX -- the shared create-vs-update/lighting/starting-view
%   boilerplate DrawBrainMap.m (scalp-topography projection) and
%   DrawSourceMap.m (MNE source estimate) each independently reimplemented,
%   byte-for-byte identical apart from the colormap/colour range/mesh they
%   draw -- consolidated here so the two cannot silently drift apart.
%
%   VERTICES/FACES are the mesh geometry (Nx3 mm / Mx3, 1-based -- either
%   DrawBrainMap's own display mesh or DrawSourceMap's cortical-sheet
%   sourcemodel). VERTEXDATA is one value per vertex (FaceVertexCData).
%   CMAP is the colormap to use (DrawBrainMap's diverging scale for signed
%   scalp amplitude; DrawSourceMap's sequential parula for non-negative
%   source power). CLIMRANGE is a [lo, hi] pair.
%
%   BRAINPATCH, if a valid patch graphics object, is updated in place
%   (FaceVertexCData only -- geometry untouched) instead of rebuilt: both
%   callers' meshes are tens of thousands of vertices, and Brain3DView
%   calls this on every slider tick while scrubbing (including
%   continuously during a drag, the same ValueChangingFcn behaviour
%   ScalpDistributionView's own slider uses) -- rebuilding that much
%   geometry from scratch on every tick visibly lagged the drag; updating
%   one existing patch's colour data does not. Pass [] (or a deleted/
%   invalid handle) to force a rebuild -- e.g. Brain3DView does this on
%   every Projection-mode switch, since the two modes' meshes have
%   different vertex/face counts, so an in-place update cannot work
%   across them. Returns the (possibly newly created) patch handle for the
%   caller to pass back in next time.
%
%   Rotation itself is wired in Brain3DView, not here: it sets
%   Axes.Interactions = rotateInteraction so a plain click-and-drag orbits
%   the head (see its constructor's own comment for why that is set
%   explicitly), plus the standard axtoolbar.
%
%   See also TRANSTOOLS.DRAWBRAINMAP, TRANSTOOLS.DRAWSOURCEMAP, BRAIN3DVIEW.
    if ~isempty(brainPatch) && isvalid(brainPatch)
        brainPatch.FaceVertexCData = vertexData;
    else
        cla(ax);
        colormap(ax, cmap);
        brainPatch = patch(ax, 'Vertices', vertices, 'Faces', faces, ...
            'FaceVertexCData', vertexData, 'FaceColor', 'interp', 'EdgeColor', 'none', ...
            'FaceLighting', 'gouraud', 'AmbientStrength', 0.55, 'SpecularStrength', 0.1);
        light(ax, 'Position', [1 1 1], 'Style', 'infinite');
        light(ax, 'Position', [-1 -1 0.5], 'Style', 'infinite');
        axis(ax, 'equal');
        axis(ax, 'off');
        view(ax, [-37.5, 30]);   % a three-quarter starting view; freely rotatable from here by dragging
    end
    ax.CLim = climRange;
end
