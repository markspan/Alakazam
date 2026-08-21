function onPlotTabSelected(this, eventData)
%ONPLOTTABSELECTED  PlotsTabGroup.SelectionChangedFcn: keep
%   Workspace.EEG in sync when the user switches tabs by clicking
%   a tab header directly, not a tree node -- see
%   syncActiveDataset for why this matters.
    if isempty(eventData.NewValue) || ~isvalid(eventData.NewValue)
        return;
    end
    this.syncActiveDataset(eventData.NewValue.Tag);
end
