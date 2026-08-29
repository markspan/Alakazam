function entries = collectEntriesWithField(this, fieldName)
%COLLECTENTRIESWITHFIELD  Every dataset in either tree carrying FIELDNAME
%   on its loaded EEG struct, as a struct array with .subject,
%   .datasetType ('subject'/'grand_average'), .group (see
%   WorkSpace.groupFor/editSubjects), .person (WorkSpace.personFor,
%   defaults to .subject itself -- see its own header comment), .session
%   (WorkSpace.sessionFor) and .EEG (already loaded).
%
%   Shared by collectMeasurementEntries (FIELDNAME = "measurements", see
%   onExportMeasurements/exportMeasurementsCSV) and collectSpectralEntries
%   (FIELDNAME = "spectralMeasures", see onExportSpectral/
%   exportSpectralCSV) -- previously two separately-maintained, otherwise
%   byte-identical copies of this same walk.
%
%   Checks each node's JSON cache sidecar (readEegCacheInfo) for FIELDNAME
%   before loading it in full: most nodes in a processing tree are
%   continuous intermediate steps (Filter, ArtefactDetect, ...), often
%   100+ MB apiece, that were never going to carry a Measure/SpectralMeasure
%   result -- a full load is only actually needed for the (few) nodes that
%   do.
%
%   .group/.session are always '' for a grand_average entry, and .person
%   is always its own node name (not looked up): a grand average is
%   already an aggregate across several subjects (possibly straddling
%   more than one group, person or session), not a single between-
%   subjects/single-person unit itself, so generateQuartoReport's own
%   group filtering already excludes rows with no group -- this just
%   makes that exclusion automatic for grand averages rather than
%   requiring a per-subject lookup that would not mean anything for one.
    entries = struct('subject', {}, 'datasetType', {}, 'group', {}, 'person', {}, 'session', {}, 'EEG', {});

    dataNodes = this.Workspace.Tree.allNodes();
    for i = 1:numel(dataNodes)
        node = dataNodes(i);
        if exist(node.UserData, "file") ~= 2
            continue; % a node can outlive its file -- see loadNodeEEG's own note
        end
        if ~ismember(fieldName, readEegCacheInfo(node.UserData).fieldNames)
            continue;
        end
        subjectNode = this.Workspace.Tree.rootOf(node.Id);
        if isempty(subjectNode)
            subject = node.Name; % defensive fallback; rootOf should always find at least node itself
        else
            subject = subjectNode.Name;
        end
        % Exclusion applies here, at the source, so an excluded recording is
        % absent from the exported measurements and therefore from every
        % report, statistic and grand average built on them -- one stated
        % reason rather than several implicit ones downstream. Checked
        % before the load, since an excluded dataset need not be read at
        % all. See WorkSpace.includedFor.
        if ~this.Workspace.includedFor(subject)
            continue;
        end
        loaded = load(node.UserData, "EEG");
        entries(end + 1) = struct('subject', subject, 'datasetType', 'subject', ...
            'group', this.Workspace.groupFor(subject), 'person', this.Workspace.personFor(subject), ...
            'session', this.Workspace.sessionFor(subject), 'EEG', loaded.EEG); %#ok<AGROW>
    end

    gaNodes = this.Workspace.GrandAveragesTree.allNodes();
    for i = 1:numel(gaNodes)
        node = gaNodes(i);
        if exist(node.UserData, "file") ~= 2
            continue;
        end
        if ~ismember(fieldName, readEegCacheInfo(node.UserData).fieldNames)
            continue;
        end
        loaded = load(node.UserData, "EEG");
        entries(end + 1) = struct('subject', node.Name, 'datasetType', 'grand_average', ...
            'group', '', 'person', node.Name, 'session', '', 'EEG', loaded.EEG); %#ok<AGROW>
    end
end
