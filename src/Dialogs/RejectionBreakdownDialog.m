function fig = RejectionBreakdownDialog(report, nodeName, parentFig)
%REJECTIONBREAKDOWNDIALOG  Which detector rejected what, for one ArtefactDetect node.
%
%   FIG = REJECTIONBREAKDOWNDIALOG(REPORT, NODENAME, PARENTFIG) shows REPORT,
%   the per-detector record ArtefactDetect writes as it runs
%   (EEG.etc.alz.artefactDetectors), as a table: one row per detector with
%   the epochs it would have rejected on its own, the epochs only it caught
%   and the channel-epochs it flagged, and a last row with the epochs any
%   detector rejected. NODENAME names the node in the summary line;
%   PARENTFIG, optional, is the window it is centred on. Returns the figure,
%   which stays open until closed (it asks nothing).
%
%   A TABLE, NOT A MESSAGE. This used to be a uialert holding a
%   sprintf-padded block, whose columns only line up in a fixed-width font
%   while the alert draws in a proportional one, and which the manual's
%   screenshot tool could not capture at all (exportapp leaves an alert out).
%
%   The note under the table says that the per-detector counts overlap,
%   because they do not add up to the total and a reader who assumed they
%   did would move the wrong threshold. "Only this one" is the column that
%   answers what switching a detector off would cost.
%
%   Read-only and styled like DesignSummaryDialog, its sibling.
%
%   See also ARTEFACTDETECT, ALAKAZAM/ONREJECTIONBREAKDOWN, DESIGNSUMMARYDIALOG.
    accentColor = [0.290 0.498 0.788];   % AlakazamRibbon.html's .alz-tab-home (#4a7fc9)
    bgColor     = [0.9608 0.9608 0.9608];
    rowHeight   = 25;   % a uitable row as drawn, with its borders

    nDetectors = numel(report.methods);
    tableHeight = 32 + rowHeight * (nDetectors + 1);   % header, then every row with no scrollbar
    position = [420 300 600, 40 + 12 + 44 + 12 + tableHeight + 12 + 64 + 46];
    if nargin >= 3 && ~isempty(parentFig) && isvalid(parentFig)
        parentPos = parentFig.Position;
        position(1) = parentPos(1) + (parentPos(3) - position(3)) / 2;
        position(2) = parentPos(2) + (parentPos(4) - position(4)) / 2;
    end

    fig = uifigure('Name', 'Rejection breakdown', 'Position', fitOnScreen(position), ...
        'Color', bgColor);
    outer = uigridlayout(fig, [3, 1], 'RowHeight', {40, '1x', 46}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);

    header = uilabel(outer, 'Text', '  Rejection breakdown', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    header.Layout.Row = 1;

    body = uigridlayout(outer, [3, 1], 'RowHeight', {'fit', tableHeight, 'fit'}, ...
        'Padding', [16 12 16 8], 'RowSpacing', 12);
    body.Layout.Row = 2;

    summary = uilabel(body, 'Text', summaryText(report, nodeName), 'WordWrap', 'on');
    summary.Layout.Row = 1;

    t = uitable(body, 'Data', breakdownRows(report), ...
        'ColumnName', {'Detector', 'Epochs', 'Only this one', 'Channel-epochs'}, ...
        'ColumnWidth', {'1x', 80, 110, 120}, 'RowName', {}, ...
        'ColumnEditable', false(1, 4), 'Tag', 'breakdownTable');
    t.Layout.Row = 2;
    try
        addStyle(t, uistyle('FontWeight', 'bold'), 'row', nDetectors + 1);
    catch
        % uistyle is unavailable in some configurations; the total is still
        % the labelled last row, so this is presentation, not content.
    end

    note = uilabel(body, 'WordWrap', 'on', 'FontColor', [0.35 0.42 0.49], 'Text', ...
        ['"Epochs" is what each detector would have rejected on its own, so the ' ...
         'figures overlap and do not add up to the total: one blink usually trips ' ...
         'several detectors at once. "Only this one" is the epochs no other detector ' ...
         'caught, which is what switching that detector off would cost.']);
    note.Layout.Row = 3;

    buttonRow = uigridlayout(outer, [1, 2], 'ColumnWidth', {'1x', 90}, ...
        'Padding', [16 6 16 10]);
    buttonRow.Layout.Row = 3;
    closeBtn = uibutton(buttonRow, 'Text', 'Close', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) delete(fig));
    closeBtn.Layout.Column = 2;
end

% ----------------------------------------------------------------------- %
function text = summaryText(report, nodeName)
%SUMMARYTEXT  The node, the scope and the total, above the table.
    if isempty(report.methods)
        text = sprintf(['"%s" had no detectors ticked, so nothing was tested and ' ...
            'nothing was rejected: all %d epoch(s) passed through untouched.'], ...
            nodeName, report.nTrials);
        return;
    end
    share = 100 * report.totalEpochs / max(report.nTrials, 1);
    text = sprintf(['"%s": %d of %d epoch(s) rejected (%.0f%%), %d channel(s) ' ...
        'tested, scope %s.'], nodeName, report.totalEpochs, report.nTrials, share, ...
        report.channelsTested, report.scope);
end

function rows = breakdownRows(report)
%BREAKDOWNROWS  One row per detector, then the total over all of them.
    n = numel(report.methods);
    rows = cell(n + 1, 4);
    for m = 1:n
        rows(m, :) = {report.methods{m}, report.epochs(m), report.onlyThis(m), ...
            report.channelEpochs(m)};
    end
    rows(n + 1, :) = {'Any detector', report.totalEpochs, '', ''};
end
