function onApplyTemplate(this)
%ONAPPLYTEMPLATE  Context-menu callback: apply a previously saved
%   template (see onSaveTemplate) to the selected node -- replaying
%   its saved sequence of (transformId, params) steps in order,
%   exactly as if each had been run interactively from the ribbon.
%   Available on any node in Tree or GrandAveragesTree (root or not):
%   the common case is running a whole saved pipeline on a freshly
%   imported raw recording in one action, but applying a partial
%   template on top of an already-processed node (or even a Grand
%   Average) is equally valid -- there is nothing tree- or root-specific
%   about "replay these steps here", unlike Save Template/Apply to All
%   Raw Files, which both act on "this branch" as a structural unit.
%   NOT available in ReportsTree, though: a rendered report's own EEG is
%   a synthetic struct (see Alakazam.persistReportNode) with none of the
%   real fields (.data, .chanlocs, ...) a transformation expects, so
%   applying steps to it would fail confusingly rather than doing
%   anything meaningful -- same reasoning persistReportNode's own
%   canListEvents/canRecalculate/canApplyToAll/canExportErpset already
%   cover, just via a tree-level check here since WorkSpaceTree has no
%   per-node "canApplyTemplate" opt to hook into (onSaveTemplate guards
%   itself the same way, against everything but Workspace.Tree).
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node)
        return;
    end
    if isequal(this.Workspace.ActiveTree, this.Workspace.ReportsTree)
        uialert(this.MainFigure, ['I''m afraid a rendered report is not a dataset, so a template ' ...
            '(a sequence of transformation steps) cannot be applied to it. Please select a ' ...
            'subject or Grand Average node instead.'], 'Cannot apply template', 'Icon', 'warning');
        return;
    end

    exportsDir = this.Workspace.ExportsDirectory;
    if isempty(exportsDir) || ~isfolder(exportsDir)
        exportsDir = pwd;
    end
    [fileName, pathName] = uigetfile({'*.alztemplate', 'Alakazam Template (*.alztemplate)'}, ...
        'Apply Template', exportsDir);
    if isequal(fileName, 0)
        return; % cancelled
    end

    try
        templateNodes = this.readTemplate(fullfile(pathName, fileName));
    catch ME
        uialert(this.MainFigure, sprintf('I''m sorry, I was unable to read this template:\n\n%s', ME.message), ...
            'Could not apply template', 'Icon', 'warning');
        return;
    end
    if isempty(templateNodes)
        uialert(this.MainFigure, 'I''m afraid this template file has no steps to apply.', ...
            'Could not apply template', 'Icon', 'warning');
        return;
    end

    restoreDir = this.enterRepoRoot();
    restoreBusy = beginBusy(this.MainFigure, "Applying template...");

    % Rebuild the whole tree the template captured: apply each node to its
    % recorded parent's result, with the selected node standing in for the
    % root's parent. readTemplate guarantees a parent appears before its
    % children, so resultNodes{parent} is always ready when a child is applied
    % -- and a node with several children recreates that fork (each child
    % applied to the same parent result), not just one linear path.
    resultNodes = cell(1, numel(templateNodes));
    applied = 0;
    try
        for k = 1:numel(templateNodes)
            if templateNodes(k).parent < 1
                parentNode = node;                        % the selected target
            else
                parentNode = resultNodes{templateNodes(k).parent};
            end
            resultNodes{k} = this.applyStepToTarget( ...
                templateNodes(k).transformId, templateNodes(k).params, parentNode);
            applied = applied + 1;
        end
    catch ME
        this.restoreFocus();
        uialert(this.MainFigure, sprintf( ...
            ['I''m sorry to say that only %d of %d step(s) were applied before this one failed:\n\n%s\n\n' ...
             'The steps that succeeded beforehand are still in the tree.'], ...
            applied, numel(templateNodes), ME.message), 'Could not apply template', 'Icon', 'warning');
        return;
    end

    % Show the final result. applyStepToTarget only persists each step (it is
    % also used where plotting would be wrong, e.g. batch apply-to-all), so
    % without this the template runs silently and nothing appears -- which
    % reads as broken when the last step is a plot (TimeFrequency / Coherence
    % / Scalp), whose plot IS the deliverable. persistResultNode already made
    % the last result the workspace's current dataset, so plotCurrent draws it
    % in the right view (see AlakazamPlotter's id / .ersp / .coherence routing).
    this.Plotter.plotCurrent();

    this.restoreFocus();
    % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
    msgbox(sprintf('Applied template "%s" (%d step(s)).', fileName, applied), ...
        'Template applied');
end
