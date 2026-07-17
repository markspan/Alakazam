function onSaveTemplate(this)
%ONSAVETEMPLATE  Context-menu callback: save the selected branch
%   (its own transformation plus every step below it -- the exact
%   same scope dragging this node onto another dataset, or "Apply
%   to All Raw Files", would replay) as a reusable template file on
%   disk: a plain JSON list of (transformId, params) steps,
%   decoupled from this workspace's own cache files, so it can be
%   applied later -- to a dataset in a different workspace, or
%   after Alakazam has been restarted -- via "Apply Template..."
%   (see onApplyTemplate).
%
%   Reuses canApplyToAll's eligibility (a non-root node in
%   Workspace.Tree, see persistResultNode): a template most
%   naturally describes "how to process a raw recording", which is
%   what a subject's own analysis branch captures; re-validated
%   here too, defence in depth.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node) || node.IsRoot || ~isequal(this.Workspace.ActiveTree, this.Workspace.Tree)
        return;
    end

    try
        steps = this.collectBranchSteps(node.UserData);
    catch ME
        uialert(this.MainFigure, sprintf('Could not read this branch:\n\n%s', ME.message), ...
            'Could not save template', 'Icon', 'warning');
        return;
    end

    % The {arrayfun(...)} wrapping (not a bare struct array) is
    % deliberate: jsonencode collapses a 1-element struct array to a
    % bare JSON object instead of a single-element array (the same
    % gotcha WorkSpaceTree.buildData's own header comment documents
    % for the JS tree push) -- a cell array sidesteps it, so a
    % one-step template still round-trips through readTemplate as a
    % one-element list, not a bare object. Each step's params goes
    % through templateParams first, so a step with a derivable
    % compiled cache (currently just DefineBins' .bins, derivable
    % from .script) is re-derived on apply instead of trusting the
    % cache to survive jsonencode/jsondecode with its original
    % MATLAB types intact.
    template = struct( ...
        'alakazamTemplate', true, ...
        'version', 1, ...
        'name', node.Name, ...
        'steps', {arrayfun(@(s) struct('transformId', s.transformId, ...
            'params', this.templateParams(s.params)), steps, 'UniformOutput', false)});

    exportsDir = this.Workspace.ExportsDirectory;
    if isempty(exportsDir) || ~isfolder(exportsDir)
        exportsDir = pwd;
    end
    defaultFile = fullfile(exportsDir, [char(matlab.lang.makeValidName(node.Name)) '.alztemplate']);
    [fileName, pathName] = uiputfile({'*.alztemplate', 'Alakazam Template (*.alztemplate)'}, ...
        'Save Template', defaultFile);
    if isequal(fileName, 0)
        return; % cancelled
    end

    try
        % ConvertInfAndNaN=false: the default (true) silently turns
        % NaN into JSON null, which jsondecode then reads back as []
        % (empty), not NaN -- a params field that happens to be NaN
        % (a real, if currently unused, sentinel value some
        % transform could reasonably store) would otherwise change
        % meaning across a save/apply round trip with no error at
        % all. false instead writes/reads MATLAB's own NaN/Infinity/
        % -Infinity tokens, which is not standard JSON but round-
        % trips exactly through this file's only two readers/
        % writers of it (this method and readTemplate).
        json = jsonencode(template, 'PrettyPrint', true, 'ConvertInfAndNaN', false);
        fid = fopen(fullfile(pathName, fileName), 'w');
        if fid < 0
            throw(MException('Alakazam:onSaveTemplate', 'Could not open the file for writing.'));
        end
        closeFile = onCleanup(@() fclose(fid));
        fwrite(fid, json, 'char');
    catch ME
        uialert(this.MainFigure, sprintf('Could not save the template:\n\n%s', ME.message), ...
            'Could not save template', 'Icon', 'warning');
        return;
    end

    % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
    msgbox(sprintf('Saved template "%s" (%d step(s)) to:\n%s', node.Name, numel(steps), ...
        fullfile(pathName, fileName)), 'Template saved');
end
