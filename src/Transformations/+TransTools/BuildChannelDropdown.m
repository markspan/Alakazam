function dropdown = BuildChannelDropdown(grid, row, col, channelLabels, valueChangedFcn)
%BUILDCHANNELDROPDOWN  The "Channel:" label + uidropdown row shared by every
%   view that steps a single channel with the arrow keys/mouse wheel
%   (EpochView, AverageView, TimeFrequencyView, CoherenceView, FourierView,
%   SpectralMeasureView, the last two via ZoomPanButtons) -- the channel
%   counterpart of BuildBinDropdown, letting the analyst jump straight to an
%   electrode instead of stepping to it one channel at a time.
%
%   Builds into a nested [1,2] uigridlayout inside GRID at ROW/COL
%   (ColumnWidth {70,'1x'} for the "Channel:" label + the dropdown itself).
%   VALUECHANGEDFCN is called with the selected ItemsData value directly (an
%   index 1:numel(CHANNELLABELS)), not the uidropdown event struct -- every
%   caller just wants "which channel was picked". The caller is responsible
%   for keeping DROPDOWN.Value in step with its own current channel when it
%   changes some other way (arrow keys, mouse wheel, ViewFocus) -- setting
%   Value programmatically does not re-fire VALUECHANGEDFCN.
%
%   See also BUILDBINDROPDOWN, EPOCHVIEW, AVERAGEVIEW, TIMEFREQUENCYVIEW,
%   COHERENCEVIEW, FOURIERVIEW, SPECTRALMEASUREVIEW, ZOOMPANBUTTONS.
    dropdownGrid = uigridlayout(grid, [1, 2], ...
        "ColumnWidth", {70, '1x'}, "Padding", [0 0 0 0], "ColumnSpacing", 4);
    dropdownGrid.Layout.Row = row;
    dropdownGrid.Layout.Column = col;
    uilabel(dropdownGrid, "Text", "Channel:", "HorizontalAlignment", "right");
    dropdown = uidropdown(dropdownGrid, "Items", channelLabels, ...
        "ItemsData", 1:numel(channelLabels), "Value", 1, ...
        "ValueChangedFcn", @(dd, ~) valueChangedFcn(dd.Value));
end
