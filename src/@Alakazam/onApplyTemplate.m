function onApplyTemplate(this)
%ONAPPLYTEMPLATE  Context-menu callback: apply a previously saved
%   template (see onSaveTemplate) to the selected node -- replaying
%   its saved sequence of (transformId, params) steps in order,
%   exactly as if each had been run interactively from the ribbon.
%   Available on ANY node (root or not, in either tree): the common
%   case is running a whole saved pipeline on a freshly imported
%   raw recording in one action, but applying a partial template on
%   top of an already-processed node (or even a Grand Average) is
%   equally valid -- there is nothing tree- or root-specific about
%   "replay these steps here", unlike Save Template/Apply to All
%   Raw Files, which both act on "this branch" as a structural unit.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node)
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
        steps = this.readTemplate(fullfile(pathName, fileName));
    catch ME
        uialert(this.MainFigure, sprintf('Could not read this template:\n\n%s', ME.message), ...
            'Could not apply template', 'Icon', 'warning');
        return;
    end
    if isempty(steps)
        uialert(this.MainFigure, 'This template file has no steps to apply.', ...
            'Could not apply template', 'Icon', 'warning');
        return;
    end

    % Run from the repository root (historic behaviour): individual
    % plugins may resolve resources relative to it -- same as
    % onTransformation/onNodeDropped/onApplyToAllRawFiles.
    originalDir = cd(this.RepoRoot);
    restoreDir  = onCleanup(@() cd(originalDir)); % restores cwd at method exit
    this.MainFigure.Pointer = "watch";
    restorePointer = onCleanup(@() set(this.MainFigure, "Pointer", "arrow"));

    applied = 0;
    try
        for k = 1:numel(steps)
            node = this.applyStepToTarget(steps(k).transformId, steps(k).params, node);
            applied = applied + 1;
        end
    catch ME
        this.restoreFocus();
        uialert(this.MainFigure, sprintf( ...
            ['Applied %d of %d step(s) before this one failed:\n\n%s\n\n' ...
             'The steps that succeeded are still in the tree.'], ...
            applied, numel(steps), ME.message), 'Could not apply template', 'Icon', 'warning');
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
