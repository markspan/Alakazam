function entries = collectMeasurementEntries(this)
%COLLECTMEASUREMENTENTRIES  Every dataset in either tree carrying a
%   Measure result, as a struct array with .subject, .datasetType
%   ('subject'/'grand_average'), and .EEG (already loaded) -- see
%   Alakazam.onExportMeasurements/exportMeasurementsCSV. Loads
%   every node's own .mat to check for EEG.measurements, the same
%   "load and check" approach findGrandAverageCandidates uses (for
%   DataFormat there, EEG.measurements here).
    entries = struct('subject', {}, 'datasetType', {}, 'EEG', {});

    dataNodes = this.Workspace.Tree.allNodes();
    for i = 1:numel(dataNodes)
        node = dataNodes(i);
        if exist(node.UserData, "file") ~= 2
            continue; % a node can outlive its file -- see loadNodeEEG's own note
        end
        loaded = load(node.UserData, "EEG");
        if ~isfield(loaded.EEG, "measurements")
            continue;
        end
        subjectNode = this.Workspace.Tree.rootOf(node.Id);
        if isempty(subjectNode)
            subject = node.Name; % defensive fallback; rootOf should always find at least node itself
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
        if ~isfield(loaded.EEG, "measurements")
            continue;
        end
        entries(end + 1) = struct('subject', node.Name, 'datasetType', 'grand_average', ...
            'EEG', loaded.EEG); %#ok<AGROW>
    end
end
