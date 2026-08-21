function dropdown = BuildBinDropdown(grid, row, col, binLabels, valueChangedFcn)
%BUILDBINDROPDOWN  The "Bin:" label + uidropdown row shared by
%   TimeScrubStrip (paired with its own time slider) and
%   CoherenceTopographyView (standalone, no time scrubbing) -- both built
%   the identical nested-grid label+dropdown block independently;
%   consolidated here.
%
%   Builds into a nested [1,2] uigridlayout inside GRID at ROW/COL
%   (ColumnWidth {40,'1x'} for the "Bin:" label + the dropdown itself,
%   matching both original call sites). VALUECHANGEDFCN is called with the
%   selected ItemsData value directly (an index 1:numel(BINLABELS)), not
%   the uidropdown event struct -- both callers just want "which bin was
%   picked".
%
%   See also TIMESCRUBSTRIP, COHERENCETOPOGRAPHYVIEW.
    dropdownGrid = uigridlayout(grid, [1, 2], ...
        "ColumnWidth", {40, '1x'}, "Padding", [0 0 0 0], "ColumnSpacing", 4);
    dropdownGrid.Layout.Row = row;
    dropdownGrid.Layout.Column = col;
    uilabel(dropdownGrid, "Text", "Bin:", "HorizontalAlignment", "right");
    dropdown = uidropdown(dropdownGrid, "Items", binLabels, ...
        "ItemsData", 1:numel(binLabels), "Value", 1, ...
        "ValueChangedFcn", @(dd, ~) valueChangedFcn(dd.Value));
end
