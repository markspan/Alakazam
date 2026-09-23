function bytes = availableMemory()
%AVAILABLEMEMORY  Free physical memory in bytes, or NaN when it cannot be read.
%   Windows reads it from `memory`, Linux from /proc/meminfo's MemAvailable.
%   Anywhere else, and on any failure, it is NaN, which every caller must
%   treat as "unknown" rather than as "none": refusing to do anything on a
%   machine whose memory cannot be read would be worse than proceeding.
%
%   IT IS A SHARED FILE because two callers need the same answer about the
%   same machine at two different moments: applyToAllWorkers decides how many
%   recordings to start at once before the batch begins, and
%   replayBranchOnTargets checks again before it starts each one, since the
%   first estimate is only as good as its guess about what a branch costs.
%
%   See also APPLYTOALLWORKERS, REPLAYBRANCHONTARGETS.
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
