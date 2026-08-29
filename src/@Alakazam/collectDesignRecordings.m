function recordings = collectDesignRecordings(this)
%COLLECTDESIGNRECORDINGS  The Averaged datasets the design is read from,
%   one row per recording, with the identity and grouping already attached.
%
%   Driven from the tree, not from a scan of the cache directory, for the
%   same reason findGrandAverageCandidates is: a cache outlives the
%   workspaces that wrote it, and a design built from stale files would
%   describe a study this workspace is not running.
%
%   One row per Averaged dataset rather than per root recording: a root that
%   has not been averaged yet contributes no bins and belongs to no cell, so
%   including it would put a subject in the design who cannot appear in any
%   result. Reads each dataset's small JSON sidecar rather than loading the
%   .mat, the same way findGrandAverageCandidates does, since only the bin
%   labels are wanted.
%
%   See also DERIVEDESIGN, ALAKAZAM.ONSHOWDESIGN,
%   ALAKAZAM.FINDGRANDAVERAGECANDIDATES.
    recordings = struct('name', {}, 'person', {}, 'group', {}, 'session', {}, ...
        'bins', {}, 'included', {}, 'file', {});

    nodes = this.Workspace.Tree.allNodes();
    if isempty(nodes)
        return;
    end

    for i = 1:numel(nodes)
        file = nodes(i).UserData;
        if isempty(file) || exist(file, 'file') ~= 2
            continue;
        end
        info = readEegCacheInfo(file);
        if info.isGrandAverage || ~isAveragedErp(info) || isempty(info.bindescLabels)
            continue;
        end

        rootName = rootNameFor(this.Workspace.Tree, nodes(i));
        if isempty(rootName)
            continue;
        end
        recordings(end + 1) = struct( ...
            'name',    rootName, ...
            'person',  char(this.Workspace.personFor(rootName)), ...
            'group',   char(this.Workspace.groupFor(rootName)), ...
            'session', char(this.Workspace.sessionFor(rootName)), ...
            'bins',    {ordinaryBins(info.bindescLabels)}, ...
            'included', this.Workspace.includedFor(rootName), ...
            'file',    file); %#ok<AGROW>
    end
end

% ----------------------------------------------------------------------- %
function tf = isAveragedErp(info)
%ISAVERAGEDERP  Average.m's own output, not a downstream step that merely
%   requires Averaged input. Mirrors findGrandAverageCandidates' own
%   isFreshAverage: without it, every Measure or ScalpDistribution node
%   built on an Average would count as a second recording for the same
%   subject and double its contribution to every cell.
    tf = strcmpi(info.DataFormat, "Averaged") ...
        && (isempty(info.Call) || strcmpi(info.Call, 'Average')) ...
        && ~info.hasErsp && ~info.hasCoherence;
end

function name = rootNameFor(tree, node)
%ROOTNAMEFOR  The recording an Average descends from, which is the name
%   Edit Subjects assigned its group, person and session against.
    if node.IsRoot
        name = node.Name;
        return;
    end
    root = tree.rootOf(node.Id);
    if isempty(root)
        name = '';
    else
        name = root.Name;
    end
end

function labels = ordinaryBins(labels)
%ORDINARYBINS  Drop the combination (difference) bins. They are a linear
%   combination of the others rather than conditions in their own right, so
%   counting them as levels of the bin factor would overstate the design --
%   the same distinction generateQuartoReport's own classifyBins draws
%   before choosing a test.
%
%   The sidecar carries labels only, not each bin's own .combo, so this
%   cannot tell them apart with certainty; a bin whose label reads as a
%   difference of two others is treated as one. That is a heuristic, and it
%   is only ever used for display.
    labels = labels(:)';
    keep = true(1, numel(labels));
    for i = 1:numel(labels)
        label = char(string(labels{i}));
        keep(i) = isempty(regexp(label, '^\s*\S.*\s[-+]\s.*\S\s*$', 'once'));
    end
    labels = labels(keep);
end
