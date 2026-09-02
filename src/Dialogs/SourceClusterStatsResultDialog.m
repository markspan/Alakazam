function SourceClusterStatsResultDialog(summary, assets, contrastLabel)
%SOURCECLUSTERSTATSRESULTDIALOG  Shows a SourceClusterStats() result: a
%   narrated summary plus a table of every cluster found, for an immediate
%   on-screen glance while the companion Quarto report renders.
%
%   A SEPARATE DIALOG FROM ClusterStatsResultDialog, not a shared one with
%   a flag. That one identifies a cluster by listing its channels, which is
%   exactly right for 30-odd electrodes and unreadable for the 10000-odd
%   vertices a cortical cluster routinely spans -- it would print a
%   ten-thousand-item sentence. Here the same column carries the anatomical
%   description instead, which is the only form in which a source cluster's
%   location can be read at a glance. The two dialogs share a shape and a
%   purpose but not a single line that would have had to branch.
%
%   ASSETS is generateSourceClusterAssets' own return value, used only for
%   the location text; clusters it did not render (the non-significant
%   ones, by default) are still listed, without one. Nothing is recomputed
%   here: an atlas lookup per cluster would repeat work already done.
%
%   Like its scalp counterpart this is the quick look, not a competing
%   report format, so it has no save or export of its own.
    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'Source Cluster Statistics Result', ...
        'Position', [120 120 760 500], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Source Cluster Statistics Result', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    outer = uigridlayout(root, [3 1], 'RowHeight', {'fit', '1x', 44}, 'Padding', [10 10 10 10]);

    narrLabel = uitextarea(outer, 'Value', narrativeText(summary, assets, contrastLabel), ...
        'Editable', 'off', 'FontSize', 12);
    narrLabel.Layout.Row = 1;

    tbl = uitable(outer, 'Data', tableData(summary, assets), ...
        'ColumnName', {'Sign', 'p-value', 'Significant', 'Vertices', 'Time (ms)', 'Location'}, ...
        'ColumnWidth', {70, 70, 80, 70, 100, '1x'});
    tbl.Layout.Row = 2;

    note = uilabel(outer, 'Text', ...
        ['A full report with a cortical map and a time course per cluster is being generated. ' ...
         'A cluster means an effect exists, not where it is -- see the report''s own note.'], ...
        'FontColor', [0.4 0.4 0.4], 'FontSize', 11, 'WordWrap', 'on');
    note.Layout.Row = 3;
end

% ======================================================================= %
function data = tableData(summary, assets)
    if isempty(summary.clusters)
        data = cell(0, 6);
        return;
    end
    c = summary.clusters;
    data = cell(numel(c), 6);
    for k = 1:numel(c)
        data(k, :) = {c(k).sign, c(k).pValue, c(k).significant, ...
            numel(c(k).channels), ...
            sprintf('%.0f to %.0f', c(k).timeRangeMs(1), c(k).timeRangeMs(2)), ...
            locationOf(assets, k)};
    end
end

function text = locationOf(assets, clusterIndex)
%LOCATIONOF  The rendered description for this cluster, if it was rendered.
%   Matched on SourceIndex rather than on position: generateSourceClusterAssets
%   renders only the significant clusters by default, so its rows and
%   summary.clusters' rows do not line up.
    text = '(not rendered)';
    if isempty(assets)
        return;
    end
    hit = find([assets.SourceIndex] == clusterIndex, 1);
    if ~isempty(hit)
        text = assets(hit).Description.Text;
    end
end

function lines = narrativeText(summary, assets, contrastLabel)
%NARRATIVETEXT  Cellstr, one line per row -- uitextarea's Value needs a
%   cellstr, not a plain char with embedded newlines.
    nSig = sum([summary.clusters.significant]);
    if ischar(summary.opts.numrandomization) || isstring(summary.opts.numrandomization)
        permText = 'all (exhaustive)';
    else
        permText = sprintf('%d', summary.opts.numrandomization);
    end
    lines = {contrastLabel, '', ...
        sprintf('%d subject(s), %s inverse, %s permutation(s), %s correction.', ...
            summary.nSubjects, TransTools.SourceMethodName(summary.opts.Method), ...
            permText, upper(summary.opts.correctm)), ...
        sprintf('%d vertices x %d samples, %.0f to %.0f ms.', ...
            numel(summary.vertexLabels), numel(summary.times), ...
            summary.times(1), summary.times(end)), ...
        '', ...
        sprintf('%d cluster(s) found, %d significant at p < %.3g.', ...
            numel(summary.clusters), nSig, summary.opts.alpha)};
    if nSig > 0
        best = summary.clusters(1); % already sorted by p ascending
        lines = [lines, {'', sprintf('The strongest effect is a %s cluster, %.0f to %.0f ms (p = %.4g).', ...
            best.sign, best.timeRangeMs(1), best.timeRangeMs(2), best.pValue)}];
        located = locationOf(assets, 1);
        if ~strcmp(located, '(not rendered)')
            lines = [lines, {located}];
        end
    end
end
