function onTransformation(this, entry)
%ONTRANSFORMATION  Toolbar callback: run a transformation on the current EEG.
%   ONTRANSFORMATION(THIS, ENTRY) executes the transformation whose
%   entry file is ENTRY (for example "Fourier.m") on the selected
%   dataset, stores the result as a new child node, and plots it. The
%   stem of ENTRY is both the transformation id and the function that
%   is invoked with feval. Two-arg form (was THIS, ~, ~, ENTRY): a
%   uibutton's ButtonPushedFcn passes (source, eventdata), not a
%   Toolstrip gallery item's three -- see BuildToolbarAlakazam.
%
%   A transformation returns [EEG, params]; if it instead returns a
%   graphics handle it was a pure plot and nothing is persisted.
    % The gallery passes the entry file name (e.g. "Fourier.m"); its
    % stem is the transformation id and the function to call. The '.'
    % is a char so the element-wise comparison works. Computed before
    % the try block (cheap, pure string parsing) so it is always
    % available in the catch block below, even if something upstream
    % of the feval call itself somehow fails.
    entryName   = char(entry);
    transformId = entryName(1:find(entryName == '.', 1, "last") - 1);

    try
        restoreDir = this.enterRepoRoot();

        % Pointer is figure-wide (every dataset is a tab on the one
        % shared MainFigure), so no per-tab lookup is needed here.
        this.MainFigure.Pointer = "watch";

        % Apply the transformation to the current dataset.
        [result.EEG, usedParams] = feval(transformId, this.Workspace.EEG);

        if isempty(result.EEG) || ishandle(result.EEG)
            % Either the transformation's own options dialog was
            % cancelled (result.EEG is [] -- see
            % TransformOptionsDialog's own header comment for why
            % every transformation using it must return [] on
            % Cancel rather than proceeding), or the plugin
            % returned a graphics handle instead of a dataset (a
            % pure plot). Either way there is nothing to persist,
            % and -- unlike an actual failure -- nothing the user
            % needs to see an error about. Still reset the
            % pointer/focus exactly like the success/failure
            % paths below do (previously left stuck on "watch"
            % for the pure-plot case).
            this.MainFigure.Pointer = "arrow";
            this.restoreFocus();
            return;
        end

        % Record how the result was produced, so it can be re-applied
        % when this branch is later dragged onto another dataset.
        % Call is just the transformation id (a plain function name,
        % fed straight to feval on replay -- see evaluateDroppedBranch);
        % it used to be a fake "EEG=<id>(x.EEG);" command string that
        % was then re-parsed with strfind, which added a redundant,
        % error-prone round trip for no benefit.
        result.EEG.Call = transformId;
        if isstruct(usedParams)
            result.EEG.params = usedParams;
        else
            result.EEG.params = struct('Param', usedParams);
        end

        % Persist under the selected node (its file is the source cache
        % file at this point) and display the result. ActiveTree
        % (see onSelectionChanged/onNodeDoubleClicked/
        % onContextMenuAction) is whichever of the two trees that
        % selection actually lives in -- Tree or GrandAveragesTree,
        % since a transformation can be run on a currently-selected
        % grand average too.
        displayBase = this.Workspace.ActiveTree.SelectedNodes.Name;
        this.persistResultNode(result.EEG, result.EEG.File, displayBase, ...
            transformId, this.Workspace.ActiveTree.SelectedNodes);

        this.Plotter.plotCurrent();
        this.MainFigure.Pointer = "arrow";
        this.restoreFocus();

    catch ME
        this.MainFigure.Pointer = "arrow";
        this.restoreFocus();
        this.showTransformationError(transformId, ME);
    end
end
