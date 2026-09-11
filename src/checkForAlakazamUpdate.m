function info = checkForAlakazamUpdate(fetchLatestRelease)
%CHECKFORALAKAZAMUPDATE  Ask GitHub whether a newer Alakazam release exists.
%   INFO = checkForAlakazamUpdate() queries the GitHub Releases API for this
%   repository's latest published release and compares its tag against the
%   version this copy reports (ALAKAZAMVERSION), returning a scalar struct:
%
%     CheckSucceeded   true if the API answered with a usable release (false
%                      on no network, a GitHub outage, or a response with no
%                      .zip asset -- callers show "couldn't check" for all
%                      of these rather than an error dialog)
%     UpdateAvailable  true if the release outnumbers the running version
%                      (only meaningful when CheckSucceeded)
%     CurrentVersion   alakazamVersion().Version, for display
%     LatestVersion    the release's own tag (e.g. 'V0.5.0')
%     DownloadUrl      the .zip asset's browser_download_url
%     Notes            the release body (Markdown, shown as plain text --
%                      short enough not to be worth rendering)
%
%   FETCHLATESTRELEASE, optional, is a zero-argument function handle
%   returning a struct shaped like webread's parse of the GitHub API
%   response. Every real caller omits it and gets the default (a live
%   webread against the actual API); it exists so tests can supply a canned
%   response instead of depending on the network and this repository's own
%   release history.
%
%   Only called from Alakazam.onUpdate -- a button someone presses by hand.
%   There is deliberately no startup or timer-driven call anywhere in this
%   app: checking for an update is something the analyst asks for, not
%   something that happens to them while they are trying to work.
%
%   See also ALAKAZAMVERSION, ISALAKAZAMVERSIONNEWER, ALAKAZAM/ONUPDATE,
%   DOWNLOADALAKAZAMUPDATE.

    if nargin < 1
        fetchLatestRelease = @() webread( ...
            'https://api.github.com/repos/markspan/Alakazam/releases/latest', ...
            weboptions('Timeout', 10, 'ContentType', 'json'));
    end

    info = struct( ...
        'CheckSucceeded',  false, ...
        'UpdateAvailable', false, ...
        'CurrentVersion',  alakazamVersion().Version, ...
        'LatestVersion',   '', ...
        'DownloadUrl',     '', ...
        'Notes',           '');

    try
        release = fetchLatestRelease();
    catch
        return;   % no network, API rate limit, GitHub outage: not an error
    end

    if ~isstruct(release) || ~isfield(release, 'tag_name') || ~isfield(release, 'assets')
        return;   % unexpected shape; treat like any other failed check
    end

    assets = release.assets;
    if isstruct(assets) && ~isempty(assets)
        isZip = arrayfun(@(a) isfield(a, 'name') && isfield(a, 'browser_download_url') ...
            && endsWith(a.name, '.zip'), assets);
        assets = assets(isZip);
    else
        assets = assets([]);
    end
    if isempty(assets)
        return;   % a release with no downloadable package (e.g. a draft)
    end

    info.CheckSucceeded  = true;
    info.LatestVersion   = release.tag_name;
    info.DownloadUrl     = assets(1).browser_download_url;
    if isfield(release, 'body')
        info.Notes = release.body;
    end
    info.UpdateAvailable = isAlakazamVersionNewer(info.LatestVersion, info.CurrentVersion);
end
