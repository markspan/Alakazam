function onUpdate(this)
%ONUPDATE  Ribbon callback ('update'): check GitHub for a newer release and
%   offer to download it.
%
%   Click-only, deliberately. There is no startup check and no background
%   timer anywhere that calls checkForAlakazamUpdate -- an analyst mid-
%   analysis should never see a surprise dialog about a new version; this
%   only ever runs because they pressed the Update button in the About
%   group themselves.
%
%   Downloading does not touch this running install: downloadAlakazamUpdate
%   stages the new release in a sibling folder and this only ever reports
%   where it landed. See that function's own header for why it does not
%   overwrite CURRENTROOT or relaunch the app.
%
%   See also CHECKFORALAKAZAMUPDATE, DOWNLOADALAKAZAMUPDATE, ALAKAZAM/ONABOUT.

    [restoreBusy, ~] = beginBusy(this.MainFigure, 'Checking for updates...'); %#ok<ASGLU>
    info = checkForAlakazamUpdate();
    clear restoreBusy;   % dismiss the overlay BEFORE any dialog below

    if ~info.CheckSucceeded
        uialert(this.MainFigure, ...
            'I wasn''t able to reach GitHub to check for an update. Check your internet connection and try again.', ...
            'Update Alakazam', 'Icon', 'warning');
        return;
    end

    if ~info.UpdateAvailable
        uialert(this.MainFigure, ...
            sprintf('You are up to date (%s).', info.CurrentVersion), ...
            'Update Alakazam', 'Icon', 'success');
        return;
    end

    prompt = sprintf('%s is available (you have %s).', info.LatestVersion, info.CurrentVersion);
    if ~isempty(strtrim(info.Notes))
        prompt = sprintf('%s\n\n%s', prompt, info.Notes);
    end
    selection = uiconfirm(this.MainFigure, prompt, 'Update Alakazam', ...
        'Options', {'Download', 'Not now'}, 'DefaultOption', 1, 'CancelOption', 2, ...
        'Icon', 'info');
    if ~strcmp(selection, 'Download')
        return;
    end

    [restoreBusy, ~] = beginBusy(this.MainFigure, ...
        sprintf('Downloading %s...', info.LatestVersion)); %#ok<ASGLU>
    try
        newRoot = downloadAlakazamUpdate(info, this.RepoRoot);
    catch ME
        clear restoreBusy;
        uialert(this.MainFigure, ME.message, 'Could not download the update', 'Icon', 'warning');
        return;
    end
    clear restoreBusy;

    uialert(this.MainFigure, ...
        sprintf(['Downloaded %s to:\n%s\n\n' ...
                 'This running copy is untouched. Close Alakazam and run startAlakazam ' ...
                 'from that folder when you are ready to switch to it.'], ...
            info.LatestVersion, newRoot), ...
        'Update downloaded', 'Icon', 'success');
end
