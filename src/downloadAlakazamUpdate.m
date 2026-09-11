function pendingPath = downloadAlakazamUpdate(info, currentRoot)
%DOWNLOADALAKAZAMUPDATE  Fetch and stage a newer Alakazam release.
%   PENDINGPATH = downloadAlakazamUpdate(INFO, CURRENTROOT), where INFO is a
%   struct from CHECKFORALAKAZAMUPDATE and CURRENTROOT is the running app's
%   own repository root (Alakazam.RepoRoot: the folder holding
%   startAlakazam.m, src/, Data/, ...), downloads INFO.DownloadUrl and
%   unpacks it into "AlakazamUpdatePending", a FIXED-NAME sibling folder of
%   CURRENTROOT -- replacing anything already staged there from an earlier,
%   unapplied download.
%
%   NOT APPLIED YET. This only stages the download; CURRENTROOT itself is
%   untouched, so this running session keeps working exactly as before no
%   matter how the download goes. The swap into CURRENTROOT happens the next
%   time startAlakazam runs (see APPLYPENDINGALAKAZAMUPDATE), which is also
%   where Data/ and any *.wksp workspace files get carried across -- not
%   here, so a download taken today and applied next week carries next
%   week's copy of those, not today's.
%
%   WHY NOT APPLY IT NOW. CURRENTROOT is on this MATLAB process's path right
%   now, with its classdefs already loaded -- Alakazam itself is a live
%   instance of one of them. Overwriting those files under a running session
%   risks leaving MATLAB in a confused state until `clear classes`, which
%   this call cannot safely do to itself. Staging now and swapping in on the
%   next ordinary restart costs nothing an analyst was not already doing
%   (quitting and reopening MATLAB) and never touches a file this process
%   has open.
%
%   A FIXED PENDING-FOLDER NAME, NOT ONE PER VERSION: at most one staged
%   download exists at a time, so clicking Update again before restarting
%   just replaces what was staged, rather than accumulating a new sibling
%   folder per release.
%
%   Throws (rather than returning an error struct) on any failure: the
%   caller, Alakazam.onUpdate, is a single button-press handler that already
%   wraps this in try/catch to show ME.message in a uialert.
%
%   See also CHECKFORALAKAZAMUPDATE, APPLYPENDINGALAKAZAMUPDATE,
%   ALAKAZAM/ONUPDATE.

    if ~info.CheckSucceeded || isempty(info.DownloadUrl)
        error('downloadAlakazamUpdate:NoDownloadUrl', ...
            'No download URL for this release -- run checkForAlakazamUpdate first.');
    end

    % Fixed name: must match the sibling applyPendingAlakazamUpdate (at the
    % repository root, not here) looks for. Kept as a literal in both rather
    % than a shared function, because that one runs before src/ -- where
    % this function lives -- is even on the path; AlakazamPendingUpdatePath
    % TestConsistency (tests/) pins the two literals to match.
    pendingPath = fullfile(fileparts(currentRoot), 'AlakazamUpdatePending');
    if isfolder(pendingPath)
        rmdir(pendingPath, 's');   % a stale, unapplied download from earlier
    end

    zipPath = [tempname() '.zip'];
    cleanupZip = onCleanup(@() deleteIfExists(zipPath)); %#ok<NASGU>
    websave(zipPath, info.DownloadUrl);

    stagingDir = tempname();
    unzip(zipPath, stagingDir);
    cleanupStaging = onCleanup(@() deleteIfExists(stagingDir)); %#ok<NASGU>

    % The release workflow zips exactly one top-level folder (stage/<name>,
    % see release.yml), so the extraction has exactly one top-level entry --
    % anything else means this was not an Alakazam release package.
    entries = dir(stagingDir);
    entries = entries([entries.isdir] & ~ismember({entries.name}, {'.', '..'}));
    if numel(entries) ~= 1
        error('downloadAlakazamUpdate:UnexpectedLayout', ...
            'The downloaded package does not look like an Alakazam release.');
    end
    movefile(fullfile(stagingDir, entries(1).name), pendingPath);
end

% ======================================================================= %
function deleteIfExists(path)
%DELETEIFEXISTS  Best-effort cleanup of a temp file or folder; never throws,
%   since this only ever runs from an onCleanup and an update that otherwise
%   succeeded should not fail over a leftover temp file.
    try
        if exist(path, 'file') == 2
            delete(path);
        elseif exist(path, 'dir') == 7
            rmdir(path, 's');
        end
    catch
    end
end
