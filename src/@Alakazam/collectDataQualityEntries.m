function entries = collectDataQualityEntries(this)
%COLLECTDATAQUALITYENTRIES  One data-quality entry per Averaged ERP in the
%   Data & Analyses tree, as a struct array with .subject/.group/.session
%   and .quality (a dataQualityMetrics() return) -- see
%   Alakazam.onExportDataQuality.
%
%   Keyed on Average nodes, not on epoched ones, for two reasons: an
%   Average is the unit that actually enters the group analysis (the same
%   thing the ERP/Spectral/Cluster reports are all keyed on), and
%   Average.m is where the SME dataQualityMetrics reports alongside its own
%   rejection rates was computed. The trial-level metrics still come from
%   the epoched data, found by walking up from each Average to its nearest
%   segmented ancestor: that is the dataset the average was actually
%   computed from, so its rejection state is by construction the rejection
%   state behind that average, rather than whichever epoched node in the
%   subject's branch happens to be newest.
%
%   Nodes are matched to their parents through their cache FILE, not a node
%   id: WorkSpaceTree exposes parentFile (used by recalculateTransformNode
%   for the same reason) but no parentOf, so the walk resolves each parent
%   file back to its node through a file -> node map built once here.
%
%   See also DATAQUALITYMETRICS, COLLECTENTRIESWITHFIELD.
    entries = struct('subject', {}, 'group', {}, 'session', {}, 'quality', {});

    nodes = this.Workspace.Tree.allNodes();
    if isempty(nodes)
        return;
    end
    byFile = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:numel(nodes)
        if ~isempty(nodes(i).UserData)
            byFile(nodes(i).UserData) = nodes(i);
        end
    end

    for i = 1:numel(nodes)
        node = nodes(i);
        if exist(node.UserData, 'file') ~= 2
            continue; % a node can outlive its file -- see loadNodeEEG's own note
        end
        info = readEegCacheInfo(node.UserData);
        if ~strcmpi(info.DataFormat, 'Averaged') || ~strcmpi(info.Call, 'Average')
            continue;
        end
        epochedFile = nearestEpochedAncestor(this.Workspace.Tree, byFile, node);
        if isempty(epochedFile)
            continue; % nothing segmented behind it (e.g. a loaded .erp)
        end

        epoched  = load(epochedFile, 'EEG');
        averaged = load(node.UserData, 'EEG');
        windows  = measureWindowsUnder(this.Workspace.Tree, byFile, nodes, node);
        rejectionRan = rejectionInChain(this.Workspace.Tree, byFile, epochedFile);
        try
            quality = dataQualityMetrics(epoched.EEG, averaged.EEG, windows, rejectionRan);
        catch
            continue; % single-trial or otherwise undescribable -- see dataQualityMetrics' own guard
        end

        subjectNode = this.Workspace.Tree.rootOf(node.Id);
        if isempty(subjectNode)
            subject = node.Name;
        else
            subject = subjectNode.Name;
        end
        entries(end + 1) = struct('subject', subject, ... %#ok<AGROW>
            'group', this.Workspace.groupFor(subject), ...
            'session', this.Workspace.sessionFor(subject), ...
            'quality', quality);
    end
end

% ----------------------------------------------------------------------- %
function tf = rejectionInChain(tree, byFile, epochedFile)
%REJECTIONINCHAIN  Has an artefact-rejection step actually been run on this
%   dataset? True when ArtefactDetect or ManualReject appears anywhere from
%   the epoched node up to its root.
%
%   dataQualityMetrics needs this because an all-NaN trial has two possible
%   causes that look identical in the data: a whole-epoch rejection, or an
%   epoch DefineBins could not cut at all (an anchor event past the end of
%   the recording). Calling the second one "rejected" invites the obvious
%   question of who rejected it, and there is no answer. Knowing whether
%   any rejection step exists settles it in the common case.
    tf = false;
    if ~isKey(byFile, epochedFile)
        return;
    end
    current = byFile(epochedFile);
    for hop = 1:numel(keys(byFile))
        if ismember(lower(readEegCacheInfo(current.UserData).Call), ...
                {'artefactdetect', 'manualreject'})
            tf = true;
            return;
        end
        parentFile = tree.parentFile(current.Id);
        if isempty(parentFile) || ~isKey(byFile, parentFile) ...
                || exist(parentFile, 'file') ~= 2
            return;
        end
        current = byFile(parentFile);
    end
end

% ----------------------------------------------------------------------- %
function windows = measureWindowsUnder(tree, byFile, nodes, averageNode)
%MEASUREWINDOWSUNDER  The Measure windows belonging to AVERAGENODE: the
%   EEG.measurements of the nearest Measure node DESCENDED from it, or {}
%   if the subject has no Measure result. They are what dataQualityMetrics
%   scores a per-window SME for (see erpScoreSME).
%
%   Descent is checked by walking each candidate UP to see whether it
%   passes through AVERAGENODE's own file, rather than by looking for
%   children: WorkSpaceTree is a flat id -> struct map with parent links
%   only (see its class header), so upwards is the only direction that can
%   be walked at all.
%
%   Restricting to descendants matters in a branch with more than one
%   Average (two different pipelines on the same recording): a Measure node
%   under one of them describes windows scored on THAT average's data, and
%   attaching its windows to the other would report SMEs computed from the
%   wrong trials.
    windows = {};
    for i = 1:numel(nodes)
        candidate = nodes(i);
        if exist(candidate.UserData, 'file') ~= 2
            continue;
        end
        if ~ismember('measurements', readEegCacheInfo(candidate.UserData).fieldNames)
            continue;
        end
        if ~isDescendantOf(tree, byFile, candidate, averageNode.UserData)
            continue;
        end
        loaded = load(candidate.UserData, 'EEG');
        if isfield(loaded.EEG, 'measurements') && ~isempty(loaded.EEG.measurements)
            windows = loaded.EEG.measurements;
            return;
        end
    end
end

function tf = isDescendantOf(tree, byFile, node, ancestorFile)
%ISDESCENDANTOF  Does NODE's parent chain pass through ANCESTORFILE? Hop
%   count is bounded by the map size for the same reason
%   nearestEpochedAncestor bounds its own walk.
    tf = false;
    current = node;
    for hop = 1:numel(keys(byFile))
        parentFile = tree.parentFile(current.Id);
        if isempty(parentFile)
            return;
        end
        if strcmp(parentFile, ancestorFile)
            tf = true;
            return;
        end
        if ~isKey(byFile, parentFile)
            return;
        end
        current = byFile(parentFile);
    end
end

% ----------------------------------------------------------------------- %
function file = nearestEpochedAncestor(tree, byFile, node)
%NEARESTEPOCHEDANCESTOR  The cache file of the closest ancestor of NODE
%   whose sidecar reports segmented data, or '' if there is none. Bounded
%   by the number of nodes rather than by "until the root": the file -> node
%   map cannot represent a cycle, but a malformed workspace whose parent
%   links do form one would otherwise spin here forever.
    file = '';
    current = node;
    for hop = 1:numel(keys(byFile))
        parentFile = tree.parentFile(current.Id);
        if isempty(parentFile) || exist(parentFile, 'file') ~= 2
            return;
        end
        if strcmpi(readEegCacheInfo(parentFile).DataFormat, 'EPOCHED')
            file = parentFile;
            return;
        end
        if ~isKey(byFile, parentFile)
            return;
        end
        current = byFile(parentFile);
    end
end
