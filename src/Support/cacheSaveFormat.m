function args = cacheSaveFormat(bytes)
%CACHESAVEFORMAT  The save() flags a cache file of BYTES should be written with.
%   ARGS = cacheSaveFormat(BYTES) is {'-v7', '-nocompression'} when a
%   variable that size fits in a version 7 MAT-file, and
%   {'-v7.3', '-nocompression'} when it does not.
%
%   NEVER COMPRESSED, and this is the whole point. Measured on a real
%   recording, a 65-channel hour at 512 Hz, 543 MB in memory:
%
%       format                   save      size      load
%       -v7 (compressed)         11.2 s    510 MB    2.7 s
%       -v7 -nocompression        1.1 s    563 MB    0.2 s
%       -v7.3 (compressed)       20.4 s    527 MB    4.4 s
%       -v7.3 -nocompression      3.9 s    578 MB    2.4 s
%
%   Compression bought a tenth off the file and cost ten times the save
%   and thirteen times the load. EEG is noisy floating point, and noise is
%   precisely what a general-purpose compressor cannot shrink, so the CPU
%   was being spent for almost nothing. A cache is written once and read
%   many times, and read in the middle of someone clicking through a tree,
%   so it is the read that matters most and the read gained the most.
%
%   VERSION 7 WHERE IT FITS, because it is the fastest by a wide margin in
%   both directions. It cannot hold a single variable of 2 GB or more,
%   which is why the importers used -v7.3 unconditionally: a long
%   high-density recording does cross that line. So the choice is made by
%   size instead, with a margin under the limit, and only the files that
%   genuinely need -v7.3 pay for it. Even they come out five times faster
%   than they did compressed.
%
%   Separated out so the threshold can be tested without building a
%   two-gigabyte struct to find out which side of it you are on.
%
%   See also SAVEEEGCACHE.
    arguments
        bytes (1, 1) double {mustBeNonnegative}
    end

    % 2^31 bytes is the version 7 per-variable limit. A margin, because the
    % size whos reports is the in-memory size, and the file adds headers.
    if bytes < 1.9e9
        args = {'-v7', '-nocompression'};
    else
        args = {'-v7.3', '-nocompression'};
    end
end
