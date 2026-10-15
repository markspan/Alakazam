function [branch, names, recordings] = datasetBranches(tree, files)
%DATASETBRANCHES  Which way each of a set of datasets was made, and a name
%   for each way.
%
%   [BRANCH, NAMES, RECORDINGS] = datasetBranches(TREE, FILES) finds each
%   cache file's node in TREE (a WorkSpaceTree, or anything with its
%   findByFile and lineageOf), reads the steps from its recording down to
%   it, and hands them to analysisBranches: a step's label comes from the
%   tree, its transformation and settings from the cache's small record
%   (readEegCacheMeta), never from the data. BRANCH(k) and NAMES are
%   analysisBranches' own; RECORDINGS{k} is the recording FILES{k} descends
%   from. A file no node holds counts as a recording of its own.
%
%   Several recordings with a dataset in more than one way are what makes
%   a report ask which analysis it is of (Alakazam.chooseAnalysisBranches),
%   and the names are what a grand average's inputs are told apart by
%   (findGrandAverageCandidates).
%
%   See also ANALYSISBRANCHES, WORKSPACETREE.LINEAGEOF.
    files = reshape(cellstr(string(files)), 1, []);
    n = numel(files);
    chains = cell(1, n);
    recordings = cell(1, n);
    records = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for k = 1:n
        lineage = [];
        id = tree.findByFile(files{k});
        if ~isempty(id)
            lineage = tree.lineageOf(id);
        end
        chain = struct('label', {}, 'call', {}, 'params', {});
        if isempty(lineage)
            recordings{k} = files{k};
            chains{k} = chain;
            continue;
        end
        recordings{k} = char(string(lineage(1).Name));
        for step = reshape(lineage(2:end), 1, [])
            record = recordOf(records, step.UserData);
            chain(end + 1) = struct('label', char(string(step.Name)), ... %#ok<AGROW>
                'call', record.call, 'params', {record.params});
        end
        chains{k} = chain;
    end
    [branch, names] = analysisBranches(chains, recordings);
end

function record = recordOf(records, file)
%RECORDOF  A step's transformation and settings, each file read once.
    file = char(file);
    if isKey(records, file)
        record = records(file);
        return;
    end
    record = struct('call', '', 'params', []);
    if exist(file, 'file') == 2
        try
            meta = readEegCacheMeta(file);
            record = struct('call', char(string(meta.Call)), 'params', {meta.params});
        catch
            % An unreadable step is told apart by its label alone.
        end
    end
    records(file) = record;
end
