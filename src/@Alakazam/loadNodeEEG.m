function EEG = loadNodeEEG(this, file, action)
%LOADNODEEEG  Load a tree node's backing .mat file, or [] (with a
%   clear uialert instead of a raw crash) if it is missing or
%   unreadable. A tree node can outlive its file -- the cache
%   folder cleared by hand, a workspace copied from another
%   machine with different paths, a branch deleted outside the
%   app -- and every caller here is reached directly from a JS
%   tree event, so an uncaught error would otherwise propagate as
%   a raw "Unable to find file" stack trace through the uihtml
%   event bridge (appdesservices...AbstractModel/
%   executeUserCallback) instead of a message the analyst can
%   actually act on. ACTION is a short present-tense phrase
%   naming what was being attempted, used only in the alert text
%   (e.g. 'select this dataset', 'rename this dataset').
    EEG = [];
    if isempty(file) || exist(file, "file") ~= 2
        uialert(this.MainFigure, sprintf( ...
            ['I''m afraid I could not %s: its cache file appears to be missing.\n\n    %s\n\n' ...
             'It may have been deleted or moved outside Alakazam, or ' ...
             'this workspace may have been copied from another computer.'], ...
            action, file), 'File not found', 'Icon', 'warning');
        return;
    end
    try
        loaded = load(file, "EEG");
        EEG = loaded.EEG;
        % FILE (just verified to exist, right here, on THIS
        % machine) always wins over whatever EEG.File happens to
        % already be: that field was baked into the .mat at the
        % moment it was saved, correct only on the machine/
        % username that created it (see treeTraverse's own note).
        % Every caller that later re-derives a path from
        % Workspace.EEG.File (persisting a new result, renaming,
        % finding an open tab by Tag, ...) needs the real one.
        EEG.File = file;
    catch ME
        uialert(this.MainFigure, sprintf('I''m sorry, I was not able to %s:\n\n%s\n\n    %s', ...
            action, ME.message, file), 'Could not load dataset', 'Icon', 'warning');
    end
end
