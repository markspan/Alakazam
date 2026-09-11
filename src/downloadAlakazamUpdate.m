function newRoot = downloadAlakazamUpdate(info, currentRoot)
%DOWNLOADALAKAZAMUPDATE  Fetch and stage a newer Alakazam release.
%   NEWROOT = downloadAlakazamUpdate(INFO, CURRENTROOT), where INFO is a
%   struct from CHECKFORALAKAZAMUPDATE and CURRENTROOT is the running app's
%   own repository root (Alakazam.RepoRoot: the folder holding
%   startAlakazam.m, src/, Data/, ...), downloads INFO.DownloadUrl and
%   unpacks it into a SIBLING folder of CURRENTROOT named after the new
%   release (e.g. "...\Alakazam-V0.5.0"), then copies this install's Data/
%   folder and any *.wksp workspace files at its root into it -- neither is
%   part of the packaged zip (see .github/workflows/release.yml's own
%   exclusion check), so the new install would otherwise come up with no
%   data and no saved workspace to open.
%
%   WHY A SIBLING FOLDER, NOT IN PLACE. CURRENTROOT is on this MATLAB
%   process's path right now, with its classdefs already loaded -- Alakazam
%   itself is a live instance of one of them. Deleting or overwriting those
%   files under a running session risks leaving MATLAB in a confused state
%   until `clear classes`, which this call cannot safely do to itself.
%   Staging beside the current install and asking the analyst to relaunch
%   startAlakazam from there costs one extra step but never touches a file
%   this process has open. CURRENTROOT itself is never modified, so nothing
%   here can lose an analyst's existing install or data even if the update
%   is abandoned partway through.
%
%   Throws (rather than returning an error struct) on any failure: the
%   caller, Alakazam.onUpdate, is a single button-press handler that already
%   wraps this in try/catch to show ME.message in a uialert.
%
%   See also CHECKFORALAKAZAMUPDATE, ALAKAZAM/ONUPDATE.

    if ~info.CheckSucceeded || isempty(info.DownloadUrl)
        error('downloadAlakazamUpdate:NoDownloadUrl', ...
            'No download URL for this release -- run checkForAlakazamUpdate first.');
    end

    parentDir  = fileparts(currentRoot);
    targetName = ['Alakazam-' info.LatestVersion];
    newRoot    = fullfile(parentDir, targetName);
    if exist(newRoot, 'dir')
        error('downloadAlakazamUpdate:AlreadyStaged', ...
            ['"%s" already exists. Delete it (if it is a leftover from a previous ' ...
             'download) or launch startAlakazam from there.'], newRoot);
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
    movefile(fullfile(stagingDir, entries(1).name), newRoot);

    dataDir = fullfile(currentRoot, 'Data');
    if exist(dataDir, 'dir')
        copyfile(dataDir, fullfile(newRoot, 'Data'));
    end
    workspaceFiles = dir(fullfile(currentRoot, '*.wksp'));
    for k = 1:numel(workspaceFiles)
        copyfile(fullfile(currentRoot, workspaceFiles(k).name), ...
            fullfile(newRoot, workspaceFiles(k).name));
    end
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
