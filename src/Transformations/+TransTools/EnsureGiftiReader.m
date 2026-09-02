function EnsureGiftiReader()
%ENSUREGIFTIREADER  Make sure ft_read_headshape can actually read a .gii.
%
%   ft_read_headshape needs FieldTrip's bundled gifti toolbox to read a
%   .surf.gii, and FieldTrip adds that folder to the path lazily, on first
%   use, via ft_hastoolbox -- which then CACHES that it has done so in a
%   persistent variable. If anything removes the folder afterwards,
%   ft_hastoolbox still believes it is loaded and never re-adds it, and the
%   next read fails with a bare "Undefined function 'gifti'".
%
%   THAT IS NOT HYPOTHETICAL, and it has now bitten twice. matlab.unittest's
%   PathFixture restores the path when a test class tears down, so a class
%   that reads a template surface leaves the NEXT class unable to read the
%   same file it had just read successfully. The failure appears in innocent
%   code, in a different file, and only when the classes run in a particular
%   order, which is the worst combination to debug from.
%
%   Checking costs one which() and makes any caller independent of
%   FieldTrip's own path bookkeeping. Every place that reads a template
%   surface should call this first, which is why it is one function rather
%   than a comment repeated at each call site.
%
%   See also TRANSTOOLS.BUILDSOURCEFORWARDMODEL, TRANSTOOLS.ENSUREFIELDTRIP.
    if ~isempty(which('gifti'))
        return;
    end
    ftRoot = fileparts(which('ft_defaults'));
    if isempty(ftRoot)
        return;   % no FieldTrip at all: the caller's own check reports that
    end
    addpath(fullfile(ftRoot, 'external', 'gifti'));
end
