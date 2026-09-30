function dropdown = BuildBinDropdown(grid, row, col, binLabels, valueChangedFcn, label)
%BUILDBINDROPDOWN  The "Bin:" label + uidropdown row shared by the views
%   that show one bin (or trial) at a time: TimeScrubStrip (paired with its
%   own time slider), EpochView, FourierView, SpectralMeasureView,
%   CovarianceView and CrossCorrelationView. It began as two identical
%   copies, consolidated here.
%
%   Builds into a nested [1,2] uigridlayout inside GRID at ROW/COL
%   (ColumnWidth {40,'1x'} for the "Bin:" label + the dropdown itself,
%   matching both original call sites). VALUECHANGEDFCN is called with the
%   selected ItemsData value directly (an index 1:numel(BINLABELS)), not
%   the uidropdown event struct -- both callers just want "which bin was
%   picked".
%
%   LABEL, "Bin:" when omitted, names what the items are: FourierView
%   passes "Trial:" when the spectra it steps through are single trials.
%   Any other label gets a column fitted to its own width.
%
%   See also TIMESCRUBSTRIP, EPOCHVIEW, FOURIERVIEW, SPECTRALMEASUREVIEW.
    labelWidth = 40;
    if nargin < 6 || isempty(label)
        label = "Bin:";
    else
        labelWidth = 'fit';
    end
    dropdownGrid = uigridlayout(grid, [1, 2], ...
        "ColumnWidth", {labelWidth, '1x'}, "Padding", [0 0 0 0], "ColumnSpacing", 4);
    dropdownGrid.Layout.Row = row;
    dropdownGrid.Layout.Column = col;
    uilabel(dropdownGrid, "Text", label, "HorizontalAlignment", "right");
    dropdown = uidropdown(dropdownGrid, "Items", binLabels, ...
        "ItemsData", 1:numel(binLabels), "Value", 1, ...
        "ValueChangedFcn", @(dd, ~) valueChangedFcn(dd.Value));
end
