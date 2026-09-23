function [results, width] = replayBranchOnTargets(sourceFile, targetFiles, transRoot, nWorkers, onResult, onStart)
%REPLAYBRANCHONTARGETS  replayBranch onto several datasets, in parallel when
%   asked and possible.
%
%   RESULTS = replayBranchOnTargets(SOURCEFILE, TARGETFILES, TRANSROOT,
%   NWORKERS) replays the branch at SOURCEFILE onto each cache file in the
%   cell array TARGETFILES. RESULTS(k), for TARGETFILES{k}, has
%     .nodes    what replayBranch wrote (see its help)
%     .error    '' on success, else why it stopped
%     .seconds  how long that target took
%
%   NWORKERS below 2 runs everything in this MATLAB, one target after
%   another. Otherwise a pool of worker processes (the one already running,
%   or a new one of NWORKERS) takes up to NWORKERS targets at a time, fewer
%   if the running pool is smaller. The cap matters: each worker holds a
%   whole recording and its intermediate results, so it is memory, not the
%   number of cores, that says how many can safely run at once (see
%   applyToAllWorkers). Without the Parallel Computing Toolbox, or when no
%   pool can be started, it falls back to one at a time, with a warning.
%
%   WIDTH is how many targets were processed at once in the end: 1 when it
%   ran here, whatever NWORKERS asked for.
%
%   ONRESULT(k, RESULT), when given, is called in this MATLAB as each target
%   finishes, in the order they finish: Apply to All Raw Files adds the
%   nodes to the tree there. ONSTART(k), when given, is called as each
%   target is started.
%
%   Workers get this MATLAB's path and current folder before each target, so
%   they see the same transformations, EEGLAB and FieldTrip as the app does.
%
%   See also REPLAYBRANCH, APPLYTOALLWORKERS.
    if nargin < 5
        onResult = [];
    end
    if nargin < 6
        onStart = [];
    end
    targetFiles = cellstr(targetFiles);
    n = numel(targetFiles);
    emptyNodes = struct('File', {}, 'ParentFile', {}, 'Label', {}, 'Icon', {}, 'Opts', {});
    results = repmat(struct('nodes', emptyNodes, 'error', '', 'seconds', NaN), 1, n);

    pool = [];
    if nWorkers >= 2 && n >= 2
        pool = startPool(nWorkers);
    end

    if isempty(pool)
        width = 1;
        for k = 1:n
            callIfGiven(onStart, k);
            results(k) = replayTimed(sourceFile, targetFiles{k}, transRoot);
            callIfGiven(onResult, k, results(k));
        end
        return;
    end

    width = min([nWorkers, pool.NumWorkers, n]);
    % A pool worker computes on one thread by default, where the app uses
    % every core for filtering and FFTs. With fewer workers than cores the
    % rest would sit idle, so each worker gets its share of them. On the RIFT
    % branch it made no measurable difference (213 s against 215 s for nine
    % recordings on three workers), since that branch is held back by the
    % disk and by CoherenceMap's FFTs, which the app already runs on all
    % cores; it is kept for branches that compute more than they write.
    threads = max(1, floor(feature('numcores') / width));
    clientPath = path;
    here = pwd;
    inFlight = struct('future', {}, 'index', {});
    next = 1;
    while next <= n || ~isempty(inFlight)
        while numel(inFlight) < width && next <= n && memoryAllowsAnother(inFlight)
            callIfGiven(onStart, next);
            inFlight(end + 1) = struct('future', parfeval(pool, @replayOnWorker, 1, ...
                clientPath, here, threads, sourceFile, targetFiles{next}, transRoot), 'index', next); %#ok<AGROW>
            next = next + 1;
        end
        % Polled rather than fetchNext: fetchNext cannot say which future
        % threw when a worker itself fails, and the pause lets the app
        % repaint its progress dialog while it waits.
        states = arrayfun(@(s) char(s.future.State), inFlight, 'UniformOutput', false);
        finished = ismember(states, {'finished', 'failed', 'unavailable'});
        if ~any(finished)
            pause(0.25);
            continue;
        end
        for j = find(finished)
            k = inFlight(j).index;
            try
                results(k) = fetchOutputs(inFlight(j).future);
            catch err
                results(k).error = sprintf('the worker processing it failed: %s', err.message);
            end
            callIfGiven(onResult, k, results(k));
        end
        inFlight(finished) = [];
    end
end

function r = replayOnWorker(clientPath, here, threads, sourceFile, targetFile, transRoot)
%REPLAYONWORKER  One target, on a worker set up like the client.
    path(clientPath);
    cd(here);
    maxNumCompThreads(threads);
    r = replayTimed(sourceFile, targetFile, transRoot);
end

function r = replayTimed(sourceFile, targetFile, transRoot)
    started = tic;
    [nodes, message] = replayBranch(sourceFile, targetFile, transRoot);
    r = struct('nodes', nodes, 'error', message, 'seconds', toc(started));
end

function callIfGiven(fcn, varargin)
    if ~isempty(fcn)
        fcn(varargin{:});
    end
end

function tf = memoryAllowsAnother(inFlight)
%MEMORYALLOWSANOTHER  Is there room to start one more recording right now?
%   The width of the batch was decided before it began, from an estimate of
%   what one replay costs (applyToAllWorkers). That estimate is made from
%   the recording's file size, which says nothing about a step whose cost is
%   the model it builds, so it can be badly optimistic: the reported symptom
%   was a machine stalling in swap on a branch whose steps each wanted
%   several GB while the budget had allowed 1.55 GB apiece.
%
%   This is the check that cannot be fooled by a bad estimate: before
%   starting each recording, look at what is actually free. Below the floor,
%   wait for one of the running ones to finish and free its memory instead.
%
%   ALWAYS TRUE WHEN NOTHING IS RUNNING, so a batch can never deadlock
%   waiting for memory that only finishing work would release, and always
%   true where free memory cannot be read: an unreadable gauge is not a
%   reason to serialise the whole batch.
    FLOOR = 4e9;   % bytes free below which another worker is not started
    tf = true;
    if isempty(inFlight)
        return;
    end
    free = availableMemory();
    if isfinite(free)
        tf = free >= FLOOR;
    end
end

function pool = startPool(nWorkers)
%STARTPOOL  The running process pool, or a new one of NWORKERS; [] if none.
%   A thread pool is not used: its workers cannot take this MATLAB's path or
%   folder, which the transformations need.
    pool = [];
    if ~license('test', 'Distrib_Computing_Toolbox') || isempty(ver('parallel'))
        return;
    end
    try
        pool = gcp('nocreate');
        if ~isempty(pool) && isa(pool, 'parallel.ThreadPool')
            warning('Alakazam:replayBranchOnTargets:threadPool', ...
                'A thread pool is running, which cannot run transformations; processing one recording at a time.');
            pool = [];
            return;
        end
        if isempty(pool)
            pool = parpool('Processes', nWorkers);
        end
    catch err
        warning('Alakazam:replayBranchOnTargets:noPool', ...
            'I could not start parallel workers (%s), so I am processing one recording at a time.', err.message);
        pool = [];
    end
end
