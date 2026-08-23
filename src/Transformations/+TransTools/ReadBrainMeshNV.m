function mesh = ReadBrainMeshNV(nvFile)
%READBRAINMESHNV  Parse a BrainNet Viewer ".nv" surface mesh file.
%   MESH = READBRAINMESHNV(nvFile) returns a struct with:
%     .Vertices  Nx3 double, vertex coordinates in mm (MNI-ish space, same
%                convention as dipfit's standard_1005.elc electrode
%                template -- see DrawBrainMap for the coordinate-alignment
%                note)
%     .Faces     Mx3 double, 1-based vertex indices per triangle (already
%                the convention patch()'s own Faces property expects)
%
%   Format (see the BrainNet Viewer manual, "Surface files" -- a plain
%   ASCII file, verified directly against the bundled BrainMesh_ICBM152.nv,
%   see Meshes/README.md): a line with the vertex count N, N lines of
%   "x y z", a line with the face count M, then M lines of "i j k" (1-based
%   vertex indices). Read with two bulk fscanf calls rather than a
%   textscan/line loop -- BrainMesh_ICBM152.nv alone is 81,924 vertices +
%   163,840 faces, and this is re-read every time a Brain3D tab opens (see
%   Brain3DView), so parse speed matters here in a way it never did for
%   DrawScalpMap's own few-dozen-electrode template lookups.
%
%   See also DRAWBRAINMAP, BRAIN3DVIEW, MESHES/README.MD.
    fid = fopen(nvFile, 'r');
    if fid < 0
        throw(MException('Alakazam:ReadBrainMeshNV', ...
            'I''m sorry, I was unable to read the brain mesh file: %s', nvFile));
    end
    closer = onCleanup(@() fclose(fid));

    nVert = fscanf(fid, '%d', 1);
    vertices = fscanf(fid, '%f', [3, nVert])';
    nFace = fscanf(fid, '%d', 1);
    faces = fscanf(fid, '%f', [3, nFace])';

    mesh = struct('Vertices', vertices, 'Faces', faces);
end
