function onRejectionBreakdown(this)
%ONREJECTIONBREAKDOWN  Context-menu action: show which detector rejected what.
%
%   An ArtefactDetect node knows how many trials it threw away, and the
%   view already shows which ones. What it could not say, until the
%   breakdown was recorded, is WHICH detector did it -- and with several
%   detectors ticked that is the question worth asking, because it is the one
%   that tells you which threshold to move. This reads
%   EEG.etc.alz.artefactDetectors, written by ArtefactDetect as the detection
%   ran, so nothing is recomputed and the numbers cannot disagree with the
%   node's own data.
%
%   Only reachable for a node that carries the field (see
%   WorkSpaceTree.optsFor, which greys the item out otherwise), but
%   re-checked here: a node cached before the breakdown existed reaches this
%   with no field at all, and gets a plain explanation rather than an error.
%
%   See also ARTEFACTDETECT, ALAKAZAM/ONCONTEXTMENUACTION,
%   ALAKAZAM/ONRECALCULATENODE.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node)
        uialert(this.MainFigure, 'Please select a node in the tree first.', ...
            'Nothing selected', 'Icon', 'warning');
        return;
    end

    % node.UserData is the node's own cache file; loadNodeEEG reports a
    % missing or unreadable one itself, the same way Recalculate does.
    EEG = this.loadNodeEEG(node.UserData, 'show the rejection breakdown for this dataset');
    if isempty(EEG)
        return;
    end
    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) || ~isfield(EEG.etc, 'alz') ...
            || ~isstruct(EEG.etc.alz) || ~isfield(EEG.etc.alz, 'artefactDetectors')
        uialert(this.MainFigure, ...
            ['This node has no per-detector record. ArtefactDetect writes one as ' ...
             'it runs, so a node computed before that existed does not carry it -- ' ...
             'Recalculate the node and the breakdown will be there.'], ...
            'Rejection breakdown', 'Icon', 'info');
        return;
    end

    report = EEG.etc.alz.artefactDetectors;
    uialert(this.MainFigure, breakdownText(report, char(string(node.Name))), ...
        'Rejection breakdown', 'Icon', 'info');
end

% ======================================================================= %
function text = breakdownText(report, nodeName)
%BREAKDOWNTEXT  The report as a fixed-width block for a uialert.
%
%   Says out loud that the per-detector figures overlap, because they do not
%   sum to the total and a reader who assumed they did would draw the wrong
%   conclusion about a threshold. "Only this one" is the column that answers
%   "what would I lose by switching this detector off".
    if isempty(report.methods)
        text = sprintf(['"%s" had no detectors ticked, so nothing was tested and ' ...
            'nothing was rejected: all %d epoch(s) passed through untouched.'], ...
            nodeName, report.nTrials);
        return;
    end

    lines = {sprintf('"%s", scope: %s', nodeName, report.scope), ...
             sprintf('%d of %d epoch(s) rejected, %d channel(s) tested.', ...
                report.totalEpochs, report.nTrials, report.channelsTested), ...
             '', ...
             sprintf('%-28s %8s %10s %12s', 'detector', 'epochs', 'only this', 'chan-epochs')};
    for m = 1:numel(report.methods)
        lines{end + 1} = sprintf('%-28s %8d %10d %12d', ...   %#ok<AGROW>
            truncate(report.methods{m}, 28), report.epochs(m), ...
            report.onlyThis(m), report.channelEpochs(m));
    end
    lines{end + 1} = '';
    lines{end + 1} = sprintf('%-28s %8d', 'any detector', report.totalEpochs);
    lines{end + 1} = '';
    lines{end + 1} = ['"epochs" is what each detector would have rejected on its own, so ' ...
        'the figures OVERLAP and do not add up to the total: one blink usually trips ' ...
        'several detectors at once. "only this" is the epochs nothing else caught, ' ...
        'which is what you would lose by switching that detector off.'];
    text = strjoin(lines, newline);
end

function s = truncate(s, n)
    s = char(string(s));
    if numel(s) > n
        s = [s(1:n - 1) '.'];
    end
end
