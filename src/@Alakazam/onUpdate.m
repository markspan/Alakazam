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
%   PATH SHADOWING. alakazamVersion, like everything else this app calls, is
%   a plain function resolved by the MATLAB path -- not by which install's
%   window asked. Launching a second copy of Alakazam in the same MATLAB
%   session, rather than quitting MATLAB and reopening it from the new
%   install, can leave two folders' alakazamVersion.m on the path at once;
%   whichever one MATLAB finds first answers, regardless of which window
%   this callback is running for. shadowNote below detects exactly that (the
%   answer did not come from THIS instance's own RootDir) and appends a
%   warning rather than silently showing an unreliable comparison.
%
%   See also CHECKFORALAKAZAMUPDATE, DOWNLOADALAKAZAMUPDATE, ALAKAZAM/ONABOUT.

    [restoreBusy, ~] = beginBusy(this.MainFigure, 'Checking for updates...'); %#ok<ASGLU>
    info = checkForAlakazamUpdate();
    clear restoreBusy;   % dismiss the overlay BEFORE any dialog below

    note = shadowNote(this);

    if ~info.CheckSucceeded
        uialert(this.MainFigure, ...
            'I wasn''t able to reach GitHub to check for an update. Check your internet connection and try again.', ...
            'Update Alakazam', 'Icon', 'warning');
        return;
    end

    if ~info.UpdateAvailable
        uialert(this.MainFigure, ...
            withNote(sprintf('You are up to date (%s).', info.CurrentVersion), note), ...
            'Update Alakazam', 'Icon', 'success');
        return;
    end

    prompt = sprintf('%s is available (you have %s).', info.LatestVersion, info.CurrentVersion);
    if ~isempty(strtrim(info.Notes))
        prompt = sprintf('%s\n\n%s', prompt, info.Notes);
    end
    selection = uiconfirm(this.MainFigure, withNote(prompt, note), 'Update Alakazam', ...
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

% ======================================================================= %
function note = shadowNote(this)
%SHADOWNOTE  '' normally; a warning when alakazamVersion (as MATLAB will
%   actually resolve it) does not live under THIS.ROOTDIR -- see this file's
%   own header for why that can happen and what it means for the check that
%   just ran.
    matches = which('alakazamVersion', '-all');
    if numel(matches) <= 1 || strcmpi(fileparts(matches{1}), this.RootDir)
        note = '';
        return;
    end
    note = ['Note: another copy of Alakazam is also on the MATLAB path in this ' ...
        'session, so this answer may be about that copy rather than this one. ' ...
        'Quit MATLAB and reopen it from this install to be sure.'];
end

% ======================================================================= %
function message = withNote(message, note)
    if ~isempty(note)
        message = sprintf('%s\n\n%s', message, note);
    end
end
