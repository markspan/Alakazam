function entries = collectEntriesWithField(this, fieldName)
%COLLECTENTRIESWITHFIELD  Every dataset in either tree carrying FIELDNAME
%   on its loaded EEG struct, as a struct array with .subject,
%   .datasetType ('subject'/'grand_average'), .group (see
%   WorkSpace.groupFor/editGroups) and .EEG (already loaded). Loads every
%   node's own .mat to check for FIELDNAME, the same "load and check"
%   approach findGrandAverageCandidates uses.
%
%   Shared by collectMeasurementEntries (FIELDNAME = "measurements", see
%   onExportMeasurements/exportMeasurementsCSV) and collectSpectralEntries
%   (FIELDNAME = "spectralMeasures", see onExportSpectral/
%   exportSpectralCSV) -- previously two separately-maintained, otherwise
%   byte-identical copies of this same walk.
%
%   .group is always '' for a grand_average entry: a grand average is
%   already an aggregate across several subjects (possibly straddling
%   more than one group), not a single between-subjects unit itself, so
%   generateQuartoReport's own group filtering already excludes rows with
%   no group -- this just makes that exclusion automatic for grand
%   averages rather than requiring a per-subject lookup that would not
%   mean anything for one.
    entries = struct('subject', {}, 'datasetType', {}, 'group', {}, 'EEG', {});

    dataNodes = this.Workspace.Tree.allNodes();
    for i = 1:numel(dataNodes)
        node = dataNodes(i);
        if exist(node.UserData, "file") ~= 2
            continue; % a node can outlive its file -- see loadNodeEEG's own note
        end
        loaded = load(node.UserData, "EEG");
        if ~isfield(loaded.EEG, fieldName)
            continue;
        end
        subjectNode = this.Workspace.Tree.rootOf(node.Id);
        if isempty(subjectNode)
            subject = node.Name; % defensive fallback; rootOf should always find at least node itself
        else
            subject = subjectNode.Name;
        end
        entries(end + 1) = struct('subject', subject, 'datasetType', 'subject', ...
            'group', this.Workspace.groupFor(subject), 'EEG', loaded.EEG); %#ok<AGROW>
    end

    gaNodes = this.Workspace.GrandAveragesTree.allNodes();
    for i = 1:numel(gaNodes)
        node = gaNodes(i);
        if exist(node.UserData, "file") ~= 2
            continue;
        end
        loaded = load(node.UserData, "EEG");
        if ~isfield(loaded.EEG, fieldName)
            continue;
        end
        entries(end + 1) = struct('subject', node.Name, 'datasetType', 'grand_average', ...
            'group', '', 'EEG', loaded.EEG); %#ok<AGROW>
    end
end
