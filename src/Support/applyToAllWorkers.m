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
%   Name-value pairs replace what it would otherwise look up, for tests:
%   'Parallel', 'MaxWorkers', 'HaveToolbox', 'Cores', 'AvailableBytes' and
%   'FileBytes' (one per target).
%
%   See also REPLAYBRANCHONTARGETS, ALAKAZAMSETTINGS.
    PEAKFACTOR = 3;          % peak memory of one replay, in multiples of its cache file
    WORKEROVERHEAD = 1.5e9;  % bytes: a worker MATLAB with the toolboxes loaded
    RESERVE = 2e9;           % bytes kept free for the app and the system

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
        perWorker = PEAKFACTOR * max(o.FileBytes) + WORKEROVERHEAD;
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

function bytes = availableMemory()
%AVAILABLEMEMORY  Free physical memory in bytes, or NaN when it cannot be read.
    bytes = NaN;
    try
        if ispc
            [~, sys] = memory;
            bytes = sys.PhysicalMemory.Available;
        elseif isfile('/proc/meminfo')
            txt = fileread('/proc/meminfo');
            kb = regexp(txt, 'MemAvailable:\s*(\d+)', 'tokens', 'once');
            if ~isempty(kb)
                bytes = str2double(kb{1}) * 1024;
            end
        end
    catch
        bytes = NaN;
    end
end
