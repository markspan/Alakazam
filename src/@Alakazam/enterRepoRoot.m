function restoreDir = enterRepoRoot(this)
%ENTERREPOROOT  cd to RepoRoot for the duration of the caller's own scope,
%   restoring the previous working directory on exit (including on error).
%   Run from the repository root (historic behaviour): individual plugins
%   may resolve resources relative to it.
%
%   RESTOREDIR is an onCleanup object; assign it to a local variable in
%   the calling method (`restoreDir = this.enterRepoRoot();`) -- its
%   restore-on-exit only fires once THAT variable goes out of scope, not
%   this helper's own (which returns immediately), so it must be kept
%   alive in the caller, not just called for its side effect. Previously
%   this exact two-line `cd`/`onCleanup` pair was duplicated identically
%   in onTransformation.m, onNodeDropped.m, onApplyToAllRawFiles.m,
%   onApplyTemplate.m and recalculateTransformNode.m; consolidated here.
    originalDir = cd(this.RepoRoot);
    restoreDir  = onCleanup(@() cd(originalDir));
end
