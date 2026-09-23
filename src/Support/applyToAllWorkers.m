function n = applyToAllWorkers(targetFiles, varargin)
%APPLYTOALLWORKERS  How many recordings Apply to All Raw Files runs at once.
%   N = applyToAllWorkers(TARGETFILES) is 1 (one at a time, in the app) or
%   the number of parallel workers to use for replaying a branch onto the
%   cache files in TARGETFILES (see replayBranchOnTargets).
%
%   It is 1 when parallel processing is switched off in Settings
%   (Processing > Apply to All Raw Files), when the Parallel Computing
%   Toolbox is missing, or when there is only one recording. Otherwise it is
%   the smallest of: the number of recordings, the number of physical cores,
%   what the free memory allows, and the maximum set in Settings (0 there
%   means no maximum of its own).
%
%   WHY MEMORY DECIDES. A worker holds a whole recording and the results of
%   the step it is running, and several of the steps (filtering, epoching)
%   make a full copy of the data along the way. Each worker is therefore
%   budgeted BYTESPERWORKER = PEAKFACTOR x the largest recording's cache
%   file plus WORKEROVERHEAD for the MATLAB process itself, and RESERVE is
%   left over for the app and the system. Starting more workers than that
%   would push the machine into swapping, which is slower than running
%   them one at a time. Where free memory cannot be read, two workers are
%   used.
%
%   WHY THERE IS A FLOOR (MINPERWORKER) under that budget. The recording's
%   size predicts the cost of a step that copies the data, and predicts
%   nothing about a step whose cost is the model it builds: a source
%   estimate's leadfield, or a deconvolution's time-expanded design, are the
%   same size whether the recording is 10 MB or 1 GB. A Chapter3 branch
%   (Filter, Deconvolve, Brain3D, Measure) on 17 MB recordings was budgeted
%   1.55 GB a worker and observed to peak near 6 GB, so eight cores' worth
%   of workers asked for some 50 GB on a 24 GB machine and the whole machine
%   stalled in swap. The floor makes the estimate wrong in the safe
%   direction; replayBranchOnTargets then checks the free memory again
%   before it starts each recording, which is what catches the case where
%   even the floor is optimistic.
%
%   MEASURED on the RIFT workspace (subject 1's eight-step branch replayed
%   onto nine recordings of 0.38 to 0.68 GB, 8 cores, 24 GB): one MATLAB
%   replaying alone took 3.4 GB at its peak, which is what the budget gives
%   the largest recording (3 x 0.68 GB + 1.5 GB). Nine recordings took 364 s
%   one at a time, 215 s on three workers (plus 13 s to start the pool the
%   first time) and 201 s on four, with 5.4 and 3.3 GB left free. The gain
%   flattens because much of the one-at-a-time run was already parallel:
%   CoherenceMap's FFTs, the largest step, run on all cores in the app, and
%   the rest is dominated by writing some 2.3 GB of cache per recording.
%
%   Name-value pairs replace what it would otherwise look up, for tests:
%   'Parallel', 'MaxWorkers', 'HaveToolbox', 'Cores', 'AvailableBytes' and
%   'FileBytes' (one per target).
%
%   See also REPLAYBRANCHONTARGETS, ALAKAZAMSETTINGS.
    PEAKFACTOR = 3;          % peak memory of one replay, in multiples of its cache file
    WORKEROVERHEAD = 1.5e9;  % bytes: a worker MATLAB with the toolboxes loaded
    RESERVE = 2e9;           % bytes kept free for the app and the system
    MINPERWORKER = 4e9;      % bytes: the least a worker is ever assumed to need

    targetFiles = cellstr(targetFiles);
    p = inputParser;
    p.addParameter('Parallel', []);
    p.addParameter('MaxWorkers', []);
    p.addParameter('HaveToolbox', []);
    p.addParameter('Cores', []);
    p.addParameter('AvailableBytes', []);
    p.addParameter('FileBytes', []);
    p.parse(varargin{:});
    o = p.Results;

    if isempty(o.Parallel)
        o.Parallel = logical(AlakazamSettings.get('processing', 'applyToAll', 'parallel'));
    end
    if isempty(o.MaxWorkers)
        o.MaxWorkers = double(AlakazamSettings.get('processing', 'applyToAll', 'maxWorkers'));
    end
    if isempty(o.HaveToolbox)
        o.HaveToolbox = license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
    end

    n = 1;
    if ~o.Parallel || ~o.HaveToolbox || numel(targetFiles) < 2
        return;
    end

    if isempty(o.Cores)
        o.Cores = feature('numcores');
    end
    if isempty(o.AvailableBytes)
        o.AvailableBytes = availableMemory();
    end
    if isempty(o.FileBytes)
        o.FileBytes = cellfun(@fileBytes, targetFiles);
    end

    if isfinite(o.AvailableBytes)
        perWorker = max(MINPERWORKER, PEAKFACTOR * max(o.FileBytes) + WORKEROVERHEAD);
        byMemory = floor((o.AvailableBytes - RESERVE) / perWorker);
    else
        byMemory = 2;
    end
    n = min([numel(targetFiles), o.Cores, byMemory]);
    if o.MaxWorkers > 0
        n = min(n, round(o.MaxWorkers));
    end
    n = max(1, n);
end

function bytes = fileBytes(file)
    info = dir(file);
    if isempty(info)
        bytes = 0;
    else
        bytes = info.bytes;
    end
end
