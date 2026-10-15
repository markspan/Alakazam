function [files, labels, kinds, included, branches] = findGrandAverageCandidates(this)
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
%
%   INCLUDED says, per candidate, whether its recording is in the study
%   (WorkSpace.includedFor, the Grouping dialog's "In study"). An excluded
%   recording is still offered, since choosing one by hand is the user's
%   decision, but its label starts with "(not in study)", and the cluster
%   tests leave it unselected, so it is never combined without anyone
%   having seen that it was taken out.
%
%   BRANCHES names, per candidate, the way it was made, when a kind's
%   candidates were not all made the same way ('' when they were): what
%   sets its chain of steps apart from the others' (datasetBranches), such
%   as "AutoICA" and "without AutoICA", or "Filter (lowpass.freq 30)". Every
%   subject's average is called "Average", so without it two analyses of
%   one recording were two identical rows. The label carries it in square
%   brackets, and the Grand Average dialog offers each way as a whole.
    files    = {};
    labels   = {};
    kinds    = {};
    included = false(1, 0);
    branches = {};
    recordings = {};
    ids = {};
    bins = {};
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
        recording = rootNameFor(this.Workspace.Tree, nodes(i));
        files{end + 1}  = file; %#ok<AGROW>
        kinds{end + 1}  = tag; %#ok<AGROW>
        included(end + 1) = this.Workspace.includedFor(recording); %#ok<AGROW>
        recordings{end + 1} = recording; %#ok<AGROW>
        ids{end + 1} = info.id; %#ok<AGROW>
        bins{end + 1} = info.bindescLabels; %#ok<AGROW>
    end

    % A grand average combines one kind, so each kind's ways are its own.
    branches = repmat({''}, 1, numel(files));
    for kind = reshape(unique(kinds), 1, [])
        mine = strcmp(kinds, kind{1});
        [branch, names] = datasetBranches(this.Workspace.Tree, files(mine));
        if ~isempty(names)
            branches(mine) = names(branch);
        end
    end
    labels = cell(1, numel(files));
    for k = 1:numel(files)
        labels{k} = candidateLabel(recordings{k}, ids{k}, branches{k}, bins{k}, included(k));
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

function label = candidateLabel(recording, id, branch, binLabels, inStudy)
%CANDIDATELABEL  "<recording>: <node> [<way>] (<bins>)", marked when the
%   recording has been taken out of the study under Grouping. The way is
%   left out when there is only one, or when the node's own name already
%   says it ("Average" beside "Deconvolve").
    node = id;
    if ~isempty(branch) && ~strcmp(branch, id)
        node = sprintf('%s [%s]', id, branch);
    end
    label = sprintf('%s: %s (%s)', recording, node, strjoin(binLabels, ', '));
    if ~inStudy
        label = ['(not in study) ' label];
    end
end

function tag = candidateKind(info)
%CANDIDATEKIND  Short label tag for a grand-average candidate, or '' if the
%   dataset is not one (mirrors GrandAverage's own kind detection).
    if info.hasErsp
        tag = 'TF';
    elseif info.hasCoherence
        tag = 'coherence';
    elseif strcmpi(info.DataFormat, "Averaged") && producesSubjectAverage(info.Call)
        tag = 'ERP';
    else
        tag = '';
    end
end

