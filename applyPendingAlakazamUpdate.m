function applied = applyPendingAlakazamUpdate(here)
%APPLYPENDINGALAKAZAMUPDATE  Swap in a downloaded-but-not-yet-applied update.
%   APPLIED = applyPendingAlakazamUpdate(HERE), where HERE is the repository
%   root (the folder holding startAlakazam.m), looks for a staged update at
%   HERE's sibling "AlakazamUpdatePending" (see downloadAlakazamUpdate, which
%   writes it there) and, if one is there and looks like a real release,
%   swaps it into HERE. Returns true if it did.
%
%   CALLED FROM STARTALAKAZAM, BEFORE ANYTHING FROM src/ IS ON THE PATH OR
%   LOADED, which is what makes this safe to do at all: no classdef this app
%   defines is live yet, so overwriting the files that define it cannot
%   leave a running instance confused about what it is. That is also why
%   this file lives at the repository root next to startAlakazam.m rather
%   than in src/ -- src/ is not on the path yet at the point this needs to
%   run, and this function's only caller needs it to be reachable exactly
%   when startAlakazam.m itself already is (same folder, same moment).
%
%   A FIXED-NAME SIBLING FOLDER, "AlakazamUpdatePending", not one named
%   after the version: at most one staged update exists at a time, so a
%   second Update click before the first is applied simply replaces it
%   (downloadAlakazamUpdate's own job), rather than piling up a new sibling
%   folder per release the way this used to work.
%
%   THE OLD INSTALL IS MOVED ASIDE, NOT DELETED, to "AlakazamPreUpdateBackup"
%   -- a fixed name too, so at most one backup is ever kept; applying a
%   second update replaces the first backup rather than accumulating them.
%   A broken update this way leaves a manual way back (copy
%   AlakazamPreUpdateBackup over HERE by hand) instead of none.
%
%   WHY THE SWAP MOVES CONTENTS, NOT THE WHOLE FOLDER. The obvious version --
%   movefile(here, backup) then movefile(pending, here) -- is wrong on
%   Windows specifically because HERE is the folder this very call chain is
%   executing from. Confirmed empirically before writing this: after the
%   first move, every file HERE had contained really did end up in BACKUP
%   (Data, VERSION, src/, even startAlakazam.m itself), but Windows would
%   not release the now-empty HERE directory entry while this process still
%   had it as part of its current execution context -- isfolder(here) kept
%   reporting true afterwards, pause() included. The second movefile then
%   found an EXISTING folder at HERE and moved PENDING inside it as a
%   subfolder instead of renaming it onto HERE -- silently, no error, and
%   Alakazam would have gone on running the OLD code with a half-applied
%   update sitting one level too deep to ever be found again. Moving
%   PENDING's own children into HERE one at a time, rather than moving
%   PENDING itself, sidesteps the question entirely: HERE, empty stub or
%   not, already exists as a real directory to move things into, and
%   movefile onto an existing target never has anywhere ambiguous to nest.
%
%   See also DOWNLOADALAKAZAMUPDATE, STARTALAKAZAM.
    applied = false;
    pending = fullfile(fileparts(here), 'AlakazamUpdatePending');
    if exist(fullfile(pending, 'startAlakazam.m'), 'file') ~= 2 || ...
            exist(fullfile(pending, 'VERSION'), 'file') ~= 2
        return;   % nothing staged, or an incomplete/corrupt stash: ignore either way
    end

    try
        backup = fullfile(fileparts(here), 'AlakazamPreUpdateBackup');
        if isfolder(backup)
            rmdir(backup, 's');   % a leftover from an earlier update; this session holds no lock on it
        end

        movefile(here, backup);
        if ~isfolder(here)
            mkdir(here);
        end
        entries = dir(pending);
        entries = entries(~ismember({entries.name}, {'.', '..'}));
        for k = 1:numel(entries)
            movefile(fullfile(pending, entries(k).name), fullfile(here, entries(k).name));
        end
        rmdir(pending, 's');

        % Data/ and *.wksp are not part of a release package (see
        % .github/workflows/release.yml's own exclusion check), so without
        % this the swapped-in install would come up with no data and no
        % saved workspace to open. Done here, at apply time, rather than
        % when the update was downloaded, so an update downloaded today and
        % applied next week carries today's Data/, not last week's.
        dataDir = fullfile(backup, 'Data');
        if isfolder(dataDir)
            copyfile(dataDir, fullfile(here, 'Data'));
        end
        workspaceFiles = dir(fullfile(backup, '*.wksp'));
        for k = 1:numel(workspaceFiles)
            copyfile(fullfile(backup, workspaceFiles(k).name), ...
                fullfile(here, workspaceFiles(k).name));
        end

        applied = true;
    catch ME
        warning('Alakazam:update:applyFailed', ...
            ['Could not apply the update staged in "%s" (%s). Starting from the ' ...
             'current install instead; the update will be tried again next launch.'], ...
            pending, ME.message);
    end
end
