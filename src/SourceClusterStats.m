function summary = SourceClusterStats(sourceFiles, contrast, opts)
%SOURCECLUSTERSTATS  Group statistics on distributed source estimates:
%   spatio-temporal cluster permutation over the cortical sheet.
%
%   SUMMARY = SourceClusterStats(SOURCEFILES, CONTRAST, OPTS)
%
%   The source-space counterpart of ClusterStats. Each subject's averaged
%   ERP is inverted onto FieldTrip's template cortical sheet, and the
%   resulting per-subject source waveforms are tested across subjects by
%   permutation, with family-wise error controlled over the whole
%   vertex x time volume at once.
%
%   SOURCEFILES is a cell array of paths to Averaged subject .mat datasets,
%   the same candidates ClusterStats and Grand Average already accept.
%   CONTRAST is ClusterStats' own contrast struct ('vsZero', 'paired' or
%   'independent'); the design logic is literally shared, see
%   ClusterStats.buildDesign.
%
%   WHY THIS IS THE RIGHT TEST, rather than the cheaper alternatives:
%
%   PER SUBJECT, NOT ON THE GRAND AVERAGE. The group question is whether an
%   effect holds ACROSS subjects, which is answered by permuting condition
%   labels across subjects. A source estimate of the grand average has one
%   observation and supports no inference at all.
%
%   MASS-UNIVARIATE OVER VERTEX x TIME, corrected by permutation. With
%   ~20000 vertices, per-vertex correction is either uncorrected (useless)
%   or Bonferroni (absurd, given how strongly neighbouring vertices
%   correlate). Cluster/TFCE permutation is the standard answer, and is what
%   MNE-Python's spatio_temporal_cluster_test and FieldTrip's own
%   ft_sourcestatistics both implement.
%
%   TFCE BY DEFAULT (Smith & Nichols 2009), not a cluster-forming threshold.
%   Classic cluster permutation makes the analyst choose clusteralpha, an
%   arbitrary cut that decides which effects survive; TFCE integrates over
%   all thresholds and removes that free parameter. 'cluster' remains
%   available via OPTS.correctm for continuity with ClusterStats and with
%   the older literature.
%
%   OPTS fields, all optional:
%     Method            'mne' (dSPM) or 'sloreta'      (default 'mne')
%     Orientation       'normal' (signed) | 'magnitude' (default 'normal')
%     TimeWindow        [startMs stopMs], [] = whole epoch (default [])
%     ResampleHz        decimate to about this rate, [] = none (default 200)
%     RegParam          inverse regularization         (default 0.05)
%     SourceSpace       template sheet: 20484|8196|5124 (default 20484)
%     Accelerate        use the compiled TFCE kernel     (default true)
%     Workers           parallel workers for permutations (default 1)
%     correctm          'tfce' | 'cluster' | 'no' | ... (default 'tfce')
%     numrandomization  permutations                   (default 1000)
%     alpha, tail, clusteralpha, minnbchan             (as ClusterStats)
%
%   METHOD DELIBERATELY EXCLUDES eLORETA. A vertex-wise test compares
%   vertices with each other, so they must be on comparable footing.
%   dSPM and sLORETA are noise-normalized/standardized and correct the
%   depth bias that otherwise makes superficial vertices systematically
%   larger; eLORETA returns an un-normalized amplitude and does not. It is
%   an excellent localizer of a single source and the wrong input to a
%   group test, so it is refused rather than quietly allowed.
%
%   ORIENTATION 'normal' IS THE DEFAULT FOR A REASON THAT BITES. A magnitude
%   estimate is the L2 norm of three dipole components and is therefore
%   non-negative at every vertex. A one-sample test of a magnitude map
%   against zero is not a test of anything -- every vertex is positive by
%   construction, and a 'vsZero' contrast would "find" the entire cortex.
%   The signed, cortical-normal projection keeps polarity, so the test has
%   a meaningful null. Magnitude is still selectable (a paired difference
%   of two magnitude maps is legitimate), but 'vsZero' with 'magnitude' is
%   refused outright rather than producing a confidently wrong map.
%
%   SIGNS ARE COMPARABLE ACROSS SUBJECTS here, which is what makes the
%   signed test valid at all: every subject is inverted onto the SAME
%   template sheet, so a given vertex's normal points the same way for
%   everyone. An analysis on per-subject anatomy would have to solve that
%   by morphing to a common space first.
%
%   TIME IS DECIMATED BY DEFAULT, to about ResampleHz. The permutation cost
%   is proportional to vertices x samples x randomizations, and a 1000 Hz
%   epoch oversamples an effect whose interesting structure is tens of
%   milliseconds wide. Decimating to 200 Hz costs nothing statistically
%   here and turns an intractable run into a feasible one; set it to [] to
%   keep every sample.
%
%   SUMMARY mirrors ClusterStats' own return value (.clusters, .stat,
%   .contrast, .opts, .nSubjects, .sourceFiles), plus:
%     .sourcemodel   the cortical sheet the test ran on, for rendering
%     .vertexLabels  the synthetic labels .stat's rows correspond to
%     .times         the (possibly decimated) latencies, in ms
%
%   WHAT A SIGNIFICANT CLUSTER DOES AND DOES NOT LICENSE. It supports "an
%   effect exists somewhere in this space-time region". It does NOT support
%   "the effect is in this gyrus between 300 and 500 ms": cluster inference
%   is about a cluster's existence, not its extent, and this is among the
%   most frequently misreported results in the literature. On top of that
%   the forward model is a TEMPLATE -- template head, template electrodes,
%   ~60 channels explaining ~20000 vertices -- so the spatial claim carries
%   far more uncertainty than any p-value here expresses.
%
%   See also CLUSTERSTATS, CLUSTERSTATS.BUILDDESIGN,
%   TRANSTOOLS.SOURCENEIGHBOURS, TRANSTOOLS.INVERSESOLUTION,
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL.
    if numel(sourceFiles) < 2
        throw(MException('Alakazam:SourceClusterStats', ...
            'I''m afraid a cluster test needs at least 2 subjects.'));
    end
    opts = withDefaults(opts);
    validateOptions(opts, contrast);

    TransTools.ensureFieldTrip('Source cluster statistics');

    subjects = cell(1, numel(sourceFiles));
    for i = 1:numel(sourceFiles)
        loaded = load(sourceFiles{i}, 'EEG');
        % Tagged with its own path because nothing inside the dataset
        % identifies the subject: EEG.id is the node name ('Average') and is
        % therefore identical for everyone, and setname is empty. Keying
        % per-subject diagnostics on EEG.id collapsed all 18 subjects into
        % one row before this was noticed.
        loaded.EEG.AlakazamSourceFile = sourceFiles{i};
        subjects{i} = loaded.EEG;
    end

    % ONE forward model for the whole study, and every subject must already
    % be on it. Anything else would invert different subjects onto different
    % source spaces and make their vertices incomparable, which is the one
    % thing a vertex-wise group test cannot survive.
    labels = sharedMontage(subjects);
    [leadfield, sourcemodel, resolvedLabels, elec, headmodel] = ...
        TransTools.BuildSourceForwardModel(labels, opts.SourceSpace);
    normals = TransTools.SurfaceNormals(sourcemodel);
    [neighbours, vertexLabels, adjacency] = TransTools.SourceNeighbours(sourcemodel);

    % A containers.Map is a HANDLE object, so the timelock factory can
    % record what each subject's inverse actually did and have it survive
    % back here. The alternative was returning diagnostics through
    % ClusterStats.buildDesign, which is shared with the scalp test and has
    % no business knowing about inverse solutions.
    diagnostics = containers.Map('KeyType', 'char', 'ValueType', 'any');

    inverse = struct('leadfield', leadfield, 'elec', elec, 'headmodel', headmodel, ...
        'resolvedLabels', {resolvedLabels}, 'normals', normals, ...
        'vertexLabels', {vertexLabels}, 'opts', opts, 'diagnostics', diagnostics);

    % The timelock factory is the ONLY thing that differs from the scalp
    % test; the design, permutation and correction are ClusterStats' own.
    timelockFcn = @(EEG, binLabel) sourceTimelock(EEG, binLabel, inverse);
    [timelocks, design, ivar, uvar, statistic] = ...
        ClusterStats.buildDesign(subjects, contrast, timelockFcn);

    opts.numrandomization = ClusterStats.resolveNumRandomization( ...
        opts.numrandomization, contrast.mode, numel(subjects));

    cfg = struct();
    cfg.method            = 'montecarlo';
    cfg.statistic         = statistic;
    cfg.correctm          = opts.correctm;
    cfg.clusteralpha      = opts.clusteralpha;
    cfg.clusterstatistic  = 'maxsum';
    cfg.minnbchan         = opts.minnbchan;
    cfg.neighbours        = neighbours;
    cfg.tail              = opts.tail;
    cfg.clustertail       = opts.tail;
    cfg.alpha             = opts.alpha;
    cfg.numrandomization  = opts.numrandomization;
    cfg.design            = design;
    cfg.ivar              = ivar;
    if ~isempty(uvar)
        cfg.uvar = uvar;
    end
    % A two-sided test spends alpha on both tails, exactly as ClusterStats
    % does -- kept in step deliberately, since the two report the same way.
    if opts.tail == 0
        cfg.correcttail = 'alpha';
    end

    % THE ACCELERATED ROUTE, taken only when it is exactly equivalent.
    % ClusterStats.tfceStatfun's own header explains why correctm='max'
    % with a pre-enhanced statistic is the same test as correctm='tfce';
    % SourceClusterMexTest asserts it on identical seeds. Anything that
    % does not qualify (a different correction, no compiled kernel) simply
    % runs FieldTrip's own path, slower and identical.
    workers = 1;
    if opts.Accelerate && strcmp(opts.correctm, 'tfce') && TransTools.EnsureTfceMex()
        nTime = numel(timelocks{1}.time);
        cfg.correctm     = 'max';
        cfg.statistic    = @ClusterStats.tfceStatfun;
        cfg.alakazamTfce = struct( ...
            'base',  statistic, ...
            'edges', TransTools.TfceEdges(adjacency, [numel(vertexLabels), nTime]), ...
            'E', 0.5, 'H', 2);
        % Drawn fresh per analysis, not fixed. Chunk seeds are derived
        % from it, so they stay distinct from one another either way; the
        % point of randomising the base is that the serial path does not
        % fix its seed either, and a parallel run that silently became
        % reproducible would behave differently from the serial one for no
        % reason the analyst could see.
        cfg.randomseedBase = randi(2^31 - 1024);
        workers = resolveWorkers(opts.Workers);
    end

    stat = ClusterStats.runMontecarlo(cfg, timelocks, workers);
    stat = restoreStatNaming(stat);

    summary = struct();
    summary.clusters     = ClusterStats.summarizeClusterStat(stat, opts.alpha);
    summary.stat         = stat;
    summary.contrast     = contrast;
    summary.opts         = opts;
    summary.nSubjects    = numel(subjects);
    summary.sourceFiles  = sourceFiles;
    summary.sourcemodel  = sourcemodel;
    summary.vertexLabels = vertexLabels;
    summary.times        = timelocks{1}.time * 1000;   % s -> ms
    summary.provenance   = buildProvenance(opts, labels, resolvedLabels, ...
        sourcemodel, diagnostics, subjects, sourceFiles);
end

% ======================================================================= %
function tl = sourceTimelock(EEG, binLabel, inverse)
%SOURCETIMELOCK  One subject's one bin, inverted onto the cortical sheet
%   and returned as a FieldTrip timelock whose "channels" are vertices.
    bins = {EEG.bindesc.label};
    match = find(strcmp(bins, binLabel), 1);
    if isempty(match)
        throw(MException('Alakazam:SourceClusterStats', '%s', sprintf( ...
            'Bin "%s" was not found on "%s" (bins present: %s).', ...
            binLabel, datasetName(EEG), strjoin(bins, ', '))));
    end

    % Reorder to the forward model's own channel order -- REQUIRED, and
    % silent if wrong: see BuildSourceForwardModel's own header.
    have = {EEG.chanlocs.labels};
    [tf, reorder] = ismember(lower(inverse.resolvedLabels), lower(have));
    if ~all(tf)
        throw(MException('Alakazam:SourceClusterStats', '%s', sprintf( ...
            ['"%s" is missing a channel the shared forward model needs. Every subject in ' ...
             'one test must resolve the same channel set, or their vertices are not ' ...
             'comparable.'], datasetName(EEG))));
    end

    if size(EEG.data, 3) < match
        throw(MException('Alakazam:SourceClusterStats', '%s', sprintf( ...
            ['"%s" describes %d bins but its data holds %d. The dataset is ' ...
             'inconsistent and cannot be inverted.'], ...
            datasetName(EEG), numel(bins), size(EEG.data, 3))));
    end

    % A STORED ESTIMATE IS USED ONLY IF IT PROVES IT MATCHES. The
    % SourceEstimate transformation may have inverted this dataset already,
    % but it did so against ITS OWN channel set, while a group test must use
    % the one set every subject shares. The key carries everything that
    % decides the answer (SourceCache.Key), so agreement can be
    % checked rather than assumed; on any disagreement this recomputes, and
    % the caller reports how many subjects were reused.
    % The window and rate are asked for rather than keyed on: a stored
    % estimate that COVERS them is cropped to them on the way out, since
    % cropping commutes with inverting (see SourceCache.Lookup). One
    % whole-epoch estimate per subject therefore serves every window later
    % analysed, instead of one estimate per window.
    wanted = SourceCache.Key(inverse.resolvedLabels, inverse.opts);
    [storedValues, storedInfo] = SourceCache.Lookup(EEG, binLabel, wanted, ...
        struct('TimeWindow', inverse.opts.TimeWindow, ...
               'ResampleHz', inverse.opts.ResampleHz));
    if ~isempty(storedValues)
        tl = struct('label', {inverse.vertexLabels(:)}, 'time', storedInfo.times / 1000, ...
            'avg', storedValues, 'dimord', 'chan_time');
        inverse.diagnostics(sprintf('%s|%s|reused', subjectKey(EEG), binLabel)) = true;
        return;
    end

    values = double(EEG.data(reorder, :, match));
    times  = reshape(EEG.times, 1, []);

    % Note the '%s' in the throws below and above: MException treats its
    % message as a FORMAT string, so a Windows path inside one is read as
    % escape sequences and the message is truncated at the first of them
    % ("C:\Users..." stops dead at \U). Passing the text as an argument
    % rather than as the format is the fix, and it is why these errors name
    % a subject rather than a path.
    %
    % CHECKED BECAUSE THE FAILURE WOULD BE SILENT. The restriction step
    % (TransTools.RestrictAndDecimate) selects data
    % columns with a logical mask built from times. MATLAB errors on a mask
    % LONGER than the dimension, but a mask that is too SHORT simply selects
    % a prefix, so a times vector out of step with the data would quietly
    % shift every latency in the analysis and report a cluster at the wrong
    % moment. Nothing downstream could detect that, so it is caught here.
    if numel(times) ~= size(values, 2)
        throw(MException('Alakazam:SourceClusterStats', '%s', sprintf( ...
            ['"%s" has %d latencies for %d samples of data. Timing cannot be ' ...
             'trusted on this dataset, so the analysis is stopped rather than ' ...
             'reporting effects at latencies that may be wrong.'], ...
            datasetName(EEG), numel(times), size(values, 2))));
    end

    [values, times] = TransTools.RestrictAndDecimate(values, times, ...
        inverse.opts.TimeWindow, inverse.opts.ResampleHz, 'Alakazam:SourceClusterStats');

    solveOpts = struct('RegParam', inverse.opts.RegParam);
    if strcmpi(inverse.opts.Orientation, 'normal')
        solveOpts.Orientation = 'normal';
        solveOpts.Normals     = inverse.normals;
    end
    [sourcePower, info] = TransTools.InverseSolution(values, inverse.leadfield, ...
        inverse.elec, inverse.headmodel, inverse.opts.Method, solveOpts);

    % Recorded per subject and bin so the report can state how well the
    % forward model actually explained each subject's scalp data. This is
    % the quantity that exposed a reference mismatch during development:
    % a fit of 25% where 96% was available.
    [trials, trialsText] = binTrialCount(EEG, match);
    inverse.diagnostics(sprintf('%s|%s', subjectKey(EEG), binLabel)) = struct( ...
        'residualVariance', scalarOrNan(info.ResidualVariance), ...
        'lambda', scalarOrNan(info.Lambda), ...
        'trials', trials, 'trialsText', trialsText);

    tl = struct();
    tl.label  = inverse.vertexLabels(:);
    tl.time   = times / 1000;    % ms -> s, FieldTrip's own convention
    tl.avg    = sourcePower;
    tl.dimord = 'chan_time';
end

function labels = sharedMontage(subjects)
%SHAREDMONTAGE  The montage every subject is on, refusing anything else.
%
%   THIS USED TO INTERSECT SILENTLY, and that was the wrong kind of helpful.
%   One subject with a rejected electrode quietly removed that channel from
%   the forward model for the whole group: the analysis ran, the report said
%   nothing, and the source space was not the one the analyst thought they
%   had asked for. It was unstable too, since adding a subject could change
%   the model, and so every result, with no setting having changed.
%
%   Which channels to drop is a scientific decision, so it belongs to the
%   analyst rather than to an intersection buried inside a group test.
%   Making it explicit also makes stored source estimates reusable:
%   SourceEstimate keys on its own dataset's channels, so only when those
%   already equal the group's can the estimates on the tree serve the report
%   instead of being recomputed here.
%
%   ONLY CHANNELS THE TEMPLATE CAN POSITION ARE COMPARED, which is what
%   makes the demand a reasonable one. BuildSourceForwardModel keeps exactly
%   the channels that match FieldTrip's 10-5 template and drops the rest, so
%   two subjects differing only in a photodiode, an EOG or an ECG derivation
%   produce the identical forward model. Comparing raw label lists would
%   refuse those, and the first real pair this was run against differed in
%   precisely that way: one subject carried a photodiode channel the other
%   did not, with all 62 scalp electrodes in common. Refusing that would be
%   the sort of strictness that teaches people to work around the check.
    elcFile = TransTools.Template1005File();

    reference = sourceChannels(subjects{1}, elcFile);
    labels = {subjects{1}.chanlocs.labels};

    differs = false(1, numel(subjects));
    for i = 2:numel(subjects)
        differs(i) = ~isequal(sourceChannels(subjects{i}, elcFile), reference);
    end
    if ~any(differs)
        return;
    end

    shared = reference;
    for i = 2:numel(subjects)
        shared = shared(ismember(shared, sourceChannels(subjects{i}, elcFile)));
    end

    idx = find(differs);
    offenders = cell(1, numel(idx));
    for k = 1:numel(idx)
        EEG = subjects{idx(k)};
        name = subjectDisplayName(subjectKey(EEG));
        if isempty(name)
            name = sprintf('subject %d', idx(k));
        end
        theirs = sourceChannels(EEG, elcFile);
        offenders{k} = sprintf('%s (%s)', name, ...
            differenceText(setdiff(reference, theirs, 'stable'), ...
                           setdiff(theirs, reference, 'stable')));
    end

    first = subjectDisplayName(subjectKey(subjects{1}));
    if isempty(first)
        first = 'the first subject';
    end

    % Assembled from lines and joined with newline rather than written with
    % escape sequences: easier to read, and it survives being edited by
    % tools that treat backslashes as their own.
    throw(MException('Alakazam:SourceClusterStats', '%s', strjoin({ ...
        sprintf(['These datasets are not all on the same montage, so there is no ' ...
                 'single source space to compare their vertices in. Counting only ' ...
                 'the electrodes that can be positioned on the template, and ' ...
                 'compared with %s: %s.'], first, strjoin(offenders, '; ')), ...
        '', ...
        sprintf('All %d share these %d electrodes:', numel(subjects), numel(shared)), ...
        strjoin(shared, ' '), ...
        '', ...
        ['Select those with SelectData and Apply to All, then run this again. ' ...
         '(Interpolate is the other way round: it puts a rejected electrode back, ' ...
         'so a subject keeps the full montage.)']}, newline)));
end

function labels = sourceChannels(EEG, elcFile)
%SOURCECHANNELS  The channels of EEG a forward model could actually use:
%   those FieldTrip's 10-5 template can position, sorted and lower-cased so
%   that two montages compare on their content rather than their order.
    [~, hasPos] = TransTools.TemplateScalpLocs(EEG.chanlocs, elcFile);
    labels = sort(lower({EEG.chanlocs(hasPos).labels}));
end

function text = differenceText(missing, extra)
%DIFFERENCETEXT  How one subject's montage differs from the reference.
    parts = {};
    if ~isempty(missing)
        parts{end+1} = sprintf('missing %s', strjoin(missing, ' '));
    end
    if ~isempty(extra)
        parts{end+1} = sprintf('extra %s', strjoin(extra, ' '));
    end
    if isempty(parts)
        parts = {'a different montage'};
    end
    text = strjoin(parts, ', ');
end

function validateOptions(opts, contrast)
%VALIDATEOPTIONS  Refuse the combinations that would produce a confidently
%   wrong answer, rather than letting them run.
    if ~ismember(lower(opts.Method), {'mne', 'sloreta'})
        throw(MException('Alakazam:SourceClusterStats', '%s', sprintf( ...
            ['Method must be "mne" (dSPM) or "sloreta" for a group test, not "%s". A ' ...
             'vertex-wise test compares vertices with one another, so they have to be ' ...
             'on comparable footing: dSPM and sLORETA correct the depth bias that makes ' ...
             'superficial vertices systematically larger, and eLORETA, being an ' ...
             'un-normalized amplitude, does not.'], string(opts.Method))));
    end
    if ~ismember(lower(opts.Orientation), {'normal', 'magnitude'})
        throw(MException('Alakazam:SourceClusterStats', ...
            'Orientation must be "normal" (signed) or "magnitude".'));
    end
    if strcmpi(opts.Orientation, 'magnitude') && strcmp(contrast.mode, 'vsZero')
        throw(MException('Alakazam:SourceClusterStats', ...
            ['A "vs zero" test on magnitude source estimates is not a test of anything: ' ...
             'a magnitude is the L2 norm of three dipole components, so it is positive at ' ...
             'every vertex by construction and the whole cortex would come out ' ...
             'significant. Use Orientation "normal" (signed), or contrast two bins ' ...
             'against each other instead.']));
    end
    if ~isempty(opts.TimeWindow) && numel(opts.TimeWindow) ~= 2
        throw(MException('Alakazam:SourceClusterStats', ...
            'TimeWindow must be [startMs stopMs], or [] for the whole epoch.'));
    end
end

function opts = withDefaults(opts)
    if nargin < 1 || isempty(opts)
        opts = struct();
    end
    defaults = struct( ...
        'Method', 'mne', 'Orientation', 'normal', 'TimeWindow', [], ...
        'ResampleHz', 200, 'RegParam', 0.05, ...
        'SourceSpace', 20484, 'Accelerate', true, 'Workers', 1, ...
        'correctm', 'tfce', 'clusteralpha', 0.05, 'alpha', 0.05, ...
        'numrandomization', 1000, 'tail', 0, 'minnbchan', 0);
    fields = fieldnames(defaults);
    for i = 1:numel(fields)
        if ~isfield(opts, fields{i})
            opts.(fields{i}) = defaults.(fields{i});
        end
    end
end

function stat = restoreStatNaming(stat)
%RESTORESTATNAMING  Present the accelerated result the way FieldTrip's own
%   TFCE path presents it: .stat is the raw statistic, .stattfce the
%   enhanced one. On the accelerated route the enhanced map is what drove
%   the inference and so arrives as .stat, with the raw one carried
%   alongside as .statraw (see ClusterStats.tfceStatfun).
%
%   Renamed here rather than left for callers to branch on, so that
%   nothing downstream -- the cluster summary, the figures' "mean t over
%   cluster vertices" axis, the report -- can tell which route ran.
    if ~isfield(stat, 'statraw')
        return;
    end
    stat.stattfce = stat.stat;
    stat.stat     = stat.statraw;
    stat = rmfield(stat, 'statraw');
end

function n = resolveWorkers(requested)
%RESOLVEWORKERS  How many workers can actually be used.
%   Capped at the physical core count and silently reduced to 1 when the
%   Parallel Computing Toolbox is absent: asking for parallelism the
%   machine cannot provide should cost speed, never results.
    n = double(requested);
    if isempty(n) || ~isscalar(n) || n <= 1
        n = 1;
        return;
    end
    if isempty(ver('parallel')) || ~license('test', 'Distrib_Computing_Toolbox')
        n = 1;
        return;
    end
    n = max(1, min(round(n), feature('numcores')));
end

function name = datasetName(EEG)
%DATASETNAME  Something to call this dataset in an error message.
%   Used only in error paths, which is exactly why it cannot assume a field
%   exists: reading a missing EEG.id while building an error message
%   replaces the real diagnosis with "Unrecognized field name", and the
%   analyst then debugs the wrong problem. Prefers the source file, since
%   EEG.id is the node name and is the same for every subject anyway.
    if isfield(EEG, 'AlakazamSourceFile') && ~isempty(EEG.AlakazamSourceFile)
        % The subject folder, not the whole path: a cache path is a dozen
        % transformation nodes deep and unreadable in a sentence.
        name = subjectDisplayName(EEG.AlakazamSourceFile);
        if ~isempty(name)
            return;
        end
    end
    for candidate = {'setname', 'id'}
        if isfield(EEG, candidate{1}) && ~isempty(EEG.(candidate{1}))
            value = EEG.(candidate{1});
            if ischar(value) || isstring(value)
                name = char(string(value));
                return;
            end
        end
    end
    name = 'this dataset';
end

function key = subjectKey(EEG)
%SUBJECTKEY  A per-subject key that is actually unique.
%   The dataset's own path, since nothing inside it distinguishes subjects.
    if isfield(EEG, 'AlakazamSourceFile') && ~isempty(EEG.AlakazamSourceFile)
        key = char(string(EEG.AlakazamSourceFile));
    else
        key = char(string(EEG.id));
    end
end

function name = subjectDisplayName(file)
%SUBJECTDISPLAYNAME  The subject folder a cached dataset sits under.
%   Cache paths are <root>/<subject>/<Transform><stamp>/.../<Transform><stamp>.mat,
%   so walking up from the file past every folder that looks like a
%   transformation node lands on the subject. Derived by shape rather than
%   by assuming a folder called 'Cache', so a relocated or renamed cache
%   still names subjects correctly.
    name = '';
    if isempty(file)
        return;
    end
    folder = fileparts(char(file));
    previous = '';
    while ~isempty(folder)
        [parent, leaf] = fileparts(folder);
        if isempty(leaf)
            break;
        end
        if isempty(regexp(leaf, '^[A-Za-z]+\d{6,}$', 'once'))
            name = leaf;      % first folder that is not a transformation node
            return;
        end
        previous = leaf;
        folder = parent;
    end
    if isempty(name)
        name = previous;
    end
end

function [n, text] = binTrialCount(EEG, match)
%BINTRIALCOUNT  How many trials went into this subject's bin.
%   Signal-to-noise in a source estimate follows directly from it, and
%   reporting guidelines ask for it, so it is carried rather than left for
%   a reader to go and look up in a different report.
%
%   A COMBINATION BIN HAS NO SINGLE COUNT. DefineBins records .n for an
%   ordinary bin as a number, but for a difference bin it records the
%   constituents as text ('39-161'), which is not something that can be
%   summed. Returning it unchecked put a six-character array where a scalar
%   was expected and failed the whole test with "Non-scalar in Uniform
%   Output", from a line that has nothing to do with the statistics.
%
%   Both forms are kept: N for arithmetic (NaN when there is no number),
%   TEXT for display, so the report can show '39-161' rather than pretending
%   the information is missing.
    n = NaN;
    text = '';
    if ~isfield(EEG.bindesc, 'n')
        return;
    end
    value = EEG.bindesc(match).n;
    if isnumeric(value) && isscalar(value)
        n = double(value);
        text = sprintf('%d', round(n));
    elseif ischar(value) || isstring(value)
        text = char(value);
    end
end

function v = scalarOrNan(x)
%SCALARORNAN  Guarantee something that can go in a numeric array.
%   Defensive for the same reason as binTrialCount above: these values are
%   aggregated across subjects and bins, and one non-scalar among them takes
%   down an analysis that had already finished computing.
    if isnumeric(x) && isscalar(x)
        v = double(x);
    else
        v = NaN;
    end
end

function provenance = buildProvenance(opts, requestedLabels, resolvedLabels, ...
        sourcemodel, diagnostics, subjects, sourceFiles)
%BUILDPROVENANCE  Everything the report needs to describe the analysis that
%   ran, as opposed to the analysis that was requested.
%
%   COLLECTED HERE BECAUSE THIS IS WHERE IT IS KNOWN. The report is handed a
%   summary, not the pipeline, and every value below would otherwise have to
%   be guessed from defaults, which is exactly how a methods section comes
%   to describe something that did not happen. Assembled to answer the
%   COBIDAS MEEG (Pernet et al., 2020) reporting items for source analysis:
%   forward model, inverse and its regularisation, noise model, channel set,
%   and software versions.
    provenance = struct();
    provenance.requestedChannels = numel(requestedLabels);
    % WHAT EACH SUBJECT ACTUALLY BROUGHT. Every subject is now required to
    % be on the same montage (sharedMontage above), so these counts should
    % agree -- and reporting them is how a reader confirms that rather than
    % taking it on trust. They also still differ legitimately in channels
    % the template cannot position, an EOG or a photodiode, which the
    % requirement ignores because they never reach the forward model.
    provenance.subjectChannels = subjectChannelCounts(subjects);
    provenance.limitingSubject = limitingSubjectName(subjects, sourceFiles);
    provenance.channels          = {resolvedLabels};
    provenance.nChannels         = numel(resolvedLabels);
    provenance.reference         = 'average (imposed by the leadfield)';
    provenance.headModel         = 'FieldTrip template BEM (standard_bem)';
    provenance.electrodes        = 'FieldTrip template 10-5 (standard_1005)';
    provenance.coregistration    = 'none (template anatomy, no individual MRI or digitised electrodes)';
    provenance.sourceTemplate    = sprintf('cortex_%d.surf.gii', opts.SourceSpace);
    provenance.nVertices         = size(sourcemodel.pos, 1);
    provenance.adjacency         = 'mesh triangulation (vertices sharing a triangle)';
    provenance.regParam          = opts.RegParam;
    provenance.noiseCovariance   = 'identity, scaled by lambda (not estimated from data)';
    provenance.tfce              = struct('variant', 'exact', 'E', 0.5, 'H', 2);
    provenance.software          = TransTools.SoftwareVersions();
    provenance.subjects          = subjectRows(diagnostics);

    provenance.reusedEstimates = countReused(diagnostics);

    lambdas = collectField(diagnostics, 'lambda');
    provenance.lambda = median(lambdas, 'omitnan');
    rv = collectField(diagnostics, 'residualVariance');
    provenance.residualVariance = rv;
end

function counts = subjectChannelCounts(subjects)
    counts = cellfun(@(s) numel(s.chanlocs), subjects);
end

function name = limitingSubjectName(subjects, sourceFiles)
%LIMITINGSUBJECTNAME  Whoever has the fewest channels, since they set the
%   montage for the whole analysis. Named so the analyst can decide whether
%   that trade is worth it, rather than discovering the channel count and
%   having no way to act on it.
    name = '';
    counts = subjectChannelCounts(subjects);
    if isempty(counts)
        return;
    end
    [~, at] = min(counts);
    if at <= numel(sourceFiles)
        name = subjectDisplayName(sourceFiles{at});
    end
end

function rows = subjectRows(diagnostics)
%SUBJECTROWS  One row per subject: which file, how many trials, how well the
%   forward model fitted. Keyed back from the diagnostics map, whose keys
%   are '<id>|<bin>'.
    rows = struct('id', {}, 'file', {}, 'trials', {}, 'trialsText', {}, ...
        'residualVariance', {});
    % The reuse markers are booleans keyed '<subject>|<bin>|reused', not
    % per-bin diagnostics, so they are skipped rather than counted as bins.
    keys_ = keys(diagnostics);
    keys_ = keys_(~endsWith(keys_, '|reused'));
    ids = cell(1, numel(keys_));
    for i = 1:numel(keys_)
        parts = strsplit(keys_{i}, '|');
        ids{i} = parts{1};
    end
    uniqueIds = unique(ids, 'stable');
    for i = 1:numel(uniqueIds)
        mine = strcmp(ids, uniqueIds{i});
        entries = cellfun(@(k) diagnostics(k), keys_(mine), 'UniformOutput', false);
        trials = cellfun(@(e) e.trials, entries);
        rv     = cellfun(@(e) e.residualVariance, entries);
        texts  = cellfun(@(e) e.trialsText, entries, 'UniformOutput', false);
        % The key IS the file, so the display name comes from it directly
        % rather than from a positional guess into sourceFiles.
        file = uniqueIds{i};
        % Summed when every bin reported a number; otherwise the bins'
        % own descriptions are shown, because a difference bin's '39-161'
        % is information and "not recorded" is not.
        if any(~isnan(trials))
            trialsText = '';
            total = sum(trials, 'omitnan');
        else
            named = texts(~cellfun(@isempty, texts));
            trialsText = strjoin(unique(named, 'stable'), ', ');
            % NaN, not 0: sum() of nothing is zero, and storing zero would
            % state that this subject contributed no trials at all.
            total = NaN;
        end
        rows(end + 1) = struct('id', subjectDisplayName(file), 'file', file, ...
            'trials', total, 'trialsText', trialsText, ...
            'residualVariance', mean(rv, 'omitnan')); %#ok<AGROW>
    end
end

function n = countReused(diagnostics)
%COUNTREUSED  How many subject-by-bin inversions came from a stored estimate.
%   Worth reporting: an analyst who has just run SourceEstimate on every
%   subject and sees zero reuse needs to know the keys did not match, rather
%   than concluding the step did nothing.
    n = 0;
    keys_ = keys(diagnostics);
    for i = 1:numel(keys_)
        if endsWith(keys_{i}, '|reused')
            n = n + 1;
        end
    end
end

function values = collectField(diagnostics, field)
    keys_ = keys(diagnostics);
    values = nan(1, numel(keys_));
    for i = 1:numel(keys_)
        entry = diagnostics(keys_{i});
        if isstruct(entry) && isfield(entry, field)
            values(i) = entry.(field);
        end
    end
end
