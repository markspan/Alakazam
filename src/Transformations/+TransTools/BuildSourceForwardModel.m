function [leadfield, sourcemodel, resolvedLabels, elec, headmodel] = BuildSourceForwardModel(labels, sourceSpace)
%BUILDSOURCEFORWARDMODEL  The EEG forward model (leadfield) for
%   Brain3DView's Source-estimate mode: FieldTrip's own template BEM head
%   model, paired with its own template electrode positions (NOT
%   Alakazam's own dipfit-derived chanlocs X/Y/Z -- see below for why),
%   and a template cortical-sheet source model.
%
%   LABELS is the dataset's own channel labels (case-insensitive; only
%   channels present in FieldTrip's own 10-5 template are used, the same
%   "look up by label, drop anything unresolved" approach
%   TransTools.TemplateScalpLocs already uses for dipfit's copy).
%
%   SOURCESPACE selects the template cortical sheet: 20484 (default, the
%   full-resolution one), 8196 or 5124. FEWER VERTICES IS NOT A LOSS OF
%   RESOLUTION HERE. The leadfield's rank is bounded by the channel count,
%   so ~30 electrodes cannot distinguish 20484 independent sources; the
%   fine sheet buys smoothness of rendering, not information. It does cost
%   heavily in any vertex-wise permutation test, where runtime grows
%   slightly faster than linearly in vertex count, which is why
%   SourceClusterStats exposes the choice. The default stays at 20484 so
%   that existing analyses and Brain3D's own view are unchanged.
%
%   Returns LEADFIELD (FieldTrip's own leadfield struct) and SOURCEMODEL
%   (the cortical-sheet struct, .pos/.tri, the same one
%   TransTools.DrawSourceMap renders onto -- LEADFIELD's source points are
%   exactly SOURCEMODEL's own vertices, a genuine surface model, not a
%   volumetric grid needing reprojection, so a source estimate maps onto
%   it 1:1), and RESOLVEDLABELS: the channel labels LEADFIELD's rows
%   actually correspond to, IN THAT ORDER -- the template's own electrode
%   order after filtering to LABELS' channel set, which is NOT
%   guaranteed to match the order LABELS (or a caller's own EEG.data rows)
%   came in. A caller MUST reorder its own per-channel data to
%   RESOLVEDLABELS' order before passing it to
%   TransTools.ComputeSourceEstimate -- feeding it rows in the wrong
%   order would silently scramble which amplitude gets attributed to
%   which electrode position, with no error to catch it.
%
%   Also returns ELEC and HEADMODEL, the template electrode definition and
%   BEM volume conductor the leadfield was built FROM. They are cached
%   alongside it and returned only because FieldTrip's own ft_inverse_*
%   functions take them as required positional arguments, even when handed
%   a precomputed leadfield they will not recompute (see
%   TransTools.InverseSolution). Nothing else needs them; the hand-rolled
%   TransTools.ComputeSourceEstimate path ignores them entirely, and the
%   three-output call it uses stays valid.
%
%   COORDINATE CHOICE: electrode positions come from
%   TransTools.Template1005File, the single accessor every part of the
%   application now reads its 10-5 template through. It returns FieldTrip's
%   own copy here, which keeps the electrodes self-consistent with the BEM
%   head model and cortical sheet FieldTrip ships and tests alongside them
%   for exactly this "no digitised positions, no per-subject MRI" case.
%
%   An earlier version of this comment warned that dipfit's copy of the
%   same template was "not independently verified here to be numerically
%   identical" and avoided it on that basis. It has since been measured:
%   the two files carry the same 346 labels in the same order with a
%   maximum displacement of 0 mm, and Template1005Test now asserts it. The
%   caution was reasonable and the answer turned out to be that they agree
%   (no FieldTrip installation was available while writing this).
%
%   CACHING: this is expensive (a leadfield over several thousand cortical
%   points x N electrodes), measured at 18.0 s for 29 channels on the 20484
%   sheet and 4.4 s on 5124, so the result is kept in a small in-memory LRU
%   keyed by mesh + sorted label list.
%
%   FOUR ENTRIES RATHER THAN ONE. One is right for the case this was written
%   for, Brain3DView redrawing a fixed montage, and wrong for every other:
%   alternating between two meshes, or two channel sets, evicted the other
%   on every call and rebuilt it, measured at 16.1 s per switch for a model
%   computed seconds earlier.
%
%   SESSION ONLY, no disk layer, and that is a deliberate reversal. One was
%   written, then removed once source analyses came to require every subject
%   in the study to be on the same montage (SourceClusterStats' own
%   sharedMontage): with one montage per study the leadfield is built once
%   per session and reused throughout, so persisting it bought a single
%   startup's 18 s in exchange for unbounded growth in prefdir, a second
%   invalidation rule of its own (the FieldTrip version), and cached state
%   the analyst could neither see nor clear. The tree already holds what is
%   worth keeping between sessions, which is the source estimates
%   themselves, on their own node.
%
%   NOTE: this pipeline was originally written without a FieldTrip
%   installation available to test against (see TransTools.ensureFieldTrip),
%   so some template file names/formats were guesses from documented
%   convention rather than a real install. The sourcemodel file has since
%   been confirmed directly against a real install (fieldtrip-20260812):
%   template/sourcemodel/cortex_20484.surf.gii (GIfTI, not .mat as first
%   guessed -- fixed). The headmodel (standard_bem.mat, assumed variable
%   name read defensively via loadSoleVariable) and electrode template
%   (template/electrode/standard_1005.elc, read with ft_read_sens) are
%   still UNCONFIRMED against a real install as of this note. Treat the
%   first real run through ft_prepare_leadfield as a validation pass, not
%   a trusted result, until checked against a known FieldTrip tutorial
%   output.
%
%   See also TRANSTOOLS.COMPUTESOURCEESTIMATE, TRANSTOOLS.DRAWSOURCEMAP,
%   TRANSTOOLS.ENSUREFIELDTRIP.
    persistent cache
    if isempty(cache)
        cache = emptyCacheEntry();
    end

    TransTools.ensureFieldTrip();

    if nargin < 2 || isempty(sourceSpace)
        sourceSpace = 20484;
    end
    sourceSpace = validateSourceSpace(sourceSpace);

    labelsCell = cellstr(string(labels));
    % The mesh belongs in the cache key: two analyses in one session may
    % legitimately use different sheets, and returning the cached leadfield
    % for the wrong one would be silently, catastrophically wrong.
    key = sprintf('%d|%s', sourceSpace, strjoin(sort(lower(labelsCell)), '|'));

    hit = find(strcmp(key, {cache.key}), 1);
    if ~isempty(hit)
        leadfield      = cache(hit).leadfield;
        sourcemodel    = cache(hit).sourcemodel;
        resolvedLabels = cache(hit).resolvedLabels;
        elec           = cache(hit).elec;
        headmodel      = cache(hit).headmodel;
        cache = promote(cache, hit);   % most recently used first
        return;
    end

    ftRoot = fileparts(which('ft_defaults'));

    % Template electrodes: FieldTrip's own 10-5 set, not Alakazam's dipfit
    % copy -- see the header comment for why.
    elec = ft_read_sens(TransTools.Template1005File('Alakazam:BuildSourceForwardModel'));
    elec = ft_convert_units(elec, 'mm');

    keep = ismember(lower(elec.label), lower(labelsCell));
    if ~any(keep)
        throw(MException('Alakazam:BuildSourceForwardModel', ...
            ['I''m afraid none of this dataset''s channels match FieldTrip''s own 10-5 ' ...
             'electrode template, so there is no forward model I can build.']));
    end
    elec.label    = elec.label(keep);
    elec.elecpos  = elec.elecpos(keep, :);
    elec.chanpos  = elec.chanpos(keep, :);
    resolvedLabels = elec.label; % the actual channel order LEADFIELD's rows will follow

    % Template head model: a precomputed 3-shell BEM (scalp/skull/brain),
    % the same "no per-subject MRI" template approach the scalp-projection
    % mode's own BrainMesh_ICBM152.nv uses, here for the forward
    % computation instead of just a display surface. Loaded into a struct
    % (not workspace variables) and read back by field name rather than an
    % assumed variable name (e.g. "vol"), defensively, since the exact
    % saved variable name could not be confirmed without FieldTrip
    % installed to inspect it directly.
    headmodelFile = fullfile(ftRoot, 'template', 'headmodel', 'standard_bem.mat');
    headmodel = loadSoleVariable(headmodelFile);
    headmodel = ft_convert_units(headmodel, 'mm');

    % Template cortical-sheet source model (surface, not a volumetric
    % grid -- template/sourcemodel/ also has volumetric standard_
    % sourcemodel3d*mm.mat grids, deliberately not used here): cortex_20484
    % is FieldTrip's higher-resolution template sheet, a reasonable
    % balance of anatomical detail against leadfield/inverse compute cost
    % for an interactive view. Shipped as GIfTI (.surf.gii, confirmed
    % directly against a real FieldTrip install -- .mat was an incorrect
    % guess in an earlier version of this file), read with
    % ft_read_headshape (FieldTrip's own general surface-file reader,
    % handling GIfTI/FreeSurfer/etc. uniformly), which returns .pos/.tri
    % directly -- no need for loadSoleVariable's own defensive variable-
    % name guessing here. Every vertex of a cortical SHEET is usable by
    % construction (unlike a volumetric grid, where ft_prepare_leadfield
    % itself marks some points outside the head), so .inside is set
    % explicitly rather than left to ft_read_headshape, which does not set
    % it for a plain surface file.
    sourcemodelFile = fullfile(ftRoot, 'template', 'sourcemodel', ...
        sprintf('cortex_%d.surf.gii', sourceSpace));

    % See TransTools.EnsureGiftiReader for why reading a template surface
    % needs a guard at all.
    TransTools.EnsureGiftiReader();
    sourcemodel = ft_read_headshape(sourcemodelFile);
    sourcemodel = ft_convert_units(sourcemodel, 'mm');
    sourcemodel.inside = true(size(sourcemodel.pos, 1), 1);

    cfg = [];
    cfg.headmodel   = headmodel;
    cfg.elec        = elec;
    cfg.sourcemodel = sourcemodel;
    cfg.reducerank  = 3; % EEG (unlike MEG) uses the full 3-D dipole moment
    % EXPECTED, HARMLESS WARNING: every run of this prints
    %   "assuming that the sourcemodel units are in mm"
    % from ft_prepare_sourcemodel. It is not a sign of a units problem --
    % the answer it reports is right, and it is right BECAUSE the geometry
    % above was explicitly converted: elec, headmodel and sourcemodel are
    % all ft_convert_units(..., 'mm'), and the message repeats the
    % sourcemodel's own .unit back.
    %
    % It cannot be silenced from here. ft_prepare_leadfield forwards only a
    % keepfields() whitelist to ft_prepare_sourcemodel and 'unit' is not on
    % it, so setting cfg.unit here does nothing at all (verified: identical
    % leadfields, identical warning). The warning also fires unconditionally
    % once ft_prepare_sourcemodel enters its "cfg.unit is empty" branch,
    % whichever source it then takes the unit from. Suppressing by
    % identifier is possible but the identifier ends in ":line383" -- it is
    % keyed to a LINE NUMBER, so it would rot silently at the next FieldTrip
    % bump and leave a warning nobody had noticed came back. Left visible on
    % purpose.
    leadfield = ft_prepare_leadfield(cfg);

    cache = remember(cache, key, leadfield, sourcemodel, resolvedLabels, elec, headmodel);
end

function v = loadSoleVariable(matFile)
%LOADSOLEVARIABLE  The one variable saved in MATFILE, whatever it is
%   named -- FieldTrip's own template .mat files each save exactly one
%   struct (headmodel/vol, sourcemodel/...), under a name that was not
%   possible to confirm without a FieldTrip installation to inspect
%   directly; reading it back by field name instead of an assumed name
%   avoids hard-coding a guess.
    s = load(matFile);
    f = fieldnames(s);
    if numel(f) ~= 1
        throw(MException('Alakazam:BuildSourceForwardModel', ...
            'I expected to find exactly one variable in %s, but found %d instead.', matFile, numel(f)));
    end
    v = s.(f{1});
end

function n = validateSourceSpace(sourceSpace)
%VALIDATESOURCESPACE  Only the sheets FieldTrip actually ships.
%   Checked here rather than left to a missing-file error, because the
%   failure would otherwise surface deep inside ft_read_headshape as a path
%   that means nothing to the analyst who typed the number.
    allowed = [20484, 8196, 5124];
    n = double(sourceSpace);
    if ~isscalar(n) || ~ismember(n, allowed)
        throw(MException('Alakazam:BuildSourceForwardModel:sourceSpace', ...
            'SourceSpace must be one of %s, not %s.', ...
            mat2str(allowed), mat2str(sourceSpace)));
    end
end

% ---- caching ------------------------------------------------------------ %

function entry = emptyCacheEntry()
%EMPTYCACHEENTRY  A 0x0 struct array with the right fields, so the LRU can be
%   indexed and grown without special-casing the first insertion.
    entry = struct('key', {}, 'leadfield', {}, 'sourcemodel', {}, ...
        'resolvedLabels', {}, 'elec', {}, 'headmodel', {});
end

function cache = promote(cache, hit)
%PROMOTE  Move the entry just used to the front (most recently used).
    cache = cache([hit, setdiff(1:numel(cache), hit, 'stable')]);
end

function cache = remember(cache, key, leadfield, sourcemodel, resolvedLabels, elec, headmodel)
%REMEMBER  Insert at the front, dropping the least recently used past the
%   limit. Four entries, for the reason the file header gives; each is
%   ~22 MB at 20484 vertices, so the ceiling is ~90 MB of session memory.
    fresh = struct('key', key, 'leadfield', leadfield, 'sourcemodel', sourcemodel, ...
        'resolvedLabels', {resolvedLabels}, 'elec', elec, 'headmodel', headmodel);
    if ~isempty(cache)
        cache = cache(~strcmp({cache.key}, key));
    end
    cache = [fresh, cache];
    if numel(cache) > 4
        cache = cache(1:4);
    end
end





