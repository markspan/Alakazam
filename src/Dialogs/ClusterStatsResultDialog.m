function ClusterStatsResultDialog(summary, contrastLabel)
%CLUSTERSTATSRESULTDIALOG  Shows a ClusterStats() result: a narrated
%   summary plus a sortable table of every cluster found (significant or
%   not -- a near-miss is still worth seeing), for an immediate on-screen
%   glance right after the test runs.
%
%   The full, plotted write-up (topographic + time-course plots per
%   cluster) is the companion Quarto report Alakazam.onClusterStats
%   generates and persists into the Reports tree straight after this
%   dialog is shown -- this one is just the quick look while that
%   renders, not a competing report format, so it has no save/export of
%   its own.
    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'Cluster Statistics Result', 'Position', [120 120 640 480], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Cluster Statistics Result', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [3 1], 'RowHeight', {'fit', '1x', 44}, 'Padding', [10 10 10 10]);

    narrative = narrativeText(summary, contrastLabel);
    narrLabel = uitextarea(outer, 'Value', narrative, 'Editable', 'off', 'FontSize', 12);
    narrLabel.Layout.Row = 1;

    if isempty(summary.clusters)
        data = cell(0, 6);
    else
        c = summary.clusters;
        data = [ ...
            {c.sign}', num2cell([c.pValue]'), num2cell([c.significant]'), ...
            arrayfun(@(x) strjoin(x.channels, ', '), c, 'UniformOutput', false)', ...
            arrayfun(@(x) sprintf('%.0f to %.0f', x.timeRangeMs(1), x.timeRangeMs(2)), c, 'UniformOutput', false)', ...
            num2cell([c.nPoints]')];
    end
    tbl = uitable(outer, 'Data', data, ...
        'ColumnName', {'Sign', 'p-value', 'Significant', 'Channels', 'Time (ms)', 'Extent (points)'}, ...
        'ColumnWidth', {70, 70, 80, '1x', 110, 100});
    tbl.Layout.Row = 2;

    note = uilabel(outer, 'Text', ...
        'A full report with topographic and time-course plots for each cluster is being generated...', ...
        'FontColor', [0.4 0.4 0.4], 'FontSize', 11);
    note.Layout.Row = 3;
end

function lines = narrativeText(summary, contrastLabel)
%NARRATIVETEXT  Cellstr, one line per row -- uitextarea's Value needs a
%   cellstr, not a plain char with embedded newlines.
    nSig = sum([summary.clusters.significant]);
    if ischar(summary.opts.numrandomization) || isstring(summary.opts.numrandomization)
        % ClusterStats.resolveNumRandomization upgraded this to FieldTrip's
        % own 'all' (exhaustive enumeration) -- %d on that string would
        % otherwise print each character's own code point.
        permText = 'all (exhaustive)';
    else
        permText = sprintf('%d', summary.opts.numrandomization);
    end
    lines = {contrastLabel, '', sprintf('%d subject(s), %s permutation(s), %s correction.', ...
        summary.nSubjects, permText, upper(summary.opts.correctm)), '', ...
        sprintf('%d cluster(s) found, %d significant at p < %.3g.', ...
        numel(summary.clusters), nSig, summary.opts.alpha)};
    if nSig > 0
        best = summary.clusters(1); % summarizeClusterStat already sorts by p ascending
        lines = [lines, {'', sprintf(['The strongest effect is a %s cluster spanning %s, %.0f to %.0f ms ' ...
            '(p = %.4g).'], best.sign, strjoin(best.channels, ', '), ...
            best.timeRangeMs(1), best.timeRangeMs(2), best.pValue)}];
    end
end
