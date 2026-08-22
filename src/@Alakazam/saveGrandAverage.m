function saveGrandAverage(this, spec, existingNode)
%SAVEGRANDAVERAGE  Compute a grand average from SPEC (see
%   GrandAverageDialog) and save it, creating a new top-level node
%   in Workspace.GrandAveragesTree (EXISTINGNODE empty) or
%   refreshing an existing one in place (EXISTINGNODE the node
%   being recalculated). Always GrandAveragesTree specifically
%   (not Workspace.ActiveTree): this is only ever reached from the
%   Grand Average tab's own "Define..."/"Recalculate" actions, not
%   a generic current-selection flow.
    EEG = GrandAverage(spec.sources, spec.weighted);   % may throw a
                                                        % friendly
                                                        % compatibility
                                                        % error
    EEG.id = spec.name;

    gaDir = fullfile(this.Workspace.CacheDirectory, 'GrandAverages');
    if ~exist(gaDir, "dir")
        mkdir(gaDir);
    end
    safeName = matlab.lang.makeValidName(spec.name);
    EEG.File = fullfile(gaDir, [safeName '.mat']);
    saveEegCache(EEG.File, EEG);

    if isempty(existingNode)
        % 'grandAverage', not WorkSpaceTree.iconFor(EEG.DataType)
        % (which would just give the same badge a plain per-subject
        % Average result gets) -- a Grand Average is its own
        % distinct concept with its own dedicated tree icon,
        % regardless of the underlying data's time/frequency domain.
        newNode = this.Workspace.GrandAveragesTree.addNode(EEG.id, '', ...
            'grandAverage', EEG.File, WorkSpaceTree.optsFor(EEG));
        this.Workspace.GrandAveragesTree.SelectedNodes = newNode;
    else
        this.Workspace.GrandAveragesTree.renameNode(existingNode.Id, EEG.id);
        this.Workspace.GrandAveragesTree.setUserData(existingNode.Id, EEG.File);
    end

    this.Workspace.EEG = EEG;
    this.Plotter.plotCurrent();
end
