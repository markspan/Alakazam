function [files, labels, kinds] = findGrandAverageCandidates(this)
%FINDGRANDAVERAGECANDIDATES  Every grand-averageable dataset in the cache
%   directory that is not itself a grand average -- the pool a grand average
%   can be built from. Three kinds qualify: an Averaged ERP (.data), a
%   time-frequency map (.ersp) or a coherence map (.coherence). KINDS returns
%   each candidate's kind ('ERP' / 'TF' / 'coherence'), so the dialog can put
%   each kind in its own selection list (a grand average combines one kind).
%
%   Reads each cache file's small JSON sidecar (see readEegCacheInfo /
%   saveEegCache) rather than loading the .mat itself: a cache tree mixes
%   the tiny Averaged/TF/coherence nodes this actually wants with every
%   continuous intermediate node in each subject's processing chain, which
%   run 100+ MB apiece -- a workspace with a few dozen subjects easily has
%   tens of GB of cache, almost none of which this scan has any use for.
%
%   Driven from the TREE, not from a directory scan of the cache. The cache
%   outlives the workspaces that wrote it: "Clear Other" deliberately
%   leaves a cache file that has no tree node alone, a raw recording can be
%   removed from the raw directory, and a cache folder can simply be
%   pointed at by a later workspace analysing a different study. Any of
%   those leaves .mat files on disk that belong to no current subject, and
%   a directory scan offers them as candidates: the reported symptom was a
%   grand average failing on a channel-count mismatch between an average
%   from the study being analysed and one left behind by a previous study
%   whose raw files are long gone. The tree holds exactly the datasets
%   reachable from a raw recording that is actually in this workspace,
%   which is the right definition of "available to grand-average".
    files  = {};
    labels = {};
    kinds  = {};
    nodes = this.Workspace.Tree.allNodes();
    for i = 1:numel(nodes)
        file = nodes(i).UserData;
        if isempty(file) || exist(file, 'file') ~= 2
            continue;
        end
        info = readEegCacheInfo(file);
        if info.isGrandAverage
            continue; % do not grand-average a grand average
        end
        tag = candidateKind(info);
        if isempty(tag) || isempty(info.bindescLabels)
            continue;
        end
        files{end + 1}  = file; %#ok<AGROW>
        labels{end + 1} = sprintf('%s: %s (%s)', ...
            rootNameFor(this.Workspace.Tree, nodes(i)), info.id, ...
            strjoin(info.bindescLabels, ', ')); %#ok<AGROW>
        kinds{end + 1}  = tag; %#ok<AGROW>
    end
end

function name = rootNameFor(tree, node)
%ROOTNAMEFOR  The recording a candidate descends from, for the selection
%   list. Every subject's average is called "Average", so a list of them
%   is otherwise a column of identical entries: the recording is the only
%   part that tells one row from another. Falls back to the node's own name
%   if the root cannot be resolved, which leaves the list no worse than it
%   was rather than blank.
    name = '';
    if ~node.IsRoot
        root = tree.rootOf(node.Id);
        if ~isempty(root)
            name = root.Name;
        end
    else
        name = node.Name;
    end
    if isempty(name)
        name = node.Name;
    end
end

function tag = candidateKind(info)
%CANDIDATEKIND  Short label tag for a grand-average candidate, or '' if the
%   dataset is not one (mirrors GrandAverage's own kind detection).
    if info.hasErsp
        tag = 'TF';
    elseif info.hasCoherence
        tag = 'coherence';
    elseif strcmpi(info.DataFormat, "Averaged") && isFreshAverage(info)
        tag = 'ERP';
    else
        tag = '';
    end
end

function tf = isFreshAverage(info)
%ISFRESHAVERAGE  True when INFO is Average.m's own output (or a loaded
%   .erp, which never sets .Call either) -- not a downstream step that
%   merely requires Averaged input (Measure, ScalpDistribution) and leaves
%   EEG.data/.bindesc untouched, so its own result looks exactly like a
%   second average of the same subject too. Same distinction, needed for
%   the same reason, as isOverlayableAverage's own sourceIsFreshAverage --
%   without it, every Measure/ScalpDistribution node built on a subject's
%   Average would show up as an extra, duplicate ERP candidate here.
    tf = isempty(info.Call) || strcmpi(info.Call, 'Average');
end
