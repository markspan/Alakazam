function info = checkForEEGLabUpdate(fetchLatestRelease, installedVersion)
%CHECKFOREEGLABUPDATE  Ask SCCN whether a newer EEGLAB release exists.
%   INFO = checkForEEGLabUpdate() compares the installed EEGLAB version
%   (EEG_GETVERSION) against the release SCCN currently advertises,
%   returning a scalar struct shaped like CHECKFORALAKAZAMUPDATE's:
%
%     CheckSucceeded   true if the query answered with a usable release
%                      (false on no network, an SCCN outage, or EEGLAB not
%                      being initialised -- callers show "couldn't check"
%                      for all of these rather than an error dialog)
%     UpdateAvailable  true if the advertised version differs from the
%                      installed one (only meaningful when CheckSucceeded)
%     CurrentVersion   eeg_getversion(), for display
%     LatestVersion    the advertised version (e.g. '2026.1.0')
%     DownloadUrl      the .zip for that release
%     Critical         true when SCCN flags the release as a critical fix
%     Notes            SCCN's own release notes
%
%   WHY NOT JUST CALL EEGLAB_UPDATE. EEGLAB ships its own updater, and it is
%   deliberately not used here. It is GUI-only throughout (questdlg2,
%   warndlg2, a supergui with a popupmenu for what to do with the old
%   folder), it cd's, it ends with evalin('base', 'eeglab'), it lives inside
%   the very install it replaces, and -- the decisive one -- it unzips into a
%   folder its own dialog chooses, which is how a 157 MB EEGLAB once landed
%   in the middle of this repository. Alakazam needs the version COMPARISON,
%   which is the small reusable half, and wants the install to go where
%   INSTALLFROMZIP puts things. So this function borrows only
%   plugin_getweb('update'), the same call eeglab_update itself uses to
%   discover the advertised release.
%
%   EEGLAB IS NEVER UPDATED ON ITS OWN. This is only ever reached from
%   Alakazam.onUpdate, as part of updating Alakazam itself: EEGLAB moves when
%   Alakazam moves, and not otherwise. Alakazam is validated against a
%   particular EEGLAB (see Docs/luck.md), so letting EEGLAB change underneath
%   a fixed Alakazam is how a working install quietly stops matching what was
%   tested -- which is exactly what happened when EEGLAB last updated itself
%   here and 37 test cases silently began skipping instead of running.
%
%   FETCHLATESTRELEASE, optional, is a zero-argument function handle
%   returning a struct with .version, .zip and (optionally) .critical and
%   .releasenotes. Every real caller omits it and gets the default (a live
%   plugin_getweb query); it exists so tests can supply a canned response
%   instead of depending on the network and on SCCN's release history.
%
%   INSTALLEDVERSION, optional, overrides eeg_getversion() as the version to
%   compare against. Also for tests, and for one case in particular: the
%   'dev' rule below can only be exercised on a machine whose EEGLAB is a
%   git checkout, so without this seam the test for it would skip on every
%   ordinary install -- and a skipped test is not a passing one.
%
%   See also CHECKFORALAKAZAMUPDATE, ALAKAZAM/ONUPDATE, EEGLABENVIRONMENT.

    if nargin < 1
        fetchLatestRelease = @defaultFetch;
    end

    info = struct( ...
        'CheckSucceeded',  false, ...
        'UpdateAvailable', false, ...
        'CurrentVersion',  '', ...
        'LatestVersion',   '', ...
        'DownloadUrl',     '', ...
        'Critical',        false, ...
        'Notes',           '');

    if nargin >= 2 && ~isempty(installedVersion)
        info.CurrentVersion = char(string(installedVersion));
    else
        try
            info.CurrentVersion = char(string(eeg_getversion()));
        catch
            return;   % EEGLAB not initialised: nothing to compare against
        end
    end

    try
        release = fetchLatestRelease();
    catch
        return;   % no network, SCCN outage: not an error
    end

    if ~isstruct(release) || isempty(release) ...
            || ~isfield(release, 'version') || ~isfield(release, 'zip')
        return;   % unexpected shape; treat like any other failed check
    end
    release = release(1);   % plugin_getweb can answer with several

    latest = char(string(release.version));
    zipUrl = char(string(release.zip));
    if isempty(latest) || isempty(zipUrl)
        return;
    end

    info.CheckSucceeded = true;
    info.LatestVersion  = latest;
    % SCCN has served this link over plain http in the past; eeglab_update
    % rewrites it the same way rather than trusting what it is handed.
    info.DownloadUrl    = strrep(zipUrl, 'http://', 'https://');
    if isfield(release, 'critical') && ~isempty(release.critical)
        info.Critical = logical(release.critical);
    end
    if isfield(release, 'releasenotes')
        info.Notes = char(string(release.releasenotes));
    end

    % A plain inequality, not a "which is bigger" comparison. EEGLAB's own
    % updater does the same (eeglab_update: ~isequal(update.version,
    % eeg_getversion)), because the advertised release is by definition the
    % one SCCN wants people on, and 'dev' does not order against anything.
    info.UpdateAvailable = ~strcmp(info.LatestVersion, info.CurrentVersion) ...
        && ~strcmpi(info.CurrentVersion, 'dev');
end

% ======================================================================= %
function release = defaultFetch()
%DEFAULTFETCH  The advertised release, via the call eeglab_update uses.
    if isempty(which('plugin_getweb'))
        error('Alakazam:checkForEEGLabUpdate:noEEGLab', ...
            'EEGLAB is not initialised, so its update feed cannot be queried.');
    end
    [~, release] = plugin_getweb('update', []);
end
