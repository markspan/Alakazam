function spec = ClusterStatsDialog(candidateFiles, candidateLabels, candidateBins, candidateGroups)
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
    spec = [];
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
    fig = uifigure('Name', 'Cluster Statistics', 'Position', [100 100 560 640], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Cluster Statistics', 'FontSize', 14, 'FontWeight', 'bold', ...
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
    optRow = uigridlayout(outer, [3 2], 'ColumnWidth', {170, '1x'}, 'Padding', [8 8 8 0], 'RowSpacing', 2);
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

    % Row 5: subject picker.
    listRow = uigridlayout(outer, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [8 8 8 0]);
    listRow.Layout.Row = 5;
    uilabel(listRow, 'Text', 'Include these subjects:');
    subjectList = uilistbox(listRow, 'Items', candidateLabels, 'ItemsData', candidateFiles, ...
        'Value', candidateFiles, 'Multiselect', 'on');

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
        spec = struct('sourceFiles', {sources}, 'contrast', contrast, 'opts', opts);
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end
end
