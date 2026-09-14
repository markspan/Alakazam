function assets = generateSourceEstimateReportAssets(entries, imagesDir, methods)
%GENERATESOURCEESTIMATEREPORTASSETS  Best-effort source-estimate PNG
%   snapshots + fit statistics for a Quarto report's optional Source
%   Estimate section (see ReportSections.sourceEstimateSection and
%   generateQuartoReport's own SOURCEESTIMATES argument).
%
%   ENTRIES is generateQuartoReport's own ENTRIES argument, reused
%   unchanged rather than gathered separately -- one struct array stays
%   the single source of truth for what a report is about.
%
%   SCOPE: GRAND AVERAGE ONLY, not per subject. A report is a group-level
%   results document (see generateQuartoReport's own header: "results
%   prose, not a statistics tutorial"), and a source estimate is exactly
%   the kind of thing that does not summarise across dozens of per-
%   subject images -- one grand-average snapshot per bin/method is a
%   RESULT; forty per-subject ones are a browsing tool, which Brain3DView
%   already is. The first ENTRIES(k) with .datasetType == 'grand_average'
%   is used; if none is present (a subjects-only export), this returns an
%   empty ASSETS and the caller's report simply has no Source Estimate
%   section -- not an error, since plenty of legitimate exports have no
%   grand average at all.
%
%   METHODS (default {'mne', 'eloreta', 'sloreta'}, i.e. all three, "per
%   bin/method") selects which of TransTools.InverseSolution's methods to
%   render. Each additional method repeats only the per-bin INVERSE solve,
%   not the leadfield build (TransTools.BuildSourceForwardModel caches
%   that once per channel set) -- so passing a single method here is the
%   deliberate way to make this faster when three images per bin is more
%   than a given report needs.
%
%   GATED ON TRANSTOOLS.ISFIELDTRIPAVAILABLE, NOT ENSUREFIELDTRIP: this
%   runs as a side effect of "Export Measurements", not because the user
%   directly asked for Source-estimate mode, so it must never trigger the
%   consent-gated ~400 MB download. If FieldTrip is not already installed,
%   this returns an empty ASSETS, silently -- the rest of the report is
%   still generated, just without this optional section. A caller that
%   wants to tell the analyst why can check TransTools.isFieldTripAvailable
%   itself before calling this and word its own message accordingly.
%
%   ASSETS is a struct array, one row per (bin, method) pair actually
%   rendered, fields:
%     .BinLabel           EEG.bindesc(b).label
%     .Method             'mne' | 'eloreta' | 'sloreta'
%     .MethodLabel        TransTools.InverseSolution's own INFO.ScaleLabel
%     .ImagePath          "<imagesDir's own leaf folder name>/<file>.png",
%                          i.e. relative to wherever the .qmd itself is
%                          written, NOT an absolute path -- see below
%     .ResidualVariance   INFO.ResidualVariance (a fraction, whole bin)
%     .InstantMs          the rendered latency, see RenderSourceEstimateSnapshot
%   in bin order, then method order within a bin -- the order
%   ReportSections.sourceEstimateSection renders sections in.
%
%   IMAGESDIR is an ABSOLUTE path, a direct subfolder of wherever the
%   caller is about to write the .qmd itself (exactly how CSVFILENAME is
%   already resolved relative to the .qmd's own folder elsewhere in this
%   pipeline -- see generateQuartoReport's own header). PNGs are written
%   there, but ASSETS.ImagePath stores only imagesDir's OWN LEAF FOLDER
%   NAME joined to the file name with a literal forward slash (never
%   fullfile/filesep): this is a Markdown/HTML image src bound for
%   Quarto's self-contained HTML output, not a filesystem call, and a
%   backslash there is Markdown escape syntax, not a path separator, on
%   every platform including Windows. An absolute path baked in instead
%   would also break the moment the report is shared or moved onto a
%   different machine.
%
%   FAILURES ARE PER (BIN, METHOD), NOT WHOLE-EXPORT: one method failing
%   for one bin (a channel set FieldTrip's template cannot resolve, an
%   unwritable images folder) is logged with warning() and skipped, so a
%   single bad combination cannot silently drop every OTHER snapshot the
%   analyst was expecting, nor abort the CSV export this runs alongside.
%
%   See also TRANSTOOLS.RENDERSOURCEESTIMATESNAPSHOT,
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL, TRANSTOOLS.ISFIELDTRIPAVAILABLE,
%   REPORTSECTIONS.SOURCEESTIMATESECTION, GENERATEQUARTOREPORT.
    assets = emptyAssets();

    if nargin < 3 || isempty(methods)
        methods = {'mne', 'eloreta', 'sloreta'};
    end

    if ~isfield(entries, 'datasetType')
        return; % an older entries shape with no grand/subject distinction to find one from
    end
    gaIdx = find(strcmp({entries.datasetType}, 'grand_average'), 1);
    if isempty(gaIdx)
        return;
    end
    eeg = entries(gaIdx).EEG;

    if ~isfield(eeg, 'ScalpChanlocs') || ~isfield(eeg, 'ScalpHasPos') || ~isfield(eeg, 'data')
        return; % not a scalp-positioned averaged dataset -- nothing to source-localize
    end

    if ~TransTools.isFieldTripAvailable()
        return;
    end

    if ~exist(imagesDir, 'dir')
        mkdir(imagesDir);
    end
    [~, imagesFolderName] = fileparts(imagesDir);

    % Same reorder-to-the-forward-model's-own-channel-order contract
    % Brain3DView.ensureSourceReady follows -- see
    % TransTools.BuildSourceForwardModel's own header for why getting this
    % wrong silently scrambles which amplitude gets attributed to which
    % electrode, with no error to catch it.
    scalpLabels = {eeg.ScalpChanlocs.labels};
    % The sheet this dataset already has estimates on, when it has any. Same
    % reasoning as Brain3D: an estimate is a vector over its own vertices,
    % so insisting on the full-resolution sheet would refuse every estimate
    % stored at a coarser one.
    space = SourceCache.Space(eeg, 20484);
    try
        [leadfield, sourcemodel, resolvedLabels, elec, headmodel] = ...
            TransTools.BuildSourceForwardModel(scalpLabels, space);
    catch err
        warning('Alakazam:generateSourceEstimateReportAssets', ...
            ['Could not build the source forward model, so no source-estimate section ' ...
             'will be included: %s'], err.message);
        return;
    end
    [tf, reorder] = ismember(lower(resolvedLabels), lower(scalpLabels));
    if ~all(tf)
        warning('Alakazam:generateSourceEstimateReportAssets', ...
            ['A resolved source-model channel is missing from this dataset''s own positioned ' ...
             'channels, so no source-estimate section will be included.']);
        return;
    end

    isBinned = ndims(eeg.data) == 3 && isfield(eeg, 'bindesc') && ~isempty(eeg.bindesc);
    if isBinned
        binIndices = 1:size(eeg.data, 3);
        binLabels = {eeg.bindesc.label};
    else
        binIndices = 1;
        binLabels = {char(string(eeg.id))};
    end

    % ONE ESTIMATE PER METHOD, HOLDING EVERY BIN, which is the shape a
    % stored estimate has. Solved values are collected as the loops run and
    % attached to the grand-average node afterwards, so the next report
    % reads them instead of inverting again. Whether a method can be stored
    % at all is decided per method: a partial one is never written, because
    % a consumer asking for a bin it lacks would fall back to computing and
    % the half-estimate would be dead weight.
    % Every field collectSolved ever sets is declared here: assigning a
    % struct with an extra field back into a preallocated array is an error
    % in MATLAB, not a widening.
    solved = repmat(struct('values', [], 'info', [], 'filled', [], ...
        'complete', false), 1, numel(methods));

    for b = 1:numel(binIndices)
        scalpData = eeg.data(eeg.ScalpHasPos, :, binIndices(b));
        values = scalpData(reorder, :);

        for m = 1:numel(methods)
            method = methods{m};
            fileName = sprintf('source_bin%d_%s.png', b, method);
            pngPath = fullfile(imagesDir, fileName);

            wanted = SourceCache.SnapshotKey(resolvedLabels, space, method);
            [storedValues, storedInfo] = SourceCache.Lookup( ...
                eeg, binLabels{b}, wanted);
            precomputed = [];
            if ~isempty(storedValues)
                precomputed = struct('values', storedValues, ...
                    'info', infoFromStored(storedInfo, method));
            end

            try
                [info, power] = TransTools.RenderSourceEstimateSnapshot(values, eeg.times, ...
                    leadfield, elec, headmodel, sourcemodel, method, pngPath, precomputed);
            catch err
                warning('Alakazam:generateSourceEstimateReportAssets', ...
                    'Could not render the %s source estimate for bin "%s", skipping it: %s', ...
                    method, binLabels{b}, err.message);
                continue;
            end

            if isempty(storedValues)
                solved(m) = collectSolved(solved(m), power, info, b, numel(binIndices));
            end

            assets(end + 1) = struct( ...
                'BinLabel', binLabels{b}, ...
                'Method', method, ...
                'MethodLabel', info.ScaleLabel, ...
                'ImagePath', sprintf('%s/%s', imagesFolderName, fileName), ...
                'ResidualVariance', info.ResidualVariance, ...
                'InstantMs', info.InstantMs); %#ok<AGROW>
        end
    end

    attachSolved(entries(gaIdx), eeg, solved, methods, resolvedLabels, space, binLabels);
end

% ======================================================================= %

function info = infoFromStored(storedInfo, method)
%INFOFROMSTORED  A stored estimate's descriptive fields, in the shape the
%   renderer's own INFO has, so that the drawing code cannot tell the
%   difference between a fresh solve and a stored one.
    info = struct( ...
        'ScaleLabel',       TransTools.FieldOr(storedInfo, 'scaleLabel', ''), ...
        'ScaleNote',        TransTools.FieldOr(storedInfo, 'scaleNote', ''), ...
        'ResidualVariance', TransTools.FieldOr(storedInfo, 'residualVariance', NaN), ...
        'Method',           method, ...
        'Lambda',           TransTools.FieldOr(storedInfo, 'lambda', NaN));
end

function state = collectSolved(state, power, info, bin, nBins)
%COLLECTSOLVED  Gather one method's bins as they are computed.
    if isempty(state.values)
        state.values = zeros(size(power, 1), size(power, 2), nBins);
        state.info = repmat(struct('residualVariance', NaN, 'scaleLabel', '', ...
            'scaleNote', '', 'lambda', NaN), 1, nBins);
        state.filled = false(1, nBins);
    end
    state.values(:, :, bin) = power;
    state.info(bin) = struct( ...
        'residualVariance', info.ResidualVariance, ...
        'scaleLabel', info.ScaleLabel, ...
        'scaleNote', TransTools.FieldOr(info, 'ScaleNote', ''), ...
        'lambda', TransTools.FieldOr(info, 'Lambda', NaN));
    state.filled(bin) = true;
    state.complete = all(state.filled);
end

function attachSolved(entry, eeg, solved, methods, resolvedLabels, space, binLabels)
%ATTACHSOLVED  Hand freshly computed estimates to the cache.
%   Only complete methods: an estimate missing a bin would be refused for
%   that bin anyway, so storing it would cost disk and buy nothing. The
%   writing itself, and the size limit on it, belong to
%   SourceCache.AttachToNode rather than to a report.
    if ~isfield(entry, 'file') || isempty(entry.file)
        return;
    end
    fresh = [];
    for m = 1:numel(methods)
        if ~solved(m).complete
            continue;
        end
        fresh = SourceCache.Attach(fresh, struct( ...
            'values', solved(m).values, ...
            'times', reshape(double(eeg.times), 1, []), ...
            'bins', {binLabels}, ...
            'vertexLabels', {TransTools.SourceVertexLabels(size(solved(m).values, 1))}, ...
            'info', solved(m).info, ...
            'key', SourceCache.SnapshotKey(resolvedLabels, space, methods{m}), ...
            'dataFingerprint', SourceCache.Fingerprint(eeg)));
    end
    if isempty(fresh)
        return;
    end
    if ~SourceCache.AttachToNode(entry.file, fresh)
        warning('Alakazam:generateSourceEstimateReportAssets', ...
            ['The source estimate was not kept on the node, so the next report will ' ...
             'compute it again. A whole-epoch estimate at the full-resolution sheet is ' ...
             'too large to cache; running the Source Estimate transformation at a ' ...
             'coarser sheet stores one that fits.']);
    end
end

function assets = emptyAssets()
%EMPTYASSETS  A 0x0 struct array with every field ASSETS ever carries, so
%   an early return (no grand average, FieldTrip unavailable, ...) hands
%   the caller something fieldnames()-compatible, not a bare [] that
%   would need its own special case.
    assets = struct('BinLabel', {}, 'Method', {}, 'MethodLabel', {}, ...
        'ImagePath', {}, 'ResidualVariance', {}, 'InstantMs', {});
end
