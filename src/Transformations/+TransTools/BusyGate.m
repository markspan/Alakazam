function BusyGate(action, varargin)
%BUSYGATE  Drive the app's busy indicator from inside a transformation,
%   when there is an app. ACTION is 'suspend', 'resume', or 'message' with
%   the new text:
%
%       TransTools.BusyGate('message', 'Building the head model...');
%
%   RELABELLING MATTERS for a transformation whose slow phase is not the
%   one the app's own generic "Running <id>..." names -- building a source
%   forward model, say, which takes twenty seconds before anything is
%   computed. Same reasoning as beginBusy's own updateFcn, but reachable
%   from inside a transformation, where beginBusy itself must NOT be called:
%   beginBusy opens the global gate and would seize it from the app.
%
%   A transformation invoked interactively opens its own options dialog,
%   and the app has already raised "Running <id>..." by then. That
%   indicator has to step aside for the dialog: on a local MATLAB the two
%   merely coexist untidily, but in MATLAB Online the modal progress dialog
%   covers the settings outright and has to be dismissed by hand before
%   anything can be entered. TransTools.InitGuard suspends it when a
%   transformation is entered interactively; TransformSettings.set resumes
%   it once the settings have been accepted and real work begins.
%
%   The indicator itself lives in src/Support/busyGate.m, which is part of
%   the UI layer. Transformations must stay runnable without that layer
%   loaded -- headless scripts and most of the test suite put only
%   src/Transformations on the path -- so its absence is a supported state
%   and this quietly does nothing.
%
%   Only a POSITIVE result is cached. Caching "not available" too would
%   latch the gate off for the rest of the MATLAB session the first time a
%   transformation ran without the UI layer on the path, and it would then
%   stay off even once the app had added it: found by the full test suite,
%   where an earlier headless transformation test disabled the indicator
%   for a later one that had set it up properly. Re-checking while absent
%   costs one exist() per call on a path MATLAB already caches, which is
%   nothing next to the transformation that follows it.
%
%   See also BUSYGATE, TRANSTOOLS.INITGUARD, TRANSFORMSETTINGS.
    persistent available
    if isempty(available) || ~available
        available = exist('busyGate', 'file') == 2;
    end
    if available
        busyGate(action, varargin{:});
    end
end
