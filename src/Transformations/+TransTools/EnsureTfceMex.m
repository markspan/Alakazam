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
%   on Windows, so this genuinely fails for some users, hence the fallback.
%   The build result is cached for the session: a failed build must not be
%   retried on every permutation.
%
%   THE CACHE IS RE-VALIDATED, NOT TRUSTED BLINDLY. What makes the kernel
%   usable is not the build, it is src/mex/bin sitting on the path, and a
%   cached TRUE remembers only the first of those. matlab.unittest's
%   PathFixture restores a path snapshot when a test class tears down, so a
%   class that ran earlier can take the folder away from every class that
%   follows. The stale TRUE then promises a kernel that is no longer
%   callable and TFCESCORE, which trusts that promise by design, dies on a
%   bare "Undefined function 'alakazam_tfce'" deep inside a permutation.
%   That is not the documented fallback, it is a crash. So the answer is
%   re-checked on every call, which costs one EXIST, and the folder is put
%   back when it has gone. Same hazard, same cure, as
%   TRANSTOOLS.ENSUREGIFTIREADER.
%
%   See also TRANSTOOLS.TFCESCORE, TRANSTOOLS.ENSUREGIFTIREADER,
%   SOURCECLUSTERSTATS.
    persistent state

    binDir = fullfile(mexRoot(), 'bin');

    if ~isempty(state)
        if state && ~kernelCallable()
            % Built before, since dropped off the path. Put it back, and
            % believe the re-check over the cache: the binary itself may
            % have gone too, in which case FALSE is the honest answer and
            % the caller falls back as it would on a machine without a
            % compiler.
            state = addKernelToPath(binDir);
        end
        ok = state;
        return;
    end

    if addKernelToPath(binDir)
        state = true; ok = true;
        return;
    end

    try
        if ~exist(binDir, 'dir')
            mkdir(binDir);
        end
        mex('-O', '-outdir', binDir, fullfile(mexRoot(), 'alakazam_tfce.c'));
        state = addKernelToPath(binDir);
    catch
        % No compiler, or a build failure. Not an error: see the header.
        state = false;
    end
    ok = state;
end

function tf = kernelCallable()
%KERNELCALLABLE  Whether alakazam_tfce can be called right now, which is
%   what "usable" means and the one thing a cached flag cannot know.
    tf = exist('alakazam_tfce', 'file') ~= 0;
end

function ok = addKernelToPath(binDir)
%ADDKERNELTOPATH  Put the built kernel's folder on the path when the binary
%   is there, and report whether the kernel is callable afterwards.
%   Guarded on the file so that a missing folder does not warn.
    if exist(fullfile(binDir, ['alakazam_tfce.' mexext]), 'file')
        addpath(binDir);
    end
    ok = kernelCallable();
end

function root = mexRoot()
%MEXROOT  src/mex, from this file's own location (src/Transformations/+TransTools).
    here = fileparts(mfilename('fullpath'));
    root = fullfile(fileparts(fileparts(here)), 'mex');
end
