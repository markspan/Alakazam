function startToolbox(root)
%STARTTOOLBOX  Run the Unfold toolbox's own init_unfold, quietly.
%   Unfold.startToolbox(ROOT) adds ROOT (the folder holding init_unfold.m)
%   to the path if it is not there, runs the toolbox's own initialiser, and
%   throws if uf_designmat is still unreachable afterwards. Shared by
%   Unfold.isAvailable and Unfold.ensure so the two
%   cannot start the toolbox differently.
%
%   WHY IT IS NOT JUST "init_unfold". Three things about the toolbox's own
%   initialiser have to be handled, all of them verified against tag 1.3.1
%   rather than assumed:
%
%   ITS FIRST ACT, IF EEGLAB IS ABSENT, IS "eeglab redraw", which opens
%   EEGLAB's own GUI window. Alakazam has EEGLAB on the path in any normal
%   session (EEGLabEnvironment), so the branch never runs, but a session
%   where it somehow did not would get a stray EEGLAB window out of a
%   transformation that never mentioned one. EEGLAB is therefore ensured
%   first, which is also what the Unfold functions need anyway: uf_epoch
%   calls into EEGLAB, and the toolbox's own warning says so.
%
%   IT PRINTS. "Starting unfold toolbox. Adding subfolders..." and a "Done."
%   belong to a user running it at the prompt, not to a transformation, so
%   the output is captured with evalc.
%
%   IT WARNS ABOUT WHAT ALAKAZAM DELIBERATELY DOES NOT INSTALL. Unfold keeps
%   three of its libraries as git submodules (lib/gramm, lib/eegvis,
%   lib/ept_TFCE), so a plain source archive carries them as empty folders.
%   All three are plotting or second-level statistics: Alakazam draws its
%   own figures and has its own cluster statistics (src/+ClusterStats), and
%   nothing in the fitting path (uf_designmat, uf_timeexpandDesignmat,
%   uf_glmfit, uf_condense) touches them, which is why the archive install
%   is enough and no git is required. init_unfold still addpaths one folder
%   inside the missing ept_TFCE tree, so MATLAB warns once about a
%   non-existent directory; that warning is expected here and is switched
%   off around the call rather than left to alarm a user about something
%   that is working as intended.
%
%   See also UNFOLD.ISAVAILABLE, UNFOLD.ENSURE.
    if nargin < 1 || isempty(root)
        root = fileparts(which('init_unfold.m'));
    end
    if isempty(root) || exist(fullfile(root, 'init_unfold.m'), 'file') ~= 2
        throw(MException('Alakazam:UnfoldMissing', ...
            ['I am afraid init_unfold.m could not be found, so the Unfold toolbox cannot be ' ...
             'started. Please reinstall it (Unfold.ensure) or add its folder to the ' ...
             'MATLAB path by hand.']));
    end

    % EEGLAB first, for the reason in the header: init_unfold falls back to
    % "eeglab redraw" when eeg_checkset is missing, and that opens a window.
    if isempty(which('eeg_checkset'))
        EEGLabEnvironment.ensure();
    end

    if isempty(which('init_unfold'))
        addpath(root);
    end

    previous = warning('off', 'MATLAB:mpath:nameNonexistentOrNotADirectory');
    restoreWarning = onCleanup(@() warning(previous));   % restores on return or on error
    evalc('init_unfold');

    if isempty(which('uf_designmat'))
        throw(MException('Alakazam:UnfoldMissing', sprintf( ...
            ['I am afraid the Unfold toolbox at\n\n    %s\n\nwas started but its own functions ' ...
             '(uf_designmat) are still not on the path, so the install looks incomplete. ' ...
             'Deleting that folder and letting Alakazam download it again is usually the ' ...
             'quickest fix.'], root)));
    end
end
