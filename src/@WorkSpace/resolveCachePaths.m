function [id, matfilename, rawfilename] = resolveCachePaths(this, name)
%RESOLVECACHEPATHS  The cache-id / cached-.mat-path / raw-source-path
%   triple every per-format loader (loadBVAFile/loadSETFile/loadMATFile/
%   loadERPFile) derives from a raw filename the same way.
%
%   Uses fullfile, not strcat: RawDirectory/CacheDirectory are only
%   guaranteed to end in a path separator when read from a .wksp file
%   that happened to store them that way -- WorkSpace's own constructor's
%   fallback-defaults path (reached whenever the target .wksp is missing
%   or unreadable) builds them with fullfile, which does NOT add a
%   trailing separator. strcat blindly concatenating a separator-less
%   directory with a bare filename previously produced a malformed path
%   silently (e.g. "...\Data\EEGexample1.vhdr" instead of
%   "...\Data\EEG\example1.vhdr") -- open.m's own dir() calls then simply
%   matched nothing, so a fresh install or a custom workspace name could
%   open with a silently empty tree and no error at all. Duplicated,
%   inconsistently, across all four loaders; consolidated here.
    [~, id, ~] = fileparts(name);
    matfilename = fullfile(this.CacheDirectory, [id '.mat']);
    rawfilename = fullfile(this.RawDirectory, name);
end
