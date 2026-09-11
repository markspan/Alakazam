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
%   only stages the new release in a fixed sibling folder. Applying it is
%   applyPendingAlakazamUpdate's job, run from startAlakazam on the next
%   ordinary restart -- see that function's own header for why it happens
%   there and not here. All this callback tells the analyst is to restart
%   when they are ready; there is nothing to go find or launch by hand.
%
%   PATH SHADOWING. alakazamVersion, like everything else this app calls, is
%   a plain function resolved by the MATLAB path -- not by which install's
%   window asked. This is a much narrower risk now that an update applies
%   itself on the next ordinary restart rather than asking the analyst to
%   launch a second, differently-named install folder by hand -- but running
%   two copies in the same MATLAB session at all (say, a developer comparing
%   installs deliberately) can still leave two folders' alakazamVersion.m on
%   the path at once; whichever one MATLAB finds first answers, regardless
%   of which window this callback is running for. shadowNote below detects
%   exactly that (the answer did not come from THIS instance's own RootDir)
%   and appends a warning rather than silently showing an unreliable
%   comparison.
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
        downloadAlakazamUpdate(info, this.RepoRoot);
    catch ME
        clear restoreBusy;
        uialert(this.MainFigure, ME.message, 'Could not download the update', 'Icon', 'warning');
        return;
    end
    clear restoreBusy;

    % Applying it is startAlakazam's job, next launch (see
    % applyPendingAlakazamUpdate), not this call's: this running copy is on
    % the MATLAB path with its classdefs already loaded, and overwriting
    % those files under a live session is what the sibling staging folder
    % exists to avoid. So the only thing left to tell the analyst is to
    % restart the ordinary way -- there is no folder to go find and launch
    % from any more.
    uialert(this.MainFigure, ...
        sprintf(['Downloaded %s. Quit Alakazam and run startAlakazam again ' ...
                 '(the usual way) to finish installing it.'], info.LatestVersion), ...
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
