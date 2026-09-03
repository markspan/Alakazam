function varargout = WithRestoredRng(fn)
%WITHRESTOREDRNG  Run FN and leave MATLAB's random number generator as found.
%
%   [A, B, ...] = WithRestoredRng(FN) calls FN() and restores the RNG state
%   afterwards, including rescuing it from legacy mode.
%
%   WHY THIS IS NEEDED AT ALL. EEGLAB's runica seeds itself with the old
%   rand('state', ...) syntax, which switches MATLAB into LEGACY random
%   number mode for the rest of the session. Legacy mode is not merely a
%   different stream: it makes rng() itself an error.
%
%       The current random number generator is the legacy generator. [...]
%       You may not use RNG to reseed the legacy random number generator.
%
%   So running an ICA breaks every later analysis in that MATLAB session
%   that seeds anything: the cluster permutation tests seed per run,
%   FieldTrip's own ft_preamble randomseed calls rng, and the source cluster
%   test draws a base seed for its parallel chunks. Nothing about the
%   failure points at ICA, because by then the ICA has long finished and
%   succeeded.
%
%   This was found when a new test that runs a real decomposition caused
%   fifty-two unrelated tests to fail in the same process, in files that had
%   nothing to do with ICA. In a test run the damage is visible; in a
%   working session, where a user might run ICA and then a cluster test, it
%   would surface as an inexplicable error from an unrelated feature.
%
%   rng('default') is what leaves legacy mode; the saved state is then
%   restored on top of it, so the caller's own reproducibility is preserved
%   rather than merely repaired.
%
%   See also REMOVECOMPONENTS, AUTOEYEICA.
    try
        state = rng;
    catch
        % Already in legacy mode when we were called: there is no state to
        % preserve, so restore to a defined one rather than to nothing.
        state = [];
    end
    restore = onCleanup(@() restoreState(state)); % released when this returns

    [varargout{1:nargout}] = fn();
end

% ======================================================================= %
function restoreState(state)
    rng('default');     % the only way out of legacy mode
    if ~isempty(state)
        rng(state);
    end
end
