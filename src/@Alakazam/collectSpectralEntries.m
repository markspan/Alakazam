function entries = collectSpectralEntries(this)
%COLLECTSPECTRALENTRIES  Every dataset in either tree carrying a
%   SpectralMeasure result, as a struct array with .subject, .datasetType
%   ('subject'/'grand_average') and .EEG (already loaded) -- the
%   frequency-domain sibling of collectMeasurementEntries (EEG.spectralMeasures
%   here, EEG.measurements there). See onExportSpectral/exportSpectralCSV.
    entries = struct('subject', {}, 'datasetType', {}, 'EEG', {});

    dataNodes = this.Workspace.Tree.allNodes();
    for i = 1:numel(dataNodes)
        node = dataNodes(i);
        if exist(node.UserData, "file") ~= 2
            continue;
        end
        loaded = load(node.UserData, "EEG");
        if ~isfield(loaded.EEG, "spectralMeasures")
            continue;
        end
        subjectNode = this.Workspace.Tree.rootOf(node.Id);
        if isempty(subjectNode)
            subject = node.Name;
        else
            subject = subjectNode.Name;
        end
        entries(end + 1) = struct('subject', subject, 'datasetType', 'subject', ...
            'EEG', loaded.EEG); %#ok<AGROW>
    end

    gaNodes = this.Workspace.GrandAveragesTree.allNodes();
    for i = 1:numel(gaNodes)
        node = gaNodes(i);
        if exist(node.UserData, "file") ~= 2
            continue;
        end
        loaded = load(node.UserData, "EEG");
        if ~isfield(loaded.EEG, "spectralMeasures")
            continue;
        end
        entries(end + 1) = struct('subject', node.Name, 'datasetType', 'grand_average', ...
            'EEG', loaded.EEG); %#ok<AGROW>
    end
end
