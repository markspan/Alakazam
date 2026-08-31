function sourcemodel = TemplateSourceModel()
%TEMPLATESOURCEMODEL  FieldTrip's template cortical-sheet source model.
%   SOURCEMODEL = TemplateSourceModel() returns the cortex_20484 surface
%   (.pos/.tri, mm), with .inside set for every vertex.
%
%   SEPARATED FROM BuildSourceForwardModel so the sheet can be read WITHOUT
%   building a leadfield. Listing which anatomical regions a dataset could
%   be parcellated into needs only the geometry, and the leadfield is the
%   expensive part by orders of magnitude (several thousand cortical points
%   x N electrodes). A dialog that had to compute a full forward model
%   before it could show a list of region names would be unusable.
%
%   Cached, since it is a fixed template file.
%
%   A cortical SHEET has every vertex usable by construction, unlike a
%   volumetric grid where ft_prepare_leadfield itself marks some points
%   outside the head -- so .inside is set explicitly here, which
%   ft_read_headshape does not do for a plain surface file.
%
%   See also TRANSTOOLS.BUILDSOURCEFORWARDMODEL, TRANSTOOLS.PARCELLATESOURCE,
%   TRANSTOOLS.SURFACENORMALS.
    persistent cached
    if ~isempty(cached)
        sourcemodel = cached;
        return;
    end

    TransTools.ensureFieldTrip('Source parcellation');

    ftRoot = fileparts(which('ft_defaults'));
    file = fullfile(ftRoot, 'template', 'sourcemodel', 'cortex_20484.surf.gii');
    if ~isfile(file)
        throw(MException('Alakazam:TemplateSourceModel', ...
            ['Problem in TemplateSourceModel: this FieldTrip install has no cortical ' ...
             'sheet at %s, so there is no surface to estimate sources on.'], file));
    end

    sourcemodel = ft_convert_units(ft_read_headshape(file), 'mm');
    sourcemodel.inside = true(size(sourcemodel.pos, 1), 1);
    cached = sourcemodel;
end
