function edit(this, varargin)
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
%
%   Called two ways: as the ribbon's ButtonPushedFcn (EDIT(this, src,
%   event), both ignored), or, on a guided first run (see Alakazam's own
%   constructor and WorkSpace.IsFirstRun), directly as EDIT(this, true).
%   WELCOME true adds a one-line explanation, leaves the Raw field blank
%   instead of prefilling it with the meaningless RepoRoot-relative
%   fallback nobody's own data lives in, and refuses OK until a Raw
%   folder is actually chosen.
    welcome = ~isempty(varargin) && islogical(varargin{end}) && varargin{end};

    accentColor = [0.290 0.498 0.788]; % matches AlakazamRibbon.html's .alz-tab-home (#4a7fc9)
    bgColor     = [0.9608 0.9608 0.9608]; % uifigure's own default Color

    parentFig = [];
    if isprop(this.Parent, 'MainFigure') && isvalid(this.Parent.MainFigure)
        parentFig = this.Parent.MainFigure;
    end
    if welcome
        headerText = 'Welcome to Alakazam';
        rowHeights = {40, 36, '1x', 46};
    else
        headerText = 'Edit WorkSpace';
        rowHeights = {40, '1x', 46};
    end
    position = [400 400 560 230 + (welcome * 40)];
    if ~isempty(parentFig)
        parentPos = parentFig.Position;
        position(1) = parentPos(1) + (parentPos(3) - position(3)) / 2;
        position(2) = parentPos(2) + (parentPos(4) - position(4)) / 2;
    end

    fig = uifigure('Name', headerText, 'Position', position, ...
        'Color', bgColor, 'Resize', 'off');

    outer = uigridlayout(fig, [numel(rowHeights), 1], 'RowHeight', rowHeights, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);

    header = uilabel(outer, 'Text', ['  ' headerText], 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    header.Layout.Row = 1;

    nextRow = 2;
    if welcome
        introLabel = uilabel(outer, 'Text', ['  Tell Alakazam where your raw EEG recordings live, then ' ...
            'click OK -- you can change this later from the ribbon''s Edit WorkSpace button.'], ...
            'WordWrap', 'on', 'FontColor', [0.35 0.35 0.35]);
        introLabel.Layout.Row = nextRow;
        nextRow = nextRow + 1;
    end

    fieldsGrid = uigridlayout(outer, [3, 3], 'ColumnWidth', {140, '1x', 32}, ...
        'RowHeight', {30, 30, 30}, 'Padding', [16 14 16 8], 'RowSpacing', 12);
    fieldsGrid.Layout.Row = nextRow;

    rawInitial = this.RawDirectory;
    if welcome
        rawInitial = '';
    end
    rawField    = addDirRow(fieldsGrid, 1, 'Raw data folder:', rawInitial);
    cacheField  = addDirRow(fieldsGrid, 2, 'Intermediate folder:', this.CacheDirectory);
    exportField = addDirRow(fieldsGrid, 3, 'Exports folder:', this.ExportsDirectory);

    buttonRow = uigridlayout(outer, [1, 3], 'ColumnWidth', {'1x', 90, 90}, ...
        'Padding', [16 6 16 10], 'ColumnSpacing', 8);
    buttonRow.Layout.Row = nextRow + 1;
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
            startDir = this.userHome(); % pwd depends on how MATLAB was launched, not where the user's own files are
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
        if welcome && isempty(strtrim(rawField.Value))
            uialert(fig, 'Please choose a raw data folder before continuing (or Cancel to explore first).', ...
                'Raw data folder needed');
            return;
        end
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
