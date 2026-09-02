function ok = EnsureTfceMex()
%ENSURETFCEMEX  Make the compiled TFCE kernel callable, building it once if
%   it is missing and a compiler is available.
%
%   OK = EnsureTfceMex() returns whether alakazam_tfce is usable. Callers
%   are expected to fall back to FieldTrip's own TFCE when it is not: the
%   fallback is the same answer, only slower, so a machine without a
%   compiler loses speed and nothing else. That is why this returns a flag
%   rather than throwing.
%
%   BUILT ON FIRST USE, NOT SHIPPED PRECOMPILED, because a .mexw64 in the
%   repository is a binary nobody reviews, is wrong for macOS and Linux,
%   and goes stale against the source beside it. MATLAB ships no compiler
%   on Windows, so this genuinely fails for some users -- hence the
%   fallback. The result is cached for the session: a failed build must not
%   be retried on every permutation.
%
%   See also TRANSTOOLS.TFCESCORE, SOURCECLUSTERSTATS.
    persistent state
    if ~isempty(state)
        ok = state;
        return;
    end

    binDir = fullfile(mexRoot(), 'bin');
    if exist(fullfile(binDir, ['alakazam_tfce.' mexext]), 'file')
        addpath(binDir);
        state = true; ok = true;
        return;
    end

    try
        if ~exist(binDir, 'dir')
            mkdir(binDir);
        end
        mex('-O', '-outdir', binDir, fullfile(mexRoot(), 'alakazam_tfce.c'));
        addpath(binDir);
        state = true;
    catch
        % No compiler, or a build failure. Not an error: see the header.
        state = false;
    end
    ok = state;
end

function root = mexRoot()
%MEXROOT  src/mex, from this file's own location (src/Transformations/+TransTools).
    here = fileparts(mfilename('fullpath'));
    root = fullfile(fileparts(fileparts(here)), 'mex');
end
