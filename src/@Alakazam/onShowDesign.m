function onShowDesign(this)
%ONSHOWDESIGN  Ribbon action (Home tab, Design group): show the study
%   design read from this workspace.
%
%   Read-only and side-effect free. Nothing about the analysis changes for
%   having looked; the value is that an empty cell, a markedly unbalanced
%   pair of groups, or a subject recorded under two group labels becomes
%   visible BEFORE a report is run, rather than being inferred afterwards
%   from a refused test or a surprising result.
%
%   See also DERIVEDESIGN, ALAKAZAM.COLLECTDESIGNRECORDINGS,
%   DESIGNSUMMARYDIALOG, WORKSPACE.EDITSUBJECTS.
    restoreBusy = beginBusy(this.MainFigure, 'Reading the design...');

    recordings = this.collectDesignRecordings();
    design = deriveDesign(recordings);

    clear restoreBusy;   % the dialog must not open behind the indicator
    DesignSummaryDialog(design, this.MainFigure);
end
