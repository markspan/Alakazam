function rawclear(this, mode, ~)
%RAWCLEAR  "Clear WorkSpace": delete this workspace's cached analyses, in one
%   of two strengths the user chooses between.
%
%     NORMAL CLEAR removes every transformation result, and the grand
%     averages built only from this workspace's recordings, but keeps each
%     recording's own cache file: the recording as loaded from its raw file.
%     Reopening a subject is then quick, and this is what to do before
%     re-running a revised pipeline.
%
%     DEEP CLEAN removes that loaded copy too, so every recording is read
%     from its raw file again the next time it is opened.
%
%   RAWCLEAR(THIS, MODE) with MODE 'normal' or 'deep' skips the question,
%   for scripts and tests. Any other second argument (this used to be a
%   callback, so a graphics object can arrive here) is ignored and the
%   question is asked.
%
%   SCOPED TO THIS WORKSPACE. This used to be rmdir(CacheDirectory, 's'),
%   the whole cache folder, unconditionally. One cache is routinely shared
%   by several workspaces analysing different studies (eleven .wksp files in
%   this repository alone point at Data/Cache), so "Clear WorkSpace" in one
%   of them silently destroyed every other one's work as well, with a
%   confirmation dialog that gave no hint it would. Only data rooted on a
%   recording in this workspace's Raw directory belongs to it; the rules,
%   including for grand averages, are in clearWorkspaceCache.
%
%   See also CLEARWORKSPACECACHE, CHOOSEACTION.

    fig = this.Parent.MainFigure;
    nodes = this.Tree.allNodes();

    if nargin < 2 || ~(ischar(mode) || isstring(mode)) || isempty(char(mode))
        mode = askClearMode(fig, nodes);
        if isempty(mode)
            return;
        end
    end

    % gcf ignores this app's uifigure (it only tracks classic figures),
    % so it used to silently CREATE a new blank one here, exactly the
    % stray figure window users saw, which then sat on top of/stole
    % focus from MainFigure and made the app look hung. Use the app's
    % own window instead, restored via onCleanup so the busy indicator
    % can't get stuck if a delete or open throws partway through.
    restoreBusy = beginBusy(fig, 'Clearing cache...'); %#ok<NASGU>

    clearWorkspaceCache(nodes, this.CacheDirectory, mode, false);

    if exist(this.CacheDirectory, 'dir') ~= 7
        mkdir(this.CacheDirectory);   % only if it went missing entirely
    end
    open(this);
end

% ======================================================================= %
function mode = askClearMode(fig, nodes)
%ASKCLEARMODE  Ask whether to clear normally or deeply. Returns 'normal',
%   'deep', or '' when the user cancels.
    nRecordings = 0;
    for i = 1:numel(nodes)
        if nodes(i).IsRoot && ~isempty(nodes(i).UserData)
            nRecordings = nRecordings + 1;
        end
    end

    mode = '';
    if nRecordings == 0
        if confirmAction(fig, ...
                sprintf('There are no cached analyses for this workspace to clear.\n\nClear anyway?'), ...
                'Clear Workspace?', 'Yes, clear', 'Sorry, what? No!', 'Icon', 'warning')
            mode = 'normal';
        end
        return;
    end

    normal = 'Normal clear';
    deep = 'Deep clean';
    cancel = 'Cancel';
    message = sprintf([ ...
        'Clear the cached analyses for the %d recording(s) in this workspace?\n\n' ...
        'A normal clear removes every transformation result, and grand averages built ' ...
        'only from these recordings. Each recording''s loaded data is kept, so ' ...
        'reopening it is quick.\n\n' ...
        'A deep clean also removes that loaded data, so every recording is read again ' ...
        'from its raw file the next time it is opened.\n\n' ...
        'The raw recordings themselves are not touched, and neither is anything in ' ...
        'the cache folder belonging to other workspaces. This cannot be undone.'], nRecordings);

    choice = chooseAction(fig, message, 'Clear Workspace?', ...
        {normal, deep, cancel}, normal, cancel, 'Icon', 'warning');
    switch choice
        case normal
            mode = 'normal';
        case deep
            mode = 'deep';
    end
end
