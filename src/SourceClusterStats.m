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
        subjects{i} = loaded.EEG;
    end

    % ONE forward model for the whole study, from the channel set the
    % subjects share. Anything else would invert different subjects onto
    % different source spaces and make their vertices incomparable, which is
    % the one thing a vertex-wise group test cannot survive.
    labels = commonChannels(subjects, sourceFiles);
    [leadfield, sourcemodel, resolvedLabels, elec, headmodel] = ...
        TransTools.BuildSourceForwardModel(labels, opts.SourceSpace);
    normals = TransTools.SurfaceNormals(sourcemodel);
    [neighbours, vertexLabels, adjacency] = TransTools.SourceNeighbours(sourcemodel);

    inverse = struct('leadfield', leadfield, 'elec', elec, 'headmodel', headmodel, ...
        'resolvedLabels', {resolvedLabels}, 'normals', normals, ...
        'vertexLabels', {vertexLabels}, 'opts', opts);

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
end

% ======================================================================= %
function tl = sourceTimelock(EEG, binLabel, inverse)
%SOURCETIMELOCK  One subject's one bin, inverted onto the cortical sheet
%   and returned as a FieldTrip timelock whose "channels" are vertices.
    bins = {EEG.bindesc.label};
    match = find(strcmp(bins, binLabel), 1);
    if isempty(match)
        throw(MException('Alakazam:SourceClusterStats', sprintf( ...
            'Bin "%s" was not found on "%s" (bins present: %s).', ...
            binLabel, string(EEG.id), strjoin(bins, ', '))));
    end

    % Reorder to the forward model's own channel order -- REQUIRED, and
    % silent if wrong: see BuildSourceForwardModel's own header.
    have = {EEG.chanlocs.labels};
    [tf, reorder] = ismember(lower(inverse.resolvedLabels), lower(have));
    if ~all(tf)
        throw(MException('Alakazam:SourceClusterStats', sprintf( ...
            ['"%s" is missing a channel the shared forward model needs. Every subject in ' ...
             'one test must resolve the same channel set, or their vertices are not ' ...
             'comparable.'], string(EEG.id))));
    end

    values = double(EEG.data(reorder, :, match));
    times  = reshape(EEG.times, 1, []);

    [values, times] = restrictTime(values, times, inverse.opts.TimeWindow);
    [values, times] = decimateTime(values, times, inverse.opts.ResampleHz);

    solveOpts = struct('RegParam', inverse.opts.RegParam);
    if strcmpi(inverse.opts.Orientation, 'normal')
        solveOpts.Orientation = 'normal';
        solveOpts.Normals     = inverse.normals;
    end
    sourcePower = TransTools.InverseSolution(values, inverse.leadfield, ...
        inverse.elec, inverse.headmodel, inverse.opts.Method, solveOpts);

    tl = struct();
    tl.label  = inverse.vertexLabels(:);
    tl.time   = times / 1000;    % ms -> s, FieldTrip's own convention
    tl.avg    = sourcePower;
    tl.dimord = 'chan_time';
end

function [values, times] = restrictTime(values, times, window)
%RESTRICTTIME  Keep only the requested latency range.
%   Applied BEFORE the inverse rather than after, so the solve itself is
%   cheaper -- and, for eLORETA/sLORETA, so the data covariance those
%   methods take is computed over the window actually under test rather
%   than over an epoch mostly outside it.
    if isempty(window)
        return;
    end
    keep = times >= window(1) & times <= window(2);
    if ~any(keep)
        throw(MException('Alakazam:SourceClusterStats', sprintf( ...
            'The time window [%g %g] ms contains no samples of this epoch (%g to %g ms).', ...
            window(1), window(2), times(1), times(end))));
    end
    values = values(:, keep);
    times  = times(keep);
end

function [values, times] = decimateTime(values, times, targetHz)
%DECIMATETIME  Take every Nth sample, to approximately TARGETHZ.
%   Plain subsampling, not a filtered resample: these are already
%   baseline-corrected, low-pass-filtered averages, so the frequencies a
%   decimation filter would remove are not present to alias. Using
%   downsample here would also shift the latencies, and a cluster's
%   reported timing has to stay the recording's own.
    if isempty(targetHz) || numel(times) < 2
        return;
    end
    currentHz = 1000 / median(diff(times));
    step = max(1, floor(currentHz / targetHz));
    if step <= 1
        return;
    end
    values = values(:, 1:step:end);
    times  = times(1:step:end);
end

function labels = commonChannels(subjects, sourceFiles)
%COMMONCHANNELS  The channels every subject has, in the first subject's own
%   order. A vertex-wise group test needs one shared source space, so the
%   forward model is built from the intersection rather than per subject.
    labels = {subjects{1}.chanlocs.labels};
    for i = 2:numel(subjects)
        labels = labels(ismember(lower(labels), lower({subjects{i}.chanlocs.labels})));
    end
    if numel(labels) < 8
        throw(MException('Alakazam:SourceClusterStats', sprintf( ...
            ['These %d datasets share only %d channel(s), which is far too few to " ' ...
             'estimate sources from. Do they come from the same montage?'], ...
            numel(sourceFiles), numel(labels))));
    end
end

function validateOptions(opts, contrast)
%VALIDATEOPTIONS  Refuse the combinations that would produce a confidently
%   wrong answer, rather than letting them run.
    if ~ismember(lower(opts.Method), {'mne', 'sloreta'})
        throw(MException('Alakazam:SourceClusterStats', sprintf( ...
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
