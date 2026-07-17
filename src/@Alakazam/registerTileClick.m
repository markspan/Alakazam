function registerTileClick(this, tag)
%REGISTERTILECLICK  Record TAG (a tab's Tag) as the view last
%   clicked/interacted with. Wired by AlakazamPlotter as every
%   View's ActivatedFcn, so keyboard/wheel shortcuts keep tracking
%   whichever tile the user is actually working in once several are
%   visible at once in Grid/Stack mode -- see activeTileTag,
%   dispatchWheel and dispatchKey. Also keeps Workspace.EEG in
%   sync (see syncActiveDataset) -- clicking inside a tile's own
%   content is exactly the same "the user's attention moved to a
%   different open dataset" event as clicking a tab header
%   (onPlotTabSelected) in Tabs mode.
    this.LastClickedTag = string(tag);
    this.syncActiveDataset(tag);
end
