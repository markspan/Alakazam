function summary = ClusterStats(sourceFiles, contrast, opts)
%CLUSTERSTATS  Cluster-based permutation testing across the whole scalp and
%   epoch at once (Maris & Oostenveld, 2007), wrapping FieldTrip's own
%   ft_prepare_neighbours/ft_timelockstatistics rather than reimplementing
%   the permutation/clustering machinery -- see the project's own scoping
%   note on this: EEGLAB has no native equivalent (its own
%   statcondfieldtrip.m already delegates to FieldTrip for exactly this),
%   so FieldTrip is the actual engine here, not an alternative to one.
%
%   SUMMARY = CLUSTERSTATS(SOURCEFILES, CONTRAST, OPTS)
%
%   SOURCEFILES is a cell array of paths to Averaged subject .mat datasets
%   (each holding a variable "EEG"), the same "ERP" candidates
%   Alakazam.findGrandAverageCandidates already lists for Grand Average --
%   deliberately the SUBJECT-LEVEL AVERAGE, not single-trial data: the
%   group-level question this answers ("does this effect exist across
%   subjects, and where/when") is tested by permuting condition/group
%   labels ACROSS SUBJECTS, which needs one already-averaged waveform per
%   subject per condition, not their individual trials (a single-subject,
%   trial-level cluster test is a different, narrower question and not
%   what this function does).
%
%   CONTRAST selects what to test, one of:
%     .mode = 'vsZero',      .bin              -- one bin (typically a
%         DefineBins combination/difference bin, e.g. "N400" = bin4-bin3)
%         tested against zero, within subjects. Paired against a
%         same-shaped all-zero condition (see ClusterStats.zeroTimelock),
%         FieldTrip's own idiom for a one-sample cluster test.
%     .mode = 'paired',      .binA, .binB      -- two ordinary bins
%         contrasted within subjects (dependent-samples).
%     .mode = 'independent', .bin, .groupOf    -- one bin contrasted
%         BETWEEN two subject groups. GROUPOF is a cellstr/string array,
%         the same length and order as SOURCEFILES, naming each subject's
%         own group (e.g. via WorkSpace.groupFor) -- exactly two distinct
%         groups are required (see ClusterStats.independentDesign).
%
%   Three-or-more-bin/-group designs (an omnibus F-type cluster test, or a
%   bin x group interaction) are not implemented: FieldTrip supports them
%   in principle (cfg.statistic = 'depsamplesFunivariate' etc.), but they
%   need a materially different design-matrix shape and interpretation,
%   deliberately left for a later pass rather than half-supported here.
%
%   OPTS (all optional, sensible defaults applied):
%     .correctm          'cluster' (default, the classic Maris & Oostenveld
%                        fixed-threshold recipe) or 'tfce' (Threshold-Free
%                        Cluster Enhancement -- avoids having to pick a
%                        cluster-forming threshold at all; supported by
%                        the pinned FieldTrip build this ships against).
%     .clusteralpha      cluster-FORMING threshold (default 0.05). Ignored
%                        for 'tfce'.
%     .alpha             cluster/TFCE-level significance (default 0.05).
%     .numrandomization  permutations (default 1000; more = a more precise
%                        p-value estimate, at roughly linear runtime cost).
%     .tail              -1/0/1 (default 0, two-tailed).
%     .minnbchan         minimum significant neighbours for a channel to
%                        join a cluster (default 0, FieldTrip's own
%                        default; raise to 1-2 to suppress single-channel
%                        noise clusters).
%
%   SUMMARY is a struct: .clusters (see ClusterStats.summarizeClusterStat),
%   .stat (FieldTrip's own raw return struct, kept for any later custom
%   plotting), .layout (2D channel positions + head outline, see
%   buildLayout -- for a topographic plot of where a cluster sits),
%   .contrast (echoed back), .nSubjects, .sourceFiles.
    if numel(sourceFiles) < 2
        throw(MException('Alakazam:ClusterStats', ...
            'A cluster test needs at least 2 subjects.'));
    end
    opts = withDefaults(opts);

    subjects = cell(1, numel(sourceFiles));
    for i = 1:numel(sourceFiles)
        loaded = load(sourceFiles{i}, 'EEG');
        subjects{i} = loaded.EEG;
    end
    validateCompatibility(subjects, sourceFiles, contrast);

    [timelocks, design, ivar, uvar, statistic] = buildDesign(subjects, contrast);
    [tlSubjects, tlConditions] = timelockLabels(subjects, contrast);
    % Upgrade to an exhaustive 'all' rather than a merely-close-to-it random
    % sample when the requested count would already trigger FieldTrip's own
    % "close to the maximum number of unique permutations" warning -- see
    % resolveNumRandomization's own header for exactly which designs this
    % applies to and why. summary.opts below reflects whatever this
    % resolves to, so the report narrates what actually ran, not what was
    % originally requested.
    opts.numrandomization = ClusterStats.resolveNumRandomization( ...
        opts.numrandomization, contrast.mode, numel(subjects));

    TransTools.ensureFieldTrip('Cluster Statistics');
    elec = buildElec(subjects{1});
    neighbours = buildNeighbours(elec);
    layout = buildLayout(elec);

    cfg = struct();
    cfg.method           = 'montecarlo';
    cfg.statistic        = statistic;
    cfg.correctm         = opts.correctm;
    cfg.clusteralpha     = opts.clusteralpha;
    cfg.clusterstatistic = 'maxsum';
    cfg.minnbchan        = opts.minnbchan;
    cfg.neighbours       = neighbours;
    cfg.tail             = opts.tail;
    cfg.clustertail      = opts.tail;
    % A two-tailed cluster test needs correcttail = 'alpha' (halves alpha
    % correctly for both tails together) -- a well-known FieldTrip pitfall
    % that silently doubles the effective false-positive rate if left at
    % its own plain default; set explicitly here rather than leaving every
    % caller to rediscover it.
    if opts.tail == 0
        cfg.correcttail = 'alpha';
    end
    cfg.alpha             = opts.alpha;
    cfg.numrandomization  = opts.numrandomization;
    cfg.design            = design;
    cfg.ivar              = ivar;
    if ~isempty(uvar)
        cfg.uvar = uvar;
    end

    stat = ft_timelockstatistics(cfg, timelocks{:});

    summary = struct();
    summary.clusters   = ClusterStats.summarizeClusterStat(stat, opts.alpha);
    summary.stat        = stat;
    summary.layout       = layout;
    summary.contrast     = contrast;
    summary.opts        = opts;
    summary.nSubjects   = numel(subjects);
    summary.sourceFiles = sourceFiles;
    % The exact per-subject/per-condition timelocks fed to
    % ft_timelockstatistics above, kept for the companion report's own
    % time-course plot (see exportClusterStatsCSVs.m) -- TIMELOCKS(i)'s own
    % subject/condition is TLSUBJECTS{i}/TLCONDITIONS{i}, same order.
    summary.timelocks          = timelocks;
    summary.timelockSubjects   = tlSubjects;
    summary.timelockConditions = tlConditions;
end

function [tlSubjects, tlConditions] = timelockLabels(subjects, contrast)
%TIMELOCKLABELS  Subject id + condition label for each entry of the flat
%   TIMELOCKS list buildDesign returns -- same order buildDesign itself
%   builds it in (condition A's N subjects, then condition B's N, for
%   'vsZero'/'paired'; one entry per subject for 'independent').
    subjIds = cellfun(@(s) char(string(s.id)), subjects, 'UniformOutput', false);
    n = numel(subjects);
    switch contrast.mode
        case 'vsZero'
            tlSubjects   = [subjIds, subjIds];
            tlConditions = [repmat({contrast.bin}, 1, n), repmat({'zero'}, 1, n)];
        case 'paired'
            tlSubjects   = [subjIds, subjIds];
            tlConditions = [repmat({contrast.binA}, 1, n), repmat({contrast.binB}, 1, n)];
        case 'independent'
            tlSubjects   = subjIds;
            tlConditions = repmat({contrast.bin}, 1, n);
    end
end

% ----------------------------------------------------------------------- %
function opts = withDefaults(opts)
    if nargin < 1 || isempty(opts)
        opts = struct();
    end
    defaults = struct('correctm', 'cluster', 'clusteralpha', 0.05, 'alpha', 0.05, ...
        'numrandomization', 1000, 'tail', 0, 'minnbchan', 0);
    fields = fieldnames(defaults);
    for i = 1:numel(fields)
        if ~isfield(opts, fields{i}) || isempty(opts.(fields{i}))
            opts.(fields{i}) = defaults.(fields{i});
        end
    end
end

function validateCompatibility(subjects, sourceFiles, contrast)
%VALIDATECOMPATIBILITY  Every subject needs the same channel count (so
%   they share one neighbour structure) and the bin(s) this CONTRAST
%   actually needs -- mirrors GrandAverage's own validateCompatibility,
%   scoped to just what this contrast reads rather than every bin.
    switch contrast.mode
        case 'vsZero';      neededBins = string(contrast.bin);
        case 'paired';      neededBins = [string(contrast.binA), string(contrast.binB)];
        case 'independent'; neededBins = string(contrast.bin);
        otherwise
            throw(MException('Alakazam:ClusterStats', ...
                'Unknown contrast mode "%s".', char(contrast.mode)));
    end

    refChan = size(subjects{1}.data, 1);
    for i = 1:numel(subjects)
        name = displayNameFor(sourceFiles{i});
        if size(subjects{i}.data, 1) ~= refChan
            throw(MException('Alakazam:ClusterStats', sprintf( ...
                ['"%s" has %d channels, but the first subject has %d. Every subject ' ...
                 'needs the same channels for a cluster test.'], ...
                name, size(subjects{i}.data, 1), refChan)));
        end
        haveLabels = string({subjects{i}.bindesc.label});
        missing = setdiff(neededBins, haveLabels);
        if ~isempty(missing)
            throw(MException('Alakazam:ClusterStats', sprintf( ...
                '"%s" is missing bin(s) %s needed for this contrast.', ...
                name, strjoin(missing, ', '))));
        end
    end

    if strcmp(contrast.mode, 'independent')
        if numel(contrast.groupOf) ~= numel(subjects)
            throw(MException('Alakazam:ClusterStats', ...
                'contrast.groupOf must have one entry per subject.'));
        end
    end
end

function [timelocks, design, ivar, uvar, statistic] = buildDesign(subjects, contrast)
    nSubjects = numel(subjects);
    switch contrast.mode
        case 'vsZero'
            condA = cell(1, nSubjects);
            condB = cell(1, nSubjects);
            for i = 1:nSubjects
                condA{i} = ClusterStats.toFieldTripTimelock(subjects{i}, contrast.bin);
                condB{i} = ClusterStats.zeroTimelock(condA{i});
            end
            timelocks = [condA, condB];
            [design, ivar, uvar] = ClusterStats.pairedDesign(nSubjects);
            statistic = 'depsamplesT';

        case 'paired'
            condA = cell(1, nSubjects);
            condB = cell(1, nSubjects);
            for i = 1:nSubjects
                condA{i} = ClusterStats.toFieldTripTimelock(subjects{i}, contrast.binA);
                condB{i} = ClusterStats.toFieldTripTimelock(subjects{i}, contrast.binB);
            end
            timelocks = [condA, condB];
            [design, ivar, uvar] = ClusterStats.pairedDesign(nSubjects);
            statistic = 'depsamplesT';

        case 'independent'
            timelocks = cell(1, nSubjects);
            for i = 1:nSubjects
                timelocks{i} = ClusterStats.toFieldTripTimelock(subjects{i}, contrast.bin);
            end
            [design, ivar] = ClusterStats.independentDesign(contrast.groupOf);
            uvar = [];
            statistic = 'indepsamplesT';
    end
end

function elec = buildElec(referenceEEG)
%BUILDELEC  A FieldTrip 'elec' struct (.label, .elecpos, .chanpos, .unit)
%   built from the reference subject's own channel positions, auto-filled
%   from the standard 10-5 template (same mechanism AutoEyeICA already
%   uses -- see TransTools.FillChanlocs/Dipfit1005File). Shared by
%   buildNeighbours (channel adjacency) and buildLayout (2D plotting
%   positions) so position-resolution only happens once per test.
%
%   FillChanlocs is fed a minimal, freshly-built stub struct (.chanlocs +
%   .nbchan only), not REFERENCEEEG itself: an Averaged dataset has already
%   been reshaped away from a full EEGLAB-native struct (Average.m collapses
%   .data from channels x samples x TRIALS to channels x samples x BINS,
%   among other changes) and cannot be assumed to still carry every field
%   pop_chanedit's own 'lookup' path touches (confirmed the hard way:
%   it reads EEG.nbchan directly and throws "Unrecognized field name" on
%   an Averaged struct that predates any nbchan handling) -- AutoGEDAI/
%   AutoEyeICA never hit this because they run on a still EEGLAB-native
%   continuous dataset, immediately after import.
    stub = struct('chanlocs', referenceEEG.chanlocs, 'nbchan', numel(referenceEEG.chanlocs));
    EEG = TransTools.FillChanlocs(stub, 'Alakazam:ClusterStats', ...
        TransTools.Dipfit1005File('Alakazam:ClusterStats'));

    positioned = ~arrayfun(@(c) isempty(c.X) || isnan(c.X), EEG.chanlocs);
    if nnz(positioned) < numel(EEG.chanlocs)
        unpositioned = {EEG.chanlocs(~positioned).labels};
        throw(MException('Alakazam:ClusterStats', sprintf( ...
            ['Channel(s) %s have no standard 10-5 scalp position, so a channel-' ...
             'adjacency structure cannot be built. Rename them to standard 10-5 labels, ' ...
             'or exclude them (SelectData) before running a cluster test.'], ...
            strjoin(unpositioned, ', '))));
    end

    elec = struct();
    elec.label   = {EEG.chanlocs.labels}';
    elec.elecpos = [[EEG.chanlocs.X]', [EEG.chanlocs.Y]', [EEG.chanlocs.Z]'];
    elec.chanpos = elec.elecpos;
    elec.unit    = 'mm';
end

function neighbours = buildNeighbours(elec)
%BUILDNEIGHBOURS  ft_prepare_neighbours' own adjacency structure. ELEC's
%   positions are passed to FieldTrip AS-IS, without remapping EEGLAB's
%   axis convention onto FieldTrip's own: 'triangulation' neighbour-finding
%   only uses inter-electrode geometry (which channels are near which), a
%   rotation-invariant question, so the two toolkits' differing axis
%   conventions do not matter here the way they would for a head-model
%   alignment (e.g. Brain3D's source-estimate mode, which does care).
    ncfg = struct();
    ncfg.method = 'triangulation';
    ncfg.elec   = elec;
    ncfg.feedback = 'no';
    neighbours = ft_prepare_neighbours(ncfg);
end

function layout = buildLayout(elec)
%BUILDLAYOUT  2D channel positions (for a topographic plot of where a
%   cluster sits) via ft_prepare_layout's own projection of the 3-D
%   electrode positions -- the same, well-tested projection FieldTrip's
%   own topoplot functions use, rather than reimplementing an azimuthal
%   projection by hand. LAYOUT.label/.pos are trimmed down to real
%   channels only: ft_prepare_layout always appends a couple of
%   plotting-only placeholder rows (COMNT, SCALE) with no real channel
%   behind them, which a caller joining this against real channel data
%   would otherwise silently carry through as unmatched/NaN rows.
%   .outline (head/nose/ears contour line segments, each an Nx2 matrix) is
%   kept as FieldTrip returns it, purely for drawing a recognisable head
%   outline behind the electrode scatter.
    lcfg = struct();
    lcfg.elec = elec;
    lcfg.feedback = 'no';
    raw = ft_prepare_layout(lcfg);

    real = ~ismember(raw.label, {'COMNT', 'SCALE'});
    layout = struct();
    layout.label   = raw.label(real);
    layout.pos     = raw.pos(real, :);
    layout.outline = raw.outline;
end

function name = displayNameFor(file)
    [~, name, ~] = fileparts(file);
end
