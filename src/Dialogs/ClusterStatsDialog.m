function spec = ClusterStatsDialog(candidateFiles, candidateLabels, candidateBins, candidateGroups, kind, epochMs)
%CLUSTERSTATSDIALOG  Modal dialog: which subjects, which contrast, and what
%   permutation-test options to use for a cluster-based permutation test
%   (see ClusterStats.m).
%
%   SPEC = CLUSTERSTATSDIALOG(CANDIDATEFILES, CANDIDATELABELS, CANDIDATEBINS,
%   CANDIDATEGROUPS) -- CANDIDATEFILES/CANDIDATELABELS are the same shape as
%   GrandAverageDialog's own (paths and display labels, ERP-kind subjects
%   only -- see Alakazam.findGrandAverageCandidates). CANDIDATEBINS is the
%   union of every candidate's own bin labels (so the bin picker can be
%   built without this dialog doing any file I/O itself, matching
%   GrandAverageDialog's own no-I/O convention -- a subject actually
%   missing a chosen bin is caught later, with a clear error, by
%   ClusterStats' own validateCompatibility). CANDIDATEGROUPS is each
%   candidate's own between-subjects group (WorkSpace.groupFor, '' if
%   none) -- the "between groups" contrast is only offered once at least 2
%   distinct non-blank groups are present, the same "assign groups first"
%   convention generateQuartoReport already uses.
%
%   Returns a struct with .sourceFiles, .contrast (see ClusterStats.m's own
%   header for its shape) and .opts, or [] if cancelled.
%   KIND is 'scalp' (default) or 'source'. In 'source' mode the same
%   contrast picker and subject list are reused -- a cluster test's DESIGN
%   does not change with what a row of the data represents -- and four
%   source-specific settings are added to the options block: the inverse
%   method, the orientation, the time window, and the rate the data is
%   decimated to for the test. See SourceClusterStats for what each means
%   and why its default is what it is.
%
%   EPOCHMS is [startMs stopMs], the latency range every candidate shares
%   (Alakazam.candidateEpochMs), and becomes the default time window in
%   'source' mode. Passed in rather than read here, keeping this dialog's
%   no-file-I/O convention. Defaulting to the epoch matters: an earlier
%   version defaulted to a fixed 0 to 500 ms, which on a -200 to 800 ms
%   epoch quietly excluded the baseline and the last 300 ms from the
%   analysis, and the only visible trace was a time axis in the report that
%   did not match the data.
%
%   One dialog rather than two, because the alternative is a near-copy that
%   agrees about contrasts and subject selection right up until somebody
%   changes one of them.
    spec = [];
    if nargin < 5 || isempty(kind)
        kind = 'scalp';
    end
    isSource = strcmpi(kind, 'source');
    if nargin < 6 || numel(epochMs) ~= 2
        % No epoch to go on: fall back to a window that at least sits inside
        % almost any ERP epoch, rather than to nothing.
        epochMs = [0 500];
    end
    hasGroups = numel(setdiff(unique(candidateGroups), {''})) >= 2;

    modeNames = {'One bin against zero, within subjects', ...
                 'Two bins, within subjects (paired)', ...
                 'One bin, between two groups'};
    modeIds = {'vsZero', 'paired', 'independent'};
    if ~hasGroups
        modeNames(3) = [];
        modeIds(3)   = [];
    end
    modeExplain = containers.Map( ...
        {'vsZero', 'paired', 'independent'}, { ...
        ['Tests one bin (typically a DefineBins combination/difference bin, e.g. ' ...
         'an "N400" = unrelated - related contrast) against zero, across the whole ' ...
         'scalp and epoch at once -- is this effect reliably present anywhere?'], ...
        ['Tests two ordinary bins against each other, within subjects, across the ' ...
         'whole scalp and epoch -- e.g. does "unrelated" differ from "related" ' ...
         'anywhere, without picking a channel/window in advance?'], ...
        ['Tests one bin between the two groups assigned via Grouping... -- does this ' ...
         'measure differ between the groups, anywhere across the scalp and epoch?']});

    [accentColor, bgColor] = dialogChromeColors();
    if isSource
        titleText = 'Source Cluster Statistics';
        figHeight = 820;
    else
        titleText = 'Cluster Statistics';
        figHeight = 640;
    end
    fig = uifigure('Name', titleText, 'Position', [100 100 560 figHeight], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', ['  ' titleText], 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [8 1], ...
        'RowHeight', {'fit', 'fit', 'fit', 'fit', '1x', 'fit', 'fit', 44}, 'Padding', [10 10 10 10]);

    % Row 1: contrast mode.
    modeRow = uigridlayout(outer, [1 2], 'ColumnWidth', {90, '1x'}, 'Padding', [8 8 8 0]);
    modeRow.Layout.Row = 1;
    uilabel(modeRow, 'Text', 'Contrast:');
    modeDrop = uidropdown(modeRow, 'Items', modeNames, 'ItemsData', modeIds, 'Value', modeIds{1}, ...
        'ValueChangedFcn', @(src, ~) refreshForMode(src.Value));

    explainLabel = uilabel(outer, 'Text', modeExplain(modeIds{1}), 'WordWrap', 'on', ...
        'FontColor', [0.4 0.4 0.4], 'FontSize', 11);
    explainLabel.Layout.Row = 2;

    % Row 3: bin picker(s) -- rebuilt per mode by refreshForMode.
    binRow = uigridlayout(outer, [2 2], 'ColumnWidth', {90, '1x'}, 'Padding', [8 8 8 0]);
    binRow.Layout.Row = 3;
    binALabel = uilabel(binRow, 'Text', 'Bin:');
    binADrop  = uidropdown(binRow, 'Items', candidateBins);
    binBLabel = uilabel(binRow, 'Text', 'Bin B:');
    binBDrop  = uidropdown(binRow, 'Items', candidateBins);

    % Row 4: options (cluster-forming alpha / permutations / correction).
    optRow = uigridlayout(outer, [3 + 6 * isSource, 2], 'ColumnWidth', {170, '1x'}, 'Padding', [8 8 8 0], 'RowSpacing', 2);
    optRow.Layout.Row = 4;
    uilabel(optRow, 'Text', 'Cluster-forming p <', ...
        'Tooltip', 'How extreme a single point must be to join a candidate cluster. Ignored for TFCE.');
    alphaField = uieditfield(optRow, 'numeric', 'Value', 0.05, 'Limits', [0.001 0.5]);
    uilabel(optRow, 'Text', 'Permutations', ...
        'Tooltip', 'More = a more precise p-value, at roughly linear runtime cost. 1000 is a common default.');
    permField = uieditfield(optRow, 'numeric', 'Value', 1000, 'Limits', [50 100000], 'RoundFractionalValues', 'on');
    uilabel(optRow, 'Text', 'Correction method', ...
        'Tooltip', ['Cluster: the classic Maris & Oostenveld recipe. TFCE: Threshold-Free Cluster ' ...
            'Enhancement, avoids having to pick a cluster-forming threshold at all -- recommended.']);
    correctmDrop = uidropdown(optRow, 'Items', {'TFCE (recommended)', 'Cluster (classic)'}, ...
        'ItemsData', {'tfce', 'cluster'}, 'Value', 'tfce');

    % Source-only settings. eLORETA is deliberately absent: it is not
    % depth-normalized, so its vertices are not on comparable footing in a
    % vertex-wise test, and SourceClusterStats refuses it outright.
    % Gathered into one struct rather than five separately-declared handles:
    % they exist only in source mode, and a conditionally-assigned variable
    % read from a nested function is exactly the shape MATLAB's own analyzer
    % cannot follow. One variable, always defined, no ambiguity.
    sourceCtl = struct();
    if isSource
        uilabel(optRow, 'Text', 'Inverse method', ...
            'Tooltip', ['dSPM and sLORETA are both depth-corrected, so vertices can be ' ...
                'compared with one another. eLORETA is not, and is not offered here.']);
        sourceCtl.method = uidropdown(optRow, 'Items', {'dSPM (recommended)', 'sLORETA'}, ...
            'ItemsData', {'mne', 'sloreta'}, 'Value', 'mne');

        uilabel(optRow, 'Text', 'Orientation', ...
            'Tooltip', ['Signed keeps the polarity of the effect and is required for a ' ...
                '"vs zero" test: a magnitude estimate is positive at every vertex, so ' ...
                'testing it against zero would flag the whole cortex.']);
        sourceCtl.orientation = uidropdown(optRow, 'Items', {'Signed (cortical normal)', 'Magnitude'}, ...
            'ItemsData', {'normal', 'magnitude'}, 'Value', 'normal');

        uilabel(optRow, 'Text', 'Time window (ms)', ...
            'Tooltip', ['Defaults to the whole epoch, so nothing is excluded unless you ' ...
                'exclude it. Narrowing to the latencies of interest is the single biggest ' ...
                'lever on runtime, and on sensitivity: every extra sample is another few ' ...
                'thousand comparisons the correction has to pay for.']);
        windowRow = uigridlayout(optRow, [1 3], 'ColumnWidth', {'1x', 16, '1x'}, ...
            'Padding', [0 0 0 0], 'ColumnSpacing', 4);
        sourceCtl.windowStart = uieditfield(windowRow, 'numeric', 'Value', epochMs(1));
        uilabel(windowRow, 'Text', 'to', 'HorizontalAlignment', 'center');
        sourceCtl.windowStop = uieditfield(windowRow, 'numeric', 'Value', epochMs(2));

        uilabel(optRow, 'Text', 'Test at (Hz)', ...
            'Tooltip', ['The data is decimated to about this rate before testing. A 1000 Hz ' ...
                'epoch oversamples an effect tens of milliseconds wide, and the permutation ' ...
                'cost is proportional to the sample count.']);
        sourceCtl.resample = uieditfield(optRow, 'numeric', 'Value', 200, 'Limits', [10 1000]);

        uilabel(optRow, 'Text', 'Source space', ...
            'Tooltip', ['How many vertices the template cortical sheet has. A finer sheet ' ...
                'does not buy resolution: with a few dozen electrodes the forward model ' ...
                'cannot distinguish that many independent sources. It does cost, steeply.']);
        sourceCtl.space = uidropdown(optRow, ...
            'Items', {'20484 vertices (full)', '8196 vertices', '5124 vertices (fastest)'}, ...
            'ItemsData', {20484, 8196, 5124}, 'Value', 20484);

        uilabel(optRow, 'Text', 'Parallel workers', ...
            'Tooltip', ['Splits the permutations across cores. The result is the same test: ' ...
                'each worker draws its own permutations and the null distributions are ' ...
                'pooled. Needs the Parallel Computing Toolbox; without it this is ignored.']);
        sourceCtl.workers = uieditfield(optRow, 'numeric', 'Value', 1, ...
            'Limits', [1 64], 'RoundFractionalValues', 'on');

        sourceCtl.space.ValueChangedFcn   = @(~, ~) refreshEstimate();
        sourceCtl.workers.ValueChangedFcn = @(~, ~) refreshEstimate();

        % A source test costs minutes, not seconds, and the three settings
        % just above are what decide how many. Showing the consequence while
        % they are still adjustable is the point: the alternative is finding
        % out after committing to the run.
        sourceCtl.estimate = uilabel(outer, 'Text', '', 'WordWrap', 'on', ...
            'FontColor', [0.4 0.4 0.4], 'FontSize', 11);
        sourceCtl.estimate.Layout.Row = 7;

        sourceCtl.windowStart.ValueChangedFcn = @(~, ~) refreshEstimate();
        sourceCtl.windowStop.ValueChangedFcn  = @(~, ~) refreshEstimate();
        sourceCtl.resample.ValueChangedFcn    = @(~, ~) refreshEstimate();
        permField.ValueChangedFcn             = @(~, ~) refreshEstimate();
    end

    % Row 5: subject picker.
    listRow = uigridlayout(outer, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [8 8 8 0]);
    listRow.Layout.Row = 5;
    uilabel(listRow, 'Text', 'Include these subjects:');
    subjectList = uilistbox(listRow, 'Items', candidateLabels, 'ItemsData', candidateFiles, ...
        'Value', candidateFiles, 'Multiselect', 'on', ...
        'ValueChangedFcn', @(~, ~) refreshEstimate());

    warnLabel = uilabel(outer, 'Text', '', 'WordWrap', 'on', 'FontColor', [0.75 0.35 0.1], 'FontSize', 11);
    warnLabel.Layout.Row = 6;
    if ~hasGroups
        warnLabel.Text = ['"One bin, between two groups" is hidden: fewer than two groups are assigned ' ...
            '(Home tab, Design group, Grouping...).'];
    end

    % Row 7: OK / Cancel.
    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 100}, 'Padding', [8 6 8 6]);
    buttons.Layout.Row = 8;
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    cancelBtn.Layout.Column = 2;
    okBtn = uibutton(buttons, 'Text', 'Run Test', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 3;
    fig.CloseRequestFcn = @(~,~) onCancel();

    refreshForMode(modeIds{1});
    refreshEstimate();
    uiwait(fig);

    function refreshForMode(mode)
        explainLabel.Text = modeExplain(mode);
        switch mode
            case 'vsZero'
                binALabel.Text = 'Bin:';
                binALabel.Visible = 'on'; binADrop.Visible = 'on';
                binBLabel.Visible = 'off'; binBDrop.Visible = 'off';
            case 'paired'
                binALabel.Text = 'Bin A:';
                binALabel.Visible = 'on'; binADrop.Visible = 'on';
                binBLabel.Visible = 'on'; binBDrop.Visible = 'on';
            case 'independent'
                binALabel.Text = 'Bin:';
                binALabel.Visible = 'on'; binADrop.Visible = 'on';
                binBLabel.Visible = 'off'; binBDrop.Visible = 'off';
        end
    end

    function refreshEstimate()
    %REFRESHESTIMATE  Roughly how long the source test will take, live.
    %
    %   FITTED TO CLEAN END-TO-END MEASUREMENTS on 18 real subjects, one
    %   run at a time. That qualifier is the important one: an earlier set
    %   of constants came from timing runs that overlapped each other on
    %   the same cores, and was wrong by up to a factor of two in both
    %   directions. Every number below comes from a run with nothing else
    %   competing for the machine.
    %
    %   Two costs. A fixed one, the forward model and one inverse per
    %   subject, proportional to subjects and to vertices; and a
    %   per-permutation one, proportional to permutations and samples and
    %   growing a little faster than linearly in vertices (measured
    %   exponent 1.25, from the 20484 and 5124 sheets in one round).
    %
    %       fixed = 3.4 s per subject at 20484 vertices
    %       perm  = 0.735 s per permutation at 20484 vertices, 41 samples
    %       the compiled kernel divides the permutation term by 2.66
    %
    %   The model reproduces six of seven measured configurations within
    %   6%% and the seventh within 17%%, across 50 to 1000 permutations,
    %   21 to 41 samples, both sheets, accelerated and not.
    %
    %   PARALLEL WORKERS ARE MODELLED PESSIMISTICALLY, because measurement
    %   says they deserve it: 8 workers returned about 2.4x on the
    %   permutation term, not 8x, and cost about 25 s in broadcast on top.
    %   At 100 permutations that made the run SLOWER than serial; at 1000
    %   it saved a third. The estimate shows the crossover rather than
    %   hiding it, which is the whole reason it is on screen.
    %
    %   Still reported as "about N minutes" and captioned as a rough
    %   guide: it exists to answer "is this a coffee or an afternoon".
        if ~isSource
            return;
        end
        nSubjects = numel(subjectList.Value);
        spanMs    = max(0, sourceCtl.windowStop.Value - sourceCtl.windowStart.Value);
        nSamples  = max(1, round(spanMs / 1000 * sourceCtl.resample.Value) + 1);
        nPerms    = round(permField.Value);
        vertices  = sourceCtl.space.Value;
        workers   = round(sourceCtl.workers.Value);

        meshRatio = vertices / 20484;
        fixed = 3.4 * nSubjects * meshRatio;
        perm  = nPerms * 0.735 * meshRatio ^ 1.25 * (nSamples / 41);
        if ~TransTools.EnsureTfceMex()
            perm = perm * 2.66;
        end

        note = '';
        if workers > 1 && ~isempty(ver('parallel'))
            perm = perm / (0.30 * workers);
            fixed = fixed + 25;
            note = sprintf(', %d workers', workers);
        elseif workers > 1
            note = ', workers ignored (no Parallel Computing Toolbox)';
        end

        sourceCtl.estimate.Text = sprintf( ...
            ['Rough estimate: %s (%d subjects, %d vertices, %d samples, ' ...
             '%d permutations%s). Measured on one machine, so treat it as an ' ...
             'order of magnitude.'], ...
            durationText(fixed + perm), nSubjects, vertices, nSamples, nPerms, note);
    end

    function onOK()
        sources = subjectList.Value;
        if numel(sources) < 2
            uialert(fig, 'I''m afraid at least two subjects need to be picked before this test can run.', 'Not enough subjects');
            return;
        end
        mode = modeDrop.Value;
        switch mode
            case 'vsZero'
                contrast = struct('mode', 'vsZero', 'bin', binADrop.Value);
            case 'paired'
                if strcmp(binADrop.Value, binBDrop.Value)
                    uialert(fig, 'Bin A and Bin B would need to be different from one another for a paired comparison.', 'Same bin picked twice');
                    return;
                end
                contrast = struct('mode', 'paired', 'binA', binADrop.Value, 'binB', binBDrop.Value);
            case 'independent'
                mask = ismember(candidateFiles, sources);
                groupOf = candidateGroups(mask);
                if numel(setdiff(unique(groupOf), {''})) < 2
                    uialert(fig, ['I''m afraid the selected subjects don''t span at least two groups. ' ...
                        'Would you pick subjects from both groups, or choose a different contrast instead?'], ...
                        'Not enough groups selected');
                    return;
                end
                contrast = struct('mode', 'independent', 'bin', binADrop.Value, 'groupOf', {groupOf});
        end
        opts = struct('correctm', correctmDrop.Value, 'clusteralpha', alphaField.Value, ...
            'alpha', 0.05, 'numrandomization', round(permField.Value), 'tail', 0, 'minnbchan', 0);

        if isSource
            if sourceCtl.windowStop.Value <= sourceCtl.windowStart.Value
                uialert(fig, 'The time window would need to end after it starts.', 'Time window');
                return;
            end
            opts.Method      = sourceCtl.method.Value;
            opts.Orientation = sourceCtl.orientation.Value;
            opts.TimeWindow  = [sourceCtl.windowStart.Value, sourceCtl.windowStop.Value];
            opts.ResampleHz  = sourceCtl.resample.Value;
            opts.SourceSpace = sourceCtl.space.Value;
            opts.Workers     = sourceCtl.workers.Value;

            % Caught here as well as inside SourceClusterStats, so the analyst
            % is told while the dialog is still open and can change it, rather
            % than after dismissing it. A magnitude estimate is positive at
            % every vertex, so a "vs zero" test on one would flag essentially
            % the whole cortex.
            if strcmp(mode, 'vsZero') && strcmp(opts.Orientation, 'magnitude')
                uialert(fig, ['A "vs zero" test on magnitude source estimates is not a ' ...
                    'test of anything: a magnitude is positive at every vertex, so the ' ...
                    'whole cortex would come out significant. Choose the signed ' ...
                    'orientation, or contrast two bins against each other instead.'], ...
                    'Invalid combination');
                return;
            end
        end

        spec = struct('sourceFiles', {sources}, 'contrast', contrast, 'opts', opts);
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end
end

function text = durationText(seconds)
%DURATIONTEXT  A runtime estimate at the precision it deserves.
%   Rounded coarsely and on purpose: the underlying constants are measured
%   on one machine, so "about 5 minutes" is a claim the estimate can
%   support and "4 m 41 s" is not.
    if seconds < 90
        text = 'under 2 minutes';
    elseif seconds < 3600
        text = sprintf('about %d minutes', max(2, round(seconds / 60)));
    else
        text = sprintf('about %.1f hours', seconds / 3600);
    end
end
