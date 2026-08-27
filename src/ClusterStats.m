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
            'I''m afraid a cluster test needs at least 2 subjects.'));
    end
    opts = withDefaults(opts);

    subjects = cell(1, numel(sourceFiles));
    for i = 1:numel(sourceFiles)
        loaded = load(sourceFiles{i}, 'EEG');
        subjects{i} = loaded.EEG;
    end
    subjects = restrictToScalpChannels(subjects);
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
    [elec, chanlocs] = buildElec(subjects{1});
    neighbours = buildNeighbours(elec);
    layout = buildLayout(chanlocs);

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
                'I don''t recognise the contrast mode "%s", I''m afraid.', char(contrast.mode)));
    end

    refChan = size(subjects{1}.data, 1);
    for i = 1:numel(subjects)
        name = displayNameFor(sourceFiles{i}, subjects{i});
        if size(subjects{i}.data, 1) ~= refChan
            throw(MException('Alakazam:ClusterStats', sprintf( ...
                ['"%s" has %d channels, I''m afraid, but the first subject has %d. Every ' ...
                 'subject needs the same channels for a cluster test.'], ...
                name, size(subjects{i}.data, 1), refChan)));
        end
        haveLabels = string({subjects{i}.bindesc.label});
        missing = setdiff(neededBins, haveLabels);
        if ~isempty(missing)
            throw(MException('Alakazam:ClusterStats', sprintf( ...
                'I''m afraid "%s" is missing bin(s) %s needed for this contrast.', ...
                name, strjoin(missing, ', '))));
        end
    end

    if strcmp(contrast.mode, 'independent')
        if numel(contrast.groupOf) ~= numel(subjects)
            throw(MException('Alakazam:ClusterStats', ...
                'contrast.groupOf must have one entry per subject, I''m afraid.'));
        end
    end
end

function subjects = restrictToScalpChannels(subjects)
%RESTRICTTOSCALPCHANNELS  Drop peripheral channels (EOG/ECG/EMG/... --
%   channelTypeFromLabel's own catalogue) from every subject before
%   electrode positions or the FieldTrip design are built from them: a
%   cluster is a spatial extent across scalp neighbours, and a peripheral
%   channel has no scalp position and no neighbours to begin with, so it
%   was never a meaningful part of that extent -- unlike SelectData (a
%   general-purpose, manual step the analyst may or may not have run
%   first), this always applies here, the same way ScalpDistribution/
%   eegChannelMask already exclude peripherals from a scalp-only display
%   automatically rather than requiring it to be done by hand upstream.
%
%   The mask is computed once, from the first subject's own labels, and
%   applied identically to every subject -- validateCompatibility (called
%   right after this) is what actually enforces that every subject shares
%   the same channel set, so there is nothing to reconcile per-subject here.
    labels = {subjects{1}.chanlocs.labels};
    isScalp = cellfun(@(l) isempty(channelTypeFromLabel(l)), labels);
    if all(isScalp)
        return; % nothing to drop
    end
    for i = 1:numel(subjects)
        subjects{i}.chanlocs = subjects{i}.chanlocs(isScalp);
        subjects{i}.data     = subjects{i}.data(isScalp, :, :);
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

function [elec, chanlocs] = buildElec(referenceEEG)
%BUILDELEC  A FieldTrip 'elec' struct (.label, .elecpos, .chanpos, .unit)
%   built from the reference subject's channels, positioned via
%   TransTools.TemplateScalpLocs -- the exact same standard 10-5 template
%   lookup ScalpDistribution/Brain3D/CoherenceTopography/RemoveComponents
%   already use for their own scalp maps. Deliberately NOT
%   TransTools.FillChanlocs: FillChanlocs trusts a dataset's own
%   pre-existing chanlocs.X/Y/Z when every channel already has one (its
%   template lookup only fires for a channel missing a position) -- fine
%   for AutoGEDAI/AutoEyeICA, which only need channels positioned somehow,
%   but if a dataset's own original positions came from a different
%   source/convention than the dipfit template (e.g. the raw import's own
%   electrode file), the resulting layout comes out in a different, wrong
%   orientation from every other scalp map in Alakazam -- confirmed: this
%   is what produced a real, reproducible 45-degree-rotated cluster-report
%   topoplot even after buildLayout's own projection math was verified
%   correct in isolation. TemplateScalpLocs always re-derives fresh
%   positions from the template file itself, by label, so this always
%   agrees with those other views regardless of what the dataset's own
%   chanlocs originally carried. CHANLOCS (the positioned channels
%   themselves) is returned too, for buildLayout's own 2D projection.
    [locs, hasPos] = TransTools.TemplateScalpLocs(referenceEEG.chanlocs, ...
        TransTools.Dipfit1005File('Alakazam:ClusterStats'));

    if ~all(hasPos)
        unpositioned = {locs(~hasPos).labels};
        throw(MException('Alakazam:ClusterStats', sprintf( ...
            ['Channel(s) %s have no standard 10-5 scalp position, I''m afraid, so a channel-' ...
             'adjacency structure cannot be built. Would you rename them to standard 10-5 ' ...
             'labels, or exclude them (SelectData) before running a cluster test?'], ...
            strjoin(unpositioned, ', '))));
    end

    chanlocs = locs;
    elec = struct();
    elec.label   = {locs.labels}';
    elec.elecpos = [[locs.X]', [locs.Y]', [locs.Z]'];
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

function layout = buildLayout(chanlocs)
%BUILDLAYOUT  2D channel positions (for a topographic plot of where a
%   cluster sits), via the exact same readlocs()+pol2cart()+rotation
%   pipeline TransTools.DrawScalpMap already uses to draw every other
%   scalp map in Alakazam (see its own header comment for the full
%   derivation) -- deliberately NOT a hand-derived spherical-to-polar
%   projection from X/Y/Z, and NOT ft_prepare_layout's own projection:
%   both were tried and shown wrong. A naive conversion from X/Y/Z looks
%   plausible (it agrees with this pipeline for a fresh template lookup)
%   but is not guaranteed to, because readlocs()/convertlocs's own
%   recomputation of angle/radius from X/Y/Z does not always match a
%   template file's raw theta (DrawScalpMap's own comment: the
%   standard_1005.elc template's raw .theta for T7/T8 puts them at the
%   front/back midline, not the ears, until routed through this exact
%   readlocs call) -- and ft_prepare_layout's own auto-detected rotation
%   is separately unreliable (confirmed: correct for one channel set in
%   testing, genuinely rotated 45 degrees on a real dataset). Reusing
%   DrawScalpMap's own verified-against-real-topoplot() pipeline avoids
%   re-deriving (and re-risking) this a third time, and guarantees this
%   report's topoplot is always in the same orientation as every other
%   scalp map in Alakazam.
    [~, ~, Th, Rd, indices] = readlocs(chanlocs);
    theta  = deg2rad(Th);
    radius = Rd;
    [a, b] = pol2cart(theta, radius);
    horiz  =  a;   % DrawScalpMap's own 90-degree-clockwise correction --
    vert   = -b;   % see its header comment for why (topoplot's raw output
                    % plots anterior-posterior horizontally, not "nose up").

    allLabels = {chanlocs.labels}';
    layout = struct();
    layout.label   = allLabels(indices);
    layout.pos     = [horiz(:), vert(:)];
    layout.outline = headOutline();
end

function outline = headOutline()
%HEADOUTLINE  Head/nose/ear contour segments (each an Nx2 matrix) in the
%   same (x,y) convention as buildLayout's electrode positions (0.5 =
%   head edge), purely for drawing a recognisable outline behind the
%   electrode scatter.
    headR = 0.5;
    th = linspace(0, 2 * pi, 100)';
    headCircle = [headR * cos(th), headR * sin(th)];

    nose = [-0.08, headR; 0, headR + 0.08; 0.08, headR];

    earTh = linspace(-pi / 2, pi / 2, 20)';
    rightEar = [headR + 0.05 * cos(earTh), 0.15 * sin(earTh)];
    leftEar  = [-(headR + 0.05 * cos(earTh)), 0.15 * sin(earTh)];

    outline = {headCircle, nose, leftEar, rightEar};
end

function name = displayNameFor(file, subject)
%DISPLAYNAMEFOR  How a subject is named in the compatibility errors above.
%   Same problem and same solution as GrandAverage's own copy: every
%   subject's average is called "Average" plus a timestamp, so naming a
%   mismatch by the cache file alone identifies nothing. The recording it
%   came from is carried on the dataset as EEG.setname, so both are
%   reported: "12_N400_preprocessed / Average25225213". Degrades to the
%   bare file stem when setname is absent or blank.
    [~, stem, ~] = fileparts(file);
    name = stem;
    if nargin < 2 || ~isstruct(subject)
        return;
    end
    root = '';
    for candidate = {'setname', 'filename'}
        field = candidate{1};
        if isfield(subject, field) && (ischar(subject.(field)) || isstring(subject.(field)))
            root = strtrim(char(string(subject.(field))));
            if strcmp(field, 'filename') && ~isempty(root)
                [~, root, ~] = fileparts(root);
            end
            if ~isempty(root)
                break;
            end
        end
    end
    if ~isempty(root)
        name = sprintf('%s / %s', root, stem);
    end
end
