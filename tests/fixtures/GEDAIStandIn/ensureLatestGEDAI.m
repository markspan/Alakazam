function installed = ensureLatestGEDAI(varargin)
%ENSURELATESTGEDAI  A stand-in for Alakazam's GEDAI updater, for
%   AutoGEDAITest. Not the updater.
%
%   The real one asks GitHub for the newest release and puts it first on
%   the path, which in a test would reach the network and put the real
%   GEDAI in front of the stand-in beside this file. This one does neither:
%   it names the stand-in as the release to run, under a version no
%   release has, so a test can see that AutoGEDAI records what it is told.
%   The updater's options, which only tests pass, are ignored.
%
%   AutoGEDAITest copies it, with the GEDAI stand-in, to a temporary folder
%   first on the path. Never put this folder itself on the path.
%
%   See also AUTOGEDAI, AUTOGEDAITEST, ENSURELATESTGEDAITEST.

    installed = struct('Version', 'stand-in', 'Folder', fileparts(mfilename('fullpath')));
end
