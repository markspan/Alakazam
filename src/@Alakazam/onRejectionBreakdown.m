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
%   The report is shown in RejectionBreakdownDialog, a table: it used to be
%   a uialert of sprintf-padded columns, which a proportional font misaligns.
%
%   See also ARTEFACTDETECT, REJECTIONBREAKDOWNDIALOG,
%   ALAKAZAM/ONCONTEXTMENUACTION, ALAKAZAM/ONRECALCULATENODE.
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

    RejectionBreakdownDialog(EEG.etc.alz.artefactDetectors, char(string(node.Name)), ...
        this.MainFigure);
end
