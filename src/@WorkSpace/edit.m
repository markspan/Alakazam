function edit(this, ~, ~)
%EDIT  "Edit WorkSpace" dialog: Raw/Intermediate/Exports directory fields,
%   each with a browse ("...") button opening a native folder picker.
%   uifigure-based (styled to match the main app: header bar in the same
%   blue as the ribbon's Home tab, uifigure's own default background) --
%   replaces the old classic uiextras.inputgui, a Java/AWT figure whose
%   focus handling doesn't mix cleanly with this otherwise all-uifigure
%   app (see Alakazam.restoreFocus for the same class of issue with
%   transformations' own classic option dialogs).
%
%   OK applies the three fields to this WorkSpace and calls open();
%   directories that don't exist are handled there already (created if
%   possible, or a warning if not), so this dialog does not duplicate
%   that validation. Cancel (or closing the window) discards changes.
    accentColor = [0.290 0.498 0.788]; % matches AlakazamRibbon.html's .alz-tab-home (#4a7fc9)
    bgColor     = [0.9608 0.9608 0.9608]; % uifigure's own default Color

    parentFig = [];
    if isprop(this.Parent, 'MainFigure') && isvalid(this.Parent.MainFigure)
        parentFig = this.Parent.MainFigure;
    end
    position = [400 400 560 230];
    if ~isempty(parentFig)
        parentPos = parentFig.Position;
        position(1) = parentPos(1) + (parentPos(3) - position(3)) / 2;
        position(2) = parentPos(2) + (parentPos(4) - position(4)) / 2;
    end

    fig = uifigure('Name', 'Edit WorkSpace', 'Position', position, ...
        'Color', bgColor, 'Resize', 'off');

    outer = uigridlayout(fig, [3, 1], 'RowHeight', {40, '1x', 46}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);

    header = uilabel(outer, 'Text', '  Edit WorkSpace', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    header.Layout.Row = 1;

    fieldsGrid = uigridlayout(outer, [3, 3], 'ColumnWidth', {140, '1x', 32}, ...
        'RowHeight', {30, 30, 30}, 'Padding', [16 14 16 8], 'RowSpacing', 12);
    fieldsGrid.Layout.Row = 2;

    rawField    = addDirRow(fieldsGrid, 1, 'Raw data folder:', this.RawDirectory);
    cacheField  = addDirRow(fieldsGrid, 2, 'Intermediate folder:', this.CacheDirectory);
    exportField = addDirRow(fieldsGrid, 3, 'Exports folder:', this.ExportsDirectory);

    buttonRow = uigridlayout(outer, [1, 3], 'ColumnWidth', {'1x', 90, 90}, ...
        'Padding', [16 6 16 10], 'ColumnSpacing', 8);
    buttonRow.Layout.Row = 3;
    cancelBtn = uibutton(buttonRow, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    cancelBtn.Layout.Column = 2;
    okBtn = uibutton(buttonRow, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    okBtn.Layout.Column = 3;

    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);

    function field = addDirRow(parent, row, labelText, initialValue)
        label = uilabel(parent, 'Text', labelText, 'VerticalAlignment', 'center');
        label.Layout.Row = row;
        label.Layout.Column = 1;

        field = uieditfield(parent, 'text', 'Value', initialValue);
        field.Layout.Row = row;
        field.Layout.Column = 2;

        browseBtn = uibutton(parent, 'Text', char(8230), ... % 8230 = U+2026 horizontal ellipsis, "..."
            'Tooltip', "Browse for a folder", 'ButtonPushedFcn', @(~, ~) onBrowse(field));
        browseBtn.Layout.Row = row;
        browseBtn.Layout.Column = 3;
    end

    function onBrowse(field)
        startDir = field.Value;
        if isempty(startDir) || ~isfolder(startDir)
            startDir = pwd;
        end
        chosen = uigetdir(startDir, 'Select a folder');
        if ~isequal(chosen, 0)
            field.Value = chosen;
        end
        figure(fig); % uigetdir is a native OS dialog; refocus this uifigure once it closes
    end

    function withSeparator = ensureTrailingSeparator(pathStr)
        withSeparator = pathStr;
        if ~isempty(withSeparator) && withSeparator(end) ~= filesep
            withSeparator = [withSeparator, filesep];
        end
    end

    function onOK()
        this.RawDirectory     = ensureTrailingSeparator(rawField.Value);
        this.CacheDirectory   = ensureTrailingSeparator(cacheField.Value);
        this.ExportsDirectory = ensureTrailingSeparator(exportField.Value);
        delete(fig);
        this.open();
    end

    function onCancel()
        delete(fig);
    end
end
